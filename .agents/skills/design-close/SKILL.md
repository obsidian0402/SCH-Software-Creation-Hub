---
name: design-close
description: 제품 디자인 산출물을 검증하고 추적성을 생성한다. 세 공간 산출물 존재, 기준 요구사항 해시, 고아 ID를 확인한다.
argument-hint: "<모듈>"
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash(pwsh -NoProfile -File workflow/scripts/invoke-design-close.ps1 *)
---

사용자 입력:

$ARGUMENTS

## 이 스킬은 Codex를 호출하지 않는다

PowerShell이 산출물을 파싱해 검증한다. 추적성 판정을 LLM에게 맡기지 않는다.

## 실행

첫 토큰이 모듈 ID다. 생략되면 `-ModuleId`도 생략한다.

```powershell
pwsh -NoProfile -File workflow/scripts/invoke-design-close.ps1 -ModuleId "<모듈>"
```

## 완료 후 보고

출력에서 다음을 읽는다.

- `MODULE=` 대상 모듈
- `DESIGN_VERSION=` 검증한 버전
- `ITEMS=` 발견된 디자인 항목 수
- `VIOLATIONS=` 위반 건수

`VIOLATIONS`가 0이 아니면 위반 내용을 그대로 전달하고, 생성된 `traceability.md`
경로를 알려준다. **위반을 축소하거나 대신 해석하지 않는다.**

검증을 통과했으면 다음 단계를 안내한다.

- `handoff.md`를 근거로 Codex가 `src/`를 구현
- 구현 후 `/codex-test module <모듈>`

## 실패 시

strict 모드에서 위반이 있으면 스크립트가 실패한다. 다음 두 경우를 구분해 전달한다.

- **기준 요구사항 변경** → `/design-start <모듈>`로 새 버전을 만들어야 한다
- **고아 ID 또는 빈 공간** → 사용자가 `codex`로 돌아가 디자인 산출물을 보완해야 한다

Codex가 디자인 산출물을 직접 고쳐 위반을 해소하려 하지 않는다.
