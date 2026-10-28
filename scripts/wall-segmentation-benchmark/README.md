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

환경 변수 대신 macOS 키체인의 `wffmst-openai-api-key` 항목도 사용할 수 있다. 키 값은
로그에 출력하지 않는다.

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

## 2026-10-28 일반 아파트 3장 1차 결과

Core ML은 앱 후보와 동일한 `crop + high contrast + overlap tile`, threshold 0.5를 사용했다.
GPT는 `gpt-6-astra`, 이미지 detail `original`, 최대 256개 정규화 벽 선분 계약을 사용했다.
Foundation Models 이미지 입력은 Xcode 27에서 컴파일했지만 현재 Mac이 macOS 26.7.1이라
실제 추론에서 제외했다.

| 도면 | Core ML 시간 | GPT 시간 | GPT 선분 | GPT 토큰 | Core ML blocked | GPT blocked |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Apartment A, 3 bedrooms | 0.984초 | 32.245초 | 39 | 4,121 | 8.09% | 6.39% |
| Apartment B, 2 bedrooms | 0.944초 | 34.966초 | 41 | 3,999 | 7.58% | 6.62% |
| Apartment C, 3 bedrooms | 0.946초 | 41.852초 | 51 | 4,378 | 7.78% | 8.49% |

시간은 개발 Mac의 1회 측정값이며 Core ML 실기기 성능이나 네트워크 상태의 대표값이 아니다.
정답 마스크가 없는 실제 도면이므로 blocked 비율은 정확도 지표로 해석하지 않는다.

정성 비교에서 GPT는 문자·가구·치수선을 거의 배제하고 외곽, 주요 내부벽, 문 개구부를
정돈된 직선으로 표현했다. Core ML은 실제 벽 두께와 짧은 세부 형상을 더 충실히 보존했지만
치수선과 욕실 내부 요소 일부도 검출했다. GPT 결과는 생성형 선분이므로 곡선·비정형 벽,
반복 실행 안정성, 좌표 오차를 추가로 확인해야 하며 30초 이상의 네트워크 지연 때문에
기본 온디바이스 경로를 즉시 대체할 후보는 아니다.

재현용 출력은 Git에 포함하지 않는 `outputs/`에 저장한다.

```text
outputs/
├── coreml-vs-gpt-apartments.png
├── coreml-vs-gpt-metrics.json
├── coreml/
└── gpt/
```
