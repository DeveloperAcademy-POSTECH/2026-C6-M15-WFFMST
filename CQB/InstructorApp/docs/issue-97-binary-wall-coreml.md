# Issue #97 Fine-tuned 이진 벽 모델 Core ML 적용

## 목적

Issue #96에서 검증한 이진 벽 분할 모델을 InstructorApp의 도면 가져오기 흐름에 연결한다.
AI가 만드는 것은 최종 파일이 아니라 사용자가 검토할 `baseGrid`이며, 외곽·편집·축척과
`resolved-mask.bin` 생성 흐름은 그대로 유지한다.

## 모델 계약

- 기반 모델: `Yytsi/floorplan-to-3d-walls` U-Net ResNet-34
- 학습 데이터: `phungpx/cubicassa5k-coco`
- 학습 레이블: `blocked = wall || window`, `free = floor || door || other`
- 입력: `image`, RGB 512×512
- 출력: `blockedProbability`, `[1, 1, 512, 512]`, Float16
- Core ML 형식: ML Program, iOS 17+, FP16
- 모델 패키지: `BinaryWallSegmentation.mlpackage`
- 변환 ZIP SHA-256: `e5fa3e8538bab6307b92f3719ad39af4972057c92fb9dea5ba6098ead38df332`

모델 내부에 `1/255` 스케일, ImageNet 정규화와 sigmoid가 포함된다. 앱은 추가 정규화나
softmax 없이 `blockedProbability`를 읽고, 기본 임계값 0.5를 적용한다.

## 앱 연결

`LocalAIWallDetector`가 전역 입력과 겹치는 타일을 같은 모델로 추론한다. 전역 결과에는
전체 배치 맥락을 위한 가중치 0.5를 주고, 타일 결과와 평균한 뒤 기존 2px 장애물 격자로
복원한다. 결과 파일의 추출 버전은 `unet-resnet34-binary-fp16-v1`로 기록한다.
모델 로드나 추론이 실패하면 기존 V13 추출기로 fallback하고, 이 경우 결과 파일에는 실제로
사용한 `v13-wall-detector`를 기록한다. 취소 요청은 fallback하지 않고 즉시 전파한다. 추출된
`baseGrid`에는 이동 불가 영역 자동 보정을 적용한 뒤 기존 편집·축척·저장 흐름으로 전달한다.

Issue #96의 200장 검증 표본에서 벽 IoU는 0.3407에서 0.6302로, recall은 0.4825에서
0.8102로 증가했고 합성 방해 요소 오검출률은 0.4865에서 0.0453으로 감소했다. 이는 앱
실사용 도면의 정확도를 보장하지 않으므로 기기별 시간·메모리와 사용자 수정량은 별도로
측정해야 한다.

## 라이선스 메모

기반 모델은 MIT로 배포된다. 학습에 사용한 CubiCasa5K는 CC BY-NC 4.0이며,
`phungpx/cubicassa5k-coco`도 원 데이터셋 조건을 따른다. 이 fine-tuned 패키지는 저장소에서
비상업적 연구·교육 목적으로만 사용한다. 모델 리소스의 라이선스 안내에는 원 데이터셋,
라이선스 링크, 재가공 데이터 출처, 이진 레이블 구성·fine-tuning·Core ML 변환 내역과
CubiCasa5K 논문 인용을 함께 기록한다. 향후 상업적 이용이 필요해지면 별도 허가 또는
상업 이용 가능한 데이터로 재학습하기 전까지 이 가중치를 배포하지 않는다.

## 후속 실험

Grad-CAM은 오검출 시 모델이 문자·가구·벽 중 어디를 근거로 삼았는지 진단하는 도구로
분리한다. CBAM 같은 attention 구조 변경은 모델 재학습과 동일 조건 ablation이 필요하므로
현재 런타임 연결 작업에는 포함하지 않는다.
