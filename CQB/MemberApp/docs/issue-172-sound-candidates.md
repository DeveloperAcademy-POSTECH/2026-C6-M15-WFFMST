# #172 대원앱 녹음 중 큰 소리 후보 추출과 업로드

- 이슈: https://github.com/DeveloperAcademy-POSTECH/2026-C6-M15-WFFMST/issues/172
- 상위: #168 AAR 큰 소리(총성) 표시
- 계약 기준: 루트 `docs/cqb-core-models.md` "음향 후보", `docs/repositories.md` `SoundCandidateRepository` (#169, PR #178)
- 감지 연구: `2026-C6-M15-WFFMST-gunshot-lab` (`main` `713e743`)

대원 iPhone이 녹화하는 동안 마이크의 압축 전 소리(PCM)로 큰 소리 후보를 뽑고, 기록이 끝나면 후보 목록을 `sound-candidates.json`으로 올린다. 교관 iPad가 이 파일로 최종 판정하고 AAR 타임라인에 표시한다.

## 범위

하는 것:

- 연구 저장소에서 결합 방식에 필요한 감지 코드 2개 파일 가져오기
- 녹화 중 마이크 PCM을 녹화와 별도로 분석해 후보와 분석 구간 모으기
- 기록이 끝나면 후보 파일을 기기에 저장하고 `finishing` 동안 업로드
- 데모 모드 처리

하지 않는 것:

- 최종 판정(점수·잔향 기준, 중복 묶기)과 기기 간 합의 — 교관 앱이 한다 (#168)
- 감지 방식·기준값 결정 — gunshot-lab에서 한다
- 영상 조각의 AAC 소리 트랙 변경 — AAR 재생용으로 그대로 둔다
- `CQBCore` 계약 변경 — #169에서 끝났다

## 가져오는 코드

연구 저장소의 `Packages/GunshotDetection`에는 여러 실험 방식이 함께 있다. 결합 방식에 필요한 2개 파일만 그대로 복사한다.

| 파일 | 줄 수 | 내용 |
| --- | --- | --- |
| `OnsetDetector.swift` | 164 | 5ms 프레임 최대 진폭이 직전 0.5초 중앙값보다 급격히 커진 순간(급상승)과 잔향 감쇠 시간. 다른 파일에 의존하지 않는다 |
| `FusionJudge.swift` | 135 | 분류기 설정(`FusionConfig.standard`: 라벨, 창 길이, 겹침, 후보 직후 시점)과 점수 계산 |

가져오지 않는 것: `LoudSoundDetector`, `MultiDeviceLoudSoundFusion`, `LoudSoundEvaluation`, `OfflineAnalysis`, 연구 앱(`GunshotSpike`) 코드.

- 위치: `CQB/MemberApp/Services/SoundDetection/` (대원 앱만 쓴다)
- 파일 머리에 출처(저장소, 경로, 커밋 `713e743`)를 주석으로 남긴다. 대원 앱의 기본 `MainActor` 격리(`SWIFT_DEFAULT_ACTOR_ISOLATION`)를 피하려고 최상위 타입 선언 6곳에 `nonisolated`만 붙이고, 나머지 내용은 고치지 않는다. 고쳐야 하면 연구 저장소에서 먼저 고친 뒤 다시 가져온다.
- 연구 앱 `SoundDetector.swift`의 실시간 흐름(마이크 버퍼 → 급상승 감지 + 내장 분류기)은 복사하지 않고 대원 앱에 맞게 새로 작성한다. 화면·녹음 재생·결과 저장 같은 실험 기능이 섞여 있기 때문이다.

## 처리 흐름

```text
MemberAudioCaptureService ──PCM 버퍼──┬─▶ ARFrameVideoWriter (AAC 인코딩, 기존)
                                      └─▶ MemberSoundCandidateRecorder (새, 별도 큐)
                                              ├─ OnsetDetector: 급상승 후보 + 잔향
                                              └─ SNAudioStreamAnalyzer(.version1): 라벨별 점수 창
녹화 종료 ─▶ 후보에 점수 붙이기 ─▶ SoundCandidateDocument ─▶ 기기 저장 ─▶ finishing 중 업로드
```

- `ARRecordingService`가 마이크 버퍼를 받는 콜백에서 영상 작성기와 함께 후보 기록기에도 넘긴다.
- 후보 기록기는 자기 직렬 큐에서 처리한다. 영상 작성 큐와 분리해 분석이 늦어도 녹화를 막지 않는다.
- 버퍼는 4096 샘플 단위로 순서대로 넘긴다. `OnsetDetector`는 버퍼 크기와 무관하게 같은 결과를 낸다.
- 내장 분류기는 `SNClassifySoundRequest(classifierIdentifier: .version1)`를 `FusionConfig.standard`의 창 길이·겹침으로 돌린다.

## 후보 값

`SoundCandidate` 한 개당:

| 필드 | 값 |
| --- | --- |
| `time` | `OnsetDetector.Candidate.audioSeconds`를 기록 내부 시간으로 바꾼 값 |
| `peakLevelDBFS` | `OnsetDetector.Candidate.levelDB` |
| `decaySeconds` | `OnsetDetector.Candidate.decaySeconds`. 녹화 끝에서 잘려 잴 수 없으면 `nil` |
| `classifierScores` | 후보 직후 시점(`audioSeconds + probeDelaySeconds`)을 담은 분류기 창들에서 라벨별 최고 점수. `FusionConfig.standard.labels`(`gunshot_gunfire`, `artillery_fire`)만 남긴다 |

- **거르지 않는다.** 급상승 후보는 분류기 점수가 낮거나 잔향이 짧아도 모두 남긴다. 판정은 교관 앱이 한다.
- 급상승 기준은 `OnsetDetector.Config.standard`(최소 -20dBFS, 18dB 상승)를 그대로 쓴다. 후보가 너무 많으면(예: 분당 수백 개) 기준을 높이는 것을 gunshot-lab과 정한다.
- `detector`: `name` `"gunshot-combined"`, `version` 연구 저장소 커밋(`713e743`), `settingsID` `"onset-standard"`.

## 시간축

기록 내부 0초는 첫 녹화 프레임 시각(`ARRecordingService.firstTimestamp`, 호스트 시계)이다. 영상 조각도 같은 기준을 쓴다.

- 마이크 버퍼 시각은 `MemberAudioCaptureService`가 이미 호스트 시계로 바꿔 넘긴다(`ARFrameVideoWriter.append(audioSampleBuffer:)`와 같은 입력).
- 끊기지 않은 구간마다 첫 버퍼의 호스트 시각을 기억하고, `OnsetDetector`에는 그 구간 시작부터 센 프레임 위치를 넘긴다.
- 후보 시각 = 구간 첫 버퍼 호스트 시각 + `audioSeconds` − `firstTimestamp`
- 녹화 시작 전에 온 버퍼(시각 < `firstTimestamp`)는 분석하지 않는다.

## 분석 구간

- 녹음이 이어진 동안을 하나의 `SoundTimeRange`로 기록한다.
- 마이크 권한이 없으면 분석 구간이 비어 있다. 이때도 후보 파일을 올린다(빈 구간, 빈 후보). 교관 앱이 "분석 안 됨"과 "후보 없음"을 구분할 수 있다.
- 전화 등으로 끊기면(`onInterruption`) 지금 구간을 닫고, 재개(`onResume`) 뒤 첫 버퍼에서 새 구간을 연다. 새 구간에서는 `OnsetDetector`와 분류기를 새로 만든다. 끊긴 앞뒤가 이어지지 않으므로 직전 중앙값이 섞이지 않게 한다.
- 녹음이 이어지는 중에 다음 버퍼가 0.1초보다 늦게 오거나 샘플레이트가 바뀌어도 끊긴 것으로 보고 새 구간을 연다.
- 녹화 종료 시 마지막 구간을 닫는다. `OnsetDetector`는 잔향 측정이 끝난 후보만 내보내므로, 녹화 끝 0.5초 이내 후보는 남지 않는다. 그래서 `decaySeconds`는 항상 값이 있다.

## 저장과 업로드

- 녹화가 끝나면 `SoundCandidateDocument`를 보정 결과와 같은 기록 폴더에 `sound-candidates.json`으로 저장한다(`LocalRecordingFileStore`). 앱을 다시 켜도 같은 파일로 재시도한다.
- 업로드 순서: 영상 조각 → 보정 결과 → **음향 후보** → `done`.
- 업로드 기록표(`uploadManifest`)에 후보 업로드 여부를 남겨 다시 올리지 않는다.
- 후보 업로드는 업로드 한 번에 한 번 시도한다. 실패하면 로그만 남기고 `done`으로 바꾼다. 후보 때문에 기록을 `failed`로 만들지 않는다. 사용자가 다른 항목 실패로 재시도하면 기록표를 보고 아직 안 올린 후보를 다시 시도한다.
- 감지·분석이 실패해도(분류기 생성 실패 등) 녹화, 보정, 영상 업로드를 막지 않는다. 이때 후보 파일을 만들지 않는다.
- 기기 저장에 실패해도 동선 저장을 막지 않는다. 메모리의 문서로 업로드는 그대로 시도한다.
- 업로드 기록표에 `uploadedSoundCandidates`를 더했다. 이 항목이 없는 예전 기록표는 `false`로 읽는다.

## 데모 모드

- 데모도 같은 카메라 서비스를 써서 후보 기록기는 돈다. 결과로 후보 문서를 만들지 않고, 저장·업로드도 하지 않는다.
- 교관 앱 데모 마커는 교관 앱 데모 데이터로 따로 보여 준다(#168).

## 코드 구조

| 파일 | 내용 |
| --- | --- |
| `Services/SoundDetection/OnsetDetector.swift` | 연구 저장소 복사본 |
| `Services/SoundDetection/FusionJudge.swift` | 연구 저장소 복사본 |
| `Services/SoundDetection/MemberSoundCandidateRecorder.swift` (새) | 별도 큐, 구간 관리, 급상승 감지, 분류기 창 수집, 점수 붙이기, 문서 만들기 |
| `Services/ARRecordingService.swift` | 마이크 콜백에서 기록기에 버퍼 전달, 끊김·재개 전달, 녹화 종료 시 문서 받기 |
| `Services/LocalRecordingFileStore.swift` | 후보 파일 저장·읽기 |
| `Services/VideoChunkUploadQueue.swift` | 업로드 기록표에 후보 업로드 여부 |
| `Stores/MemberStore.swift` | `finishing` 업로드 순서에 후보 추가, 실패해도 `done` |
| `App/AppContainer.swift` | `StorageSoundCandidateRepository` 주입 |

## 검증 계획

- [x] 단위 테스트 (`MemberAppTests/MemberSoundCandidateTests.swift`, 10개 통과)
  - 합성한 16비트 마이크 버퍼의 큰 소리가 기록 시간 1.5초 후보가 되고, 녹화 시작 전은 0초로 자름
  - 끊김 콜백·0.1초 넘는 공백 모두 구간을 둘로 나누고, 끊긴 동안에는 후보가 없음
  - 마이크가 없으면 빈 결과, 시작 전 버퍼는 무시
  - 점수 붙이기: 후보 직후 시점을 담은 창의 라벨별 최고 점수, 덮는 창이 없으면 0
  - 예전 업로드 기록표를 읽으면 후보는 안 올린 것으로 봄
  - 업로드 순서가 보정 결과 → 후보 → `done`, 후보 업로드가 실패해도 `done`
- [x] 대원 앱 기존 테스트 회귀: 62개 통과. `MemberDemoScenarioTests.testDemoModeCreatesANewRunWhenRestarted`는 #161과 같은 Xcode 27 동기 테스트 크래시라 빼고 실행
- [ ] 연구 저장소 녹음을 흘려 넣은 결과가 연구 비교 도구와 같은 후보 시각을 내는지
- [ ] 에뮬레이터: 기록 종료 후 `sound-candidates.json`이 올라가는지
- [ ] 실기기
  - 총성 모사음(공포탄, 풍선 터뜨리기 등)과 폰 치기·박수·고함이 후보로 남는지
  - 녹화 중 전화 수신 후 재개
  - 13분 녹화 동안 배터리·발열, 영상 프레임 누락이 늘지 않는지

## 정해야 할 것

- [ ] 급상승 기준을 연구 기본값 그대로 쓸지, 후보 수를 보고 조정할지 (gunshot-lab)
- [ ] 분류기 라벨을 두 개만 남길지, 다른 라벨(예: 폭발음)도 남길지
- [ ] 연구 저장소에 "제품용으로 2개 파일을 복사했다"는 기록 남기기 (새미)
