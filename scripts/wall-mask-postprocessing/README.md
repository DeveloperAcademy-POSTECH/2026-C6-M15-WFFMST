# 이동 불가 영역 보수적 후처리 실험

Issue #111에서 Core ML 원본 마스크를 보존하면서 작은 고립 영역과 작은 내부 구멍만
정리했을 때 사용자 편집량이 줄어드는지 비교한다. 이 도구는 앱의 기본 추론 경로에
후처리를 적용하지 않는다.

## 안전 조건

- 이미지 경계에 닿은 blocked 성분은 제거하지 않는다.
- blocked 성분은 8방향 연결, 내부 free 구멍은 4방향 연결로 판정한다.
- 이미지 경계와 연결된 free 영역은 채우지 않는다.
- 전체 추가·삭제 셀 수는 `maximumChangedFraction`을 넘지 않는다.
- 원본 마스크와 후처리 마스크를 모두 저장한다.

기본값은 2px 격자 기준 blocked 성분 8셀 미만 제거, 내부 구멍 8셀 이하 채우기,
전체 격자의 0.5% 변경 상한이다. 이 값은 실험 기준이며 제품 정책이 아니다.

직선 정렬은 기본적으로 꺼져 있다. 활성화하면 충분히 긴 가로·세로 run이 2행 이상
연속되고 각 끝점 차이가 제한값 이내일 때만 끝점을 중앙값으로 맞춘다. 수직 방향의
blocked 지지가 있는 셀은 코너 또는 교차점일 수 있으므로 삭제하지 않는다.

## 빌드

저장소 루트에서 모델과 실행기를 같은 `outputs/` 디렉터리에 만든다.

```bash
mkdir -p scripts/wall-mask-postprocessing/outputs
xcrun coremlcompiler compile \
  CQB/InstructorApp/Resources/Models/BinaryWallSegmentation.mlpackage \
  scripts/wall-mask-postprocessing/outputs
xcrun swiftc -parse-as-library -O \
  scripts/wall-mask-postprocessing/coreml_postprocess_main.swift \
  CQB/InstructorApp/Services/Import/LocalAIWallDetector.swift \
  CQB/InstructorApp/Services/Import/LocalAIWallMaskGridBuilder.swift \
  CQB/InstructorApp/Services/Import/LocalWallMaskPostprocessor.swift \
  -framework CoreML -framework CoreGraphics -framework ImageIO \
  -framework CoreVideo -framework UniformTypeIdentifiers \
  -o scripts/wall-mask-postprocessing/outputs/coreml-postprocess
```

## 실행

```bash
scripts/wall-mask-postprocessing/outputs/coreml-postprocess \
  --output scripts/wall-mask-postprocessing/outputs/conservative \
  --minimum-component-area 8 \
  --maximum-hole-area 8 \
  --maximum-changed-fraction 0.005 \
  /path/to/floorplans/*.png
```

제한적 직선 정렬 비교는 다음 옵션을 추가한다.

```bash
  --minimum-axis-length 24 \
  --maximum-axis-thickness 12 \
  --maximum-axis-snap-distance 2
```

`metrics.json`, 정규화된 원본, Core ML 원본 PGM, 후처리 PGM이 생성된다.

시각화는 Pillow만 사용한다.

```bash
python3 -m pip install -r scripts/wall-mask-postprocessing/requirements.txt
python3 scripts/wall-mask-postprocessing/render_comparison.py \
  scripts/wall-mask-postprocessing/outputs/conservative
```

비교 이미지의 검정은 유지된 blocked 셀, 빨강은 제거된 셀, 파랑은 추가된 셀이다.

## 해석

작은 변화량만으로도 문자·가구 오검출이 줄어드는지 먼저 확인한다. 실제 얇은 벽이
제거되거나 문·개구부가 채워지면 해당 파라미터는 폐기한다. 직선 정렬과 짧은 틈 연결은
이 결과를 확인한 뒤 별도 단계로 추가하며, 이 실험 결과만으로 앱 기본 동작을 변경하지 않는다.
