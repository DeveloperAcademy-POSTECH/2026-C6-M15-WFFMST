# CubiCasa5K 이진 벽 마스크 fine-tuning 실험

Issue #96은 기존 4-class U-Net을 앱의 이동 가능성 기준에 직접 맞춘 이진 모델로
fine-tuning한다. CubiCasa5K COCO polygon에서 `wall + window`는 blocked, `door`를 포함한
나머지는 free로 합친다. free 영역에는 글씨, 치수선, 단순 가구 선을 합성하여 이 요소를
벽으로 오검출하는 비율이 기존 모델보다 줄어드는지 비교한다.

데이터셋은 Hugging Face streaming으로 읽으므로 2GB 전체 데이터셋을 Mac이나 Colab
드라이브에 미리 내려받지 않는다. 실행 중인 샘플과 Hub 캐시만 Colab 런타임의 임시
저장소를 사용하며 런타임을 삭제하면 함께 사라진다.

COCO polygon은 원본 크기의 마스크를 만들지 않고 512×512 letterbox 좌표로 직접
변환한다. 4천만 픽셀을 넘는 극단적인 원본 outlier는 전처리 병목을 피하기 위해 건너뛴다.
Hugging Face image column도 lazy decode하여 outlier는 원본 이미지를 열기 전에 제외한다.

## Colab 실행

GPU 런타임에서 다음 명령을 실행한다. 저장소 clone URL은 실제 원격 저장소 주소로
바꾼다.

```python
!git clone --branch feat/96-binary-wall-finetune \
  https://github.com/DeveloperAcademy-POSTECH/2026-C6-M15-WFFMST.git
%cd 2026-C6-M15-WFFMST/scripts/wall-segmentation-finetune
!pip install -r requirements-colab.txt
!python -m unittest -v test_binary_wall_data.py
```

먼저 64장으로 입출력과 마스크 방향을 확인한다.

```python
!python train_binary_wall.py \
  --epochs 1 \
  --max-train-samples 64 \
  --max-valid-samples 32 \
  --batch-size 4
```

smoke test가 통과하면 본 실험을 실행한다.

```python
!python train_binary_wall.py \
  --epochs 3 \
  --max-train-samples 3000 \
  --max-valid-samples 300 \
  --batch-size 4 \
  --synthetic-probability 0.75 \
  --export-coreml
```

메모리가 부족하면 batch size만 2로 낮춘다. 결과는 Git에 포함하지 않는 `outputs/`에
생성된다.

```text
outputs/binary-finetune/
├── BinaryWallSegmentation.safetensors
├── BinaryWallSegmentation-FP16.mlpackage/
├── BinaryWallSegmentation-FP16.mlpackage.zip
├── comparison.png
└── metrics.json
```

`comparison.png`는 원본, 이진 정답, 기존 4-class 모델, fine-tuned 모델을 한 장에
보여준다. `metrics.json`에는 wall IoU·precision·recall과 합성 방해 요소 영역의
false-positive rate가 기록된다. `distractor_false_positive_rate`는 낮을수록 좋다.

Mac으로 받을 파일은 비교 이미지와 지표, 채택 가능성이 확인된 경우 Core ML ZIP이다.

```python
from google.colab import files

files.download("outputs/binary-finetune/comparison.png")
files.download("outputs/binary-finetune/metrics.json")
files.download("outputs/binary-finetune/BinaryWallSegmentation-FP16.mlpackage.zip")
```

## 해석 시 주의점

- 기존 모델도 CubiCasa5K 계열이므로 이 실험은 새로운 도면 스타일을 학습시키는 실험이
  아니라 앱의 blocked/free 목적함수를 직접 최적화하는 실험이다.
- 합성 선은 실제 도면의 모든 문자·가구 분포를 대신하지 못한다. 실제 예상 입력 6장은
  학습에 넣지 않고 최종 비교용으로 유지한다.
- 데이터셋은 CubiCasa5K 연구용 라이선스를 따른다. 제품 채택 전 원본 라이선스를 다시
  검토한다.
