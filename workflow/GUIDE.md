# 사용 설명서

이 문서는 **어떻게 쓰는가**를 다룬다.
구조와 스키마 레퍼런스는 [`README.md`](README.md)에 있다.

---

## 1. 5분 요약

두 AI가 서로를 견제하며 소프트웨어를 만든다.

| 담당 | 역할 | 소유 경로 |
|---|---|---|
| **Codex** | 요구사항, 제품 디자인, 모듈·시스템 테스트 | `docs/`, `tests/module`, `tests/system`, `design-assets/` |
| **Claude** | 제품 코드, 단위 테스트 | `src/`, `tests/unit` |
| **사용자** | 결정, 승인, 커밋 | 전부 |

### 왜 이렇게 나누는가

AI가 자기 코드를 자기가 테스트하면 **테스트를 코드에 맞춰 낮춘다.** "요구사항을
쓴 쪽"과 "코드를 쓴 쪽"을 분리하면 그게 구조적으로 불가능해진다.

Codex는 코드를 못 고치니 실패를 보고밖에 할 수 없고, Claude는 테스트를 못 고치니
코드를 고칠 수밖에 없다.

### 무엇으로 강제하는가

규칙 문서로 부탁하지 않는다. Codex는 **전권 샌드박스**로 돌고, 실행이 끝난 뒤
두 겹의 가드가 소유권을 검사한다.

1. **경로 허용 목록** — 단계별로 허용된 경로 밖의 git 변경을 자동 복원하고 그
   실행을 무효 처리한다.
2. **보호 트리 해시** — `src/`와 `tests/unit/`의 파일별 SHA256을 실행 전후로
   비교한다. `.gitignore`된 파일까지 잡는다.

가드에 걸리면 그 실행 결과는 전부 폐기된다.

---

## 2. 전체 흐름

```
  /requirements system "<프로그램 설명>"
        │  Codex가 시스템 요구사항 + 모듈 분해 제안
        ▼
  ┌─ 사용자 검토 ─────────────────────┐
  │  /requirements confirm-modules     │  ← 이 단계를 건너뛸 수 없다
  └───────────────────────────────────┘
        ▼
  /requirements module AUTH
        │  Codex가 모듈 요구사항 (상위 SYS-* 연결 필수)
        ▼
  /design-start AUTH          ← Codex 호출 안 함. 폴더·지시문만 생성
        │
        │  터미널에서 codex 를 열고 @product design 으로 대화형 작업
        ▼
  /design-close AUTH          ← Codex 호출 안 함. 검증 + 추적성 생성
        │
        ▼
  Claude가 src/ 구현 + tests/unit 작성
        │
        ▼
  /codex-test module AUTH
        │  Codex가 tests/module/auth 작성·실행·판정
        ├── PASS ──────────────────────────► 다음 모듈
        ├── PRODUCT_CODE_BUG ──────────────► Claude가 src/ 수정 → 재실행
        └── TEST_OR_REQUIREMENT_SUSPECT ──► /codex-recheck module AUTH
                                                  │
                    ┌─────────────────────────────┤
                    ▼                             ▼
              TEST_DEFECT               REQUIREMENT_SUSPECT
         Codex가 테스트 수정          /requirements module AUTH
                    ▼                             │
              PRODUCT_CODE_BUG_CONFIRMED ─────────┘
              Claude가 src/ 수정

  모든 모듈이 끝나면
  /codex-test system            ← 모듈 간 통합 검증
```

각 Codex 단계 전후로 사용자가 커밋한다. 커밋은 자동화하지 않는다.

---

## 3. 처음 시작하기

### 3.1 환경 확인

```powershell
pwsh -NoProfile -File workflow/scripts/check-codex-env.ps1
```

7단계가 `FAIL`이면 프로젝트 `.codex/config.toml`이 무시된다는 뜻이다. 정상이다
(0.146.0 기준 확인됨). 권한은 래퍼가 CLI 플래그로 통제한다.

5단계가 `FAIL`이면 codex 버전이 바뀌어 인자 배치가 안 맞는 것이다.
`Common.ps1`의 `Invoke-CodexPrompt` 안 `$CodexArgs`를 고쳐야 한다.

### 3.2 초기화

```powershell
pwsh -NoProfile -File workflow/scripts/init-workspace.ps1
pwsh -NoProfile -File workflow/scripts/install-skills.ps1
```

Claude Code를 재시작하면 스킬 5종이 잡힌다.

### 3.3 README 작성

**이게 산출물 품질에 가장 큰 영향을 준다.** 루트 `README.md`가 Codex의 유일한
프로젝트 맥락 창구다. 비어 있으면 Codex는 미결 질문만 남기거나 지어낸다.

템플릿의 TODO를 채운다. 15~30줄이면 충분하다.

### 3.4 첫 커밋

```powershell
git add -A; git commit -m "chore: 워크플로 초기화"
```

---

## 4. 명령 레퍼런스

### 스킬 (Claude Code 안에서)

| 명령 | 하는 일 | Codex 호출 |
|---|---|---|
| `/requirements system "<요청>"` | 시스템 요구사항 + 모듈 분해 제안 | 예 |
| `/requirements confirm-modules [A,B]` | 모듈 목록 확정. 생략 시 전체 확정 | 아니오 |
| `/requirements module <모듈> [요청]` | 모듈 요구사항 작성 | 예 |
| `/design-start <모듈>` | 버전 폴더 + 지시문 생성 | 아니오 |
| `/design-close <모듈>` | 산출물 검증 + 추적성 | 아니오 |
| `/codex-test module <모듈>` | 모듈 테스트 작성·실행 | 예 |
| `/codex-test system` | 시스템 테스트 작성·실행 | 예 |
| `/codex-recheck module <모듈>` | 의심 판정 재검토 | 예 |
| `/codex-recheck system` | 동일 | 예 |

### 스크립트 (터미널에서)

| 명령 | 하는 일 |
|---|---|
| `check-codex-env.ps1` | codex CLI 환경 진단. 기본 무료, `-Deep`은 호출 1회 |
| `init-workspace.ps1` | 스택 프리셋 적용, 디렉터리 생성, 홈 config 패치 |
| `install-skills.ps1` | 스킬 설치 + 구 자산 정리. `-WhatIfOnly`로 미리보기 |
| `build-traceability.ps1` | 추적성 생성 + 검증. `-FailOnViolation`으로 강제 실패 |

`invoke-*.ps1`은 스킬이 호출한다. 직접 실행할 필요는 없지만 디버깅 시 유용하다.

---

## 5. ID 규칙

| 종류 | 형식 | 예시 |
|---|---|---|
| 시스템 기능 | `SYS-FR-###` | `SYS-FR-003` |
| 시스템 비기능 | `SYS-NFR-###` | `SYS-NFR-002` |
| 시스템 인수 조건 | `SYS-AC-###` | `SYS-AC-007` |
| 모듈 기능 | `MOD-<모듈>-FR-###` | `MOD-AUTH-FR-001` |
| 모듈 비기능 | `MOD-<모듈>-NFR-###` | `MOD-AUTH-NFR-001` |
| 모듈 인수 조건 | `MOD-<모듈>-AC-###` | `MOD-AUTH-AC-004` |
| 사용자 흐름 | `FLOW-###` | `FLOW-001` |
| 화면 | `SCREEN-###` | `SCREEN-001` |
| 상태 | `STATE-###` | `STATE-001` |
| 컴포넌트 | `COMP-###` | `COMP-001` |
| 디자인 미결 질문 | `ODQ-###` | `ODQ-001` |

### 연결 의무

```
SYS-FR-003 ──구현 모듈──► AUTH, CART
     ▲                       │
     └────── 상위 ───── MOD-AUTH-FR-001
                             │
                        관련 요구사항
                             ▼
                       MOD-AUTH-AC-004
                             │
                        테스트 이름에 ID
                             ▼
              it('MOD-AUTH-AC-004 ...', ...)
```

한 방향이라도 끊기면 `build-traceability.ps1`이 잡는다.

**테스트 이름에 인수 조건 ID를 넣는 것이 가장 잊기 쉽다.** 없으면 그 인수 조건은
`UNVERIFIED_AC`가 된다. 하이픈·밑줄 표기 모두 인식한다.

---

### 모듈 상태

`workflow/state.json`의 `modules.<모듈>.status`가 진행 단계를 나타낸다.

```
proposed → confirmed → requirements_ready → design_ready → implemented → verified
```

| 상태 | 의미 | 다음 명령 |
|---|---|---|
| `proposed` | Codex가 분해를 제안했고 사용자 미확정 | `/requirements confirm-modules` |
| `confirmed` | 모듈 존재 확정, 요구사항 미작성 | `/requirements module <모듈>` |
| `requirements_ready` | 모듈 요구사항 완료 | `/design-start` 또는 바로 구현 |
| `design_ready` | 디자인 검증 통과 | Claude가 `src/` 구현 |
| `implemented` | 모듈 테스트 실행했으나 미통과 | 실패 분류에 따라 대응 |
| `verified` | 모듈 테스트 통과 | 다음 모듈 |

여기에 `stale` 플래그가 독립적으로 붙는다. 상태가 `verified`여도 상위 시스템
요구사항이 개정되면 `stale: true`가 되어 후속 단계가 잠긴다.

현재 상태는 이렇게 확인한다.

```powershell
Get-Content workflow/state.json | ConvertFrom-Json | Select-Object -ExpandProperty modules
```

---

## 6. 모드 (vibe / strict)

`workflow/config.json`의 `mode`가 프로젝트 기본값이고,
`workflow/state.json`의 `modules.<모듈>.mode`가 모듈별로 덮어쓴다.

| | vibe | strict |
|---|---|---|
| 깨끗한 git 트리 요구 | 끔 | 켬 |
| 경로 허용 목록 가드 | **끔** | 켬 |
| 보호 트리 해시 가드 | 켬 | 켬 |
| `proposed` / `stale` 차단 | 경고 | 거부 |
| 추적성 위반 | 경고 | 실패 |
| 디자인 버전 | `draft` 한 폴더 | `v001` 불변 |

### vibe에서 경로 가드를 끄는 이유

이 가드는 "실행 전 트리가 깨끗함"을 기준으로 Codex의 변경을 식별한다.
더러운 트리에서 돌리면 **사용자의 미커밋 작업을 Codex 변경으로 오인해
`git restore`로 삭제한다.**

그래서 두 검사를 `Start-CodexGuard` / `Complete-CodexGuard` 한 쌍으로 묶어
스크립트가 따로 호출할 수 없게 만들었다. 안전을 코드 구조로 강제한 것이다.

보호 트리 해시 가드는 git과 무관하므로 두 모드 모두에서 동작한다.
**Codex가 `src/`나 `tests/unit/`을 건드리는 것은 어느 모드에서도 막힌다.**

### 권장 사용법

탐색은 vibe, 굳은 모듈만 strict로 승격한다.

```json
"modules": {
  "auth": { "mode": "strict" },
  "editor": { "mode": null }
}
```

Codex는 이미 돌아가는 코드를 읽고 요구사항을 **역으로** 쓸 수 있다. 모듈이
안정되면 `/requirements module`을 사후 적용해 현재 동작을 요구사항으로 고정하고,
`/codex-test module`로 회귀를 잠근 뒤 strict로 올린다.

---

## 7. 시나리오별 대응

### 요구사항을 바꾸고 싶다

**시스템 요구사항** → `/requirements system "<변경 요청>"`

개정 번호가 오르고, 그 개정을 기준으로 하지 않는 **모든 모듈이 `stale`로
표시된다.** strict 모드에서 stale 모듈은 `/design-start`와 `/codex-test module`이
거부한다.

해제 방법은 하나뿐이다. `/requirements module <모듈>`로 각 모듈을 새 시스템 개정
기준으로 갱신하는 것. 이게 요구 2번의 "서로에게 업데이트"를 기계적으로 강제하는
지점이다.

**모듈 요구사항만** → `/requirements module <모듈> "<변경 요청>"`

시스템 요구사항은 영향받지 않는다.

### 모듈을 추가하고 싶다

`/requirements system`을 다시 실행해 Codex가 모듈 분해를 다시 제안하게 한다.
기존 모듈 ID는 보존된다. 신규만 `proposed`로 추가되므로
`/requirements confirm-modules`로 확정한다.

### 모듈을 없애고 싶다

`/requirements confirm-modules A,B` 형태로 **남길 모듈만** 지정한다.
빠진 모듈은 `docs/requirements/modules/_archived/`로 이동한다. 삭제하지 않는다.

### 디자인을 다시 하고 싶다

```
/design-start <모듈> --new-version
```

`v002`가 새로 생긴다. `v001`은 그대로 남는다.

요구사항이 바뀌었다면 `--new-version` 없이도 자동으로 새 버전이 생긴다.

vibe 모드에서는 `draft` 폴더를 계속 재사용한다.

### 테스트가 실패했다

보고서의 **실패 분류**를 본다.

| 분류 | 누가 | 무엇을 |
|---|---|---|
| `PRODUCT_CODE_BUG` | Claude | `src/`와 `tests/unit/`만 수정 → `/codex-test` 재실행 |
| `TEST_OR_REQUIREMENT_SUSPECT` | Codex | `/codex-recheck` 실행 |
| `BLOCKED_ENVIRONMENT` | 사용자 | 보고서의 조치 항목 수행 |

재검토 판정별 대응.

| 판정 | 누가 | 무엇을 |
|---|---|---|
| `TEST_DEFECT` | Codex | 이미 테스트를 고치고 재실행했다. 결과만 확인 |
| `REQUIREMENT_SUSPECT` | 사용자 → Codex | 변경 제안 검토 후 `/requirements` |
| `PRODUCT_CODE_BUG_CONFIRMED` | Claude | `src/` 수정 |
| `BLOCKED_ENVIRONMENT` | 사용자 | 환경 조치 |

### 스택을 바꿨다

세 곳을 함께 갱신한다.

1. `workflow/presets.json` — 프리셋 추가 또는 수정
2. `init-workspace.ps1 -Preset <새프리셋> -Force` — config 재적용
3. `workflow/rules/claude.md` 2절과 루트 `CLAUDE.md`의 스택 불변조건

`README.md` 4절도 함께 고친다.

### 다른 프로젝트에 이식하고 싶다

`workflow/`, `AGENTS.md`, `CLAUDE.md` 세 항목만 복사한다.

경로는 전부 `config.json`의 `paths`에서 지정하므로, 기존 프로젝트 구조가 다르면
`init-workspace.ps1` 실행 **전에** `paths`를 수정한다.

이미 `AGENTS.md`/`CLAUDE.md`가 있다면 루트 파일은 얇은 포인터이므로 기존 내용에
한 줄만 추가해도 된다.

```
작업 전에 workflow/rules/codex.md 를 읽는다.
```

---

## 8. 가드가 나를 막았을 때

### "git 작업 트리가 깨끗해야 합니다"

strict 모드에서 커밋하지 않은 변경이 있다. 메시지에 복사할 명령이 포함되어 있다.

```powershell
git add -A; git commit -m "checkpoint: codex 단계 실행 전"
```

### "허용되지 않은 경로를 수정했습니다"

Codex가 담당 경로를 벗어났다. 변경은 **이미 자동 복원되었고** 그 실행은 무효다.
같은 명령을 다시 실행하면 된다. 반복되면 프롬프트 템플릿의 금지 항목을 강화한다.

### "보호 트리를 변경했습니다"

Codex가 `src/` 또는 `tests/unit/`을 건드렸다. **자동 복원되지 않는다.**
어느 모드에서도 발생하며 수동으로 되돌려야 한다.

```powershell
git status
git restore --source=HEAD --staged --worktree -- <경로>
```

### "모듈이 아직 제안 상태입니다"

`/requirements confirm-modules`를 먼저 실행한다.

### "요구사항이 낡았습니다" (stale)

`/requirements module <모듈>`로 갱신한다.

### "요구사항 파일이 상태 파일 기록과 다릅니다"

요구사항 문서를 손으로 편집했다. 두 선택지가 있다.

- `/requirements module <모듈>`로 다시 생성 (권장)
- 편집을 되돌려 해시를 맞춤

요구사항은 Codex 소유다. 손으로 고치면 추적성이 어긋난다.

---

## 9. 문제 해결

### 응답이 검증을 통과하지 못했다 (`.rejected`)

Codex 응답이 너무 짧거나 필수 구간이 없었다. **기존 문서는 덮어쓰지 않았다.**
`.rejected` 파일에 원문이 있으니 내용을 확인하고 다시 실행한다.

기준은 `config.json`의 `validation`에서 조정한다.

### 시간이 초과됐다

`config.json`의 `codex.timeoutSeconds`(기본 1800초)를 늘리거나, 작업 범위를
모듈 단위로 줄인다. 시스템 테스트가 가장 오래 걸린다.

Claude Code의 Bash 타임아웃도 따로 있다. 필요하면 `BASH_MAX_TIMEOUT_MS`를 올린다.

### 실패했는데 원인을 모르겠다

`workflow/.tmp/`에 프롬프트 원문, stdout, stderr가 **성공 시에만 삭제된다.**
실패하면 그대로 남아 있다.

```
workflow/.tmp/prompt-<단계>-<시각>.md
workflow/.tmp/stdout-<단계>-<시각>.log
workflow/.tmp/stderr-<단계>-<시각>.log
```

### 모듈 분해 표를 찾지 못했다

Codex가 `## 모듈 분해` 제목이나 표 헤더를 다르게 썼다. 요구사항 문서는 정상
저장되었으니 표만 고치면 된다. 헤더는 정확히 이래야 한다.

```
| 모듈 ID | 모듈 이름 | 책임 | 담당 시스템 요구사항 |
```

헤더 문구는 `config.json`의 `traceability.columns`에서 바꿀 수 있지만,
프롬프트 템플릿과 반드시 함께 바꿔야 한다.

### 한글이 깨진다

프롬프트는 UTF-8 파일로 전달되고 stdin에는 ASCII 한 줄만 보내므로 원칙적으로
발생하지 않는다. 발생하면 `workflow/.tmp/prompt-*.md`를 열어 파일 자체가
깨졌는지 확인한다. 파일이 정상이면 Codex 쪽 문제다.

### 추적성 위반이 너무 많다

`docs/requirements/traceability.md`의 위반 목록을 본다.

| 종류 | 의미 | 대응 |
|---|---|---|
| `ORPHAN_MODULE_REQ` | 모듈 요구사항에 상위 없음 | `/requirements module` 재실행 |
| `ORPHAN_SYSTEM_REQ` | 시스템 요구사항에 구현 모듈 없음 | `/requirements system` 재실행 |
| `ORPHAN_AC` | 인수 조건에 관련 요구사항 없음 | 해당 요구사항 재실행 |
| `DANGLING_REF` | 존재하지 않는 ID 참조 | 요구사항 재실행 |
| `UNVERIFIED_AC` | 검증 테스트 없음 | `/codex-test` 실행 |
| `ORPHAN_TEST` | 테스트가 없는 ID 참조 | `/codex-test` 재실행 |
| `STALE_TEST` | 요구사항이 테스트보다 나중에 수정됨 | `/codex-test` 재실행 |
| `MODULE_NOT_READY` | 상태가 `proposed`/`confirmed` | `/requirements module` |
| `MISSING_DOCUMENT` | 상태 파일이 가리키는 요구사항 문서가 없음 | `/requirements module` 재실행 또는 파일 복원 |
| `PARSE` | 표를 읽지 못함 | 표 헤더 확인 |

---

## 10. 설계 근거 (자주 나오는 질문)

### 왜 단위 테스트는 추적성 대상이 아닌가

단위 테스트는 함수·클래스 내부 구조에 붙어 있다. 리팩터링 한 번에 테스트 20개가
사라지고 생긴다. 이걸 요구사항 ID에 매핑하면 **추적 매트릭스가 리팩터링마다
깨지고 결국 아무도 안 믿는 문서가 된다.**

요구사항 검증 책임은 `tests/module`과 `tests/system`이 진다.

### 왜 추적성을 Codex가 아니라 PowerShell이 만드는가

추적성은 기계적 작업이다. LLM에게 표를 채우라고 하면 **그럴듯하게 채운다.**
검증되지 않은 "PASS"는 검증이 없는 것보다 나쁘다.

파서는 요구사항 표 + 테스트 소스 스캔 + JUnit XML을 조인한다. 셋 다 사람이
꾸밀 수 없는 자료다.

### 왜 제품 디자인만 대화형인가

`codex exec`는 일회성이다. 요구사항 작성이나 테스트 실행처럼 "던지면 결과 나오는"
작업에는 완벽하다.

제품 디자인은 본질적으로 반복 대화다. "이 화면 이렇게 바꿔줘"를 왕복해야 하는데
일회성으로 감싸면 매번 처음부터 시작한다. 그래서 디자인 작업 자체는 대화형에
남기고, 스킬은 앞뒤(버전 폴더 생성, 검증)만 잡는다.

### 왜 Codex에 전권을 주는가

능력을 제한하면 Codex가 패키지를 설치하거나 테스트를 실행하지 못한다. 그건
작업 자체를 못 하게 만드는 것이다.

대신 경계는 **사후에** 검사한다. Codex는 무엇이든 할 수 있지만, 담당 영역을
벗어난 결과는 남지 못한다.

### 왜 프로젝트 `.codex/config.toml`을 안 쓰는가

codex CLI 0.146.0에서 **읽히지 않음이 실측으로 확인됐다.** 깨진 TOML을 심어도
`codex exec`가 정상 완료했다. `check-codex-env.ps1`의 7단계가 이 테스트다.

권한은 래퍼가 넘기는 CLI 플래그로 통제한다. 이식성에도 유리하다.
대화형 세션만 `~/.codex/config.toml`을 따른다.

### 왜 커밋을 자동화하지 않는가

가드가 "실행 전 상태"를 기준으로 침범을 판정한다. 커밋 시점은 그 기준선을
정하는 행위이므로 사람이 의도적으로 결정해야 한다.

자동 커밋은 검토하지 않은 상태를 기준선으로 만들어 가드를 무력화한다.

### 왜 프롬프트를 파일로 넘기는가

`codex`는 npm 전역 설치 시 `.cmd` 셔임으로 잡힌다. 한글을 argv나 파이프로 넘기면
cmd.exe를 경유하며 깨질 수 있다.

프롬프트 전문을 UTF-8 파일로 쓰고 stdin에는 ASCII 한 줄만 보내면 한글이 프로세스
경계를 넘지 않는다. 덤으로 실패 시 프롬프트가 남아 진단이 된다.

---

## 11. 알려진 한계

정직하게 적어둔다.

### 아직 실전 검증되지 않음

구문 검사, JSON 유효성, 프롬프트 자리표시자 대조, 함수 호출 대조는 통과했다.
그러나 **실제 Codex 왕복은 아직 한 번도 하지 않았다.** 첫 실행에서 다음이
문제될 수 있다.

- Codex가 모듈 분해 표 헤더를 정확히 쓰는지
- `codex exec --ephemeral` 조합이 실제로 동작하는지
- Codex가 stdin의 ASCII 지시를 받아 프롬프트 파일을 읽는지

실패하면 `workflow/.tmp/`의 로그를 확인한다.

### 시스템 테스트 JUnit 경로

Playwright는 `playwright.config.ts`에서 리포터 출력 경로를 지정해야 한다.
프리셋의 명령만으로는 부족하다.

```ts
reporter: [['junit', { outputFile: 'workflow/.tmp/junit/system.xml' }]]
```

### 모듈 수가 많아지면

추적성 마크다운이 길어진다. 20개를 넘으면 `traceability.json`을 정본으로 쓰고
마크다운은 요약만 보게 된다.

### 단일 활성 모듈

`state.json`의 `activeModuleId`는 하나다. 여러 모듈을 병행 작업하려면 명령마다
모듈 ID를 명시해야 한다.

### 디자인 버전 되돌리기

`v002`를 만든 뒤 `v001`로 돌아가는 명령은 없다. `state.json`의
`modules.<모듈>.design`을 손으로 고쳐야 한다.

---

## 12. 첫 실행 체크리스트

```
[ ] check-codex-env.ps1 실행, 5단계 OK 확인
[ ] init-workspace.ps1 로 스택 프리셋 적용
[ ] install-skills.ps1 로 스킬 설치
[ ] Claude Code 재시작 후 스킬 5종 확인
[ ] 루트 README.md 의 TODO 채우기          ← 품질에 가장 큰 영향
[ ] git add -A; git commit
[ ] /requirements system "<프로그램 설명>"
[ ] 모듈 분해 표 검토
[ ] /requirements confirm-modules
[ ] /requirements module <첫 모듈>
[ ] git commit
```
