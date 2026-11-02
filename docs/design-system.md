# CQB 디자인 시스템

## 기준

CQB의 신규 UI는 Figma의 `디자인 시스템` 섹션을 단일 기준으로 사용한다.

- Figma: <https://www.figma.com/design/3tndfCqfeh1Z1dLRXu2qXk/%ED%92%8D%EB%A6%BC%ED%99%94%EC%82%B0%EC%9D%8C%EB%A2%B0?node-id=2832-1756>
- 구현 모듈: `CQBDesignSystem`

기존 `DSColor.background/main/area1/area2/area3`와 `DSTypography.h1/h2/h3/body` API는 화면 마이그레이션이 끝날 때까지 유지한다. 신규 코드는 아래의 새 API를 사용한다.

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
| `Spacing/4...60` | `DSSpacing.s4...s60` |
| `radius/sm` | `DSRadius.small` |
| `radius/md` | `DSRadius.medium` |
| `radius/lg` | `DSRadius.large` |
| `radius/full` | `DSRadius.full` |
| `Size/control-height` | `DSSize.controlHeight` |
| `Size/compact-control-height` | `DSSize.compactControlHeight` |
| `Shadow/Button` | `View.dsButtonShadow()` |
| `Shadow/Floating` | `View.dsFloatingShadow()` |

## 타이포그래피

Figma의 Apple SD Gothic Neo 17개 스타일을 `DSTypography`에 같은 계층으로 정의한다. 폰트뿐 아니라 Figma의 행간과 자간을 적용하려면 `dsTextStyle(_:)`을 사용한다.

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

`DSSegmentedControl`, `DSLabeledSlider`, `DSStepIndicator`, `DSStatusBadge`, `DSGuideToast`, `DSFloatingBanner`는 Store와 도메인 모델에 의존하지 않는다.

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

`DSGuideToast`는 문구를 외부에서 받고 Store와 앱 도메인에 의존하지 않는다. Compact와 Card는 최대 두 줄까지 표시한다. 기존 `DSFloatingBanner`는 호환성을 위해 유지하며 내부에서 `DSGuideToast(type: .regular)`에 위임한다. 신규 코드는 `DSGuideToast`를 사용하고 기존 화면의 일괄 마이그레이션과 `DSFloatingBanner` 제거는 별도 이슈에서 진행한다.

## 마이그레이션

1. 새 API를 기존 API와 병렬로 추가한다.
2. 화면 단위로 색상, typography, spacing, radius, effect를 함께 전환한다.
3. 저장소 전체의 레거시 사용처가 0인지 확인한다.
4. 별도 이슈와 PR에서 기존 토큰, 폰트, Asset을 제거한다.
