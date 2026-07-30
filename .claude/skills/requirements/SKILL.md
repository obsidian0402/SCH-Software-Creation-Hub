---
name: requirements
description: Codex가 요구사항 작성, 수정, 자체 검토와 인수 조건 작성을 전담한다.
argument-hint: "<기능 이름과 요청 내용>"
disable-model-invocation: true
allowed-tools:
  - Bash(pwsh -NoProfile -File scripts/invoke-codex-requirements.ps1 *)
---

사용자 요청:

$ARGUMENTS

Claude는 요구사항을 분석하거나 검토하지 않는다.

다음 작업만 수행한다.

1. 요청에서 짧은 기능 이름을 정한다.
2. 사용자 요청 전문을 변경하지 않고 스크립트에 전달한다.
3. 다음 명령을 실행한다.

```powershell
pwsh -NoProfile `
  -File scripts/invoke-codex-requirements.ps1 `
  -FeatureName "<짧은 기능 이름>" `
  -Request "<사용자 요청 전문>"

4. 생성된 요구사항 문서 경로를 알려준다.
5. 제품 구현을 시작하지 않고 종료한다.


## 기존 활성 기능 처리

`.codex-workflow-state.json`이 존재하면 먼저 읽는다.

사용자의 요청이 현재 활성 기능을 수정하는 내용이라면:

- 기존 `featureName`을 그대로 사용한다.
- 기존 `featureId`를 그대로 사용한다.
- 새로운 기능 이름을 만들지 않는다.
- 기존 `requirementPath`의 요구사항을 수정한다.

사용자가 명시적으로 새로운 기능을 요청한 경우에만
새로운 기능 이름과 featureId를 생성한다.
