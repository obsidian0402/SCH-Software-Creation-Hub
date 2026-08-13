---
name: requirements
description: Codex가 시스템 및 모듈 요구사항 작성과 자체 검토, 인수 조건 정의를 전담한다. 모듈 분해 확정도 처리한다.
argument-hint: "system <요청> | module <모듈> [요청] | confirm-modules [모듈,모듈]"
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash(pwsh -NoProfile -File workflow/scripts/invoke-requirements.ps1 *)
  - Write(workflow/.tmp/**)
---

사용자 입력:

$ARGUMENTS

Codex는 요구사항을 분석하거나 검토하거나 수정하지 않는다. 스크립트를 실행하고
결과를 보고하는 역할만 한다.

## 1. 첫 토큰으로 모드를 판별한다

| 첫 토큰 | 모드 |
|---|---|
| `system` | 전체 프로그램 요구사항 + 모듈 분해 제안 |
| `module` | 모듈 하나의 요구사항 |
| `confirm-modules` | 제안된 모듈 목록 확정 |

첫 토큰이 위 셋 중 하나가 아니면 `system`으로 간주하고 입력 전체를 요청으로
취급한다.

## 2. 요청 본문은 파일로 전달한다

요청 본문에 한글이나 줄바꿈이 있으면 인자로 넘기지 않는다. 인코딩과 인용부호
문제가 생긴다.

Write 도구로 `workflow/.tmp/request.md`에 요청 전문을 저장한 뒤 `-RequestFile`로
넘긴다. 요청 원문은 한 글자도 바꾸지 않는다.

## 3. 모드별 실행

### system

```powershell
pwsh -NoProfile -File workflow/scripts/invoke-requirements.ps1 -Mode system -RequestFile workflow/.tmp/request.md
```

### module

두 번째 토큰이 모듈 ID다. 생략되면 `-ModuleId`도 생략한다(활성 모듈 사용).
세 번째 토큰 이후가 있으면 요청 본문으로 파일에 저장한다.

```powershell
pwsh -NoProfile -File workflow/scripts/invoke-requirements.ps1 -Mode module -ModuleId "<모듈>" -RequestFile workflow/.tmp/request.md
```

요청 본문이 없으면 `-RequestFile`을 생략한다.

### confirm-modules

두 번째 토큰이 쉼표로 구분된 모듈 목록이면 `-ModuleIds`로 넘긴다. 없으면 생략해
제안된 전체를 확정한다.

```powershell
pwsh -NoProfile -File workflow/scripts/invoke-requirements.ps1 -Mode confirm-modules -ModuleIds AUTH,CART
```

## 4. 완료 후 보고

스크립트 출력에서 다음을 읽어 간결히 보고한다.

- `REQUIREMENT=` 생성된 문서 경로
- `REVISION=` 개정 번호
- `PROPOSED=` 제안된 신규 모듈
- `STALE=` stale로 표시된 모듈
- `CONFIRMED=` / `ARCHIVED=` 확정 및 보관된 모듈

`PROPOSED`가 비어 있지 않으면 **사용자에게 모듈 목록 검토를 요청하고
`/requirements confirm-modules` 실행을 안내한다.** 이 확인 단계를 건너뛰지 않는다.

`STALE`이 비어 있지 않으면 해당 모듈들이 잠겼음을 알리고 `/requirements module
<모듈>`로 갱신해야 한다고 안내한다.

생성된 문서를 요약하거나 평가하지 않는다. 경로만 알려주고 사용자가 직접 읽게
한다. 제품 구현을 시작하지 않고 종료한다.

## 5. 실패 시

스크립트가 실패하면 오류 메시지를 그대로 전달한다. 임의로 재시도하거나 요구사항을
직접 작성하지 않는다.

`.rejected` 파일이 언급되면 Codex 응답이 검증을 통과하지 못한 것이다. 기존 문서는
보존되었음을 알린다.
