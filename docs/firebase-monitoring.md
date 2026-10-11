# Firebase 사용량 알림

운영 Firebase(`cqb-wffmst`)의 사용량이 기준을 넘으면 Slack으로 알린다.
요금이 생기기 전에 버그(반복 다운로드, 리스너 중복 등)나 외부 남용을 알아채기 위해서다.

- 알림 채널: Slack `풍림화산음뢰` 워크스페이스 `#firebase-사용량알림`
- 설정 위치: [Google Cloud Monitoring 알림](https://console.cloud.google.com/monitoring/alerting?project=cqb-wffmst)

## 알림 정책

| 정책 | 기준 | 알림이 오면 |
| --- | --- | --- |
| Storage 내려받기 많음 | 1시간에 1GB 초과 | 영상이 반복해서 다운로드되거나 외부에서 받아 가는지 확인 |
| Storage 저장 용량 | 4GB 초과 | 지우지 않은 영상이 쌓였는지 확인 |
| Firestore 읽기 많음 | 1시간에 1만 회 초과 | 리스너 중복이나 반복 읽기 버그 확인 |
| Firestore 쓰기 많음 | 1시간에 5천 회 초과 | 생존 신호 주기나 반복 저장 버그 확인 |

- 기준을 넘으면 한 번 알리고, 기준 아래로 내려가면 해결됨 메시지를 보낸다. 해결되지 않으면 하루 뒤 자동으로 닫힌다.
- 메시지에는 정책 이름, 실제 값과 기준값(바이트 단위), 위의 확인할 내용이 함께 온다.
- Storage 지표는 몇 분 늦게 반영되고, 저장 용량은 하루에 한 번 갱신된다.

## 기준값을 정한 이유

- **Storage 내려받기:** 요금이 가장 많이 나오는 항목이다. 30분 영상(720p HEVC 약 2Mbps)은 약 450MB라서 교관이 대원 3명 이상의 영상을 한 시간 안에 받으면 기준을 넘는다. 테스트 중 알림이 잦으면 기준을 올린다.
- **Storage 저장 용량:** 무료 저장 한도(약 5GB)에 닿기 전에 알린다.
- **Firestore 읽기·쓰기:** 무료 한도는 하루 읽기 5만 회, 쓰기 2만 회다. 한 시간 만에 그 20%를 쓰면 버그를 의심한다.

무료 한도는 요금제와 버킷 지역에 따라 다르다. 정확한 값은 Firebase 콘솔의 **사용량 및 결제**에서 확인한다.

## 바꾸거나 끄기

[Google Cloud Monitoring 알림](https://console.cloud.google.com/monitoring/alerting?project=cqb-wffmst)에서 정책을 골라 기준값을 고치거나 끈다. 바꾸면 이 문서의 표도 함께 고친다.

## 요금

- 사용량 지표 수집과 Slack 알림 전송은 무료다.
- 알림 정책은 2027년 9월 1일부터 지표 1개당 월 $0.35가 부과된다. 4개면 월 약 $1.40. ([가격표](https://cloud.google.com/stackdriver/pricing))
