# Issue #46 구현 기록

## 범위

InstructorApp의 `LocalRegisteredFloorPlan`을 기존 CQBCore 파일 계약으로 변환하고,
`StorageFloorPlanFileRepository`를 통해 Firebase Storage에 등록한다.
CQBCore 모델, Storage 경로, 파일 형식과 공통 enum은 변경하지 않았다.

## 파일 변환

- `original.png`: 정규화된 `LocalImportedImage.pngData`
- `resolved-mask.bin`: `LocalObstacleGrid.blocked`의 row-major `UInt8` 바이트
- `navigation-map.json`: 키를 정렬해 인코딩한 `FloorPlanManifest`

이미지 가져오기 시 EXIF 방향 보정과 최대 4,096px 축소 후, 가로·세로가 V13 탐색 셀
크기(2px)의 배수가 되도록 우측·하단에 흰색을 패딩한다. 원본 픽셀은 좌측 상단에 유지하며
늘리거나 자르지 않는다. 편집·외곽선·축척 설정은 패딩된 이미지에서 시작하므로 PNG,
격자와 Manifest가 같은 좌표계를 사용한다. 파일 생성기는 이미지 크기와
`격자 수 × 셀 크기`가 정확히 일치하지 않으면 업로드 전에 거부한다.

이미지와 마스크의 SHA-256은 Manifest에 기록한다. 완성된 JSON 바이트의 SHA-256은
`FloorPlanReference.navigationSHA256`으로 사용한다. Storage 경로는 기존
`floorPlans/{floorPlanID}/` 계약을 그대로 사용한다.

축척의 정규화 좌표는 이미지 가로·세로 픽셀 수를 곱해 `ImagePoint`로 변환한다.
추출 알고리즘은 `v13-wall-detector`, 편집 rasterization은 현재 앱 구현과 같은 버전 2로 기록한다.

## 등록 상태

- 업로드 성공 후에만 등록 도면 목록에 추가하고 draft를 초기화한다.
- 업로드 중에는 중복 등록과 뒤로 가기를 막는다.
- 실패하면 검토가 끝난 draft와 같은 `floorPlanID`를 유지하고 재시도한다.
- 실패 상태에서도 뒤로 가기는 허용한다. 첫 뒤로 가기는 오류·재시도 스냅샷을 정리하고
  축척에서 편집 단계로 돌아가며, 다시 누르면 draft를 초기화하고 목록으로 이동한다.
  실패 화면의 파일 변경과 편집 입력은 뒤로 가기 전까지 비활성화한다.
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
  - 업로드 중 이동 차단, 실패 후 편집·목록 복귀, 재진입 시 이전 재시도 제거
  - 홀수 크기 PNG 가져오기 → 파일 생성 시 PNG·Manifest·격자 크기 및 해시 일치
  - 정렬되지 않은 이미지의 업로드 파일 생성 거부
- `bash scripts/check-floorplan-import.sh`
  - 홀수 너비·높이와 짝수 이미지의 원본 픽셀 보존 및 우측·하단 흰색 패딩
  - EXIF 회전 후 정렬, 최대 크기 축소, 투명 배경·문·통로 보존
- `bash scripts/check-floorplan-geometry.sh`
- `bash scripts/check-instructor-store.sh`
- `swift test --package-path CQB/Packages/CQBCore`
- InstructorApp iOS Simulator 빌드
- `CQB_FIREBASE_EMULATOR_TESTS=1 swift test --package-path CQB/Packages/CQBCore --filter floorPlanUploadToEmulator`
  - Emulator Auth로 익명 사용자 생성
  - 기존 Storage 경로에 파일 3개 생성
  - 동일 바이트 재시도와 다운로드 검증
  - 각 파일의 Content-Type 검증

Emulator 통합 검사는 환경 변수를 지정한 경우에만 실행한다. 일반 패키지 테스트에서는 건너뛴다.

### PR #48 리뷰 수정 검증 (2026-10-12)

위 import·geometry·registration·InstructorStore 검사와 CQBCore 테스트,
InstructorApp iOS Simulator 빌드를 통과했다. 이번 검증에서는 Storage Emulator 검사는
재실행하지 않았으며 일반 패키지 테스트에서 skip되었다.

iPadOS 27.0 Simulator에서 별도 테스트 번들에 실패 Repository를 주입해 확인했다.
저장 → 업로드 중 뒤로 가기·파일 변경 잠금 → 무결성 오류 후 뒤로 가기 활성화 →
편집 복귀와 오류 제거 → 목록 복귀 → 빈 도면으로 재진입 흐름을 실제 버튼으로 확인했다.
테스트용 Repository와 앱 초기화 코드는 임시 사본에만 사용했다.
