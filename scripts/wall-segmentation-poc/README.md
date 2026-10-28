# AI 벽 추출 Core ML 변환 PoC

Issue #95에서 비교할 두 공개 모델을 Google Colab에서 내려받아 Core ML
`mlpackage`로 변환한다. 원본 가중치와 변환 결과는 Git에 포함하지 않는다.

## 모델

| 스크립트 | 입력 | 출력 | 원본 라이선스 |
| --- | --- | --- | --- |
| `convert_unet_resnet34.py` | 512×512 RGB | 4채널 logits (`floor`, `wall`, `door`, `window`) | MIT |
| `convert_rmbg.py` | 1024×1024 RGB | 1채널 벽 확률 | Hugging Face 표기 `other`; 제품 사용 전 확인 필요 |

두 스크립트 모두 이미지의 0~255 RGB 값을 Core ML 입력으로 받고, 학습 시 사용한
정규화를 모델 그래프 안에서 수행한다. 따라서 앱에서 별도의 평균·표준편차 정규화를
중복 적용하면 안 된다.

## Colab 실행

Colab 런타임은 Python 3을 사용한다. GPU는 다운로드와 변환에 필수는 아니지만 RMBG
TorchScript 검증 시간을 줄이는 데 도움이 된다.

```python
!git clone https://github.com/DeveloperAcademy-POSTECH/2026-C6-M15-WFFMST.git
%cd 2026-C6-M15-WFFMST/scripts/wall-segmentation-poc
!pip install -r requirements-colab.txt
```

먼저 변환 가능성이 높은 U-Net을 실행한다.

```python
!python convert_unet_resnet34.py --int8
```

그다음 RMBG를 별도로 실행한다. 1024×1024 입력과 더 큰 네트워크를 사용하므로 더 많은
메모리와 시간이 필요하다.

```python
!python convert_rmbg.py --int8
```

FP16만 만들려면 `--int8`을 생략한다. 결과는 `outputs/`에 생성된다.

```text
outputs/
├── FloorPlanUNetResNet34-FP16.mlpackage.zip
├── FloorPlanUNetResNet34-W8A16.mlpackage.zip
├── RMBGWallSegmentation-FP16.mlpackage.zip
└── RMBGWallSegmentation-W8A16.mlpackage.zip
```

Colab에서 Mac으로 받을 파일만 선택한다.

```python
from google.colab import files
files.download("outputs/FloorPlanUNetResNet34-FP16.mlpackage.zip")
```

Mac에서 압축을 풀고 `.mlpackage`를 Xcode 프로젝트에 추가한다. `.zip`, 원본
`.safetensors`, Python 환경, CubiCasa5K 데이터셋은 Xcode에 추가하지 않는다.

## FP16과 W8A16의 의미

- FP16: 가중치와 일반 연산을 Float16으로 변환한 기준 모델이다.
- W8A16: 가중치만 INT8로 압축하고 활성값과 연산은 FP16인 비교 모델이다.

W8A16은 파일 크기를 줄이는 실험이며, 모든 연산을 INT8로 실행한다는 의미가 아니다.
두 결과는 동일한 도면 세트에서 벽 IoU뿐 아니라 얇은 벽 누락, 문 개구부 폐쇄,
사용자 수정 셀 수를 비교해야 한다.

## 검증 경계

Linux 기반 Colab에서는 `.mlpackage` 생성까지 확인할 수 있지만 Apple Core ML 런타임으로
실제 예측을 실행하거나 Neural Engine 사용 여부를 확정할 수 없다. 다음 검증은 Mac과
지원 대상 iPad에서 수행한다.

1. Xcode에서 모델 컴파일 성공
2. 입력·출력 이름과 shape 확인
3. 동일 이미지의 PyTorch 결과와 Core ML 결과 비교
4. `computeUnits = .all`에서 실기기 시간과 메모리 측정
5. FP16과 W8A16의 벽 마스크 정확도 비교

## 앱 출력 계약

모델은 `.bin`을 직접 출력하지 않는다. 모델 출력은 픽셀별 logits 또는 확률이며 앱에서
다음 순서로 기존 계약에 맞춘다.

```text
도면 이미지 → Core ML 출력 → 벽 픽셀 결정 → 원본 좌표 복원
→ 2×2 셀 집계 → LocalObstacleGrid.blocked → 사용자 편집
→ Data(blocked) → resolved-mask.bin
```

`resolved-mask.bin`은 기존과 동일한 row-major `UInt8` 배열이며 `0`은 이동 가능,
`1`은 벽·외곽을 포함한 이동 불가 셀이다.
