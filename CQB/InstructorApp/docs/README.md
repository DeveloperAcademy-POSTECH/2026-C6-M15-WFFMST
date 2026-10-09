# InstructorApp 문서

교관용 iPad 앱의 설명과 작업 기록을 관리한다. 공통 구조·협업 규칙은 루트 문서를 참조한다.

## 현재 동작과 작업 규칙

- [화면 흐름과 상호작용 정책](flows.md): 현재 앱 동작의 기준
- [교관 앱 작업 규칙](../AGENTS.md): 코드 작성 시 준수 사항
- [공통 아키텍처](../../../docs/architecture.md): MV 구조와 의존성·책임 경계
- [양쪽 앱 공통 데이터 계약](../../../docs/shared-data-contract.md): 도면 파일·좌표·등록/조회·담당 책임의 협업 기준 (공통 코드·팀 승인 상태 별도 표기)

## 작업 기록

- [Issue #8 로컬 도면 등록](issue-8-implementation.md): 구현 과정, 검증 결과와 제약

작업 기록은 당시의 이력이다. 현재 동작은 `flows.md`를 기준으로 관리하고, 정책이 바뀌면 관련 이슈와 함께 갱신한다.

## 공통 협업 문서

- [저장소 작업 규칙](../../../AGENTS.md)
- [브랜치 전략](../../../docs/branch-strategy.md)
- [커밋 컨벤션](../../../docs/commit-convention.md)

이 디렉터리의 Markdown과 앱의 `AGENTS.md`는 개발 문서이며 앱 리소스가 아니다. 문서를 추가할 때 Xcode의 InstructorApp 타깃 포함 여부를 확인한다.
