# InstructorApp 문서

교관용 iPad 앱의 설명과 작업 기록을 관리한다. 공통 구조·협업 규칙은 루트 문서를 참조한다.

## 현재 동작과 작업 규칙

- [화면 흐름과 상호작용 정책](flows.md): 현재 앱 동작의 기준
- [교관 앱 작업 규칙](../AGENTS.md): 코드 작성 시 준수 사항
- [공통 아키텍처](../../../docs/architecture.md): MV 구조와 의존성·책임 경계

## 작업 기록

- [Issue #8 로컬 도면 등록](issue-8-implementation.md): 구현 과정, 검증 결과와 제약
- [Issue #49 세션·준비 상태 연동](issue-49-implementation.md): 구현 범위, 경계 조건 회귀 검사와 실제 앱 검증
- [Issue #56 훈련·기록 생명주기 연동](issue-56-implementation.md): 서버 상태 전환, 기록 종결 대기, 회귀·에뮬레이터 검증
- [Issue #80 데모 실행 환경](issue-80-implementation.md): TestFlight 심사용 메모리 저장소와 세션 흐름
- [Issue #82 데모 AAR 샘플](issue-82-implementation.md): 결과 처리 완료, 3인 동선과 번들 영상 흐름

작업 기록은 당시의 이력이다. 현재 동작은 `flows.md`를 기준으로 관리하고, 정책이 바뀌면 관련 이슈와 함께 갱신한다.

## 공통 협업 문서

- [저장소 작업 규칙](../../../AGENTS.md)
- [브랜치 전략](../../../docs/branch-strategy.md)
- [커밋 컨벤션](../../../docs/commit-convention.md)

이 디렉터리의 Markdown과 앱의 `AGENTS.md`는 개발 문서이며 앱 리소스가 아니다. 문서를 추가할 때 Xcode의 InstructorApp 타깃 포함 여부를 확인한다.
