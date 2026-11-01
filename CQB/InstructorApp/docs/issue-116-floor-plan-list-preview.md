# Issue #116 도면 목록 선택 미리보기

## 화면 상태

도면 관리 화면의 행 선택은 세션 생성에 사용하는 `selectedFloorPlanID`와 분리한다. 목록은 `previewedFloorPlanID`와 `FloorPlanListPreviewState`를 사용해 미선택, 로딩, 표시 성공, 실패 상태를 구분한다. 행을 누르면 오른쪽 패널에 원본 도면과 최종 마스크를 겹쳐 표시하고, 기존 상세보기 버튼은 상세·수정·삭제 흐름을 그대로 연다.

새 항목을 선택하면 이전 목록 미리보기 task를 취소한다. Loader는 같은 reference의 요청자들을 waiter로 추적하며, 마지막 waiter가 취소되면 진행 중인 썸네일 생성 task도 취소한다. 다른 waiter가 남아 있으면 공유 작업을 유지한다. 완료된 결과를 적용하기 전에 현재 화면, 도면 ID, `FloorPlanReference`를 다시 확인하므로 취소를 무시하고 늦게 끝난 작업도 최신 선택을 덮어쓰지 않는다. 같은 항목이 이미 로딩 또는 표시 중이면 Store에서 새 요청을 만들지 않는다.

## 파일과 썸네일 재사용

`LocalFloorPlanListPreviewLoader`는 다음 순서로 목록 이미지를 준비한다.

1. 같은 `FloorPlanReference`의 메모리 썸네일
2. 로컬 등록 직후 Store에 남아 있는 `LocalRegisteredFloorPlan`
3. Issue #115의 `CachedFloorPlanFileRepository`
4. Firebase Storage

원본 PNG는 ImageIO 썸네일 API로 긴 변 최대 1,600픽셀까지 직접 다운샘플링한다. 전체 해상도 `UIImage`를 먼저 만들지 않는다. 최종 마스크는 grid 해상도 PNG로 만들고 `cellSizePixels`를 scale에 반영해 원본과 같은 좌표 비율로 겹친다. 같은 reference의 진행 중 작업과 완성된 결과를 공유하므로 반복 선택 시 다운로드와 원본 디코딩을 반복하지 않는다.

완성된 썸네일의 메모리 캐시는 원본·마스크 PNG의 바이트 합계를 기준으로 32 MiB를 상한으로 사용한다. 캐시 적중 시 최근 접근 순서를 갱신하고 상한을 넘으면 가장 오래 사용하지 않은 항목부터 제거한다. 단일 썸네일이 상한보다 크면 현재 요청에는 반환하지만 메모리 캐시에는 남기지 않는다.

앱 재실행 뒤 메모리 썸네일은 사라지지만, 원본 파일은 Issue #115의 디스크 캐시에서 읽어 다시 다운샘플링한다. 따라서 캐시된 도면은 오프라인에서도 표시되며, 캐시 미적중 상태에서 네트워크를 사용할 수 없으면 실패와 재시도 UI를 표시한다.

## 검증

- `bash scripts/check-instructor-store.sh`
- `FloorPlanListPreviewTests`
  - 선택 상태와 세션 선택 독립성
  - 빠른 선택 변경 시 마지막 결과만 적용
  - waiter가 모두 취소될 때 실제 썸네일 작업 취소 및 재시도
  - 같은 항목·reference 재요청 방지
  - 32 MiB 메모리 상한과 LRU 제거
  - 실패 후 재시도
  - ImageIO 다운샘플링 크기
  - 앱 재실행에 해당하는 새 캐시 인스턴스의 오프라인 표시
- InstructorApp iOS Simulator 빌드
