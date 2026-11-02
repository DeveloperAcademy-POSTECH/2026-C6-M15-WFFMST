# Issue #141 도면 관리 하이파이 사전 정의

## 목적과 기준

Issue #141의 구현 전에 도면 목록, 상세 조회, 삭제 확인, 수정 진입의 시각 규칙과 상태 전이를 고정한다.

- 기준 캔버스: iPad landscape `1366 × 1024`
- InstructorApp은 iPad landscape left/right만 지원하며, 회전 방향을 보장하기 위해 full screen으로 실행한다.
- 목록: [Figma `2714:4892`](https://www.figma.com/design/3tndfCqfeh1Z1dLRXu2qXk/?node-id=2714-4892)
- 상세: [Figma `2714:5546`](https://www.figma.com/design/3tndfCqfeh1Z1dLRXu2qXk/?node-id=2714-5546)
- 삭제 확인: [Figma `2714:5526`](https://www.figma.com/design/3tndfCqfeh1Z1dLRXu2qXk/?node-id=2714-5526)
- 기능 기준: Issue #113의 상세·마스크 수정·삭제와 Issue #116의 목록 미리보기
- 디자인 시스템 기준: Issue #128에서 추가한 의미 색상, Figma 타이포그래피, spacing/radius/control 토큰

Figma의 절대 좌표는 1366 × 1024 기준 검수값이다. SwiftUI 구현은 Stack, 유연한 frame, safe area를 사용하고 화면 전체를 절대 좌표로 구성하지 않는다.

## 공통 토큰

화면 코드에 원시 색상값을 직접 쓰지 않고 `CQBDesignSystem`의 의미 토큰을 사용한다.

| 역할 | Figma 값 | 코드 토큰 |
| --- | --- | --- |
| 앱 배경 | `#0D0D0E` | `DSColor.backgroundPrimary` |
| 기본 패널·미선택 항목 | `#1E1E24` | `DSColor.surfacePrimary` |
| 미리보기 패널 | `#2D2D31` | `DSColor.surfaceSecondary` |
| 선택 항목 | `#40444B` | `DSColor.surfaceSelected` |
| 기본 테두리 | `#34363A` | `DSColor.borderPrimary` |
| 기본 텍스트 | `#FAFAFA` | `DSColor.contentPrimary` |
| 보조 텍스트 | `#B7B8BA` | `DSColor.contentSecondary` |
| 비활성 선택 아이콘·미리보기 버튼 테두리 | `#9A9B9C` | 앱 의미 토큰 → `DSPalette.Gray.g200` |
| 주 행동 배경 | `#FFD900` | `DSColor.actionPrimary` |
| 주 행동 테두리·선택 아이콘 | `#FFE866` | `DSColor.borderEmphasized` |
| 보조 행동 배경 | `#7C7D7F` | `DSColor.actionSecondary` |
| 마스크·오류 | `#CC0000` | `DSColor.statusError` |
| 삭제 alert dim | `#070707`, 45% | 시스템 alert dim 또는 동등한 overlay |

`#9A9B9C`는 현재 Package에 맞는 content 의미 토큰이 없다. Package API를 임의로 확장하지 않고 `InstructorColor.floorPlanSelectionIdle`과 `InstructorColor.floorPlanPreviewActionBorder`처럼 화면 역할이 드러나는 앱 토큰으로 `DSPalette.Gray.g200`을 감싼다.

Figma의 Apple SD Gothic Neo 스타일은 Issue #128의 `DSTypography`와 `dsTextStyle`로 적용한다.

| 용도 | 크기·굵기·행간 | 코드 스타일 |
| --- | --- | --- |
| 목록 화면 제목 | 36 Bold, tracking 1.25 | `headingBold36` |
| 상세 도면명 | 32 Bold | `headingBold32` |
| 목록 항목명 | 24 SemiBold | `headingSemiBold24` |
| 상세 수정 시각 | 24 Regular | `bodyRegular24` |
| 섹션 제목 | 20 Bold, line height 30 | `headingBold20` |
| 버튼·필드 라벨 | 20 SemiBold, line height 30 | `headingSemiBold20` |
| 본문·생성일 | 16 Regular | `bodyRegular16` |
| 상단 경로 라벨 | 16 Regular | `bodyRegular16` |
| 시스템 alert | SF Pro 17 | SwiftUI `.alert`의 시스템 스타일 |

공통 간격은 `DSSpacing`, 모서리는 `DSRadius`, 컨트롤 높이는 `DSSize`를 우선 사용한다. Figma에만 있는 `40`, `60`도 기존 토큰에 포함되어 있다.

## 도면 목록

### 화면 골격

| 요소 | 기준 위치·크기 | 내부 규칙 |
| --- | --- | --- |
| 화면 | `1366 × 1024` | 배경 `backgroundPrimary` |
| 뒤로가기 | leading 40, top 40, `56 × 56` | `DSCircularButtonStyle(size: .regular)`, radius full, button shadow |
| 경로 라벨 | 뒤로가기 내부 기준 x 64, 세로 중앙 | `훈련 도면`, body 16 |
| 새 도면 추가 | trailing 40, top 40, `180 × 56` | primary, radius full, horizontal padding 20 |
| 화면 제목 | leading 40, top 195, height 36 | `도면 관리`, heading 36 |
| 콘텐츠 행 | leading/trailing 40, top 256, bottom 60 | 좌우 gap 24 |
| 목록 패널 | `465 × 708` | radius 16, padding 12, `surfacePrimary`, border `surfaceSecondary` 1pt |
| 미리보기 패널 | 남은 폭 `797 × 708` | radius 16, clip, `surfaceSecondary` |

1366pt보다 좁아질 때 목록 패널은 465pt를 우선 보존하고 미리보기 패널이 남은 폭을 사용한다. 두 패널의 gap은 24pt로 유지한다. 콘텐츠 폭이 두 패널의 최소 폭을 수용하지 못하면 목록 패널을 최소 360pt까지 줄이고 텍스트를 한 줄 말줄임한다.

### 목록 패널

- 패널 내부 상단 제목은 `등록된 도면`이며 높이 30pt, `headingBold20`을 사용한다.
- 제목과 목록 사이 간격은 40pt이다.
- 목록 viewport는 기준 `439 × 605`이고 세로 스크롤한다.
- 항목 크기는 `439 × 95`, 항목 간 gap은 4pt, radius는 16pt이다.
- 항목의 horizontal padding은 leading 22pt, trailing 20pt이다.
- 선택 아이콘과 텍스트 묶음의 gap은 32pt이다.
- 선택 아이콘은 `24 × 24`이다. 선택은 `borderEmphasized`, 미선택은 앱 토큰 `floorPlanSelectionIdle`을 사용한다.
- 텍스트 묶음은 vertical gap 8pt이다.
- 항목명은 `headingSemiBold24`, 생성일은 `bodyRegular16`이다.
- 선택 항목 배경은 `surfaceSelected`, 텍스트는 `contentPrimary`이다.
- 미선택 항목 배경은 `surfacePrimary`, 텍스트는 `contentSecondary`이다.

목록 로드가 끝나고 항목이 하나 이상이면 첫 항목을 기본 선택해 미리보기를 즉시 요청한다. 사용자가 항목을 누르면 선택과 미리보기만 바뀌고, 상세 진입은 미리보기 패널의 `상세보기 및 편집`으로 분리한다. 삭제 뒤에는 삭제된 위치의 다음 항목, 다음 항목이 없으면 이전 항목을 선택한다.

Figma 좌측 바깥의 빨간 `40` 표시는 margin 주석이며 앱 UI에 포함하지 않는다.

### 미리보기 패널

- 섹션 라벨 `도면 미리보기`는 leading/top 20pt, `headingBold20`, `DSColor.surfaceSelected`를 사용한다. 밝은 이미지 위에서도 대비가 부족하면 scrim을 추가한다.
- `상세보기 및 편집`은 trailing 12pt, top 12pt, `180 × 56`, radius full이다.
- 버튼 배경은 `surfacePrimary`, border는 앱 토큰 `floorPlanPreviewActionBorder` 1pt, 텍스트는 `contentPrimary`이다.
- 목록 미리보기에는 도면 원본 이미지만 표시하고 최종 마스크는 표시하거나 렌더링하지 않는다.
- Figma 기준 이미지는 패널을 채우고 바깥을 clip한다. 전체 도면 확인과 pan/zoom은 상세 화면의 책임으로 둔다.
- 선택을 빠르게 바꾸면 이전 요청을 취소하고 마지막 선택 결과만 표시한다.

상태별 표현은 다음과 같다.

| 상태 | 표현 |
| --- | --- |
| 목록 loading | 두 패널 영역에 progress와 `등록한 도면을 불러오는 중입니다.` |
| 목록 empty | 패널 전체에 `등록된 도면이 없습니다.`와 새 도면 추가 행동 유지 |
| 미리보기 loading | 패널 크기를 유지한 채 progress overlay, 상세 버튼 disabled |
| 미리보기 failed | 오류 문구와 `다시 불러오기`, 현재 선택 유지 |
| loaded | 도면 원본 이미지, 상세 버튼 enabled |

## 도면 상세

### 화면 골격

| 요소 | 기준 위치·크기 | 내부 규칙 |
| --- | --- | --- |
| 왼쪽 미리보기 영역 | `962 × 1024` | 배경 `backgroundPrimary` |
| 오른쪽 정보 패널 | trailing 고정 `404 × 1024` | 배경 `surfacePrimary` |
| 뒤로가기 | leading/top 40, `56 × 56` | 목록과 동일 |
| 도면 canvas | 기준 `409 × 864`, top 77 | 왼쪽 영역 중앙, aspect fit, pan/zoom 허용 |
| 정보 패널 padding | horizontal 20, top 40, bottom 30 | leading 정렬 |
| 삭제 | `132 × 56` | secondary, radius full |
| 도면 수정 | `220 × 56` | primary, radius full |
| 버튼 gap | 12 | 하단 고정 |

도면 canvas는 원본 이미지 위에 최종 마스크를 겹친다. 마스크의 이동 불가 외곽은 `statusError` 4pt, 기준점은 지름 20pt로 표시한다. 실제 마스크가 raster라면 같은 색과 인지 강도를 유지하되 임의의 벡터 외곽을 새 데이터로 저장하지 않는다.

정보 패널의 도면명은 `headingBold32`이다. `최종 수정 시간`은 도면명 아래 60pt 간격으로 배치하고 `headingSemiBold20`을 사용한다. 값은 4pt 아래에 `bodyRegular24`로 표시하며 형식은 `yyyy.MM.dd _ HH:mm`으로 고정한다.

상세 loading 중에는 정보는 유지하고 canvas에 progress를 표시한다. 실패 시 같은 화면에서 오류와 재시도를 제공한다. 로드가 완료되기 전에는 `도면 수정`을 비활성화한다. 삭제는 로컬 카탈로그 항목을 대상으로 하므로 상세 파일 로드 실패와 무관하게 실행할 수 있다.

## 삭제 확인과 완료

SwiftUI `.alert`를 사용해 iPad의 시스템 접근성, 키보드 탐색, VoiceOver 행동을 유지한다. Figma의 glass 재질을 별도 커스텀 modal로 복제하지 않는다.

- 제목: `‘{도면명}’ 도면을 삭제하시겠습니까?`
- 메시지: `삭제한 도면은 되돌릴 수 없습니다.`
- destructive action: `도면 삭제`
- cancel action: `취소`
- cancel이 기본 안전 행동이다.
- 확인 전에는 데이터가 바뀌지 않는다.
- 성공하면 목록에서 제거하고 목록 화면으로 돌아간다.
- 실패하면 상세 화면을 유지하고 재시도 가능한 오류를 표시한다.
- 로컬 카탈로그에서만 제거하며 기존 세션이 참조하는 Storage 파일은 즉시 삭제하지 않는다.

Figma 기준 alert는 `300 × 240`, padding 14, 제목·메시지 영역 padding top/leading/trailing 8과 bottom 24, 제목·메시지 gap 10, action gap 8, action 높이 48이다. 이 수치는 시스템 alert 검수 참고값이며 OS가 결정하는 실제 geometry를 강제하지 않는다.

## 수정 범위 제안과 Issue 경계

`도면 수정`은 기존 마스크 편집 화면으로 이동한다. Issue #113과 #141의 현재 범위로 확정된 동작은 다음과 같다.

- 지원: 이동 불가/가능 영역 마스크 수정
- 읽기 전용: 도면 이름, 원본 이미지, 축척
- 미지원: 원본 파일 교체, WorldMap 재스캔, 축척 재설정

사용자가 수정에 진입할 때 도면 이름도 함께 바꾸고 싶어 할 가능성이 높으므로 이름 변경 지원을 권장한다. 다만 Issue #113은 이름 변경을 명시적으로 제외했고 Issue #141은 하이파이 전환 범위이므로, 구현 전에 Issue #141의 범위를 갱신하거나 별도 기능 Issue로 분리한다. 범위가 갱신되기 전에는 이름 field를 #141 구현에 섞지 않는다.

이름 변경을 채택한다면 다음 규칙을 사용한다.

- 도면 이름은 공통 `FloorPlanManifest`가 아니라 InstructorApp의 로컬 카탈로그 필드이므로 공통 데이터 계약을 바꾸지 않는다.
- 수정 화면 상단에 현재 이름이 채워진 text field를 제공한다.
- 앞뒤 공백을 제거한 값이 비어 있으면 저장을 막는다.
- 최대 길이 등 새 제품 정책은 임의로 추가하지 않는다.

저장 동작은 변경 종류를 구분한다.

- 이름만 변경: 로컬 카탈로그의 이름과 `updatedAt`만 갱신하고 Storage 파일을 새로 업로드하지 않는다.
- 마스크 변경: 기존 정책대로 새 `floorPlanID`의 파일 묶음을 업로드하고 로컬 카탈로그의 reference와 `updatedAt`을 교체한다.
- 이름과 마스크 변경: 새 마스크와 WorldMap 재결합 업로드가 성공한 뒤 이름과 reference를 함께 반영한다. 실패하면 기존 이름과 reference를 유지한다.

WorldMap은 수정 화면에서 다시 스캔하지 않는다. 기존 구현은 마스크 수정으로 새 `FloorPlanReference`가 생기면 기존 WorldMap 파일을 내려받아 새 도면 reference에 rebind하고 새 `WorldMapReference`로 업로드한다. 이 재결합까지 성공해야 로컬 카탈로그를 갱신한다. 이름만 바꾸는 경우에는 도면 reference가 유지되므로 WorldMap 다운로드·업로드도 하지 않는다.

## 접근성·반응형 규칙

- 버튼의 최소 hit target은 `44 × 44`, 주요 버튼은 56pt 높이를 유지한다.
- 선택 항목에는 `.isSelected` trait와 도면명 접근성 라벨을 제공한다.
- 목록 미리보기 이미지는 하나의 접근성 요소로 묶고 `선택한 도면 미리보기`로 설명한다.
- 제목과 버튼 텍스트는 Dynamic Type에서 잘리지 않게 하고, 도면명·생성일만 한 줄 말줄임을 허용한다.
- 화면 폭이 줄어도 오른쪽 상세 패널 404pt와 주요 행동 버튼의 높이는 유지한다.
- 화면은 landscape left/right에서만 실행하며 portrait와 iPad 멀티태스킹은 지원하지 않는다.
- loading overlay는 기존 내용을 갑자기 제거하지 않아 선택 변경 시 화면 점프를 만들지 않는다.

## 구현 연결 지점

- `FloorPlanListView`: 두 패널 layout, 기본 선택, 목록 item, 미리보기 상태와 상세 행동
- `FloorPlanDetailView`: 962/404 layout, 상세 metadata, 하단 행동, 시스템 alert
- `FloorPlanCreateView`: 읽기 전용 범위 표시. 이름 변경이 별도 승인되면 수정 모드 이름 field 추가
- `InstructorStore`: 삭제 후 인접 선택. 이름 변경이 별도 승인되면 이름-only 저장과 마스크 저장 시 이름 반영
- `FloorPlanDraftStore`: 이름 변경이 별도 승인되면 수정 초안 이름과 dirty state
- `InstructorColor` 또는 화면: Issue #128의 Package 의미 토큰을 직접 매핑하고 원시 hex 중복 금지

공통 모델, Storage 경로, 파일 형식, 공통 enum은 변경하지 않는다. 필요해지면 Issue #141 구현에 섞지 않고 별도 데이터 계약 Issue로 분리한다.

## 검증 체크리스트

- 1366 × 1024에서 목록과 상세의 기준 좌표·크기·간격이 맞는다.
- 기기를 portrait로 회전해도 InstructorApp이 landscape를 유지한다.
- 항목 0개, 1개, 6개 이상에서 empty·기본 선택·스크롤이 동작한다.
- 빠른 선택 변경 뒤 마지막 도면만 미리보기에 남는다.
- 목록·미리보기·상세 loading/failure/retry가 구분된다.
- 상세에서 삭제 취소 시 아무 상태도 바뀌지 않는다.
- 삭제 성공 후 목록과 세션 도면 선택지에서 사라지고 인접 항목이 선택된다.
- 삭제 실패 시 상세 화면과 기존 항목이 유지된다.
- 이름 변경 범위가 승인되면 이름-only 수정은 Storage 업로드 없이 유지되고 앱 재실행 후 복원된다.
- 마스크 수정은 새 reference로 저장되고 기존 세션 reference는 계속 유효하다.
- WorldMap 스캔 UI가 수정 흐름에 노출되지 않고 기존 WorldMap은 새 도면 reference에 재결합된다.
- VoiceOver 라벨, 선택 trait, Dynamic Type을 확인한다.
- InstructorApp 관련 타깃 빌드와 도면 관리 관련 테스트가 통과한다.
