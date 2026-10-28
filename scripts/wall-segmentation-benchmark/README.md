# 벽 추출 방식 비교 Spike

Core ML, Apple Foundation Models, GPT API를 최종 `blocked/free` 결과 기준으로 비교한다.
Core ML은 픽셀 확률맵을 직접 만들고, 생성형 모델은 정규화된 벽 중심선과 두께를 만든 뒤
동일한 원본 크기 마스크로 rasterize한다. 생성형 모델에 512×512 전체 마스크를 텍스트로
출력시키면 좌표당 토큰이 필요하므로 비교 계약으로 사용하지 않는다.

## 고정 조건

- 입력: 학습에 사용하지 않은 일반 아파트 도면 3장
- 좌표: 좌상단 원점, X/Y `0...1000`
- 장애물: `wall || window`
- 이동 가능: `floor || door || passable opening`
- 후처리: 결과를 원본 크기 이진 마스크로 변환한 뒤 앱과 같은 2px 격자로 샘플링
- 비교: 벽 연속성, 가구·글씨 오검출, 문/개구부 보존, 사용자 수정량, 처리 시간,
  앱 용량, 네트워크·지원 OS 제약

생성형 모델은 최대 256개의 직선 벽 선분을 반환한다. 문과 뚫린 벽은 별도 의미 클래스로
분류하지 않고, 벽 선분이 끊긴 `free` 구간으로 표현한다.

## GPT API

Responses API의 이미지 입력과 Structured Outputs를 사용한다. 키가 설정된 환경에서만 실제
요청을 보내며, 이미지가 API 제공자에게 전송되고 사용량 비용이 발생한다.

```bash
export OPENAI_API_KEY='...'
python run_gpt_api.py /path/to/floorplan.png \
  --output outputs/gpt/floorplan.json
python render_vector_result.py /path/to/floorplan.png \
  outputs/gpt/floorplan.json \
  --output outputs/gpt/floorplan-comparison.png \
  --title 'GPT API'
```

기본 모델은 이미지 입력과 구조화 출력을 지원하는 `gpt-6-astra`다. 응답 JSON과 함께 모델,
응답 ID, 처리 시간, 토큰 사용량을 별도 metadata JSON에 저장한다.

## Apple Foundation Models

Foundation Models의 이미지 `Attachment`와 `@Generable`을 사용한다. 이미지 프롬프트는
iOS 27/macOS 27 기능이며 Apple Intelligence 지원 기기에서만 후보가 된다. 현재 개발 Mac은
macOS 26.7.1이므로 소스 컴파일까지만 검증하고 로컬 추론은 macOS 27 또는 iOS 27 실기기에서
실행한다.

```bash
xcrun swiftc -parse-as-library -target arm64-apple-macosx27.0 \
  foundation_models_wall_spike.swift \
  -o outputs/foundation-models-wall-spike
outputs/foundation-models-wall-spike /path/to/floorplan.png \
  outputs/foundation/floorplan.json
```

## 해석

이 비교는 각 접근의 내부 표현을 같게 만드는 실험이 아니다. 최종 이진 장애물 마스크와
동선 보정 결과를 같게 맞추는 비교다. 생성형 모델의 벽 선분 출력이 도면 곡선이나 복잡한
벽 형태를 충분히 표현하지 못하면 모델 성능과 별개로 이 계약 자체를 폐기한다.
