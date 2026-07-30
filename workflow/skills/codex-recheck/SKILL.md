---
name: codex-recheck
description: Codex가 TEST_OR_REQUIREMENT_SUSPECT 판정을 재검토해 테스트 결함인지 요구사항 문제인지 제품 코드 버그인지 확정한다.
argument-hint: "module <모듈> [보고서 경로] | system [보고서 경로]"
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash(pwsh -NoProfile -File workflow/scripts/invoke-recheck.ps1 *)
---

사용자 입력:

$ARGUMENTS

## 실행

첫 토큰이 범위(`module` 또는 `system`)다.

`module`이면 두 번째 토큰이 모듈 ID다. 그 뒤에 경로처럼 보이는 토큰이 있으면
`-ReportPath`로 넘긴다. 없으면 생략한다. 스크립트가 상태 파일에서 마지막
보고서를 찾는다.

```powershell
pwsh -NoProfile -File workflow/scripts/invoke-recheck.ps1 -Scope module -ModuleId "<모듈>" -ReportPath "<보고서>"
```

```powershell
pwsh -NoProfile -File workflow/scripts/invoke-recheck.ps1 -Scope system -ReportPath "<보고서>"
```

## 완료 후 보고

출력에서 다음을 읽는다.

- `RECHECK_REPORT=` 재검토 보고서 경로
- `VERDICT=` 최종 판정

## 판정별 처리

### TEST_DEFECT

Codex가 테스트를 수정하고 재실행했다. Claude는 아무것도 하지 않는다.
보고서의 재실행 결과를 사용자에게 전달한다.

### REQUIREMENT_SUSPECT

요구사항 변경이 필요하다. **Claude는 요구사항을 수정하지 않는다.**

보고서의 변경 제안을 사용자가 검토한 뒤 실행할 명령을 안내한다.

```
/requirements module <모듈>
/requirements system
```

시스템 수준 문제인지 모듈 수준 문제인지 보고서에 명시되어 있으므로 그에 맞는
명령을 안내한다.

### PRODUCT_CODE_BUG_CONFIRMED

Claude가 대응할 차례다.

1. 보고서를 Read로 읽는다.
2. 재현 절차와 근거를 확인한다.
3. `src/`만 수정한다.
4. 필요하면 `tests/unit/`을 추가하거나 수정한다.
5. `commands.unitTest`를 실행한다.
6. 사용자에게 `/codex-test`로 재검증할 것을 안내한다.

### BLOCKED_ENVIRONMENT

보고서의 사용자 조치 항목을 전달한다.

## Claude가 하지 않는 일

- 모듈 테스트 또는 시스템 테스트 수정
- 요구사항 문서 수정
- 판정을 임의로 뒤집거나 재해석
- 재검토를 반복 실행해 원하는 판정이 나오게 유도
