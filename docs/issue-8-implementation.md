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

### 자동 검증

- `bash scripts/check-floorplan-import.sh`: PNG/JPEG, EXIF 방향, 투명 이미지 흰 배경 합성, 최대 해상도, V13 문·통로, 홀수 크기 격자, 잘못된 파일과 취소 통과.
- `bash scripts/check-floorplan-geometry.sh`: 막기/열기 순서, 얇은 획, 외곽 우선 처리, 잘못된 폴리곤, 축척 검증, PNG 생성과 반복 결과 동일성 통과.
- `bash scripts/check-floorplan-registration.sh`: 등록 조건, preview/등록 격자 일치, 중복 등록 방지, 이미지 교체 초기화, 지연된 이전 결과 무시, 취소/재시도, Store 해제 통과.
- `bash scripts/check-instructor-store.sh`: 기존 화면 이동, 세션 준비 상태와 AAR 선택 제한 회귀 통과.
- `bash scripts/check-floorplan-canvas.sh <booted-simulator-UDID>`: 실제 UIKit에서 확대·이동 전후 좌표 변환, PKStroke transform 및 정규화, 빠른 막기/열기 순서, 지연된 획, 이미지 교체 후 bounds/fit 초기화, teardown 후 콜백 해제 통과. 별도 임시 테스트 앱을 설치·실행하며 Xcode 프로젝트를 변경하지 않는다.
- InstructorApp의 generic iOS Simulator 빌드 통과. Swift 코드 경고 없음. AppIntents 미사용에 따른 metadata extraction 안내만 출력됨.
- 독립 리뷰에서 확정 외곽 수정 후 이전 마스크가 남는 문제를 발견해 즉시 무효화 및 재계산하도록 수정하고 회귀 테스트 추가.

### 시뮬레이터 사용자 흐름

iPad Pro 13-inch (M5), iPadOS 27.0, 가로 화면에서 확인:

1. 도면 목록 → 등록 → 실제 시스템 파일 선택기로 PoC 도면 PNG 선택.
2. 2172 × 724px 원본과 추출 결과 중첩 확인.
3. 막기 획 위에 열기 획을 그려 중간 부분이 제거되는 결과 확인.
4. 외곽 네 점 지정 및 확정 → 외곽 밖 통과 불가 표시.
5. A/B 지정 → 10m 입력 → 최종 확인 전 등록 비활성화 확인.
6. 사용자 확인 후 등록 → 목록 3개로 증가 → 세션 생성에 새 도면 자동 선택 및 실제 이미지 표시 확인.

파일 선택 테스트를 위해 시뮬레이터의 임시 빌드 산출물에만 파일 공유를 켜고 PoC 입력을 배치했다. 프로젝트 설정에는 추가하지 않았으며, 별도 DerivedData에서 생성한 최종 빌드로 재설치하고 홈 화면 실행을 확인했다.

### 남은 제약 / 리뷰 시 확인

- 실제 Apple Pencil 입력, 두 손가락 확대·이동 제스처의 충돌 및 체감 성능은 실기기 확인 필요. 시뮬레이터 마우스 입력 검증과 구분한다.
- 자동 추출은 PoC의 기본 V13 경로를 사용한다. 특정 샘플 hash/외곽 자동 적용과 `paleWalls` 선택 모드, 동선 보정, PoC 영속 저장은 포함하지 않는다. 추출 임계값은 추출기 내부 기본값이며 도면별 정확도를 보장하지 않아 사용자 검수가 필요하다.
- 공통 도면 계약이 아직 없으므로 앱 내부 임시 타입으로 연결했다. 선행 데이터 계약 완료 조건은 충족된 것으로 간주하지 않는다. 계약 PR 이후 공통 타입·서비스 연결은 별도 작업이다.
- 모든 등록 결과는 메모리에만 존재한다. Firebase 요청, 파일 영속 저장, 앱 재실행 복원, 상세/수정/삭제는 구현하지 않는다.
- Issue의 체크박스와 PR은 자동으로 수정하지 않는다. 실기기 입력 검증과 선행 계약 상태를 확인한 뒤 완료 판단한다.
