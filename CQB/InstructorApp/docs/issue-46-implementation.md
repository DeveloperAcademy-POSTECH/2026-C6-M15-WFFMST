# Issue #46 구현 기록

## 범위

InstructorApp의 `LocalRegisteredFloorPlan`을 기존 CQBCore 파일 계약으로 변환하고,
`StorageFloorPlanFileRepository`를 통해 Firebase Storage에 등록한다.
CQBCore 모델, Storage 경로, 파일 형식과 공통 enum은 변경하지 않았다.

## 파일 변환

- `original.png`: 정규화된 `LocalImportedImage.pngData`
- `resolved-mask.bin`: `LocalObstacleGrid.blocked`의 row-major `UInt8` 바이트
- `navigation-map.json`: 키를 정렬해 인코딩한 `FloorPlanManifest`

이미지와 마스크의 SHA-256은 Manifest에 기록한다. 완성된 JSON 바이트의 SHA-256은
`FloorPlanReference.navigationSHA256`으로 사용한다. Storage 경로는 기존
`floorPlans/{floorPlanID}/` 계약을 그대로 사용한다.

축척의 정규화 좌표는 이미지 가로·세로 픽셀 수를 곱해 `ImagePoint`로 변환한다.
추출 알고리즘은 `v13-wall-detector`, 편집 rasterization은 현재 앱 구현과 같은 버전 2로 기록한다.

## 등록 상태

- 업로드 성공 후에만 등록 도면 목록에 추가하고 draft를 초기화한다.
- 업로드 중에는 중복 등록과 뒤로 가기를 막는다.
- 실패하면 검토가 끝난 draft와 같은 `floorPlanID`를 유지하고 재시도한다.
- 업로드된 `FloorPlanReference`는 앱 내부 등록 도면에 보관하고 세션의 `floorPlan`에 전달한다.

Storage 규칙은 불변 파일의 update를 막는다. 첫 업로드에서 일부 파일만 성공한 경우에도
재시도할 수 있도록, Repository는 기존 파일을 먼저 받고 바이트가 같으면 성공으로 간주한다.
같은 경로에 다른 바이트가 있으면 `RepositoryError.integrityMismatch`를 반환한다.

## 검증

- `bash scripts/check-floorplan-registration.sh`
  - 파일 변환과 Manifest 필드
  - 이미지·마스크·JSON SHA-256
  - 실패 시 draft 유지, 같은 참조 재시도, 성공 후 단일 등록
  - 등록 도면 참조가 세션에 전달되는지 확인
- `bash scripts/check-instructor-store.sh`
- `swift test --package-path CQB/Packages/CQBCore`
- InstructorApp iOS Simulator 빌드
- `CQB_FIREBASE_EMULATOR_TESTS=1 swift test --package-path CQB/Packages/CQBCore --filter floorPlanUploadToEmulator`
  - Emulator Auth로 익명 사용자 생성
  - 기존 Storage 경로에 파일 3개 생성
  - 동일 바이트 재시도와 다운로드 검증
  - 각 파일의 Content-Type 검증

Emulator 통합 검사는 환경 변수를 지정한 경우에만 실행한다. 일반 패키지 테스트에서는 건너뛴다.
