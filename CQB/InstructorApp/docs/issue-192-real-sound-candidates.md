# Issue #192 실제 기록의 큰 소리 후보 표시

AAR이 대원 앱이 올린 `sound-candidates.json`을 Storage에서 받아, 총성으로 판정한 소리만 재생바 마커로 표시한다.

## 흐름

```
대원 앱(#172)                          교관 앱 AAR
녹화 중 후보를 넉넉히 뽑아 올림 ──▶ 대원 기록별 파일 받기 ──▶ 판정 ──▶ 세션 시간축 ──▶ 대원 간 묶기(2명 이상) ──▶ 마커
```

- 받기·판정은 `RepositoryAARSoundCandidateLoader`가 한다. `AARStore`의 후보 로딩(#175: AAR 로딩과 따로, reset 때 취소), 세션 시간축 변환, 묶기, 화면은 그대로 쓴다.
- `AppContainer`가 실제 AAR에 `StorageSoundCandidateRepository`로 만든 로더를 넣는다. 데모는 기존 데모 후보를 쓴다.

## 실패 처리

| 받은 결과 | 처리 |
| --- | --- |
| 파일 없음(`RepositoryError.notFound`) | "분석 안 됨". 빈 배열 |
| 모르는 버전(`SoundCandidateValidationError.unsupportedSchema`) | "분석 안 됨". 빈 배열 |
| 다른 기록의 문서, 손상된 문서, 네트워크·권한 오류 | 던진다. `AARStore`가 로그를 남기고 그 대원만 빼고 묶는다 |

후보 파일을 받지 못해도 AAR 동선·영상 재생에는 영향이 없다.

## 판정 (`AARSoundCandidateJudge.standard`)

gunshot-lab `713e743` 결합 방식(`FusionConfig.standard`)과 같은 기준이다. 후보를 시각 순으로 보며 아래를 모두 통과한 것만 남긴다.

| 조건 | 값 | 이유 |
| --- | --- | --- |
| 분류기 점수 | 0.25 이상 | 총성이 아닌 큰 소리를 거른다 |
| 잔향 | 0.05초 이상 | 폰 근처 충격음은 잔향이 짧다. 잔향을 잴 수 없는 후보(`nil`)에는 쓰지 않는다 |
| 앞 총성과 간격 | 0.45초 이상 | 같은 총성의 잔향을 하나로 본다. 실탄 더블탭(약 0.51초)은 남는다 |

- 점수는 `gunshot_gunfire`와 `artillery_fire`의 라벨별 최고 점수를 더하고 1을 넘지 않게 한다.
  - 연구 코드는 분류기 창마다 두 라벨을 더한 뒤 최고값을 쓰지만, 파일에는 라벨별 최고값만 있다.
  - 라벨별 최고값의 합은 연구 점수보다 같거나 크다. 총성을 놓치기보다 남기는 쪽으로 기운다.
- 걸러진 후보는 간격 계산에 쓰지 않는다. 간격은 앞에서 **고른** 총성 기준이다.

### 기준값을 다시 볼 근거 (#196 실기기 확인)

| 녹음 | 후보 | 판정 통과 | 점수(두 라벨 합) |
| --- | --- | --- | --- |
| 맥 스피커로 튼 총성(10발) | 23 | 5발 | 0.14~0.44 |
| 총성 없이 폰 바닥에 치기 등 | 27 | 3개 | 통과한 것 0.26~0.35 |

- 스피커 소리는 실제 총성보다 점수가 낮다. 연구 데이터의 실제 총성은 대부분 0.7 이상이다.
- 폰 한 대 근처에서만 난 소리는 대원 간 묶기(2명 이상)에서도 빠질 가능성이 크다.
- 기준값은 사격장 녹음으로 다시 조정한다. 바꿀 때는 `AARSoundCandidateJudge.standard`만 고치면 된다.

## 하지 않은 것

- **분석 구간 반영:** 어떤 대원이 그 시각을 분석하지 못했으면(전화, 권한 없음) "못 들음"이 아니라 "판단 불가"다. 지금은 2명 이상 규칙에 반영하지 않는다. 대원이 많으면 영향이 작아 실사용을 본 뒤 정한다.
- **판정 결과 표시:** 걸러진 후보를 화면에 보여 주거나 기준값을 화면에서 바꾸는 기능은 없다.

## 변경 파일

| 파일 | 내용 |
| --- | --- |
| `Models/AARSoundCandidateJudge.swift` (새) | 판정 기준과 점수 계산 |
| `Services/AAR/AARSoundCandidateLoading.swift` | `RepositoryAARSoundCandidateLoader` 추가. `UnavailableAARSoundCandidateLoader`는 미리보기·테스트용 |
| `App/AppContainer.swift` | 실제 AAR에 Storage 로더 주입 |
| `Models/AARSoundEvent.swift` | `AARSoundCandidate` 설명 갱신 |

## 검증

- [x] `AARSoundCandidateJudgeTests`: 점수 합과 상한, 점수·잔향·간격으로 거르기, 더블탭 유지, 걸러진 후보는 간격 기준이 아님, 경계값 포함
- [x] `RepositoryAARSoundCandidateLoaderTests`: 판정 통과 시각만 반환, 파일 없음·모르는 버전은 빈 배열, 다른 기록·손상·네트워크 오류는 던짐
- [x] `AARSoundEventStoreTests`: 두 대원의 후보 파일이 판정 → 세션 시간축(녹화 시작 차 2초) → 묶기를 거쳐 마커 하나가 됨
- [ ] 실제 기록으로 AAR을 열어 마커 확인(에뮬레이터 또는 운영). #196 머지 후 대원 앱이 올린 파일로 확인한다
