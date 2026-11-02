# Issue #126 이전 훈련 기록

교관이 훈련을 마친 뒤에도 지난 훈련을 다시 열어 AAR(동선·영상)을 볼 수 있게 한다. 지금은 AAR을 닫고 홈으로 돌아가면 지난 세션에 다시 들어갈 방법이 없다.

## 범위

만드는 것:

- 훈련 종료 시 기록을 iPad에 저장한다 (SwiftData).
- `이전 훈련 기록` 목록 화면: 최신순, 삭제
- 기록 삭제 시 그 세션의 서버 영상도 삭제
- 기록을 눌러 AAR 다시 열기
- 홈의 `이전 훈련 기록` 카드에 최근 기록 연결
- 데모 모드 샘플 기록

하지 않는 것:

- 서버에서 내 세션 목록 가져오기. 교관 앱은 익명 로그인이라 앱을 다시 설치하거나 다른 iPad를 쓰면 교관 ID가 바뀐다. 서버 목록 조회를 열어도 예전 세션을 내 것으로 찾을 수 없고 녹화도 읽을 수 없다. 교관 계정이 생긴 뒤에 다룬다.
- 서버 동선(보정 결과) 파일과 Firestore 세션·녹화 문서 삭제. 동선 삭제는 `TrackResultRepository`에 삭제가 없어 `CQBCore` 변경이 필요하고, 세션 문서는 삭제 규칙이 없다. 둘 다 크기가 작아 남겨 둔다.
- `CQBCore` 모델·Firebase 규칙 변경

완료 조건:

- 훈련을 끝내고 앱을 다시 실행해도 그 훈련이 목록에 최신순으로 보인다.
- 기록을 누르면 그 세션의 동선·영상 AAR이 열린다.
- 삭제하면 서버 영상이 지워지고, 목록에서 사라지며 재실행 후에도 나타나지 않는다.
- 에뮬레이터 시험 데이터로 `훈련 종료 → 목록 → AAR` 흐름을 확인했다.

## 현재 코드 (develop `65be618`)

화면이 들어갈 자리는 홈 하이파이 작업(#146)이 먼저 만들었다. 비어 있는 것은 기록 저장과 목록 화면이다.

| 이미 있는 것 | 위치 | 이번에 할 일 |
| --- | --- | --- |
| 화면 단계 `.trainingHistory`, 뒤로 가기 → 홈 | `InstructorPhase`, `InstructorStore.goBack()` | 그대로 사용 |
| 홈 `이전 훈련 기록` 카드, 모두보기 → `openTrainingHistory()` | `HomeView`의 `TrainingHistoryCard` | 실제 기록을 넣고 누르면 AAR로 연결 |
| 홈 카드 표시 모델 `HomeTrainingRecordSummary` | `HomeView.swift` | 저장한 기록에서 만든다. 지금은 항상 빈 배열 |
| 목록 자리 화면 `TrainingHistoryPlaceholderView` | `RootView` | 목록 화면으로 교체 |
| 세션 ID로 AAR 열기 (디버그 전용) | `AARStore.debugSnapshot`, `InstructorStore.openAARForDebug` | 정식 경로로 옮김 |
| 훈련 종료: 서버에 `ended` 저장 후 결과 준비로 | `InstructorStore.finishTraining()` | 성공 직후 기록 저장 |
| 도면 목록 SwiftData 저장 | `SwiftDataFloorPlanCatalogRepository`, `InstructorApp`의 `ModelContainer` | 같은 방식으로 기록 저장소 추가 |
| 데모 모드 (별도 Store·Repository) | `InstructorDemoScenario` | 샘플 기록 추가 |

이름이 비슷한 `TrainingRecordStore`는 현재 훈련의 녹화 업로드 진행을 보는 Store라 이번 기능과 무관하다. 새 타입은 `TrainingHistory`로 이름을 구분한다.

## 저장

훈련 하나당 기록 하나를 **훈련 종료(`ended` 서버 저장)가 성공한 직후** 저장한다. 목록은 기기 데이터만으로 그리고, AAR을 열 때만 서버에서 세션·대원·녹화를 받는다.

| 항목 | 형식 | 출처 | 쓰임 |
| --- | --- | --- | --- |
| 세션 ID | `UUID` (unique) | `currentSession.id` | AAR 열기, 중복 저장 방지 |
| 훈련명 | `String` | `currentSession.name` | 목록 제목 |
| 도면 참조 | `FloorPlanReference` (ID + 해시) | `currentSession.floorPlan` | 썸네일, AAR 도면 찾기 |
| 도면 이름 | `String` | 선택한 도면 | 설명 줄. 도면을 지워도 이름이 남도록 복사한다 |
| 대원 이름 | `[String]` (참가 순서) | `participants` | `강유키 등 16명` |
| 시작 시각 | `Date` | `trainingStartedAt` | 날짜·시각, 최신순 정렬 |
| 종료 시각 | `Date` | 종료 성공 시각 | 진행 시간 = 종료 − 시작 |

- 저장에 실패해도 훈련 흐름은 막지 않는다. 로그만 남기고 결과 준비 화면으로 넘어간다.
- 같은 세션 ID가 이미 있으면 덮어쓴다. 종료를 재시도해도 기록은 하나만 남는다.
- `ModelContainer`에 `StoredTrainingHistory` 모델을 추가한다. 모델을 더하기만 하므로 기존 도면 목록은 유지된다.

## 화면과 흐름

확정 Figma iPad 디자인([`Hi-Fi_ver4`](https://www.figma.com/design/3tndfCqfeh1Z1dLRXu2qXk/?node-id=2998-10104)의 [홈](https://www.figma.com/design/3tndfCqfeh1Z1dLRXu2qXk/?node-id=2998-10860), [이전 기록 목록](https://www.figma.com/design/3tndfCqfeh1Z1dLRXu2qXk/?node-id=2998-10764), [삭제 얼럿](https://www.figma.com/design/3tndfCqfeh1Z1dLRXu2qXk/?node-id=2998-10819))을 따른다. 새 화면은 목록 하나이고, 나머지는 기존 화면에 연결한다.

```text
훈련 종료 성공 ──저장──▶ SwiftData
                              │ 최신순
                              ▼
홈 카드 ──모두보기──▶ 기록 목록 ──기록 누름──▶ 세션·대원 불러오기 ──성공──▶ AAR
   └──────────────최근 기록 누름──────────────▶      │ 실패                     │ 닫기
                       │ 삭제                         ▼                          ▼
                       ▼                         실패 안내·다시 시도             홈
                  삭제 확인 얼럿 → 서버 영상 삭제 → 기기 목록에서 삭제
```

| 화면 | Figma | 표시 |
| --- | --- | --- |
| 홈 카드 | `iPad_홈_Hi-FI_ver1` | 직전 기록 큰 카드(`직전 강평 다시 보기`, 썸네일, 훈련명, 도면 이름, `2026.10.20_13:30`, `강유키 등 16명`) + 그다음 기록 전부(썸네일 없음, 카드 안에서 스크롤), `모두보기` |
| 기록 목록 | `이전 훈련 기록_이전 기록 목록` | 뒤로 가기, 제목 `이전 훈련 기록`, 줄마다 도면 썸네일, 훈련명, `훈련장 B · 강유키 등 16명 · 2026.10.20_13:30`, 진행 시간 `13:24`, `삭제`, 줄 사이 구분선 |
| 삭제 확인 | `이전 기록 삭제 얼럿` | `'훈련명' 기록을 삭제하시겠습니까?`, `삭제한 훈련 기록을 되돌릴 수 없습니다.`, `기록 삭제` / `취소` |

상태:

- 빈 목록: 홈 카드의 기존 문구(`아직 이전 훈련 기록이 없습니다`)를 목록 화면에도 쓴다. Figma에는 목록 빈 상태가 없다.
- 목록 불러오기 실패: 안내 문구와 다시 시도
- AAR 불러오는 중: 누른 기록 줄에 진행 표시, 다른 기록은 누를 수 없다.
- AAR 불러오기 실패: 안내 문구와 다시 시도. 목록에서 자동으로 지우지 않는다.

## 코드 구조

도면 목록(#73)과 같은 모양으로 만든다. 저장은 Repository, 목록 상태와 열기·삭제는 `InstructorStore`, 그리기는 View가 맡는다.

서버 영상 삭제는 기존 코드를 재사용한다. 세션의 녹화 목록(`RecordingRepository.observeRecordings`)에서 대원별 조각 수를 얻고 `VideoChunkRepository.deleteVideo`로 지운다. AAR을 떠날 때 영상을 지우던 `AARVideoLoader.finish`와 같은 경로이며, Storage 규칙은 세션 교관에게 녹화 삭제를 이미 허용한다. 기기 영상 캐시도 함께 지운다.

새 파일 (`CQB/InstructorApp/` 아래):

| 파일 | 내용 |
| --- | --- |
| `Models/TrainingHistoryRecord.swift` | 화면이 쓰는 기록 값. 진행 시간·`대원 등 N명` 계산 |
| `Services/Persistence/TrainingHistoryRepository.swift` | `fetchAll`, `save`, `delete(sessionID:)` 프로토콜 + 사용 불가·메모리 구현 |
| `Services/Persistence/SwiftDataTrainingHistoryRepository.swift` | `@Model StoredTrainingHistory` + SwiftData 구현 |
| `Features/TrainingHistory/TrainingHistoryView.swift` | 목록 화면과 삭제 확인 얼럿 |

바뀌는 파일:

| 파일 | 변경 |
| --- | --- |
| `Stores/InstructorStore.swift` | 기록 목록 상태, `loadTrainingHistory`·`openTrainingHistoryRecord`·`deleteTrainingHistoryRecord`, `finishTraining` 성공 시 저장, `openAARForDebug`를 정식 AAR 진입으로 |
| `Stores/AARStore.swift` | `debugSnapshot`을 `#if DEBUG` 밖의 세션 불러오기로. 기록에서 열 때 받아온 대원으로 선택 대원(`selectedParticipantIDs`)을 채워야 영상 요청이 시작된다 |
| `App/InstructorApp.swift`, `App/AppContainer.swift` | `ModelContainer`에 모델 추가, 저장소 주입. 디버그 진입은 정식 경로 재사용 |
| `App/RootView.swift` | 자리 화면을 `TrainingHistoryView`로 교체 |
| `Features/Home/HomeView.swift` | Store의 기록을 `HomeTrainingRecordSummary`로 바꿔 표시, 누르면 AAR |
| `Services/Demo/InstructorDemoScenario.swift` | 데모 샘플 기록 |

기록에서 연 AAR은 닫으면 `AAR 종료` 화면 없이 항상 홈으로 간다. 훈련 직후 AAR과 구분하기 위해 Store가 AAR을 기록에서 열었는지 기억한다.

## 임시 가정

PR에도 같은 내용을 적는다.

- 삭제는 서버 영상 삭제가 성공한 뒤 기기 목록에서 지운다. 실패하면(오프라인 등) 안내하고 목록에 남겨 다시 시도할 수 있게 한다. 영상이 이미 없으면 성공으로 본다.
- 기록에서 다시 보려면 영상이 남아 있어야 하므로, AAR을 떠날 때 영상을 지우는 원래 정책(#66에서 UT 동안 꺼 둠)은 다시 켜지 않는다. 영상은 기록을 삭제할 때 지운다.
- 썸네일은 그 훈련의 도면 이미지를 쓴다. 도면이 기기에 없으면 빈 썸네일을 표시한다. (홈 큰 카드의 Figma 사진은 예시 이미지로 본다. 훈련 사진은 저장하지 않는다.)
- 앱을 지우거나 다른 iPad를 쓰면 목록이 보이지 않는다.
- 이 기능 이전에 한 훈련은 목록에 나타나지 않는다.

## 결정이 필요한 것

- [x] AAR을 닫으면 어디로 가나: 기록에서 연 AAR은 `AAR 종료` 화면 없이 항상 홈으로 간다.
- [x] 홈 카드 개수: 개수를 자르지 않고 모든 기록을 보여준다. 직전 기록은 큰 카드, 나머지는 작은 카드로 카드 안에서 스크롤한다. 지금 홈 코드의 스크롤 구조를 그대로 쓴다.
- [x] 삭제 전 확인 창: Figma에 `이전 기록 삭제 얼럿`이 있어 띄운다.

## 작업 순서

한 커밋에 한 목적씩 아래 순서로 만든다.

1. 기록 모델과 저장소(SwiftData + 메모리), `ModelContainer` 연결
2. `finishTraining` 성공 시 기록 저장
3. 세션 ID로 AAR 열기를 정식 경로로 정리
4. 목록 화면, 삭제 확인, 빈·실패 상태
5. 홈 카드 연결과 AAR 종료 후 돌아가기
6. 데모 샘플 기록

## 검증

- [x] InstructorApp 빌드
- [x] 저장소 테스트: 저장, 최신순 조회, 같은 세션 덮어쓰기, 삭제 (메모리 SwiftData)
- [x] Store 테스트: 종료 성공 시에만 저장, 저장 실패해도 결과 준비로 진행
- [x] 에뮬레이터(`scripts/seed-aar-emulator.py` 데이터)로 `기록 → AAR → 대원 선택 → 영상 → 홈` 확인. 화면을 누르지 않고 실제 Firestore·Storage 저장소로 Store 흐름을 시뮬레이터에서 실행했다. 대원 1·2 영상이 재생 준비 상태가 되고, AAR을 닫으면 홈으로 간다. 대원 앱 없이 훈련을 끝낼 수 없어 `훈련 종료 → 저장`은 Store 테스트로 대신한다.
- [x] 앱 재실행 후 목록 유지: 기기 SwiftData에 넣은 기록이 재실행 뒤 홈 카드에 보였다. 삭제 후 재실행은 저장소 테스트(새 저장소로 다시 읽기, 삭제)로 대신한다.
- [x] 삭제 후 Storage에서 그 세션 영상 조각(10개)이 사라지고 `result.json`과 도면은 남음. 에뮬레이터를 끈 상태의 삭제는 실패 안내 후 목록에 남음
- [x] 데모 모드 샘플 기록 두 건에서 AAR과 영상이 열림. 데모는 메모리 저장소만 써서 운영 SwiftData와 섞이지 않는다.

참고: 시드 스크립트가 도면 분석 형식을 `"seed"`로 올려 앱이 AAR 도면을 거부한다(`지원하지 않는 도면 분석 형식입니다`). 이번 변경 이전부터 있던 문제라 별도로 다룬다.
