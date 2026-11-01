# #80 InstructorApp 데모 실행 환경과 세션 흐름

## 구현 범위

- 홈의 `데모 모드` 버튼으로 TestFlight 심사용 데모를 시작한다.
- 데모 실행 중에는 상단 배너와 종료 버튼을 항상 표시한다.
- 샘플 도면 한 개와 준비 완료 대원 다섯 명을 제공한다.
- 세션 생성, 준비 상태 확인, 훈련 시작·종료, 결과 준비와 AAR까지 기존 사용자 흐름을 그대로 사용한다.
- 데모 종료 뒤 다시 시작하면 새 실행 식별자와 새 Store를 만들어 초기 상태로 돌아간다.
- 데모 진입점과 저장소는 `#if DEBUG`에 두지 않아 Release 빌드에서도 사용할 수 있다.

## 운영 데이터와의 경계

`InstructorDemoScenario`는 실행마다 별도의 `InstructorStore`를 만들고 모든 의존성을 앱 내부 메모리 구현으로 주입한다. 세션, 대원, 기록은 이 메모리 저장소에서만 읽고 쓰며, 운영 `FirestoreSessionRepository`, `FirestoreMemberRepository`, `FirestoreRecordingRepository`를 참조하지 않는다. 샘플 도면도 메모리 카탈로그와 파일 저장소를 사용하므로 SwiftData의 운영 도면 목록을 변경하지 않는다.

데모를 종료하면 기존 운영 Store가 다시 표시된다. 운영 Store는 데모 Store와 별도로 `AppContainer`가 계속 소유하므로 데모의 세션 상태가 운영 화면으로 전달되지 않는다.

## 흐름과 제한

1. 홈에서 데모 모드에 진입한다.
2. 미리 선택된 `데모 훈련장`으로 세션을 만들면 고정 PIN과 준비 완료 대원 다섯 명이 표시된다.
3. 훈련 시작 뒤 메모리 세션의 서버 시작 시각을 구독해 훈련 화면을 표시한다.
4. 훈련 종료 뒤 각 대원의 기록을 잠시 `finishing` 상태로 제공한 다음 `done`으로 전환해 AAR에 자동 진입한다.
5. AAR에는 다섯 대원의 샘플 동선과 번들 영상을 제공한다. 최대 네 명 선택, 다섯 번째 선택 시 가장 오래된 선택 교체, 도면·영상 화면 전환을 Firebase와 WorldMap 없이 확인할 수 있다.

## 검증

- `InstructorDemoScenarioTests`
  - 재진입 시 새 데모 실행 생성
  - 외부 기기 없이 세션 생성부터 AAR까지 진행
  - 다섯 동선과 네 선택 영상 로딩 및 다섯 번째 선택의 선입선출 교체
  - 새 Store 생성 시 초기 상태 복원
- InstructorApp Debug 및 Release iOS Simulator 빌드

공통 모델, Repository 프로토콜, Firebase 저장 경로와 파일 형식은 변경하지 않았다.
