---
name: codex-recheck
description: Codex가 의심스러운 테스트 실패를 재검토한다.
argument-hint: "<요구사항 경로> | <테스트 보고서 경로>"
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash(pwsh -NoProfile -File scripts/invoke-codex-recheck.ps1 *)
---

입력:

$ARGUMENTS

`|` 왼쪽을 요구사항 문서 경로로 사용한다.

`|` 오른쪽을 기존 인수 테스트 보고서 경로로 사용한다.

다음 명령을 실행한다.

```powershell
pwsh -NoProfile `
  -File scripts/invoke-codex-recheck.ps1 `
  -RequirementPath "<요구사항 경로>" `
  -TestReportPath "<테스트 보고서 경로>"

완료 후 다음을 보고한다.

재검토 보고서 경로
최종 판정
테스트 수정 여부
요구사항 변경 제안 여부
다음 조치

Claude Code의 도구 권한은 `allowed-tools` 또는 CLI의 `--allowedTools`를 통해 제한할 수 있습니다. 공식 예시에서 셸 명령 권한은 `Bash(...)` 패턴을 사용합니다. :contentReference[oaicite:2]{index=2}
