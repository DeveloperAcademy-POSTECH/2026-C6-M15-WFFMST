# InstructorApp 작업 규칙

이 문서는 `CQB/InstructorApp` 아래의 코드에 적용한다.
저장소 공통 규칙은 루트 `AGENTS.md`를 함께 따른다.

## 기본 구조

- InstructorApp은 MV 구조를 사용한다.
- 화면별 ViewModel을 생성하지 않는다.
- 앱 단위의 `@Observable` Store를 View가 직접 관찰한다.
- Store는 `@MainActor`로 격리한다.
- Store는 `AppContainer`에서 생성하고 하위 View에 환경으로 주입한다.
- `RootView`는 Store의 `phase`에 따라 화면을 전환한다.
- `ObservableObject`, `@Published`, `@EnvironmentObject`를 혼용하지 않는다.

## View의 책임

- View에는 SwiftUI 레이아웃, 상태 표시, 사용자 이벤트 전달을 둔다.
- alert, sheet, focus, 입력 중인 텍스트, 메뉴 펼침 여부처럼 화면이 사라질 때 함께 사라져도 되는 상태는 `@State`로 관리한다.
- 버튼 action과 `.task`에서는 Store의 의미 있는 메서드를 호출한다.
- View에서 Store의 `phase`를 직접 변경하지 않는다.
- View에서 참가자, 세션, 도면 같은 공유 데이터를 직접 추가하거나 제거하지 않는다.
- 숫자, 날짜, 시간의 표시 형식과 Grid 열 수처럼 표현에만 필요한 계산은 View에 둘 수 있다.
- SwiftUI View 타입을 Store에 저장하지 않는다.

## Store의 책임

- 화면 전환과 뒤로 가기 규칙을 관리한다.
- 여러 화면에서 유지하거나 공유하는 상태를 소유한다.
- 버튼 활성화 조건과 상태 전이 조건을 계산한다.
- 사용자 행동을 의미 단위의 메서드로 제공한다.
- 비동기 작업의 로딩, 성공, 실패 상태를 관리한다.
- Firebase, 파일, 영상 등 외부 시스템은 Repository 또는 Service를 통해 사용한다.

다음과 같은 행동 이름을 사용해 View가 구체적인 상태 변경을 알지 않도록 한다.

```swift
store.openFloorPlanList()
store.createSession()
store.startTraining()
store.finishTraining()
store.finishAAR()
store.goBack()
```

## 로직 배치 기준

- 화면이 다시 생성되어도 유지되어야 하는 상태는 Store에 둔다.
- 다른 화면에서도 사용하는 상태는 Store에 둔다.
- 앱의 상태를 변경하는 판단과 처리는 Store에 둔다.
- UI 없이 검증할 수 있는 순수한 도메인 규칙은 Store에 두고, 여러 앱에서 공유하게 되면 `CQBCore`로 이동한다.
- Firebase 접근, 파일 입출력, 디코딩, 영상 로딩, 오류 처리, 재시도는 View에 작성하지 않는다.
- View의 버튼 action이 조건문이나 여러 상태 변경을 포함하면 Store 메서드로 옮긴다.
- View의 `Task`는 하나의 비동기 Store 메서드를 호출하는 용도로만 사용한다.

## Store 분리

- 초기 구현에서는 앱 단위 Store로 시작한다.
- Store가 여러 도메인의 비동기 상태를 동시에 관리하거나, 한 파일을 여러 명이 반복해서 수정하게 되면 도메인별로 분리한다.
- 분리 예시는 `FloorPlanStore`, `TrainingSessionStore`, `TrainingRecordStore`이며 실제 책임이 생기기 전에 미리 만들지 않는다.
- MemberApp과 InstructorApp은 상태 머신이 다르므로 Store를 공유하지 않는다.

## UI 구현

- InstructorApp에서는 `CQBDesignSystem`을 사용하지 않는다.
- `CQBDesignSystem`을 import하거나 InstructorApp 구현을 위해 수정하지 않는다.
- SwiftUI 기본 컴포넌트와 InstructorApp 내부 스타일을 사용한다.
- 동일한 UI가 두 곳 이상에서 실제로 반복될 때만 `Components`로 분리한다.
- 화면 전체를 절대 좌표와 `offset`으로 구성하지 않는다.
- iPad 크기 변화에 대응하도록 Stack, Grid, 유연한 frame을 사용한다.
- 목록, 입력 폼, Picker, Toggle 등은 가능한 경우 SwiftUI 시스템 컴포넌트를 사용한다.

## 교체 가능한 UI 컴포넌트

- 디자인이 확정되지 않은 공통 Control은 `Components/Controls`의 얇은 Adapter를 통해 사용한다.
- Adapter는 현재 SwiftUI 기본 컴포넌트로 구현한다.
- Adapter의 API는 외형보다 역할과 사용자 행동을 표현한다.
- View에서 공통 버튼이나 선택 메뉴의 스타일 modifier를 반복하지 않는다.
- Adapter가 Store, Firebase, 화면 전환 규칙을 직접 알지 않게 한다.
- 선택 인원 제한과 버튼 활성화 조건은 Store에서 관리한다.
- 화면 배치에 필요한 frame과 padding은 호출하는 View가 관리한다.
- 실제로 교체 가능성이 있는 Control만 Adapter로 만든다.

## 공통 패키지

- 화면 구현을 위해 `CQBCore`, `CQBFirebase`, `CQBFixtures`의 계약을 임의로 변경하지 않는다.
- 앱 내부에서만 필요한 Mock 데이터는 InstructorApp 내부에 둔다.
- 공통 모델이나 Repository 계약이 필요하다고 확인되면 별도 데이터 계약 이슈로 분리한다.

## 리뷰 시 확인 신호

`Features` 아래 View에서 다음 코드가 발견되면 책임이 올바른 위치에 있는지 확인한다.

```text
Firebase
URLSession
FileManager
JSONDecoder
Timer
try await
store.phase =
store.participants.append/remove
```

