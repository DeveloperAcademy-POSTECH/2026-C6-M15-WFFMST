# Issue #168 AAR 큰 소리 마커

AAR 재생바에 총성(큰 소리)이 난 시각을 노란 핀으로 표시하고, 핀을 누르면 그 시각으로 이동한다. 교관이 영상을 처음부터 돌려 보지 않고 사격 순간을 바로 찾아 동선·영상을 복기하게 한다.

#168 전체 진행 순서 중 **2번(교관앱 AAR 타임라인 표시)**만 다룬다. 실제 후보 데이터는 저장 계약(#169)과 대원앱 감지(#172)가 끝나야 생기므로, 지금은 데모 모드에서만 마커가 보인다.

## 범위

만드는 것:

- 대원별 큰 소리 후보를 세션 시간축으로 바꿔 하나의 이벤트로 묶기
- 여러 대원이 함께 들은 이벤트만 재생바에 표시
- 재생바 위 Figma 노란 핀 마커, 누르면 그 시각으로 이동
- 데모 모드 샘플 후보

하지 않는 것:

- 후보 파일 저장 형식과 Repository (#169)
- 대원앱 녹음 중 PCM 감지와 업로드 (#172)
- 감지 방식·임계값 결정 (gunshot-lab)

## 흐름

```text
대원 아이폰                     서버(Storage)                         교관 아이패드
녹음 중 큰 소리 감지  ──저장──▶  기록 폴더/sound-candidates.json  ──불러오기──▶  AAR 재생바 마커
   (#172)                          (형식은 #169)                      (이번 작업)
```

AAR을 열면 `AARStore.load`가 기록 목록을 받은 뒤 대원별 후보를 따로 받기 시작한다. 마커는 부가 정보라 `load`는 후보를 기다리지 않는다. 후보 다운로드가 느리거나 끝나지 않아도 동선·영상이 준비되면 재생할 수 있다. `reset`하면 받던 후보를 취소하고, 다른 세션으로 바뀐 뒤 도착한 결과는 버린다.

1. `AARSoundCandidateLoading.candidates(for:)`로 대원 기록마다 후보(기록 내부 시각)를 받는다.
2. 대원 기록 시작 오프셋(`Recording.startedAt - Session.startedAt`)을 더해 세션 시간축(재생 위치와 같은 축)으로 바꾼다.
3. `AARSoundEventFusion`이 시각이 가까운 후보를 묶고, 들은 대원 수로 확인 여부를 정한다.
4. 확인된 이벤트만 `AARStore.soundEvents`에 담는다. 재생바가 이 목록으로 핀을 그린다.
5. 핀을 누르면 `jumpToSoundEvent`가 재생 위치를 그 시각으로 옮긴다.

후보를 받지 못한 대원은 빼고 묶는다. 세션이 바뀌면 늦게 온 결과는 버리고, AAR을 닫으면 목록을 비운다.

## 화면

[Figma `iPad 06 · AAR`](https://www.figma.com/design/3tndfCqfeh1Z1dLRXu2qXk/?node-id=2998-10412)의 재생바 마커를 따른다.

| 항목 | 값 |
| --- | --- |
| 마커 | Figma SVG 그대로(`AARSoundEventMarker`, 10×29, `Primary 500` `#FFD900`) |
| 위치 | 재생바 시각 위치에 가운데 정렬, 핀 끝이 재생바 아래 끝에 닿음 |
| 누름 영역 | 44×44pt |
| 누르면 | 그 시각으로 이동 |
| VoiceOver | `큰 소리 00:14, 대원 3명`, 안내 `이 시각으로 이동합니다.` |

## 코드 구조

| 파일 | 내용 |
| --- | --- |
| `Models/AARSoundEvent.swift` | `AARSoundCandidate`, `AARSoundEvent`, 묶기 로직 `AARSoundEventFusion` |
| `Services/AAR/AARSoundCandidateLoading.swift` | 기록별 후보를 받는 프로토콜. 실제 기록용 `UnavailableAARSoundCandidateLoader`는 계약 전이라 항상 빈 배열 |
| `Stores/AARStore.swift` | 후보 로딩, 이벤트 묶기, `soundEvents`, `jumpToSoundEvent` |
| `Features/AAR/AARTimelineView.swift` | 재생바 마커, `AAR 재생바 · 큰 소리 표시` 미리보기 |
| `Services/Demo/InstructorDemoScenario.swift` | 데모 후보 |

#169가 정해지면 `UnavailableAARSoundCandidateLoader` 자리를 Storage에서 후보 파일을 받는 구현으로 바꾼다. 묶기와 화면은 그대로 쓴다. → #192에서 `RepositoryAARSoundCandidateLoader`로 바꿨다([작업 문서](issue-192-real-sound-candidates.md)).

## 데모 후보

데모 영상(30초) 기준. 모든 데모 기록은 세션 시작과 같이 시작해 오프셋이 0이다.

| 시각 | 들은 대원 | 표시 |
| --- | --- | --- |
| 6.20초 | 1·2·3·4 (6.20~6.26) | 표시 |
| 14.80초 | 2·5·6 (14.80~14.86) | 표시 |
| 21.50초 | 3 | 한 명만 들어 표시 안 함 |
| 26.00초 | 1·4 (26.00~26.04) | 표시 |

## 임시 가정

PR에도 같은 내용을 적는다. gunshot-lab 결과로 다시 정한다.

- 서로 다른 대원의 후보가 **0.5초 안**이면 같은 소리로 묶는다. 묶음의 시각은 가장 이른 후보 시각이다.
- **2명 이상**이 들어야 표시한다. 한 명만 들은 후보는 휴대폰 접촉음일 수 있어 표시하지 않는다.
- 마커를 누르면 이벤트 시각으로 바로 이동한다.
- 그 시간대에 소리가 있는 기기가 1대뿐인 경우의 예외 처리는 후보 파일에 분석 구간이 생긴 뒤(#169) 다룬다.

## 검증

- [x] InstructorApp 빌드
- [x] 묶기 단위 테스트: 시간 창 안팎, 같은 대원 중복, 최소 대원 수
- [x] 데모 AAR 통합 테스트: 이벤트 3개(6.20·14.80·26.00초), 마커 누르면 그 시각으로 이동, AAR을 닫으면 비움
- [x] 실제 기록은 후보가 없어 마커가 나오지 않음
- [x] 재생바 캡처로 핀 3개 위치와 모양 확인
- [ ] 시뮬레이터·실기기 데모 모드에서 핀 표시와 이동, 영상 화면 확인
- [ ] `InstructorAppTests` 전체 회귀 (실행하지 않음. #161 수정 #166 머지 후 실행)
