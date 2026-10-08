# CQB Architecture

## 목표

CQB는 대원용 iPhone 앱과 교관용 iPad 앱을 하나의 저장소에서 개발한다.
두 앱은 데이터 모양과 서버 접근 계약을 공유하지만 사용자 역할과 상태 흐름은 서로 다르다.

화면 구조는 MV를 사용한다. 화면마다 ViewModel을 만들지 않고 앱 단위의 `@Observable` Store를 View가 직접 관찰한다.

## 디렉터리 구조

```text
CQB/
├─ MemberApp/
│  ├─ App/
│  │  ├─ MemberApp.swift
│  │  ├─ AppContainer.swift
│  │  └─ RootView.swift
│  ├─ Stores/
│  ├─ Features/
│  ├─ Components/
│  └─ Resources/
├─ InstructorApp/
│  ├─ App/
│  │  ├─ InstructorApp.swift
│  │  ├─ AppContainer.swift
│  │  └─ RootView.swift
│  ├─ Stores/
│  ├─ Features/
│  ├─ Components/
│  └─ Resources/
├─ Configurations/
└─ Packages/CQBCore/Sources/
   ├─ CQBCore/
   │  ├─ Models/
   │  └─ Services/
   ├─ CQBFirebase/
   ├─ CQBFixtures/
   └─ CQBDesignSystem/
```

## 각 영역의 책임

### App

- 앱 진입점을 정의한다.
- Store와 외부 의존성을 생성한다.
- 실제 구현과 Fixture 구현을 조립한다.
- `RootView`에서 앱의 최상위 phase에 맞는 화면을 표시한다.

### Stores

- 앱의 상태 머신을 관리한다.
- 여러 화면에서 공유하거나 유지할 상태를 소유한다.
- 사용자 행동에 따른 상태 전이를 수행한다.
- Repository와 Service를 호출하고 로딩, 성공, 실패 상태를 관리한다.
- SwiftUI View 타입과 화면 배치 정보는 소유하지 않는다.

### Features

- 사용자에게 표시되는 SwiftUI 화면을 기능별로 구성한다.
- View는 Store 상태를 읽어 렌더링하고 사용자 이벤트를 Store에 전달한다.
- 화면에서만 필요한 짧은 수명의 UI 상태는 View가 소유한다.
- 화면마다 별도의 ViewModel을 만들지 않는다.

### Components

- 한 앱 안의 여러 Feature가 함께 사용하는 View와 ViewModifier를 둔다.
- MemberApp과 InstructorApp 사이의 공유를 전제로 하지 않는다.
- 실제 반복이 확인된 구성요소만 이동한다.

### Resources

- 앱별 Asset Catalog, 로컬 이미지, 폰트 등 번들 리소스를 둔다.

### CQBCore

- SwiftUI와 Firebase에 의존하지 않는 공통 모델을 둔다.
- 앱과 데이터 구현 사이의 Repository 및 Service 프로토콜을 둔다.
- 여러 앱에서 공유하는 순수한 검증과 계산 로직을 둔다.

### CQBFirebase

- `CQBCore`에 정의된 Repository 및 Service 프로토콜을 Firebase로 구현한다.
- Firebase DTO와 Core 모델 사이의 변환을 담당한다.
- SwiftUI 화면에 직접 의존하지 않는다.

### CQBFixtures

- `CQBCore` 프로토콜의 가짜 구현과 공통 샘플 데이터를 제공한다.
- Preview와 개발 환경에서 서버 없이 흐름을 실행할 수 있게 한다.

### CQBDesignSystem

- 공통 색상, 타이포그래피, UI 컴포넌트를 패키지로 제공한다.
- 각 앱은 제품 결정에 따라 이 모듈을 선택적으로 사용한다.

## 의존성 방향

```text
MemberApp ────────┐
                  ├──> CQBCore
InstructorApp ────┘       ▲
                          │
CQBFirebase ──────────────┤
CQBFixtures ──────────────┘

MemberApp / InstructorApp ──선택적──> CQBDesignSystem
```

- `CQBCore`는 앱 타깃, SwiftUI, Firebase 구현을 알지 않는다.
- 앱은 Firebase SDK를 직접 호출하지 않고 `CQBCore`의 프로토콜에 의존한다.
- `CQBFirebase`와 `CQBFixtures`는 같은 프로토콜을 구현한다.
- 앱별 Store와 Feature View는 다른 앱 타깃에 의존하지 않는다.

## 상태 소유 기준

### View가 소유하는 상태

- 포커스된 입력 필드
- alert, sheet, popover 표시 여부
- 메뉴 펼침 여부
- 화면에서 편집 중이며 아직 제출하지 않은 값
- 레이아웃과 표시에만 필요한 계산

### Store가 소유하는 상태

- 현재 앱 phase
- 현재 세션과 선택된 도면
- 참가자와 준비 상태
- 훈련 시작 및 종료 상태
- 화면을 이동해도 유지해야 하는 선택값
- 비동기 요청의 로딩, 성공, 실패 상태

### Core가 소유하는 로직

- 앱 간 공유되는 모델과 enum
- PIN 형식 등 UI와 무관한 검증
- 좌표와 시간 등 공통 계산
- Repository 및 Service의 인터페이스

## Store 구성

Store는 Observation 프레임워크를 사용한다.

```swift
@MainActor
@Observable
final class SessionStore {
    var phase: SessionPhase = .idle
}
```

`AppContainer`에서 Store를 생성하고 환경으로 주입한다.

```swift
struct AppContainer: View {
    @State private var store = SessionStore()

    var body: some View {
        RootView()
            .environment(store)
    }
}
```

하위 View는 Store를 직접 관찰한다.

```swift
struct RootView: View {
    @Environment(SessionStore.self) private var store

    var body: some View {
        switch store.phase {
        case .idle:
            IdleView()
        case .active:
            ActiveView()
        }
    }
}
```

## 화면 전환

- `RootView`는 Store의 phase를 화면으로 변환한다.
- View는 phase를 직접 수정하지 않고 Store의 행동 메서드를 호출한다.
- alert, sheet, Picker 펼침 등 화면 내부 표현 상태를 앱 phase로 만들지 않는다.
- 시작, 종료, 참가처럼 서버 상태를 바꾸는 화면 전환은 서버 처리 결과와 함께 Store가 수행한다.
- 앱 흐름을 초기화하는 행동은 Store가 관련 상태를 함께 초기화한다.

### InstructorApp MVP 상호작용 결정

- 도면 생성 화면의 뒤로 가기는 도면 목록으로 이동한다. 도면 목록의 뒤로 가기는 홈으로 이동한다.
- 준비 완료 대원이 한 명도 없으면 훈련을 시작할 수 없다.
- 미준비 대원이 일부 있으면 훈련 시작 시 확인을 거쳐 미준비 대원을 현재 세션에서 일괄 제외한다. 취소하면 팀 준비 화면을 유지한다.
- AAR 동선과 영상은 같은 대원 선택값을 사용한다.
- 5명 이상 선택된 상태에서 영상 전환을 요청하면 전환하지 않고 최대 4명 제한을 안내한다. 선택값을 임의로 줄이지 않는다.

## Store 분리 기준

처음에는 앱 단위 Store로 시작한다. 다음 상황이 나타나면 도메인 단위 Store로 분리한다.

- 한 Store가 서로 독립적인 여러 비동기 생명주기를 관리한다.
- 하나의 Store 파일을 여러 작업자가 반복해서 동시에 수정한다.
- 도면, 세션, 훈련 기록처럼 상태의 생성과 소멸 시점이 명확히 다르다.
- 분리된 상태가 독립적인 Repository에 대응한다.

MemberApp Store와 InstructorApp Store는 공유하지 않는다. 대원 앱은 세션에 참가하고 신호를 받으며, 교관 앱은 세션을 만들고 상태 변경 신호를 보내므로 상태 머신이 다르다.

## 데이터 경계

Firebase 문서 구조를 SwiftUI View까지 전달하지 않는다.

```text
View
  ↓
Store
  ↓
CQBCore Repository Protocol
  ↓
CQBFirebase Repository
  ↓
Firebase DTO
```

- Firebase DTO는 `CQBFirebase` 내부에서 Core 모델로 변환한다.
- View는 Core 모델 또는 앱 내부 표시 상태만 사용한다.
- 서버 필드명과 저장 경로 변경이 View 수정으로 이어지지 않게 한다.
- 데이터 계약 변경은 기능 변경과 분리해 먼저 합의하고 반영한다.

## 작업 단위

- 하나의 GitHub Issue는 하나의 확인 가능한 사용자 결과를 목표로 한다.
- Issue에는 구현 범위, 제외 범위, 완료 조건, 임시 가정을 기록한다.
- 장기간 유지할 구조 규칙은 Issue가 아니라 이 문서와 `AGENTS.md`에 반영한다.
- 구현 중 공통 계약 변경이 필요해지면 별도 Issue와 PR로 분리한다.
