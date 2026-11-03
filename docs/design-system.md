# CQB 디자인 시스템

## 기준

CQB UI는 Figma의 디자인 시스템과 `CQBDesignSystem`을 단일 기준으로 사용한다.

- [Color](https://www.figma.com/design/3tndfCqfeh1Z1dLRXu2qXk/%ED%92%8D%EB%A6%BC%ED%99%94%EC%82%B0%EC%9D%8C%EB%A2%B0?node-id=3016-2083)
- [실사용 Color](https://www.figma.com/design/3tndfCqfeh1Z1dLRXu2qXk/%ED%92%8D%EB%A6%BC%ED%99%94%EC%82%B0%EC%9D%8C%EB%A2%B0?node-id=3016-2411)
- [Typography](https://www.figma.com/design/3tndfCqfeh1Z1dLRXu2qXk/%ED%92%8D%EB%A6%BC%ED%99%94%EC%82%B0%EC%9D%8C%EB%A2%B0?node-id=3016-2578)
- [Components](https://www.figma.com/design/3tndfCqfeh1Z1dLRXu2qXk/%ED%92%8D%EB%A6%BC%ED%99%94%EC%82%B0%EC%9D%8C%EB%A2%B0?node-id=3016-2544)
- [Effects](https://www.figma.com/design/3tndfCqfeh1Z1dLRXu2qXk/%ED%92%8D%EB%A6%BC%ED%99%94%EC%82%B0%EC%9D%8C%EB%A2%B0?node-id=3016-2568)
- [Radius](https://www.figma.com/design/3tndfCqfeh1Z1dLRXu2qXk/%ED%92%8D%EB%A6%BC%ED%99%94%EC%82%B0%EC%9D%8C%EB%A2%B0?node-id=3016-2571)
- [Spacing](https://www.figma.com/design/3tndfCqfeh1Z1dLRXu2qXk/%ED%92%8D%EB%A6%BC%ED%99%94%EC%82%B0%EC%9D%8C%EB%A2%B0?node-id=3016-2576)
- 구현 모듈: `CQBDesignSystem`

레거시 색상·타이포그래피 API와 Noto Sans KR 번들 폰트는 사용하지 않는다. Figma와 코드의 차이를 발견하면 임의의 원시값을 화면에 추가하지 말고 [감사 기록](design-system-audit.md)에 따라 의도된 확장인지 먼저 확인한다.

## 배치 기준

`CQBDesignSystem`에는 앱 이름과 도메인을 모르는 Foundation 및 범용 스타일만 둔다.

- Package: palette, 의미 색상, typography, spacing, radius, size, effect, 범용 control 스타일
- App: 훈련, 도면, 대원, AAR 상태를 아는 컴포넌트와 Store 연결

앱 컴포넌트는 값과 callback만 받도록 작성한다. InstructorApp과 MemberApp에서 역할과 상호작용이 같은 실제 사용처가 확인되면 별도 이슈로 Package에 승격한다.

## Foundation 대응표

| Figma | Swift |
| --- | --- |
| `Gray/50...900` | `DSPalette.Gray.g50...g900` |
| `Primary/50...900` | `DSPalette.Primary.p50...p900` |
| `Red/50...900` | `DSPalette.Red.r50...r900` |
| `Green/50...900` | `DSPalette.Green.g50...g900` |
| `Yellow/50...900` | `DSPalette.Yellow.y50...y900` |
| `Blue/50...900` | `DSPalette.Blue.b50...b900` |
| `Primary/500` | `DSColor.actionPrimary` |
| Primary Button `Disabled` 배경 | `DSColor.actionPrimaryDisabled` (`Gray/600`) |
| `Spacing/4...80` | `DSSpacing.s4...s80` |
| `radius/sm` | `DSRadius.small` |
| `radius/md` | `DSRadius.medium` |
| `radius/lg` | `DSRadius.large` |
| `radius/full` | `DSRadius.full` |
| Button height | `DSSize.actionButtonHeight` |
| `Size/control-height` | `DSSize.controlHeight` |
| `Size/compact-control-height` | `DSSize.compactControlHeight` |
| `Shadow/Button` | `View.dsButtonShadow()` |
| `Shadow/Floating` | `View.dsFloatingShadow()` |

## 타이포그래피

Figma의 최신 Typography 영역에 보이는 12개 스타일과 현재 화면에서 사용 중인 5개 확장 스타일을 `DSTypography`에 정의한다. 폰트뿐 아니라 Figma의 행간과 자간을 적용하려면 `dsTextStyle(_:)`을 사용한다. 특정 앱에서만 필요한 weight·size 조합은 앱의 Typography 파일에 `DSTextStyle`로 둔다.

| Figma | Swift |
| --- | --- |
| `Display/Bold/48` | `DSTypography.displayBold48` |
| `Display/SemiBold/48` | `DSTypography.displaySemiBold48` |
| `Display/Bold/40` | `DSTypography.displayBold40` |
| `Heading/Bold/36` | `DSTypography.headingBold36` |
| `Heading/Bold/32` | `DSTypography.headingBold32` |
| `Heading/SemiBold/32` | `DSTypography.headingSemiBold32` |
| `Heading/SemiBold/28` | `DSTypography.headingSemiBold28` |
| `Heading/ExtraBold/24` | `DSTypography.headingExtraBold24` |
| `Heading/SemiBold/24` | `DSTypography.headingSemiBold24` |
| `Heading/SemiBold/20` | `DSTypography.headingSemiBold20` |
| `Heading/Bold/20` | `DSTypography.headingBold20` |
| `Body/Regular/24` | `DSTypography.bodyRegular24` |
| `Body/Regular/20` | `DSTypography.bodyRegular20` |
| `Body/Regular/16` | `DSTypography.bodyRegular16` |
| `Body/Regular/12` | `DSTypography.bodyRegular12` |
| `Caption/Medium/14` | `DSTypography.captionMedium14` |
| `Caption/Regular/14` | `DSTypography.captionRegular14` |

PostScript 이름은 지원 OS의 `/System/Library/Fonts/AppleSDGothicNeo.ttc`에서 확인한 `AppleSDGothicNeo-*` 이름을 사용한다.

```swift
Text("훈련 시작하기")
    .dsTextStyle(DSTypography.headingExtraBold24)
```

## 범용 Control

SwiftUI의 상태와 접근성을 유지하기 위해 화면에서는 기본 Control에 디자인 시스템 스타일을 적용한다.

```swift
Button("도면 생성", action: createFloorPlan)
    .buttonStyle(.dsPrimary)

TextField("훈련명", text: $name)
    .textFieldStyle(.dsDefault)
```

InstructorApp 전용 iPad 컴포넌트는 `InstructorApp/Components/Previews/InstructorComponentsPreview.swift`에서 현재 실사용 상태를 비교한다. Preview에는 실제 화면에서 사용 중인 앱 전용 컴포넌트만 포함하며, 사용처가 사라진 과거 Hi-Fi 컴포넌트는 문서 목적으로 유지하지 않는다.

Package에는 양쪽 앱에서 실제로 사용하는 `DSGuideToast`와 범용 Button·TextField 스타일만 둔다. 교관 앱에만 사용되는 Step Indicator, Segmented Control, Labeled Slider, Selectable Pill은 `InstructorApp/Components/Controls`가 소유한다. 사용처가 없던 Status Badge와 Floating Banner는 제거했다.

### Control variant

Figma의 기기별 이름을 Package API에 노출하지 않고 시각적 역할을 `Size`와 `Type`으로 표현한다.

| Figma | Swift |
| --- | --- |
| Circular Button / Size=Regular | `.buttonStyle(.dsCircular(size: .regular))` |
| Circular Button / Size=Compact | `.buttonStyle(.dsCircular(size: .compact))` |
| Text Field / Focused | `.textFieldStyle(.ds(isFocused: focusedField))` |
| Guide Toast / Type=Regular | `DSGuideToast(message, type: .regular)` |
| Guide Toast / Type=Compact | `DSGuideToast(message, type: .compact)` |
| Guide Toast / Type=Card | `DSGuideToast(message, type: .card)` |

원형 버튼의 action과 화면 전환은 사용하는 화면이 소유한다. `DSCircularButtonStyle`은 외형과 상태 표현만 담당한다.

Text Field의 Focused 상태는 `@FocusState` 값을 `DSTextFieldStyle`에 함께 전달한다. Focused 테두리와 cursor는 `Gray/50`을 사용하며, Error와 Focused가 동시에 참이면 Error 표현을 우선한다.

입력 외형의 기본값은 `.outlined`다. `.ds(isFocused: focusedField, appearance: .filled)`는 값의 입력 여부와 관계없이 테두리 없는 면 형태를 사용하며, Regular 16pt와 좌우 16pt 패딩을 적용한다. Filled의 포커스는 흰색 커서로 표시하고 오류 상태에서는 오류 테두리를 표시한다.

기본 Primary 비활성 배경은 Gray/600이며, 화면 시안에서 다른 배경이 필요한 경우 `.dsPrimary(disabledBackground:)`로 선택한다. 원형 버튼은 `.dsCircular(size: .compact, showsBorder: true)`로 Gray/600 테두리를 선택할 수 있다.

`DSGuideToast`는 문구를 외부에서 받고 Store와 앱 도메인에 의존하지 않는다. Compact와 Card는 최대 두 줄까지 표시한다.

`horizontalPadding`은 타입 기본 패딩을 재정의한다. `fillsWidth: true`인 Compact는 부모가 제안한 너비를 채우며 최소 높이 48pt를 유지한다. 옵션을 생략한 기존 호출은 타입 기본값을 유지한다.

## 변경 원칙

1. Figma Foundation과 Package Foundation의 차이를 먼저 확인한다.
2. 양쪽 앱에서 같은 역할과 상호작용으로 반복되는 API만 Package에 추가한다.
3. 앱 전용 표현은 해당 앱에 두되 Package Foundation을 조합한다.
4. 원시 색상값과 폰트 선언은 화면에 직접 작성하지 않는다.
5. 토큰 변경 시 Package 테스트와 InstructorApp·MemberApp 빌드를 함께 검증한다.
6. 색상·타이포그래피·Control 외형이 달라지는 변경은 양쪽 앱의 주요 화면을 시뮬레이터에서 순회한다. AR·카메라처럼 시뮬레이터에서 확인할 수 없는 경로는 실기기 검증 대상으로 기록한다.
