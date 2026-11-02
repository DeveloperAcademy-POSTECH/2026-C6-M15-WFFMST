# Issue #142 훈련 중 화면 하이파이 사전 정의

## 목적과 기준

Issue #142 구현 전에 팀 준비에서 훈련 중 화면으로의 전환, 경과 시간 표시, 훈련 종료 확인의 시각 규칙을 고정한다.

- 기준 캔버스: iPad landscape `1366 × 1024`
- 훈련 중: [Figma `3009:1776`](https://www.figma.com/design/3tndfCqfeh1Z1dLRXu2qXk/?node-id=3009-1776)
- 종료 확인: [Figma `3009:1782`](https://www.figma.com/design/3tndfCqfeh1Z1dLRXu2qXk/?node-id=3009-1782)
- 상태 전이: `TeamReadinessView`에서 훈련 시작 저장이 성공하면 `trainingInProgress`, 종료 저장이 성공하면 `resultsPreparation`

Figma의 절대 좌표는 1366 × 1024 기준 검수값이다. SwiftUI 구현은 overlay와 Stack을 사용해 화면 크기가 달라져도 타이머를 화면 정중앙에 유지한다.

## 요소별 margin, padding, gap

| 요소 | 기준 위치·크기 | margin / padding / gap |
| --- | --- | --- |
| 화면 | `1366 × 1024` | safe area 밖까지 배경 확장 |
| `훈련 기록 중` | leading `40`, top `40` | 별도 내부 padding 없음 |
| `훈련 종료` | trailing `40`, top `40`, `180 × 55` | horizontal padding `20`, vertical padding `12`, radius full |
| 중앙 타이머 묶음 | 화면 가로·세로 중앙 | 기록점과 시간 gap `32` |
| 기록점 | `28 × 28` | 원형, 별도 padding 없음 |
| 경과 시간 | 내용 크기, 한 줄 | monospaced digit, 별도 padding 없음 |
| 보조 상태 | leading/trailing `40`, bottom `40` | 상태 내부 gap `16`, 정상 상태에서는 미표시 |

Figma 원본의 기록점은 `x=582, y=498`, 시간은 `x=642, y=490`이므로 두 요소 사이 gap은 `32pt`이다. 종료 버튼은 `x=1146, y=40`이고 화면 오른쪽 여백은 `40pt`이다.

디자인 시스템의 공통 control height는 `56pt`지만 이 프레임의 종료 버튼은 `55pt`로 명시되어 있다. Issue #142 화면에서는 Figma 기준 `55pt`를 사용한다.

## color

화면 코드에 원시 hex를 직접 쓰지 않고 `CQBDesignSystem` 또는 `InstructorColor`의 의미 토큰을 사용한다.

| 역할 | Figma 값 | 코드 토큰 |
| --- | --- | --- |
| 앱 배경 | Gray/900 `#0D0D0E` | `DSColor.backgroundPrimary` |
| 제목·시간 | Gray/50 `#FAFAFA` | `DSColor.contentPrimary` |
| 기록점 | Red/400 `#D63131` | `InstructorColor.trainingRecordingIndicator` → `DSPalette.Red.r400` |
| 종료 버튼 기본 | Main/500 `#FFD900` | `DSColor.actionPrimary` |
| 종료 버튼 pressed | Main/600 `#CCAE00` | `DSColor.actionPrimaryPressed` |
| 종료 버튼 글자 | Gray/900 `#0D0D0E` | `DSColor.contentInverse` |
| alert dim | black 45% | SwiftUI 시스템 `.alert`가 제공 |

## typography

Figma의 Apple SD Gothic Neo 스타일은 `DSTypography`와 `dsTextStyle`로 적용한다.

| 요소 | Figma 스타일 | 코드 스타일 |
| --- | --- | --- |
| `훈련 기록 중` | Bold 36, line height 100%, tracking 1.25 | `headingBold36` |
| 경과 시간 | Bold 36, line height 100%, tracking 1.25 | `headingBold36` + `.monospacedDigit()` |
| `훈련 종료` | Bold 20, line height 30, tracking 0 | `headingBold20` |
| 시스템 alert | 시스템 title/message/action | SwiftUI `.alert` 기본 타이포그래피 |

경과 시간은 제품 요구에 따라 `mm:ss`로 표시한다. 60분을 넘으면 분을 0으로 되돌리지 않고 `62:03`처럼 누적 분으로 표시한다. 서버 시작 시각을 아직 받지 못한 동안에는 같은 자리를 유지하는 `--:--`를 표시한다.

## 상태와 상호작용

- 팀 준비 화면의 시작 요청이 서버에 `running`으로 저장된 뒤에만 훈련 중 화면으로 이동한다.
- 타이머는 로컬 버튼 시각이 아니라 서버에서 다시 받은 `Session.startedAt`을 기준으로 1초마다 갱신한다.
- `훈련 종료`를 누르면 시스템 alert를 표시한다.
  - 제목: `훈련을 종료하시겠습니까?`
  - 메시지: `훈련이 종료되면 AAR 화면으로 넘어갑니다.`
  - 확인: `확인`, `store.finishTraining()` 호출
  - 취소: `취소`, 상태 변경 없음
- 종료 저장 중에는 중복 입력을 막고 버튼에 진행 상태를 표시한다.
- 종료 저장이 성공하면 기존 흐름대로 기록 결과 준비 후 AAR로 이어진다.
- 종료 실패 또는 세션 구독 오류는 훈련 중 화면과 타이머를 유지한다. 재연결 가능한 오류는 하단 보조 상태에서 다시 연결할 수 있다.
- alert는 Figma의 glass 표면을 직접 그리지 않고 SwiftUI `.alert`를 사용해 iPadOS 외형, 키보드 탐색, VoiceOver를 유지한다.

## 검증 체크리스트

- 1366 × 1024에서 제목과 종료 버튼의 top/side margin이 각각 40pt이다.
- 기록점과 `mm:ss`가 하나의 묶음으로 화면 정중앙에 있고 gap이 32pt이다.
- 서버 시작 시각 수신 전 `--:--`, 수신 후 1초 단위 경과 시간이 표시된다.
- 종료 alert의 확인은 종료 요청을 한 번만 보내고, 취소는 훈련 화면을 유지한다.
- 종료 실패 시 타이머가 유지되고 다시 종료할 수 있다.
- 세션 구독 실패 시 다시 연결할 수 있다.
- 종료 성공 후 결과 준비를 거쳐 AAR로 이동한다.
- InstructorApp 타깃과 훈련 타이머 테스트가 통과한다.
