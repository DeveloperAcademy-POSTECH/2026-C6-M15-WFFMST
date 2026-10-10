# #20 공통 도메인 모델 구현안

## 상태와 범위

**모델·Fixture 구현 및 자동 검증 완료 · 팀 승인 전** (2026-10-10). [#20](https://github.com/DeveloperAcademy-POSTECH/2026-C6-M15-WFFMST/issues/20)의 작업 기준이다. 사용자 요청에 따라 권장안을 구현하되 아래 세부 표현은 팀 검토용이며 3명 승인·노션 기록을 대신하지 않는다. 선행 PR #16의 `c46f709`를 기준으로 한다.

공통 의미의 기준은 [공통 데이터 계약](shared-data-contract.md)이다. 이 문서는 기존 초안의 이관 대응표·구현 제한·검증 기록을 모은다. Repository·Storage·Firebase DTO/인증/저장 경로 구현은 Firebase 담당자 영역이다. 기존 #14 프로토콜과 파일 schema, V13 코어를 변경하지 않는다.

## 필드 대응표

| 기존 초안 | 분류 | #20 표현과 이유 |
| --- | --- | --- |
| Session ID·PIN·이름·상태·시각·제외 대원 | 유지 | 전체 Session 값 모델. 시각은 확인된 snapshot을 전달하며 상태 전이 실행은 제외 |
| Session.floorPlan | 재사용 | FloorPlanReference 고정. Session에서 기존 SessionFloorPlanBinding을 추출하며 역방향에 임의 PIN/시각을 채우지 않음 |
| Member.id | 명확화 | 한 세션 참가자의 UUID. sessionID를 명시하며 인증 UID는 별도 서버 대응 |
| Member.name / displayName | 유지 | 입력 이름 / 소비 화면에 전달할 표시 이름. 이름 가공·번호 부여는 구현하지 않음 |
| Member.clockOffsetToServer | 수정 | 미측정은 nil. 서버−기기 초이며 음수 가능. raw의 비음수 기록 시작 offset과 다름 |
| Member.startPose | 수정 | MemberStartConfiguration?로 촬영 전 설정을 분리. nil은 미지정/무효화 |
| StartPose.start / directionPoint | 재사용·수정 | NormalizedPoint 두 개와 FloorPlanReference. px·화면 pt를 넣지 않음 |
| StartPose 회전각 / 카메라 방향 | 분리 | 회전각을 중복 저장하지 않음. 측정한 카메라 방향을 명시적으로 받아 기존 TrackStartPose를 구성 |
| DirectionReferenceMode | 보류 | 현재 계약의 촬영 시작 카메라 방향만 사용. 미확보 값을 unknown/firstWalk로 채우기 위한 공통 enum을 추가하지 않음 |
| DeviceStatus | 유지·명확화 | sessionID 추가. startPointSet은 유효한 위치·방향 설정 완료 보고, trackingReady는 추적 준비 보고, recording은 녹화 중 보고 |
| Recording.id == memberID | 수정 | TrackIdentity 재사용, id는 recordingID. 같은 대원의 다른 기록과 구분 |
| Recording 녹화 시각·종료 사유 | 유지 | 기기 시각. 종료 전 endedAt/endReason은 nil. 신호 수신 후 실제 녹화가 시작된 기록을 표현 |
| Recording.rawUploaded | 명확화 | 저장소가 확인한 업로드 상태의 snapshot. Bool은 공개 권한이나 검증된 원본의 증거가 아님 |
| Recording.video | 수정 | VideoInfo?; 메타데이터 미확보를 nil로 표현. 영상 생략 기능을 채택하는 의미는 아님 |
| ReconstructionStatus.pending | 분리 | 계산 시도 상태와 TrackResultStatus를 구분. 기존 결과 enum은 변경하지 않음 |
| ReconstructionSummary | 재사용·수정 | TrackResultSummary로 identity/resultID·도면·hash·알고리즘·상태·경고를 전달. vertices/coverage/진단 전체는 복제하지 않음 |
| Recording.reconstruction / selectedReconstructionID | 분리 | latestAttempt와 selectedResult를 독립 보관. selectedResultID는 선택 요약에서 계산해 중복 정본을 만들지 않음 |
| VideoChunk.index | 명확화 | TrackIdentity와 index의 조합으로 식별. 다른 기록의 index 0은 다른 조각 |
| VideoChunk.startSeconds | 명확화 | 기록 시작 기준 초. 세션 기준으로 재생할 때의 offset 계산은 후속 |
| VideoInfo.totalChunks / uploadedChunks | 명확화 | 총수 미확정은 nil, 업로드 수는 확인된 완료 수. chunkSeconds는 목표 분할 길이, 실제 조각 길이는 durationSeconds |
| AARSettings | 보류 | 수동 시간 조정 정책 미채택. 모델·schema를 선제 추가하지 않음 |

## 구현 제한과 담당자 확인

- SessionStatus의 preparing은 준비 구성 단계, waiting은 시작 대기, running은 훈련 중, ended는 종료 snapshot이다. 준비 조건·전이·취소 정책을 코드로 실행하지 않는다. 이 단계의 검증은 알려진 시각의 유한성·순서 등 구조 정합성에 한정한다.
- Member UUID 발급·재참가 시 재사용 정책 및 인증 UID 대응은 Firebase/아이폰 담당자가 연결 시 확인한다. 모델이 sessionID를 가진다는 사실이 참가 권한을 증명하지 않는다.
- createdAt/joinedAt/updatedAt/uploadedAt은 저장소가 확정해 전달한 기준 시각, 이름에 DeviceAt이 붙은 값은 기기 시각이다. 서버 timestamp 대기용 임시 UI 객체에 가짜 Date()를 채워 공통 snapshot으로 만들지 않는다.
- startPointSet은 같은 도면 revision에서 위치·방향이 유효하다고 보고한 사실이다. 보고 Bool만으로 지도·참가 검증을 생략하지 않는다. 초기 raw nil 허용은 trackingReady 조건 완화가 아니다.
- RecordingState의 recording/uploading/done은 녹화 중/기록 자료 전송 중/자료 전송 완료라는 snapshot이다. 보정 성공·선택 완료·AAR 진입 가능과 동의어가 아니다. 전송 실패·재시도 실행 정책은 후속이며 done 자동 계산기를 추가하지 않는다.
- ReconstructionAttempt의 pending/running은 작업 중, completed는 결과 문서가 만들어짐(결과 status가 failed일 수도 있음), failed는 결과 문서를 만들지 못한 실행 오류, cancelled는 취소다. 아직 시도가 없으면 latestAttempt가 nil이다. 선택 결과는 done/partial만 허용하고, 실패·취소 시 이전 선택을 보존한 snapshot을 표현한다.
- 선택된 결과 요약은 확보된 선택 결과를 뜻한다. 선택 ID만 알고 요약을 아직 읽지 못한 상태는 Repository/앱의 로딩 상태이며 selectedResult=nil로 '선택 없음'과 혼동하지 않는다.
- 값 모델의 생성·Codable decode는 검증 완료·권한 확인을 뜻하지 않는다. 공통 최소 검증을 별도로 제공하고, 실제 결과 문서 검증은 기존 TrackDocumentValidator를 사용한다.
- 새 모델은 Firebase 문서 DTO나 새 운영 파일 schema가 아니다. 날짜/enum의 Codable 왕복은 모델 테스트이며 기존 도면·동선 파일 schemaVersion은 유지한다. 미지원 새 모델 enum은 임의 성공 상태로 fallback하지 않고 decode 오류로 처리한다.

## 검증 결과

- [x] 외부 모듈에서 public 생성자 사용, Codable 왕복·필수/선택 필드·미지원 enum 검사
- [x] Session → Member → Recording → VideoChunk → 선택된 결과 관계 Fixture
- [x] 같은 대원의 다른 recordingID 및 각 기록의 chunk index 0 구분
- [x] 보정 결과 없음 / 재보정 실패·취소 + 기존 partial 선택 보존
- [x] 같은 시각의 정상·미해결 샘플 및 정상 복구점·연결 미확인 진단의 요약 보존
- [x] 기존 패키지 회귀 테스트 및 MemberApp/InstructorApp 빌드
- [ ] 양쪽 앱·Firebase 담당자 필드 사용 확인, 팀원 3명 승인·노션 기록

관계 Fixture는 식별·연결·상태 표현을 증명하는 합성 자료다. 같은 대원의 기록 3개를 표현하지만 실제 재촬영 기능·복수 기록 AAR 통합·상태 전이를 실행하거나 제품 범위에 추가한 것이 아니다. 첫 두 기록은 서로 겹치지 않는 시각을 사용하고, 마지막 기록은 아직 결과·영상 메타데이터가 없는 상태다. 영상 숫자는 예시이며 제품 촬영 사양이 아니다.

### 실행 기록 (2026-10-10)

- `swift test --package-path CQB/Packages/CQBCore`: **169개 통과**(Core 160개 + Fixtures 9개, 기존 빈 example 1개 포함). #20에서 35개를 추가했다.
- 새 테스트: [SessionMemberModelTests](../CQB/Packages/CQBCore/Tests/CQBCoreTests/SessionMemberModelTests.swift) 8개, [RecordingModelTests](../CQB/Packages/CQBCore/Tests/CQBCoreTests/RecordingModelTests.swift) 8개, [TrainingDomainValidationTests](../CQB/Packages/CQBCore/Tests/CQBCoreTests/TrainingDomainValidationTests.swift) 12개, [TrainingDomainFixtureTests](../CQB/Packages/CQBCore/Tests/CQBCoreTests/TrainingDomainFixtureTests.swift) 7개.
- 독립 리뷰 후 알고리즘 식별자 3개 필드의 공백-only 값을 기존 전체 결과 validator와 동일하게 거부하도록 보완했다. 회귀 테스트는 수정 전 3개 assertion 실패, 수정 후 통과했다. 업로드 개수 문서의 부등식 표현도 수정했다.
- MemberApp·InstructorApp 모두 `generic/platform=iOS Simulator`, `CODE_SIGNING_ALLOWED=NO` 빌드 성공. UI/실기기 실행 검증은 아니다.
- `node scripts/check-minimal-track-fixture.mjs`: 기존 4개 사례·공개 기대값 6개·변형 검사 6개 통과. #14의 리소스·기대값·공통 모델·Repository 프로토콜·파일 schema는 수정하지 않았다.
- [TrainingDomainFixture](../CQB/Packages/CQBCore/Sources/CQBFixtures/TrainingDomainFixture.swift)는 caller가 공급한 검증된 normal-v1 도면과 기존 validator를 사용한다. 보정기를 실행하지 않고 인덱스 경계의 합성 결과를 연결한다.

### 남은 확인과 검증 한계

- 팀원 3명 승인·노션 동기화, 양쪽 앱/Firebase 담당자의 필드 사용 확인 및 진행 중인 도메인 작업과의 중복 확인은 자동 완료 처리하지 않았다.
- 이름/상태 의미, 선택 요약 로딩 경계, 시각 출처, memberID 발급·재참가 대응은 이번 구현안을 기준으로 담당자가 확인한다. 운영 저장 DTO·날짜 직렬화·물리 경로는 Firebase 담당자 영역이다.
- 실제 앱 View/Store 주입·두 기기 통신·업로드·준비 판정·시계 동기화·영상/V13 이관은 이번 검증에 포함하지 않는다. 상태 snapshot 테스트는 실제 실행 정책을 검증한 것이 아니다.
- 새 코드는 값 타입과 순수 검증 중심으로 참조 순환·새 비동기 작업·UI 관찰을 추가하지 않는다. 장시간 Instruments·실기기 성능 측정을 수행했다는 뜻은 아니다.
