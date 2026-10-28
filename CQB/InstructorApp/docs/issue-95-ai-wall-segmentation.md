# Issue #95 AI 벽 추출 Core ML PoC

## 목적

V13 픽셀 규칙이 놓치는 얇은 벽과 곡선 벽을 AI 세그멘테이션이 보완하여 사용자의
마스크 수정량을 줄일 수 있는지 검증한다. 이번 작업은 모델 채택이 아니라 변환 및 비교
가능성 확인이 목적이다.

## 범위

- 기존 V13 추출기를 정확도 비교 기준과 fallback으로 유지한다.
- U-Net ResNet-34와 RMBG-1.4 wall segmentation을 FP16으로 변환한다.
- 가능한 모델은 INT8 weight-only 압축본도 생성한다.
- 모델의 픽셀 출력을 기존 `LocalObstacleGrid`로 변환한다.
- 최종 저장 형식 `resolved-mask.bin`과 CQBCore 계약은 변경하지 않는다.

외곽 자동 추출, CubiCasa5K 전체 다운로드, 자체 재학습, V13 제거는 이번 범위가 아니다.

## 모델 선택

### U-Net ResNet-34

- CubiCasa5K 기반의 `floor`, `wall`, `door`, `window` 4클래스 모델이다.
- 표준 PyTorch 연산과 MIT 라이선스를 사용해 첫 변환 대상으로 선택했다.
- 문 클래스를 별도로 출력하므로 벽 마스크가 문 개구부를 막는지 확인할 수 있다.
- 512×512 전체 축소에서 얇은 벽이 사라질 수 있어 후속 타일 추론 비교가 필요하다.

### RMBG-1.4 wall segmentation

- CubiCasa5K의 wall 클래스로 미세조정된 이진 분할 모델이다.
- 1024×1024 입력으로 U-Net보다 세부 선을 보존할 가능성이 있지만 모델이 더 크다.
- 커스텀 모델 코드와 `other` 라이선스 표기는 제품 채택 전 별도 검토가 필요하다.

변환 절차는 `scripts/wall-segmentation-poc/README.md`를 기준으로 한다.

## Core ML 입출력 계약

| 모델 | 입력 | 출력 | 벽 결정 |
| --- | --- | --- | --- |
| U-Net | `image`, RGB 512×512 | `classLogits`, 1×4×512×512 | 클래스 인덱스 1 |
| RMBG | `image`, RGB 1024×1024 | `wallProbability`, 1×1×1024×1024 | 기준값 0.4 이상 |

RGB 스케일과 학습 정규화는 변환된 모델 내부에 포함한다. 앱은 입력 이미지를 모델 크기로
조정하되 추가 정규화를 하지 않는다.

## 기존 파일 계약 연결

AI는 검토 전의 `baseGrid`만 대체한다. 이후 편집, 외곽 적용, 축척 설정, 파일 생성 과정은
기존 흐름을 유지한다.

```text
LocalFloorPlanImportService
  → AI 또는 V13 baseGrid
  → 사용자 편집과 외곽 적용
  → resolvedGrid
  → LocalFloorPlanFileBuilder
  → resolved-mask.bin
```

따라서 `.bin`은 모델 파일이 아니며 모델 출력 확률을 저장하지 않는다. 최종 사용자 검토가
반영된 `LocalObstacleGrid.blocked`의 `UInt8` 값만 저장한다.

## 비교 기준

테스트 도면은 실제 사용 도면에서 개인·보안 정보를 제거한 표본을 사용한다. 모델별로
다음 항목을 같은 입력에서 기록한다.

- `.mlpackage` 용량
- 지원 대상 iPad의 첫 실행 및 반복 실행 시간
- 최대 메모리
- 얇은 벽과 곡선 벽 누락
- 문자, 치수선, 가구의 벽 오검출
- 문과 통로가 벽으로 폐쇄된 횟수
- 사용자가 추가하거나 지운 셀 수

정확도는 전체 픽셀 정확도만 사용하지 않는다. 대부분이 빈 공간인 도면에서는 벽을 많이
놓쳐도 전체 정확도가 높아질 수 있으므로 벽 IoU, recall과 사용자 수정량을 함께 본다.

## 단계

1. Colab에서 U-Net FP16 변환 및 Xcode 컴파일 확인
2. U-Net W8A16 변환 및 FP16 결과 비교
3. RMBG FP16 변환 가능성 확인
4. Core ML 출력에서 `LocalObstacleGrid`를 만드는 앱 내부 adapter 구현
5. V13과 AI 결과를 동일 도면에서 비교
6. 결과에 따라 타일 추론 또는 모바일용 모델 재학습을 별도 이슈로 분리
