# 제품 디자인 지시문: {{MODULE_NAME}}

이 파일은 `/design-start`가 생성했다. 대화형 `codex` 세션에서
`@product design` 작업을 시작할 때 이 파일을 참조시킨다.

    codex
    > @product design 이 파일의 지시를 따라 작업한다: {{BRIEF_PATH}}

---

## 기준 정보 (변경 금지)

| 항목 | 값 |
|---|---|
| 모듈 ID | {{MODULE_ID}} |
| 모듈 이름 | {{MODULE_NAME}} |
| 디자인 버전 | {{DESIGN_VERSION}} |
| 기준 요구사항 | {{REQUIREMENT_PATH}} |
| 요구사항 개정 | {{REQUIREMENT_REVISION}} |
| 요구사항 해시 | {{REQUIREMENT_HASH}} |
| 시스템 개정 | {{SYSTEM_REVISION}} |
| 모드 | {{MODE}} |

## 시작 전 필수 확인

1. `workflow/rules/codex.md`를 읽는다.
2. 기준 요구사항 문서를 읽는다.
3. 기준 요구사항 문서의 SHA256을 계산해 위 `요구사항 해시`와 비교한다.
   **일치하지 않으면 작업을 시작하지 않고 사용자에게 알린다.**
   요구사항이 바뀐 상태이므로 `/design-start`를 다시 실행해야 한다.
4. 상위 시스템 요구사항 문서를 읽는다: {{SYSTEM_REQUIREMENT_PATH}}

## 이 모듈의 요구사항 ID

{{REQUIREMENT_IDS}}

모든 디자인 산출물은 위 ID 중 하나 이상을 참조해야 한다.

---

## 산출물 경로

작성은 아래 세 공간으로 **분리**한다.

    {{DESIGN_DIR}}/1-workflow/flow.md          사용자 워크플로우
    {{DESIGN_DIR}}/2-wireframe/screen-spec.md  와이어프레임
    {{DESIGN_DIR}}/3-ui/ui-spec.md             UI 스펙
    {{DESIGN_DIR}}/decision.md                 설계 결정과 근거
    {{DESIGN_DIR}}/handoff.md                  Claude 구현 인계 사항

시각 자료는 아래에 둔다.

    {{ASSETS_DIR}}/workflow/
    {{ASSETS_DIR}}/wireframe/
    {{ASSETS_DIR}}/ui/

세 공간 각각에 최소 하나의 산출물이 있어야 한다. 비어 있으면
`/design-close`가 거부한다.

`_meta.json`은 수정하지 않는다.

---

## 디자인 ID 규칙

| 종류 | 형식 | 작성 위치 |
|---|---|---|
| 사용자 흐름 | `FLOW-###` | `1-workflow/flow.md` |
| 화면 | `SCREEN-###` | `2-wireframe/screen-spec.md` |
| 상태 | `STATE-###` | `2-wireframe/screen-spec.md` |
| 컴포넌트 | `COMP-###` | `3-ui/ui-spec.md` |
| 디자인 미결 질문 | `ODQ-###` | `decision.md` |

일련번호는 세 자리로 고정한다.

## 추적성 의무 (중요)

**모든 FLOW, SCREEN, STATE, COMP 항목은 상위 요구사항 ID를 기록해야 한다.**

각 문서에서 아래 헤더의 표를 사용한다. `/design-close`가 헤더 이름으로 열을
찾으므로 문구를 바꾸면 안 된다.

    | ID | 이름 | 상위 | 설명 |
    |---|---|---|---|
    | FLOW-001 | 로그인 | MOD-{{MODULE_UPPER}}-FR-001 | |

상위가 비어 있으면 고아로 판정된다.

---

## 버전 규칙

이 버전(`{{DESIGN_VERSION}}`)은 작업 완료 후 **불변**이다. 나중에 요구사항이
바뀌면 기존 버전을 수정하지 않고 `/design-start`가 새 버전을 만든다.

---

## 수정 금지

- 기준 요구사항 문서 및 다른 모듈의 요구사항
- 다른 모듈의 디자인 산출물
- `_meta.json`
- `src/`, `tests/`
- `workflow/`
- git 커밋 및 브랜치

---

## 완료 후

사용자에게 다음을 안내한다.

    /design-close {{MODULE_ID}}

`/design-close`가 산출물 존재, 추적성, 고아 ID를 검증하고 상태를 기록한다.
