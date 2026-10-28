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

## 2026-10-28 축소 실험 결과

T4 GPU에서 train 1,000장, validation 200장, 2 epochs로 방향성 검증을 실행했다.
validation에도 학습과 다른 고정 seed의 합성 방해 요소를 넣어 해당 영역의 오검출률을
측정했다.

| 모델 | wall IoU | Precision | Recall | 방해 요소 FP rate |
| --- | ---: | ---: | ---: | ---: |
| 기존 4-class baseline | 0.3407 | 0.5368 | 0.4825 | 0.4865 |
| binary fine-tuned | 0.6302 | 0.7394 | 0.8102 | 0.0453 |

이 축소 실험에서는 앱의 blocked/free 목적함수와 합성 음성 샘플이 모든 지표를 개선했고,
방해 요소 FP rate는 약 90.7% 상대 감소했다. 단, validation도 CubiCasa5K이며 합성 요소의
모양이 학습과 같은 생성 규칙을 사용하므로 실제 예상 도면에 대한 일반화가 입증된 것은
아니다. 다음 판단은 학습에 사용하지 않은 실제 도면 6장의 정성 비교와 사용자 수정 셀 수로
내린다.

## 실제 도면 6장 비교

학습 데이터 밖의 도면 폴더는 다음 명령으로 기존 모델과 fine-tuned 모델을 같은
512×512 letterbox 입력과 0.5 임계값에서 비교한다.

```bash
python compare_actual_floorplans.py /path/to/floorplans \
  outputs/binary-finetune/BinaryWallSegmentation.safetensors \
  --output outputs/binary-finetune/actual-comparison.png \
  --tile-size 1024 --tile-overlap 0.25 --tile-weight 0.75
```

일반 아파트 도면 3장은 벽 연속성과 가구·글씨 억제가 뚜렷하게 개선됐다. 반면 세로로
매우 긴 도면은 512 축소 후 거의 검출되지 않았고, 복잡한 컬러 CAD형 도서관 도면은 곡선
좌석과 외곽선을 벽으로 오검출했다. 따라서 이진 fine-tuning 방향은 유효하지만, 큰 도면에는
overlap tile 추론을 함께 적용해야 한다.

비교 스크립트는 전체 이미지를 512로 축소한 확률 맵과, 원본을 1,024px 정사각형으로
25% 겹쳐 자른 타일 확률 맵을 각각 만든다. 타일 경계는 사인 가중치로 합치고 최종 확률은
전역 25% + 타일 75%로 결합한다.

### 2026-10-28 타일 크기 비교

실제 도면 6장에 25% overlap과 전역 25% + 타일 75% 결합을 고정하고 타일 크기만
1,024px와 512px로 비교했다.

| 도면 | 전체 512 blocked 비율 | 1,024px 타일 | 512px 타일 |
| --- | ---: | ---: | ---: |
| 세로형 C5 | 0.0116 | 0.0167 | 0.0256 |
| 도서관 4층 | 0.0697 | 0.0643 | 0.0546 |
| 도서관 5층 | 0.0770 | 0.0666 | 0.0486 |
| 일반 아파트 3장 범위 | 0.0881–0.1119 | 0.0872–0.1079 | 0.0809–0.0904 |

512px 타일은 세로형 C5의 희미한 벽선을 가장 많이 복구했지만 가구와 도면 내부의 얇은
선도 함께 검출했다. 1,024px 타일은 일반 아파트 결과를 거의 보존했지만 C5 복구 효과는
작았다. 따라서 타일을 항상 적용하기보다, 종횡비가 크거나 전체 축소율이 큰 도면에만
작은 타일을 적용하고 일반 도면은 전역 결과를 우선하는 adaptive 정책이 필요하다.
