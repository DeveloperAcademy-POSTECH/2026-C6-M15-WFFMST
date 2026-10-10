# #20 공통 도메인 모델 구현·검증 기록

## 상태와 범위

**공통 값 모델·최소 검증·AAR 관계 Fixture·자동 테스트·양쪽 앱 빌드 완료 / 팀 승인 전** (2026-10-10). [#20](https://github.com/DeveloperAcademy-POSTECH/2026-C6-M15-WFFMST/issues/20)의 작업 기록이다. 선행 PR #16의 `c46f709`를 기준으로 작업했으며, 팀원 3명 승인·노션 기록은 미완료다.

**계약 규칙은 [공통 데이터 계약](shared-data-contract.md) 한 곳에서 관리한다.** 이 문서는 이관 내역·구현 위치·진행 상태·검증 증거만 기록하며 필드 의미·검증 조건·제품 정책을 별도로 정의하지 않는다. 계약 변경 시 기준 문서를 먼저 갱신하고, 이 문서에는 관련 절 링크와 작업 결과를 남긴다.

작업 범위·제외 범위는 [제품 정책과 현재 작업 범위](shared-data-contract.md#제품-정책과-현재-작업-범위), 담당 경계는 [1.7](shared-data-contract.md#17-데이터-흐름과-담당-경계)를 참조한다. 기존 #14 프로토콜·파일 schema·V13 코어는 이번 구현에서 변경하지 않았다.

## 이관 내역과 구현 위치

이 표는 초안에서 어느 코드로 이관했는지 찾기 위한 색인이다. 변경 이유와 현재 의미는 마지막 열의 계약 절에서 확인한다.

| 이관 대상 | 작업 내역·구현 위치 | 계약 기준 |
| --- | --- | --- |
| Session·SessionStatus | 유지·명확화하여 [Session.swift](../CQB/Packages/CQBCore/Sources/CQBCore/Models/Session.swift)에 구현 | [1.2 세션](shared-data-contract.md#12-세션) |
| Session.floorPlan | 기존 타입 재사용·floorPlanBinding 연결 구현 | [1.2 세션](shared-data-contract.md#12-세션) |
| Member·DeviceStatus | 필드 조정 후 [Member.swift](../CQB/Packages/CQBCore/Sources/CQBCore/Models/Member.swift)에 구현 | [1.3 대원과 준비 상태](shared-data-contract.md#13-대원과-준비-상태) |
| 촬영 전 StartPose | MemberStartConfiguration으로 분리·기존 TrackStartPose 연결 구현 | [1.3 대원과 준비 상태](shared-data-contract.md#13-대원과-준비-상태) |
| DirectionReferenceMode | 초안 enum 미이관 | [1.3 대원과 준비 상태](shared-data-contract.md#13-대원과-준비-상태) |
| Recording·RecordingState·EndReason | 식별·선택 필드 조정 후 [Recording.swift](../CQB/Packages/CQBCore/Sources/CQBCore/Models/Recording.swift)에 구현 | [1.4 기록](shared-data-contract.md#14-기록) |
| ReconstructionStatus·ReconstructionSummary | ReconstructionAttempt와 [TrackResultSummary](../CQB/Packages/CQBCore/Sources/CQBCore/Models/TrackResultSummary.swift)로 분리·기존 동선 타입 재사용 | [계산 시도와 선택 결과](shared-data-contract.md#계산-시도와-선택-결과) |
| VideoInfo·VideoChunk | 필드 조정 후 [Video.swift](../CQB/Packages/CQBCore/Sources/CQBCore/Models/Video.swift)에 구현 | [영상 메타데이터](shared-data-contract.md#영상-메타데이터) |
| 최소 도메인 검증 | [TrainingDomainValidator](../CQB/Packages/CQBCore/Sources/CQBCore/Services/TrainingDomainValidator.swift) 추가 | [#20 공통 구현 경계](shared-data-contract.md#20-공통-구현-경계) |
| AARSettings | [AARSettings.swift](../CQB/Packages/CQBCore/Sources/CQBCore/Models/AARSettings.swift)의 모델·enum과 기존 검증기 overload·단위 테스트 추가. 기존 TrainingDomainFixture에 연결 | [1.6 AAR 설정](shared-data-contract.md#16-aar-설정) |

## 기존 도메인의 검증 결과

아래 완료 항목은 AARSettings 추가 전 세션·대원·기록·영상·보정 요약에 대한 기록이다. AARSettings 단위·관계 테스트의 실행은 다음 절에서 별도로 기록한다.

- [x] 외부 모듈에서 public 생성자 사용, Codable 왕복·필수/선택 필드·미지원 enum 검사
- [x] Session → Member → Recording → VideoChunk → 선택된 결과 관계 Fixture
- [x] 같은 대원의 다른 recordingID 및 각 기록의 chunk index 0 구분
- [x] 보정 결과 없음 / 재보정 실패·취소 + 기존 partial 선택 보존
- [x] 같은 시각의 정상·미해결 샘플 및 정상 복구점·연결 미확인 진단의 요약 보존
- [x] 기존 패키지 회귀 테스트 및 MemberApp/InstructorApp 빌드
- [ ] 양쪽 앱·Firebase 담당자 필드 사용 확인, 팀원 3명 승인·노션 기록

관계 Fixture는 식별·연결·상태 표현을 증명하는 합성 자료다. 같은 대원의 기록 3개를 표현하지만 실제 재촬영 기능·복수 기록 AAR 통합·상태 전이를 실행하거나 제품 범위에 추가한 것이 아니다. 첫 두 기록은 서로 겹치지 않는 시각을 사용하고, 마지막 기록은 아직 결과·영상 메타데이터가 없는 상태다. 영상 숫자는 예시이며 제품 촬영 사양이 아니다.

## AAR 설정 구현·검증 계획

다음은 [공통 계약 1.6](shared-data-contract.md#16-aar-설정)에 대응하는 작업 목록이다. 필드·조건·기대 판정은 링크된 계약 절에서만 관리하며, 구현 전 항목을 검증 완료로 표시하지 않는다.

- [x] 필드·식별자·초기 구성·선택 규칙·책임과 제외 범위를 공통 계약에 정리
- [x] [목적과 필드](shared-data-contract.md#목적과-필드)에 맞춰 CQBCore 값 타입과 codec 테스트 추가
- [x] [최소 정합성 검증과 로딩 경계](shared-data-contract.md#최소-정합성-검증과-로딩-경계)의 조건별 정상·오류 테스트와 검증 구현 추가
- [x] [초기 구성과 선택 규칙](shared-data-contract.md#초기-구성과-선택-규칙)을 표현하는 관계 Fixture·경계 사례 추가
- [x] [책임과 기존 앱 연결](shared-data-contract.md#책임과-기존-앱-연결)에 맞춰 기존 도메인과의 연결을 확인(값 관계 검증이며 실제 앱 연결 아님)
- [x] [포함하지 않는 값](shared-data-contract.md#포함하지-않는-값과-검증-계획)의 필드 혼입 여부 확인
- [x] 관련 패키지 빌드·단위 테스트·전체 회귀 테스트 후 실행 기록 갱신
- [x] AAR 관계 Fixture 연결 이후 영향받는 앱 타깃 빌드와 전체 검증 결과 갱신

### AAR 관계 Fixture 연결·검증 기록 (2026-10-10)

목표는 기존 도메인 관계에 AAR 설정을 연결하고, [공통 계약 1.6](shared-data-contract.md#16-aar-설정)을 공개 API로 소비할 수 있음을 확인하는 것이다. 새 정책·Core API·운영 파일 schema를 추가하지 않았다.

[TrainingDomainFixture](../CQB/Packages/CQBCore/Sources/CQBFixtures/TrainingDomainFixture.swift)의 `Snapshot`에 `members`와 `aarSettings`를 추가했다. 기존 `member`는 이전 소비자가 사용하는 주 대원 값이며, `members`에 동일한 값으로 정확히 한 번 포함됨을 검사한다. Snapshot의 Codable은 합성 자료의 왕복 검증용이지 운영 저장 형식이나 마이그레이션 계약이 아니다.

| 합성 자료 | 이번 Fixture의 구성·확인 결과 |
| --- | --- |
| 세션·대원 | 완전한 참가자 목록 7명, 제외 대원 1명, 초기 동선 선택 6명. 인원은 경계 검증용 예시다 |
| 자료가 있는 주 대원 | 기존 3개 기록·2개 raw/결과·2개 영상 조각을 유지. 표시 대상에서 기록을 찾고 각 기록의 선택 결과로 연결한다 |
| 추가 대원 | 5명은 선택 대상이지만 기록·영상·보정 결과 자료 없음. 가짜 결과나 준비 보고를 만들어 채우지 않았다 |
| 보정 결과 | 기존 partial·trackingLost/connectionUnverified와 coverage를 재검증. 최근 실패/취소 시도 ID로 선택 결과를 대체하지 않는다 |

- [AARTrainingDomainFixtureTests](../CQB/Packages/CQBCore/Tests/CQBCoreTests/AARTrainingDomainFixtureTests.swift) **7개 통과**. `@testable` 없이 합성 자료와 공통 모델·검증기를 사용했다. 위 관계와 codec, 빈 선택·같은 4명 양모드·영상 5/6명 거부·외부/제외 참조·자료 미확보 대원 선택·입력 보존을 확인했다. 기대 판정은 1.6을 따른다.
- `swift build --package-path CQB/Packages/CQBCore` 성공.
- `swift test --package-path CQB/Packages/CQBCore --filter AARTrainingDomainFixtureTests` 성공.
- `swift test --package-path CQB/Packages/CQBCore`: **187개 통과**(Core 178개 + Fixtures 9개, 기존 빈 example 1개 포함). 직전 180개에 관계 테스트 7개를 추가했다.
- MemberApp·InstructorApp 모두 `xcodebuild -project CQB/CQB.xcodeproj -scheme <앱 이름> -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` 성공. 검증 전용 DerivedData를 사용했다. 앱 코드는 수정하지 않았으며, 빌드 성공은 AAR 모델의 화면 주입이나 동작 검증을 의미하지 않는다.
- `node scripts/check-minimal-track-fixture.mjs`: 기존 4개 사례·공개 기대값 6개·변형 검사 6개 통과. normal-v1/minimal-v1 리소스·V13·기존 raw/결과 생성 코드는 변경하지 않았다.
- 독립 리뷰에서 필수 수정 사항 없음. 새 참조 소유·비동기 작업·UI 관찰을 추가하지 않았으며 메모리·실기기 성능 측정으로 해석하지 않는다.

이번 단계는 값 관계·경계 검증이다. 모든 대원의 영상 파일을 갖춘 6명 AAR 재생 Fixture, 복수 기록 선택·타임라인 통합, 앱 Store의 전환 거부/상태 유지, 실제 UI·기기 간 통신은 구현하거나 검증하지 않았다. 기존 `Session.status == running` 자료를 유지한 것은 값 검증과 AAR 진입 조건을 구분하기 위한 것으로, 실행 중 AAR 진입을 허용하는 정책 추가가 아니다.

### AAR 모델·최소 검증 실행 기록 (2026-10-10)

아래는 관계 Fixture 연결 전, 사용자가 요청한 권장 순서 1~3의 실행 이력이다. 문서 파일명·링크 정리와 계약 기준은 `ccad8c6`으로 먼저 커밋한 뒤 모델·검증·단위 테스트를 추가했다.

- [AARSettingsTests](../CQB/Packages/CQBCore/Tests/CQBCoreTests/AARSettingsTests.swift) **11개 통과**. `@testable` 없이 공개 API를 소비한다. 생성·필수 필드·미지원 값·집합 codec, 정상/오류 참조, 인원 경계, 검증 시 입력 보존을 확인했다. 기대 판정의 기준은 1.6이다.
- `swift build --package-path CQB/Packages/CQBCore` 성공.
- `swift test --package-path CQB/Packages/CQBCore --filter AARSettingsTests` 성공.
- `swift test --package-path CQB/Packages/CQBCore`: **180개 통과**(Core 171개 + Fixtures 9개, 기존 빈 example 1개 포함). 기존 169개에 AAR 단위 테스트 11개를 추가했다.
- 새 테스트 내부에서 작은 Session·Member 값을 직접 생성했다. 기존 `TrainingDomainFixture`·`CQBFixtures` 리소스는 수정하지 않았으며 기록·선택 결과까지 포함한 AAR 관계 Fixture 연결은 다음 단계다.
- 이번 추가 후 MemberApp·InstructorApp 빌드와 UI/실기기 실행은 하지 않았다. 모드 전환·거부 시 앱 상태 보존을 실행한 것이 아니라 값 표현과 순수 검증만 확인했다.

## 기존 도메인의 실행 기록 (2026-10-10)

- `swift test --package-path CQB/Packages/CQBCore`: **169개 통과**(Core 160개 + Fixtures 9개, 기존 빈 example 1개 포함). #20에서 35개를 추가했다. AARSettings 모델·테스트 추가 전의 실행 기록이다.
- 새 테스트: [SessionMemberModelTests](../CQB/Packages/CQBCore/Tests/CQBCoreTests/SessionMemberModelTests.swift) 8개, [RecordingModelTests](../CQB/Packages/CQBCore/Tests/CQBCoreTests/RecordingModelTests.swift) 8개, [TrainingDomainValidationTests](../CQB/Packages/CQBCore/Tests/CQBCoreTests/TrainingDomainValidationTests.swift) 12개, [TrainingDomainFixtureTests](../CQB/Packages/CQBCore/Tests/CQBCoreTests/TrainingDomainFixtureTests.swift) 7개.
- 독립 리뷰 후 알고리즘 식별자 3개 필드의 공백-only 값을 기존 전체 결과 validator와 동일하게 거부하도록 보완했다. 회귀 테스트는 수정 전 3개 assertion 실패, 수정 후 통과했다. 업로드 개수 문서의 부등식 표현도 수정했다.
- MemberApp·InstructorApp 모두 `generic/platform=iOS Simulator`, `CODE_SIGNING_ALLOWED=NO` 빌드 성공. UI/실기기 실행 검증은 아니다.
- `node scripts/check-minimal-track-fixture.mjs`: 기존 4개 사례·공개 기대값 6개·변형 검사 6개 통과. #14의 리소스·기대값·공통 모델·Repository 프로토콜·파일 schema는 수정하지 않았다.
- [TrainingDomainFixture](../CQB/Packages/CQBCore/Sources/CQBFixtures/TrainingDomainFixture.swift)는 caller가 공급한 검증된 normal-v1 도면과 기존 validator를 사용한다. 보정기를 실행하지 않고 인덱스 경계의 합성 결과를 연결한다.

## 남은 확인과 검증 한계

- AARSettings의 기존 관계 Fixture 연결·자동 검증·양쪽 앱 빌드는 완료했다. 모델 구현·검증 완료는 팀 승인이나 실제 앱 서비스 연결 완료를 의미하지 않는다.
- 팀원 3명 승인·노션 동기화, 양쪽 앱/Firebase 담당자의 필드 사용 확인 및 진행 중인 도메인 작업과의 중복 확인은 자동 완료 처리하지 않았다.
- 담당자 확인 기준: [1.2 세션](shared-data-contract.md#12-세션), [1.3 대원과 준비 상태](shared-data-contract.md#13-대원과-준비-상태), [1.4 기록](shared-data-contract.md#14-기록), [1.6 AAR 설정](shared-data-contract.md#16-aar-설정), [2.1 변환 규칙](shared-data-contract.md#21-변환-규칙). 확인 결과와 이견은 이 작업 기록에 남기되 규칙 변경은 공통 계약에 반영한다.
- 실제 앱 View/Store 주입·두 기기 통신·업로드·준비 판정·시계 동기화·영상/V13 이관은 이번 검증에 포함하지 않는다. 상태 snapshot 테스트는 실제 실행 정책을 검증한 것이 아니다.
- 이번에 구현한 코드는 값 타입과 순수 검증 중심이며 참조 순환·새 비동기 작업·UI 관찰을 추가하지 않았다. 장시간 Instruments·실기기 성능 측정은 수행하지 않았다.
