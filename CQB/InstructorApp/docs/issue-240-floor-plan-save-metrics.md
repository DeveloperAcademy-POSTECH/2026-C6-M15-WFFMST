# Issue #240 도면 저장 성능 계측

## 목적

실제 iPad에서 `도면 저장 중` 화면이 약 40초 동안 유지되는 원인을 추측이 아닌 측정값으로 구분한다. 계측은 동작이나 저장 계약을 바꾸지 않으며 Debug 빌드에서만 로그를 남긴다.

## Xcode 측정 절차

1. Xcode에서 `CQB/CQB.xcodeproj`를 연다.
2. `InstructorApp` scheme과 실제 iPad를 선택하고 Debug로 실행한다.
3. Debug Area를 열고 콘솔 검색창에 `event=floor-plan-save`를 입력한다.
4. 신규 도면 등록과 공간 스캔을 완료한 뒤 `도면 저장`을 누른다.
5. `stage=save.total` 로그가 나타나면 한 번의 측정이 끝난 것이다.
6. 같은 기기와 네트워크에서 3회 측정하고 로그를 함께 보관한다.

측정 기록에는 기기, iPadOS, 커밋 SHA, 네트워크 종류와 파일 크기 로그를 함께 남긴다. 첫 실행은 Firebase 인증과 연결 준비 시간이 포함될 수 있으므로 앱 실행 직후 결과와 연속 실행 결과를 구분한다.

## 로그 읽기

모든 로그의 subsystem은 `com.wffmst.cqb`, category는 `FloorPlanSave`다.

| stage | 의미 |
| --- | --- |
| `prepare.files` | 도면 manifest·mask와 WorldMap setup 파일 생성 및 해시 계산 |
| `file-sizes` | 도면 3개 파일과 WorldMap 2개 파일의 바이트 수 |
| `floorPlan.validate` | 도면 무결성 검사와 PNG 복원 |
| `remote.check` | Firebase Storage 기존 파일 다운로드 확인 |
| `remote.upload` | Firebase Storage 실제 파일 업로드 |
| `floorPlan.remoteUpload` | 도면 파일 3개의 원격 처리 합계 |
| `floorPlan.cacheWrite` | 도면 파일 디스크 캐시 기록과 재검증 |
| `floorPlan.upload` | 도면 검증·원격 처리·캐시 기록 전체. 1단계부터 WorldMap 묶음과 동시에 시작한다. |
| `worldMap.downloadAndRebind` | 기존 도면 수정 시 WorldMap 다운로드 및 새 도면 참조 결합 |
| `worldMap.upload` | WorldMap 검증과 파일 2개 원격 처리 전체 |
| `catalog.save` | SwiftData 도면 목록 저장 |
| `save.total` | 저장 버튼 처리 시작부터 로딩 오버레이 종료 직전까지 |

`remote.check`와 `remote.upload`의 `file` 값은 `floorPlan.image`, `floorPlan.mask`, `floorPlan.navigation`, `worldMap.archive`, `worldMap.setup` 중 하나다. `result=missing` 뒤에 같은 파일의 `remote.upload`가 이어지면 원격 확인 후 신규 업로드한 경우다. `result=matched`이면 같은 바이트가 이미 있어 업로드를 생략했다.

실패 또는 취소 시 `stage=save.total` 로그에 `active_stage`가 함께 기록된다.

## 해석 시 주의

- 상위 단계가 하위 단계를 포함하므로 모든 `duration_ms`를 단순 합산하지 않는다.
- `floorPlan.upload`은 `floorPlan.validate`, `floorPlan.remoteUpload`, `floorPlan.cacheWrite`를 포함한다.
- `floorPlan.remoteUpload`과 `worldMap.upload`은 각 파일의 `remote.check` 및 `remote.upload`를 포함한다.
- 기준선과 1단계에서는 각 묶음 내부 파일 업로드가 순차 실행되므로 파일별 시간이 해당 묶음의 전체 시간에 누적된다.
- 1단계부터 `floorPlan.upload`과 `worldMap.upload`은 서로 겹치므로 두 시간을 합산하지 않는다.
- 2단계부터 묶음 내부 파일도 동시에 처리하므로 파일별 시간을 서로 합산하지 않는다.
- Simulator 결과는 실제 iPad의 CPU·저장장치·Wi-Fi 조건을 대표하지 않으므로 성능 결론에 사용하지 않는다.

## 예시

```text
event=floor-plan-save stage=file-sizes floor_image_bytes=4832012 floor_mask_bytes=65536 floor_navigation_bytes=912 world_map_archive_bytes=28421904 world_map_setup_bytes=1440
event=floor-plan-save stage=remote.check file=worldMap.archive bytes=28421904 result=missing duration_ms=843
event=floor-plan-save stage=remote.upload file=worldMap.archive bytes=28421904 result=success duration_ms=30112
event=floor-plan-save stage=worldMap.upload result=success duration_ms=31240
event=floor-plan-save stage=save.total result=success duration_ms=37512
```

## 2026-11-10 실제 iPad 기준선

같은 도면을 사용하고 출발점 1개·체크포인트 2개와 비슷한 면적의 브러시 편집을 적용해, 앱을 종료하지 않고 연속 3회 신규 저장했다.

| 측정 | 전체 | 도면 묶음 | WorldMap 묶음 | 원격 확인 5회 합계 | 실제 업로드 5회 합계 |
| --- | ---: | ---: | ---: | ---: | ---: |
| test1 | 32.569초 | 19.564초 | 12.959초 | 5.086초 | 27.365초 |
| test2 | 28.281초 | 17.118초 | 11.118초 | 4.378초 | 23.786초 |
| test3 | 25.652초 | 15.738초 | 9.892초 | 2.723초 | 22.848초 |
| 평균 | 28.834초 | 17.473초 | 11.323초 | 4.062초 | 24.666초 |

평균 전체 시간 중 원격 확인과 실제 업로드가 28.728초로 99.63%를 차지했다. 파일 준비, 도면 검증, 캐시 기록, SwiftData 저장은 평균 합계 약 0.104초였다.

도면 `navigation-map.json`은 약 5KB인데도 업로드에 4.4~5.5초, WorldMap `setup.json`은 약 1.6KB인데도 4.5~4.9초가 걸렸다. WorldMap archive 크기는 452~759KB로 달라졌지만 업로드 시간은 4.5~5.8초였다. 따라서 현재 조건에서는 전송량보다 파일별 요청의 고정 비용을 5회 순차 지불하는 구조가 주 병목이다.

## 1단계: 도면·WorldMap 묶음 병렬화

도면과 WorldMap 파일 준비 및 검증이 끝나면 두 Repository의 `upload`을 `async let`으로 동시에 시작한다. 각 Repository 내부의 파일 순서와 `remote.check` 정책은 변경하지 않는다. 두 업로드가 모두 성공한 뒤에만 SwiftData catalog를 저장하며, 하나가 실패하면 구조화된 동시성 범위를 빠져나가면서 나머지 작업에 취소를 전달한다.

자동 테스트는 두 Repository가 모두 업로드를 시작하기 전에는 어느 쪽도 완료할 수 없는 게이트를 사용한다. 기존 순차 구현에서는 두 번째 업로드가 시작되지 않아 실패하고, 병렬 구현에서만 통과한다.

실제 iPad 비교는 기준선과 동일하게 같은 도면, 출발점 1개, 체크포인트 2개, 비슷한 브러시 편집으로 앱 종료 없이 3회 수행한다. 1단계에서는 각 파일의 순서는 그대로이므로 다음 로그 형태를 확인한다.

```text
stage=remote.check file=floorPlan.image ...
stage=remote.check file=worldMap.archive ...
...
stage=worldMap.upload result=success ...
stage=floorPlan.upload result=success ...
stage=save.total result=success ...
```

두 묶음의 파일 로그가 시간순으로 교차하고, `save.total`이 기존의 도면 묶음과 WorldMap 묶음 합계가 아니라 더 오래 걸린 묶음에 가까워지는지가 핵심 비교 항목이다.

### 1단계 실제 iPad 결과

기준선과 동일하게 같은 도면, 출발점 1개·체크포인트 2개와 비슷한 면적의 브러시 편집을 적용해 앱을 종료하지 않고 연속 3회 신규 저장했다.

| 측정 | 기준선 전체 | 1단계 전체 | 단축 시간 | 감소율 | 1단계 도면 묶음 | 1단계 WorldMap 묶음 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| test1 | 32.569초 | 19.565초 | 13.004초 | 39.9% | 19.519초 | 13.946초 |
| test2 | 28.281초 | 16.310초 | 11.971초 | 42.3% | 16.263초 | 10.584초 |
| test3 | 25.652초 | 16.992초 | 8.660초 | 33.8% | 16.949초 | 11.170초 |
| 평균 | 28.834초 | 17.622초 | 11.212초 | 38.9% | 17.577초 | 11.900초 |

도면 묶음과 WorldMap 묶음의 `remote.check`·`remote.upload` 로그가 시간순으로 교차해 두 Repository가 실제로 동시에 처리된 것을 확인했다. 각 측정의 `save.total`은 더 오래 걸린 도면 묶음보다 약 42~47ms만 길어, 파일 준비와 catalog 저장을 제외한 대기 시간이 두 묶음의 합이 아니라 최댓값으로 바뀌었다.

원격 확인 5회 합계는 평균 4.183초, 실제 업로드 5회 합계는 평균 25.226초로 기준선의 4.062초·24.666초와 비슷했다. 따라서 1단계 개선은 개별 Firebase 요청이 빨라진 결과가 아니라, 기존 네트워크 작업을 겹친 결과로 판단한다. WorldMap archive 크기는 기준선과 달라 직접적인 개별 측정 비교에는 한계가 있지만, 전체 시간이 모든 테스트에서 감소했고 병렬 실행 로그도 확인되어 묶음 병렬화 효과는 분명하다.

### 다음 개선 우선순위

1. 2단계에서도 같은 조건으로 3회 측정해 1단계 평균 17.622초와 비교한다.
2. 1단계 측정에서는 원격 확인 5회의 합이 약 4.2초였지만, 2단계에서 이 요청들도 겹치므로 사전 확인 제거의 실제 기대효과는 임계 경로 기준으로 다시 판단한다.

모든 파일 요청이 완전히 겹친다고 단순 가정하면 test1 기준 약 8초가 하한 후보지만, 실제 결과는 Wi-Fi 대역폭과 Firebase 동시 요청 처리에 따라 달라지므로 변경 후 같은 조건으로 다시 3회 측정한다.

test3에서 출발점 스캔 중 일시적인 터치 불가와 이후 도면 핀치 확대·축소 불가가 별도로 관찰됐다. 체크포인트 터치와 저장은 가능했으며, 저장 네트워크 병목과 직접 관련된 증거는 없어 Issue #240 범위에는 포함하지 않는다.

## 2단계: 묶음 내부 파일 병렬화

도면 Repository는 사전 navigation 해시 검증을 마친 뒤 이미지·장애물 mask·navigation JSON을 동시에 처리한다. WorldMap Repository도 archive와 setup의 크기, 해시, 도면 참조 관계를 모두 검증한 뒤 두 파일을 동시에 처리한다.

각 파일 내부의 `remote.check → 누락 시 remote.upload` 순서와 불변 파일 재시도 정책은 유지한다. 도면과 WorldMap 묶음 자체도 1단계처럼 동시에 시작하므로 한 번의 신규 저장에서 최대 5개의 독립적인 Storage 요청이 겹칠 수 있다. 파일 수가 3개와 2개로 고정되어 있어 작업 수가 입력에 따라 무제한으로 증가하지 않는다.

자동 테스트에서는 주입한 작업 실행부의 최대 동시 실행 수가 요청 개수와 같은지 확인한다. 실제 iPad에서는 다음 조건을 확인한다.

1. 다섯 파일의 `remote.check` 로그가 순차가 아니라 서로 교차해 시작한다.
2. 각 파일에서 `remote.check` 뒤에 같은 파일의 `remote.upload`가 이어지는 정책은 유지된다.
3. `save.total` 3회 평균을 1단계 평균 17.622초와 비교한다.
4. 저장된 도면을 다시 열 수 있고, WorldMap 기반 위치 복원이 정상 동작한다.

### 2단계 실제 iPad 결과

1단계와 같은 방식으로 같은 도면, 출발점 1개·체크포인트 2개와 비슷한 면적의 브러시 편집을 적용해 연속 3회 신규 저장했다.

| 측정 | 1단계 전체 | 2단계 전체 | 단축 시간 | 감소율 | 2단계 도면 묶음 | 2단계 WorldMap 묶음 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| test1 | 19.565초 | 5.146초 | 14.418초 | 73.7% | 5.106초 | 4.036초 |
| test2 | 16.310초 | 4.165초 | 12.144초 | 74.5% | 4.122초 | 3.554초 |
| test3 | 16.992초 | 4.100초 | 12.892초 | 75.9% | 4.055초 | 3.941초 |
| 평균 | 17.622초 | 4.470초 | 13.152초 | 74.6% | 4.427초 | 3.844초 |

최초 기준선 평균 28.834초와 비교하면 24.364초, 약 84.5% 감소했다.

파일별 시간을 단순 합산하면 원격 확인은 평균 2.413초, 실제 업로드는 평균 17.271초지만, 2단계에서는 이 요청들이 동시에 실행되므로 실제 경과 시간과 같지 않다. 각 측정의 도면 원격 처리 시간은 가장 오래 걸린 단일 파일의 `remote.check + remote.upload`와 거의 같았다.

- test1: 도면 이미지 약 5.032초, 도면 원격 처리 5.032초
- test2: 장애물 mask 약 4.052초, 도면 원격 처리 4.052초
- test3: 도면 이미지 약 3.992초, 도면 원격 처리 3.992초

다섯 파일의 `remote.check`가 모두 비슷한 시점에 완료되고 `remote.upload`도 서로 교차해 완료되어 묶음 내부 병렬 실행을 확인했다. test1의 WorldMap archive는 약 1.07MB로 다른 측정보다 컸지만 전체 임계 경로는 도면 이미지였으므로, 이 조건에서는 파일 크기보다 개별 요청 지연과 가장 느린 파일 하나가 전체 시간을 결정했다.

병렬화 후 원격 확인 제거의 이론적 단축 폭은 병목 파일의 확인 시간인 test1 약 0.711초, test2 약 0.336초, test3 약 0.381초로 평균 약 0.476초다. 불변 파일 재시도와 충돌 검증 정책을 바꿔야 하는 위험에 비해 기대효과가 작아졌으므로 우선순위를 다시 검토한다.
