# 브랜치 전략

| 브랜치 | 역할 |
| --- | --- |
| `main` | 훈련·시연용 안정 버전. 릴리스 PR과 hotfix로만 바뀐다 |
| `develop` | 개발 통합. 기본 브랜치 |
| `feat/12-pin-join` 등 | 이슈 하나당 하나. `develop`에서 만들어 `develop`으로 |
| `hotfix/40-upload-crash` | 급한 수정. `main`에서 만들어 `main`으로, 그다음 `develop`에도 반영 |

## 브랜치 이름

`type/이슈번호-짧은-영문`. type은 [커밋 컨벤션](commit-convention.md)과 같다. 이슈 없는 작은 작업은 번호 생략 (`chore/fix-typo`).

## 흐름

1. **작업:** 이슈 작성 → 브랜치 생성 → `develop`으로 PR → 승인 → **Merge commit**
2. **릴리스:** `develop` → `main` PR → **Merge commit** → 태그 `v0.1.0`
3. **급한 수정:** `main`에서 `hotfix/` → `main`으로 PR → 태그 → `main`을 `develop`에 머지

## PR

- 제목은 커밋 컨벤션대로 (`✨ feat: …`)
- 본문은 [PR 템플릿](../.github/pull_request_template.md)을 채우고 `Closes #번호`로 이슈를 연결한다
- 데이터 계약 변경은 기능과 별도 PR로 먼저 머지한다
