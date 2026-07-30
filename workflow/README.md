# 워크플로 프레임워크 (레퍼런스)

Codex(요구사항 / 제품 디자인 / 모듈·시스템 테스트)와 Claude(제품 코드 /
단위 테스트)의 역할을 파일 소유권으로 분리해 강제하는 프레임워크다.

> **처음 쓰신다면 [`GUIDE.md`](GUIDE.md) 를 먼저 읽으세요.**
>
> 이 문서는 구조와 스키마 레퍼런스입니다.
> 사용 절차, 시나리오별 대응, 문제 해결은 `GUIDE.md` 에 있습니다.

---

## 다른 프로젝트로 이식하기

다음 **3개 항목만** 복사한다. 개발 파일은 건드리지 않는다.

    workflow/          프레임워크 전체 (스크립트, 설정, 프롬프트, 규칙, 스킬)
    AGENTS.md          Codex 진입점 (얇은 포인터)
    CLAUDE.md          Claude 진입점 (얇은 포인터)

스킬 정본은 `workflow/skills/`에 있다. `.claude/skills/`는 설치 대상일 뿐이므로
복사 목록에 넣지 않는다.

복사 후 두 명령을 실행한다.

    pwsh -NoProfile -File workflow/scripts/init-workspace.ps1
    pwsh -NoProfile -File workflow/scripts/install-skills.ps1

첫 명령이 스택 프리셋을 적용하고 디렉터리를 만든다.
둘째 명령이 스킬을 `.claude/skills/`로 설치한다.

`docs/`, `src/`, `tests/` 경로는 전부 `workflow/config.json`의 `paths`에서
지정한다. 기존 프로젝트 구조가 다르면 `init-workspace.ps1` 실행 **전에**
`paths`를 수정하면 된다.

이미 `AGENTS.md` 또는 `CLAUDE.md`가 있는 프로젝트라면 루트 파일은 얇은
포인터이므로 기존 내용에 다음 한 줄만 추가해도 동작한다.

    작업 전에 workflow/rules/codex.md 를 읽는다.

---

## 파일 구성

    workflow/
      config.json        모드, 경로, 명령, ID 규칙, 단계별 허용 경로
      presets.json       스택 프리셋 5종
      state.json         워크플로 상태 (스크립트가 갱신)
      rules/
        codex.md         Codex 규칙 정본
        claude.md        Claude 규칙 정본
      prompts/           단계별 프롬프트 템플릿
        requirements-system.md   requirements-module.md
        test-module.md           test-system.md
        recheck.md               design-brief.md
      skills/            스킬 정본 (install-skills.ps1 이 .claude/skills 로 복사)
        requirements/  design-start/  design-close/
        codex-test/    codex-recheck/
      scripts/
        Common.ps1               공용 함수
        init-workspace.ps1       초기화 및 이식
        install-skills.ps1       스킬 설치 및 구 자산 정리
        check-codex-env.ps1      codex CLI 환경 진단
        invoke-requirements.ps1  system / module / confirm-modules
        invoke-design-start.ps1  디자인 버전 폴더와 지시문 생성
        invoke-design-close.ps1  디자인 산출물 검증과 추적성
        invoke-test.ps1          module / system 테스트
        invoke-recheck.ps1       의심 판정 재검토
        build-traceability.ps1   추적성 생성과 검증
      .tmp/              프롬프트 원본, stderr 로그, JUnit XML (gitignore)

---

## 작업 흐름

    /requirements system "<전체 프로그램 요청>"
      → docs/requirements/system/system.md
      → 모듈 분해 제안 + 모듈 스켈레톤 (status: proposed)

    /requirements confirm-modules
      → 사용자가 모듈 목록 확정

    /requirements module <모듈>
      → docs/requirements/modules/<모듈>/requirements.md

    /design-start <모듈>
      → docs/design/<모듈>/v001/{1-workflow,2-wireframe,3-ui}/
      → BRIEF-FOR-CODEX.md 생성

    (터미널에서 codex 를 열고 @product design 으로 직접 작업)

    /design-close <모듈>
      → 산출물 검증, 추적성 생성, 상태 기록

    (Claude 가 src/ 구현 + tests/unit/ 작성)

    /codex-test module <모듈>
    /codex-test system
      → tests/module/<모듈>/ 또는 tests/system/ 작성 및 실행
      → docs/test-reports/ 에 보고서

    /codex-recheck <보고서>
      → TEST_OR_REQUIREMENT_SUSPECT 재검토

각 Codex 단계는 **실행 전 깨끗한 git 작업 트리**를 요구한다. 커밋은 사용자가
직접 한다.

    git add -A; git commit -m "checkpoint: codex 단계 실행 전"

---

## 권한 모델

Codex CLI 0.146.0 기준으로 프로젝트 로컬 `.codex/config.toml`은 **읽히지
않는다.** `workflow/scripts/check-codex-env.ps1`의 7단계가 이를 실측한다.

따라서 권한은 두 곳에서 결정된다.

| 대상 | 결정 위치 |
|---|---|
| 스킬이 실행하는 단계 | 래퍼가 넘기는 CLI 플래그 (`config.json`의 `codex`) |
| 대화형 product design 세션 | `~/.codex/config.toml` |

기본값은 전권(`danger-full-access`, `approval: never`)이다. 능력을 제한하지
않는 대신 경계는 실행 후 가드가 지킨다.

### 가드 2겹

1. **git 경로 허용 목록** — 단계별로 허용된 경로 밖의 변경을 자동 복원하고
   실행 결과를 무효 처리한다.
2. **보호 트리 해시 스냅샷** — `src/`와 `tests/unit/`의 파일별 해시를 실행
   전후로 비교한다. `git ls-files --exclude-standard`가 못 보는 gitignore된
   파일까지 잡는다.

허용 경로는 `config.json`의 `stages`에서 단계별로 정의한다.

---

## state.json 구조

    {
      "schemaVersion": 2,
      "activeModuleId": "auth",

      "system": {
        "requirementPath": "docs/requirements/system/system.md",
        "revision": 3,
        "hash": "<SHA256>",
        "status": "requirements_ready",
        "updatedAt": "<ISO 8601>"
      },

      "modules": {
        "auth": {
          "moduleId": "auth",
          "moduleName": "인증",
          "requirementPath": "docs/requirements/modules/auth/requirements.md",
          "revision": 2,
          "hash": "<SHA256>",
          "parentSystemRevision": 3,
          "status": "requirements_ready",
          "stale": false,
          "staleReason": null,

          "design": {
            "version": 1,
            "path": "docs/design/auth/v001",
            "requirementHash": "<작업 시작 시점 해시>",
            "status": "design_ready"
          },

          "tests": {
            "module": {
              "lastRun": "<ISO 8601>",
              "result": "PASS",
              "reportPath": "docs/test-reports/module/auth/...",
              "stale": false
            }
          },

          "updatedAt": "<ISO 8601>"
        }
      },

      "history": []
    }

`status` 값: `proposed` → `confirmed` → `requirements_ready` → `design_ready` →
`implemented` → `verified`

- `proposed` Codex가 분해를 제안했고 사용자가 아직 확정하지 않음
- `confirmed` 사용자가 모듈 존재를 확정했으나 요구사항 미작성
- 그 이후는 각 단계 완료 시점

`stale`이 `true`면 strict 모드에서 `/design-start`와 `/codex-test module`이
거부된다. 시스템 요구사항 개정이 올라갈 때 이를 참조하는 모듈에 자동으로
설정되고 `/requirements module <모듈>`로만 해제된다.

`mode` 필드로 모듈별 vibe/strict를 덮어쓸 수 있다. `null`이면 프로젝트 기본값을
따른다.

---

## 모드 (vibe / strict)

`config.json`의 `mode`로 프로젝트 기본값을 정하고, `state.json`의
`modules.<모듈>.mode`로 모듈별로 덮어쓴다.

| | vibe | strict |
|---|---|---|
| 깨끗한 git 트리 요구 | 끔 | 켬 |
| 경로 허용 목록 가드 | **끔** | 켬 |
| 보호 트리 해시 가드 | 켬 | 켬 |
| `proposed` / `stale` 차단 | 경고 | 거부 |
| 추적성 위반 | 경고 | 실패 (종료 코드 1) |
| 디자인 버전 | `draft` 단일 폴더 | `v001` 불변 |

vibe 모드에서 경로 허용 목록 가드를 끄는 이유가 중요하다. 이 가드는 "실행 전
트리가 깨끗함"을 전제로 Codex의 변경을 식별한다. 더러운 트리에서 돌리면
**사용자의 기존 작업을 Codex 변경으로 오인해 자동 삭제한다.** 그래서 두 검사를
`Start-CodexGuard` / `Complete-CodexGuard` 한 쌍으로 묶어 따로 호출할 수 없게
만들었다.

보호 트리 해시 가드는 git과 무관하게 동작하므로 두 모드 모두에서 켜진다.
Codex가 `src/`나 `tests/unit/`을 건드리는 것은 어느 모드에서도 막힌다.

권장 사용법은 **탐색은 vibe, 안정된 모듈만 strict로 승격**하는 것이다.
Codex가 이미 돌아가는 코드를 읽고 요구사항을 역으로 쓸 수 있으므로, 굳은
모듈에 `/requirements module`을 사후 적용해 현재 동작을 고정하고
`/codex-test module`로 회귀를 잠그면 된다.

---

## ID 규칙

| 종류 | 형식 | 예시 |
|---|---|---|
| 시스템 기능 | `SYS-FR-###` | `SYS-FR-003` |
| 시스템 비기능 | `SYS-NFR-###` | `SYS-NFR-002` |
| 시스템 인수 조건 | `SYS-AC-###` | `SYS-AC-007` |
| 모듈 기능 | `MOD-<모듈>-FR-###` | `MOD-AUTH-FR-001` |
| 모듈 비기능 | `MOD-<모듈>-NFR-###` | `MOD-AUTH-NFR-001` |
| 모듈 인수 조건 | `MOD-<모듈>-AC-###` | `MOD-AUTH-AC-004` |
| 사용자 흐름 | `FLOW-###` | |
| 화면 | `SCREEN-###` | |
| 상태 | `STATE-###` | |
| 컴포넌트 | `COMP-###` | |
| 디자인 미결 질문 | `ODQ-###` | |

추적성 규칙:

- 모든 모듈 요구사항은 상위 `SYS-*` ID를 기록한다.
- 모든 시스템 요구사항은 구현 모듈 ID를 기록한다.
- 모든 FLOW/SCREEN/STATE/COMP는 상위 `MOD-*` ID를 기록한다.
- 모든 모듈·시스템 테스트는 이름 또는 속성에 검증 대상 `AC` ID를 포함한다.

추적성 파일(`traceability.md` / `.json`)은 PowerShell 파서가 생성한다.
LLM이 표를 채우는 방식은 신뢰할 수 없어 쓰지 않는다.

---

## 구 자산 정리

이전 구조의 잔여물은 `install-skills.ps1`이 함께 제거한다.

    .codex-workflow.json              → workflow/config.json
    .codex-workflow-state.json        → workflow/state.json
    scripts/CodexWorkflow.Common.ps1  → workflow/scripts/Common.ps1
    scripts/invoke-codex-*.ps1        → workflow/scripts/invoke-*.ps1
    .codex/                            codex CLI 가 읽지 않음이 확인됨
    .claude/skills/codex-acceptance    → codex-test 로 대체

구 스킬이 구 스크립트를 참조하므로 둘을 한 번에 정리해야 중간에 깨진 상태가
생기지 않는다. 먼저 확인만 하려면 `-WhatIfOnly`를 쓴다.

    pwsh -NoProfile -File workflow/scripts/install-skills.ps1 -WhatIfOnly

---

## 권한 모델 실측 결과

`check-codex-env.ps1`로 codex CLI 0.146.0 을 실측한 결과다.

| 항목 | 결과 |
|---|---|
| 프로젝트 `.codex/config.toml` | **무시됨** (깨진 TOML 로도 exec 정상 완료) |
| `--sandbox` 허용값 | `read-only`, `workspace-write`, `danger-full-access` |
| `--ask-for-approval` | 루트 위치에서만 지원 |
| `--output-last-message`, `--ephemeral` | `exec` 위치에서 지원 |
| `-c` / `--config` 덮어쓰기 | 지원 |
| `--dangerously-bypass-approvals-and-sandbox` | 지원 |
| `exec` 기본 승인 정책 | `never` (플래그 없이도) |

따라서 권한은 config 파일이 아니라 래퍼가 넘기는 CLI 플래그로 통제한다.
대화형 `codex` 세션만 `~/.codex/config.toml`을 따르므로 `init-workspace.ps1`이
그쪽에 `approval_policy`와 `sandbox_mode`를 추가한다.

새 버전으로 올릴 때는 다시 실측한다.

    pwsh -NoProfile -File workflow/scripts/check-codex-env.ps1
