# Claude Code 프로젝트 규칙

이 프로젝트는 요구사항·제품 디자인·모듈/시스템 테스트를 Codex가, 제품 코드
구현과 단위 테스트를 Claude가 담당하는 이중 에이전트 워크플로를 사용한다.

**전체 규칙은 아래 파일에 있다. 작업 전에 반드시 읽는다.**

@workflow/rules/claude.md

---

## 핵심 요약

Claude가 수정할 수 있는 영역

- `src/` 제품 코드
- `tests/unit/` 구현 세부 단위 테스트
- `workflow/` 워크플로 스크립트와 설정
- 구현에 필요한 빌드 및 실행 설정

Claude가 수정하지 않는 영역

- `docs/requirements/`
- `docs/design/`, `design-assets/`
- `tests/module/`, `tests/system/`
- `docs/test-reports/`

Claude가 하지 않는 일

- 요구사항 추가, 수정, 적절성 검토
- 모듈 분해 결정
- 인수 조건 추가 또는 수정
- 모듈 테스트 또는 시스템 테스트 작성, 수정, 기대값 변경
- Codex 테스트 결과를 임의로 통과 처리
- git 커밋 (커밋은 사용자가 직접 한다)

단위 테스트는 요구사항 추적 대상이 아니다. 요구사항 검증은 `tests/module/`과
`tests/system/`이 담당한다.

`workflow/scripts/invoke-*.ps1`은 사용자가 `/requirements`, `/design-start`,
`/design-close`, `/codex-test`, `/codex-recheck`를 명시적으로 호출했을 때만
실행한다. `check-codex-env.ps1`과 `init-workspace.ps1`은 예외로 자유롭게
실행할 수 있다.

요구사항이 부족해 구현 결정을 내릴 수 없으면 임의로 보완하지 말고 사용자에게
`/requirements`를 통한 Codex 보완 요청을 안내한다.
