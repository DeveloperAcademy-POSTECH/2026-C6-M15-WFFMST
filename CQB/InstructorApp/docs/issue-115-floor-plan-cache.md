# Issue #115 도면 파일 로컬 캐시

## 구성

`CachedFloorPlanFileRepository`가 기존 `FloorPlanFileRepository`를 감싸고 다음 순서로 파일을 조회한다.

1. 메모리 캐시
2. 앱 `Caches/FloorPlanFiles` 디렉터리
3. Firebase Storage를 사용하는 원격 Repository

캐시 키는 `floorPlanID`와 소문자로 정규화한 `navigationSHA256`을 함께 해시해 만든다. 따라서 도면 수정으로 새 `FloorPlanReference`가 생기면 이전 파일과 섞이지 않는다. 동일 키의 동시 다운로드는 하나의 작업을 공유한다.

## 무결성과 기록 방식

세 파일을 사용하기 전에 다음 항목을 모두 검증한다.

- `navigation-map.json`의 SHA-256과 `FloorPlanReference.navigationSHA256`
- manifest의 `floorPlanID`, schema, 좌표계, grid encoding과 크기
- `original.png` 및 `resolved-mask.bin`의 SHA-256
- manifest에 기록된 이미지·grid 크기와 실제 mask 바이트 수

다운로드한 파일은 숨김 staging 디렉터리에 먼저 기록하고 재검증한 다음 완성된 캐시 디렉터리로 교체한다. 파일이 없거나 검증에 실패한 디스크 항목은 전체를 폐기하고 원격에서 다시 받는다.

## 용량과 제거 정책

- 디스크 캐시 상한: 250 MiB
- 메모리 캐시 상한: 40 MiB
- 디스크 항목은 디렉터리 수정 시간을 마지막 접근 시각으로 사용하며, 상한을 넘으면 오래된 항목부터 제거한다.
- 단일 항목만으로 상한을 넘는 경우 해당 디스크 항목은 남기지 않는다.
- 로컬 카탈로그에서 도면을 삭제해도 기존 세션이 같은 참조를 사용할 수 있으므로 캐시는 즉시 삭제하지 않고 용량 기반 제거에 맡긴다.
- 도면 수정은 새 `FloorPlanReference`를 만들므로 새 캐시 항목을 사용하고 이전 항목은 오래된 항목 제거 대상이 된다.

캐시는 백업 대상이 아닌 앱 Caches 영역에만 두며 SwiftData나 공통 데이터 계약을 변경하지 않는다.
