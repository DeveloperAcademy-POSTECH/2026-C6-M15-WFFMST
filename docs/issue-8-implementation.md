# Issue #8 로컬 도면 등록

- 브랜치: `feat/8-instructor-floor-plan`, 부모 `feat/6-instructor-navigation` (`7b172ff`). 사용자 요청에 따라 미병합 PR 위에서 작업한다. 후속 PR은 부모 브랜치를 임시 base로 사용하고 부모 머지 후 develop으로 변경한다.
- 범위: 실제 이미지 입력, PoC 추출기, 순서가 있는 고정 굵기 편집, 외곽, 축척, 실행 중 로컬 등록. Firebase와 영속 저장은 제외한다.
- 선행 계약: 현재 체크아웃에는 공통 도면 모델/서비스가 없다. 앱 내부 `Local*` 타입과 서비스로 사용자 흐름을 구현한다. 이 타입은 서버 계약이나 새로운 공통 파일 형식이 아니다. 공통 계약 연결은 선행 계약 PR 이후 수행한다.
- 원본: `/Users/dayoonlee/Documents/floorplanPoC/FloorPlanPoC`. 추출은 FloorPlanWallDetector, 편집 입력은 NavigationMaskEditorRepresentable, 격자 합성은 NavigationMask를 참고한다. 특정 이미지 hash/외곽과 영속 저장, 동선 보정은 이관하지 않는다.
- 임시 입력 정책: PNG/JPEG, 처리 이미지 긴 변 최대 4096px. 축척 두 점 최소 10 이미지 px, 실제 거리 0 초과 1000m 이하. 한 손가락/Apple Pencil로 편집, 두 손가락 이동·확대. 숫자 상한은 이 앱 등록 검증용이며 공통 계약 변경이 아니다.
- 저장 정책: 정규화 PNG 바이트와 base/최종 격자, 편집 획, 외곽, 축척을 메모리에서 보유한다. 앱 종료 시 소멸한다. PKDrawing은 입력 피드백에만 사용한다.

## 담당 경계

- Lead: Models, Stores, App, 전체 등록 화면, 목록/세션 연결.
- A: Services/Import — 보안 범위 파일 읽기, 방향·해상도 정규화, 취소 가능한 PoC 검출.
- B: Features/FloorPlan/Editing — Store를 모르는 PencilKit canvas와 좌표 입력.
- C: Services/Geometry — 순수 검증·축척·격자 합성 및 테스트.
- 병렬 담당자는 자신의 경로만 수정하고 커밋하지 않는다. 공용 API 변경은 Lead에게 요청한다.

## 검증 기록

구현 및 통합 후 실제 실행 결과와 남은 제약을 기록한다.
