# #56 훈련 상태·기록 업로드 상태 Firebase 연동

## 구현 범위

- `AppContainer`에서 `FirestoreRecordingRepository`를 만들고 `InstructorStore`에 주입한다.
- 훈련 시작·종료를 `SessionRepository.updateStatus`의 `running`·`ended` 쓰기 성공 이후에만 화면에 반영한다.
- 실행 중 세션을 구독해 Firestore의 `Session.startedAt`으로 경과 시간을 표시하고, 연결 단절 시 마지막 값을 보존한 채 재연결할 수 있게 한다.
- 훈련 시작 성공 시 참가 명단을 확정한다. 미준비 대원 제외는 서버 시작 쓰기가 성공한 뒤에만 화면과 결과 대기 명단에 반영한다.
- 종료 성공 후 별도의 결과 준비 화면에서 대원별 `recording / finishing / done / failed` 상태를 표시한다.
- 빈 기록, 일부 참가자 기록, 진행 중 기록이 하나라도 있으면 AAR 진입을 막는다. 확정 참가자 전원이 `done` 또는 `failed`가 된 뒤에만 자동 진입한다.
- 기록 구독 오류에서는 마지막 스냅샷을 보존하고 재연결 첫 스냅샷 전까지 완료 판단을 중지한다.
- 홈 복귀와 화면 이탈에서는 시작·종료 Task, 세션 구독, 기록 구독을 취소하고 늦게 도착한 결과를 무시한다.
- 공통 모델, Repository 프로토콜, Firestore·Storage 경로와 파일 형식은 변경하지 않았다.

## #47 의존 경계

MemberApp이 실제 영상과 보정 동선을 업로드하고 `Recording` 문서를 생성·갱신하는 일은 #47의 범위다. 이번 구현은 기존 `RecordingRepository.observeRecordings`가 전달하는 상태를 소비하며, 파일 업로드나 기록 문서 생성의 우회 구현을 InstructorApp에 넣지 않았다.

따라서 시뮬레이터 검증에서는 MemberApp의 AR·녹화를 대신하지 않는다. 실제 앱으로 세션 시작·종료와 교관 SDK 구독을 실행하고, #47이 제공할 `finishing → done` 기록 상태만 로컬 Firestore Emulator에 주입해 결과 준비 화면과 AAR 전환을 검증한다. 대원 자격으로 기록 상태를 쓰고 교관의 기록 변조가 거부되는 보안 규칙은 별도의 Emulator REST 테스트로 검증한다.

## 회귀 검사

- `bash scripts/check-instructor-store.sh`
  - 시작·종료 ACK 전 화면 유지와 중복 요청 차단
  - 시작 실패 후 참가자 재구독, 종료 실패 후 훈련 화면 유지와 재시도
  - 서버 `startedAt` 기준 경과 시간과 세션 구독 단절·재연결
  - 빈/일부/중복 기록, 다른 세션·비참가자 기록 제외
  - 기록 구독 단절 시 상태 보존, 재연결 첫 스냅샷 대기
  - `done`·`failed` 전원 종결 후 AAR, 홈 복귀와 늦은 결과 무시
- `bash scripts/check-floorplan-registration.sh`: 기존 도면 등록·세션 참조 회귀 통과
- `CQB_FIREBASE_EMULATOR_TESTS=1 swift test --package-path CQB/Packages/CQBCore`: 전체 43개 통과, 건너뜀 없음
  - 서버 `startedAt`, `ended`, PIN 회수
  - 세션 종료 뒤 대원 본인의 `finishing / done / failed` 갱신 허용
  - 교관의 대원 기록 상태 변경 거부와 교관의 전체 기록 조회
- InstructorApp iOS Simulator Debug 빌드 통과
- MemberApp `MemberApp (Emulator)` iOS Simulator 서명 빌드 통과

## 실제 앱·에뮬레이터 검증

2026-10-12, iPad Pro 13-inch (M5) / iPhone 18 Pro iOS 27 시뮬레이터와 로컬 Auth·Firestore·Storage Emulator를 사용했다.

1. InstructorApp SDK로 세션 `A45BF4E1-294B-4A92-B28F-A366FFA5B87A`, PIN `634749`를 만들고 MemberApp에서 `Issue56 대원`으로 참가했다.
2. 준비 상태 문서 변경이 교관 앱에 `0/1 → 1/1`, `설정중 → 준비 완료`로 실시간 반영되고 훈련 시작 버튼이 활성화되는 것을 확인했다. Device Hub가 도면의 두 번째 좌표 터치를 전달하지 못해 이 실행에서는 MemberApp 테스트 스위치 대신 동일한 로컬 대원 문서의 준비 필드를 갱신했다. MemberApp Repository를 통한 준비 보고와 보안 규칙은 #49 실제 앱 검증 및 Emulator 회귀 검사에서 별도로 통과했다.
3. 교관 앱에서 훈련을 시작한 뒤 세션이 `running`으로 바뀌고 서버 `startedAt`이 생성되는 것, 앱 경과 시간이 `00:00:00`에서 증가하는 것을 확인했다.
4. 훈련 종료 뒤 세션이 `ended`가 되고 `pins/634749`가 `404 NOT_FOUND`로 회수되는 것을 확인했다.
5. 결과 준비 화면은 기록이 없을 때 `기록 수신 대기`, `finishing` 문서 수신 뒤 `기록 처리·업로드 중`을 표시했다.
6. 같은 기록을 `done`으로 바꾸자 추가 조작 없이 AAR 화면으로 자동 전환됐다.

로컬 에뮬레이터 검증 데이터는 운영 Firebase에 전송되지 않는다. 실제 실기기의 AR 녹화와 업로드 완료까지의 종단 검증은 #47 구현 후 진행한다.
