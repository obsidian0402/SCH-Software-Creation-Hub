---
name: codex-acceptance
description: Codex가 요구사항과 인수 조건 기반 인수 테스트를 작성하고 실행·분석한다.
argument-hint: "<요구사항 문서 경로>"
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash(pwsh -NoProfile -File scripts/invoke-codex-acceptance.ps1 *)
---

테스트 대상:

$ARGUMENTS

다음 스크립트를 실행한다.

```powershell
pwsh -NoProfile `
  -File scripts/invoke-codex-acceptance.ps1 `
  -RequirementPath "$ARGUMENTS"

완료 후 다음을 보고한다.

테스트 보고서 경로
전체 결과
실패 분류
다음 조치

Claude는 이 Skill 실행 중 제품 코드, 단위 테스트 또는 인수 테스트를 직접 수정하지 않는다.