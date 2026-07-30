---
name: codex-test
description: Codex가 모듈 테스트 또는 시스템 테스트를 작성하고 실행하고 분석한다. 요구사항과 인수 조건 기반 검증이다.
argument-hint: "module <모듈> | system"
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash(pwsh -NoProfile -File workflow/scripts/invoke-test.ps1 *)
  - Bash(pwsh -NoProfile -File workflow/scripts/build-traceability.ps1 *)
---

사용자 입력:

$ARGUMENTS

## 실행

첫 토큰이 범위다.

| 첫 토큰 | 범위 |
|---|---|
| `module` | 모듈 하나의 요구사항과 인수 조건 |
| `system` | 시스템 인수 조건과 모듈 간 통합 |

`module`이면 두 번째 토큰이 모듈 ID다. 생략되면 `-ModuleId`도 생략한다.

```powershell
pwsh -NoProfile -File workflow/scripts/invoke-test.ps1 -Scope module -ModuleId "<모듈>"
```

```powershell
pwsh -NoProfile -File workflow/scripts/invoke-test.ps1 -Scope system
```

결과가 `PASS`면 이어서 추적성을 갱신한다.

```powershell
pwsh -NoProfile -File workflow/scripts/build-traceability.ps1
```

## 완료 후 보고

출력에서 다음을 읽는다.

- `REPORT=` 보고서 경로
- `RESULT=` PASS / FAIL / BLOCKED
- `CLASSIFICATION=` 실패 분류

## 분류별 처리

### PRODUCT_CODE_BUG

Claude가 대응할 차례다.

1. 보고서를 Read로 읽는다.
2. 원인을 분석한다.
3. `src/`만 수정한다.
4. 필요하면 `tests/unit/`을 추가하거나 수정한다.
5. `workflow/config.json`의 `commands.unitTest`를 실행한다.
6. 사용자에게 `/codex-test`로 재검증할 것을 안내한다.

`tests/module/`과 `tests/system/`은 **절대 수정하지 않는다.**

### TEST_OR_REQUIREMENT_SUSPECT

제품 코드를 테스트에 억지로 맞추지 않는다. 사용자에게 재검토를 안내한다.

```
/codex-recheck module <모듈> "<보고서 경로>"
/codex-recheck system "<보고서 경로>"
```

### BLOCKED_ENVIRONMENT

보고서의 사용자 조치 항목을 전달한다. 환경을 임의로 설치하거나 바꾸지 않는다.

### PASS

추적성 결과를 함께 보고한다. `VIOLATIONS`가 0이 아니면 미검증 인수 조건이나
고아 테스트가 남아 있다는 뜻이므로 그대로 알린다.

## Claude가 하지 않는 일

- 모듈 테스트 또는 시스템 테스트 작성, 수정, 삭제
- 테스트 기대값 변경
- 실패를 통과로 처리
- 요구사항 문서 수정
- 보고서 내용을 유리하게 재해석
