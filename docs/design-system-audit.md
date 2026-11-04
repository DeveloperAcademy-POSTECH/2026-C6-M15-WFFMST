# 디자인 시스템 감사 기록

## 목적

Issue #180에서 Figma 정의와 실구현의 차이, `CQBDesignSystem`의 활용도, 앱별 컴포넌트 소유권을 순서대로 확인했다. 이 문서는 2026-11-03 기준의 판단 근거이며, 새로운 차이는 최신 Figma 노드와 실제 사용처를 함께 확인해 갱신한다.

## Foundation 비교

| 영역 | 확인 결과 | 조치 |
| --- | --- | --- |
| Color | Palette와 semantic color는 실제 Figma fill과 일치한다. `Primary/0.5`, `Red/0.5`, `Blue/0.5`의 화면 표기 hex는 실제 fill과 1단계 차이가 있다. | 코드는 실제 fill을 기준으로 유지한다. Figma 표기 문자열은 디자인 문서 정리 대상으로 남긴다. |
| Typography | 최신 Typography 영역에는 12개 스타일이 보이고 코드의 17개 중 나머지 5개도 제품 화면에서 사용 중이다. iOS 런타임에는 Figma가 지정한 Apple SD Gothic Neo ExtraBold face가 없어 custom font 지정 시 Regular로 fallback된다. | 공통 17개는 유지하고, `Heading/ExtraBold/24`는 시스템 Black으로 한국어 최굵기 face를 선택한다. 교관 앱에만 필요한 64 Bold·16 Medium·14 Bold는 앱 토큰으로 분리했다. |
| Effects | Button shadow는 일치했으나 Floating shadow의 코드 blur가 10, Figma가 24였다. | `dsFloatingShadow()`의 blur를 24로 수정했다. |
| Radius | 8, 12, 16, 999가 코드와 일치한다. InstructorApp에 토큰에 없는 4pt 컨테이너가 2곳 남아 있었다. | AAR 위치정보 없음 패널과 도면 처리 상태 패널을 가장 작은 컨테이너 토큰인 `DSRadius.small`(8pt)로 통일했다. |
| Spacing | Figma의 80이 코드에 없었다. | `DSSpacing.s80`을 추가하고 테스트에 포함했다. |
| Component size | Figma에는 iPad 55pt, iPhone 60pt 등 컴포넌트별 높이가 있다. Package 기본값은 Regular 56pt, Compact 44pt다. | 화면별 Figma variant와 Package의 범용 size는 목적이 다르므로 일괄 변경하지 않는다. 정확한 높이가 필요한 화면은 호출부 layout 또는 후속 variant로 명시한다. |

## Package 활용도

정적 검색으로 프로덕션 Swift 호출을 집계했다. 숫자는 리팩터링 전 기준이며 Preview와 테스트는 제외했다.

| API | InstructorApp | MemberApp | 판단 |
| --- | ---: | ---: | --- |
| Semantic `DSColor` | 150 | 51 | Package 유지 |
| `DSTypography` | 76 | 21 | Package 유지 |
| `DSSpacing` | 132 | 76 | Package 유지 |
| `DSRadius` | 18 | 4 | Package 유지 |
| Primary Button style | 11 | 2 | Package 유지 |
| Secondary Button style | 7 | 3 | Package 유지 |
| Circular Button style | 1 | 1 | Package 유지 |
| TextField style | 1 | 3 | Package 유지 |
| `DSGuideToast` | 4 | 1 | Package 유지 |
| Step Indicator | 4 | 0 | InstructorApp으로 이동 |
| Segmented Control | 1 | 0 | InstructorApp으로 이동 |
| Labeled Slider | 3 | 0 | InstructorApp으로 이동 |
| Selectable Pill | 1 | 0 | InstructorApp으로 이동 |
| Status Badge / Floating Banner | 0 | 0 | 제거 |

## 앱 간 중복 컴포넌트 검토

두 앱의 `Components`를 이름과 구현 계약으로 비교했다. 이름이 겹치는 항목은 있지만 현재 Package로 승격할 동일 컴포넌트는 확인되지 않았다.

| 후보 | 차이 | 판단 |
| --- | --- | --- |
| `ActionButton` | Instructor는 tone·density·아이콘·고정 폭 variant를 제공하고, Member는 화면 너비를 채우는 Primary action wrapper다. | 이름만 같고 API와 시각적 역할이 달라 앱별 유지 |
| Text Field wrapper | Instructor의 wrapper는 1차 Hi-Fi Preview에서만 사용됐고, Member는 실제 화면에서 focus를 전달하는 `DSTextFieldStyle` adapter를 사용한다. | Instructor wrapper 제거, Member adapter 유지 |
| Back Button | 각 앱의 navigation action과 화면 규칙에 연결된다. | 앱 흐름 컴포넌트로 유지 |
| Preview 계열 | Floor plan, camera, route처럼 표시하는 데이터와 interaction이 다르다. | 도메인 컴포넌트로 유지 |

공통화 판단은 이름이나 비슷한 모양이 아니라 양쪽 앱에서 같은 입력, 상태, interaction을 실제로 요구하는지에 따른다. 현재 공통 부분은 이미 Package의 Button·TextField style과 Foundation 토큰으로 추출되어 있다.

## 정리 결과

- 레거시 `DSColor`, `DSTypography`, `DSFonts` API와 관련 Asset Catalog를 제거했다.
- 사용하지 않던 Noto Sans KR 번들 리소스를 제거했다.
- 교관 전용 컨트롤은 `InstructorApp/Components/Controls`로 이동했다.
- 1차 Hi-Fi Preview에서만 남아 있던 `InstructorControlsPreview`, Dropdown·단일/다중 선택 묶음, `InstructorTextField`를 제거했다.
- 실제 사용처가 없던 `FloorPlanPreview`와 Preview 전용 team color를 제거했다.
- `FloorPlanCreateView`에서 최신 단계별 화면 뒤에 남아 있던 1차 Hi-Fi `creationWorkspace`,
  구형 header·preview·side panel과 도달 불가능한 `파일 변경` 경로를 제거했다.
- Figma Radius에 정의되지 않은 4pt를 쓰던 AAR 위치정보 없음 패널과 도면 처리 상태 패널을
  `DSRadius.small`로 전환했다.
- 현재 실사용 중인 Instructor 컴포넌트만 모은 1366×1024 iPad Preview를 새로 추가했다.
- 공통 Package는 palette, semantic color, typography, spacing, radius, effect, 범용 Button·TextField style, Guide Toast만 소유한다.
- 앱 전용 색상과 typography 예외는 각 앱의 지정 토큰 파일에서만 관리한다.

## 시뮬레이터 검증

2026-11-03에 iPad Pro 13-inch (M5) / iPadOS 27.0과 iPhone 18 Pro / iOS 27.0에서 Debug 빌드를 설치해 직접 순회했다.

### InstructorApp

- 홈과 데모 모드
- 도면 목록, 새 도면 추가, 도면 설정 1단계의 Step Indicator와 입력란
- 훈련 세션 생성과 도면 선택
- 대원 준비 상태, 훈련 시작·종료
- AAR 도면, 대원 선택, 영상 슬롯, timeline

위 경로에서 레거시 폰트 또는 색상 Asset 누락, 화면 진입 crash, 이동한 Instructor 전용 Control의 표시 문제는 확인되지 않았다. 실제 도면 파일 가져오기 이후의 정렬·편집 단계는 테스트 파일을 선택하지 않아 이번 순회에 포함하지 않았다.

### MemberApp

- PIN·대원명 참가 화면
- 로컬 데모 진입
- 도면의 출발 위치와 바라보는 방향 선택
- AR 추적 준비 화면

시뮬레이터는 AR 동선 추적을 지원하지 않으므로 녹화 시작, 저장, 보정·업로드 완료 화면까지 진행할 수 없었다. 해당 경로는 실기기 검증 대상으로 남긴다.

## 재검사 방법

1. Figma의 Color, 실사용 Color, Typography, Components, Effects, Radius, Spacing 노드를 확인한다.
2. `CQBDesignSystem` 공개 API를 InstructorApp과 MemberApp에서 각각 검색한다.
3. 한 앱에서만 쓰는 컴포넌트와 사용처가 없는 컴포넌트를 구분한다.
4. 레거시 심볼과 번들 리소스 참조가 0인지 확인한다.
5. `swift test --package-path CQB/Packages/CQBCore`와 양쪽 앱 빌드를 실행한다.
6. 양쪽 앱의 주요 화면을 시뮬레이터에서 순회하고, 기기 기능 때문에 제외한 경로를 기록한다.
