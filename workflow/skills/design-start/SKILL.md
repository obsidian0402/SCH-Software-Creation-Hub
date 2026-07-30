---
name: design-start
description: 제품 디자인 작업 공간을 준비한다. 버전 폴더와 세 공간을 만들고 기준 요구사항 해시를 고정한 뒤 Codex용 지시문을 생성한다.
argument-hint: "<모듈> [--new-version]"
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash(pwsh -NoProfile -File workflow/scripts/invoke-design-start.ps1 *)
---

사용자 입력:

$ARGUMENTS

## 이 스킬은 Codex를 호출하지 않는다

제품 디자인은 반복 대화가 필요한 작업이므로 일회성 `codex exec`로 감싸지 않는다.
이 스킬은 앞단만 준비한다. 실제 디자인은 사용자가 터미널에서 대화형 `codex`로
진행한다.

## 실행

첫 토큰이 모듈 ID다. 생략되면 `-ModuleId`도 생략한다(활성 모듈 사용).
`--new-version`이 있으면 `-NewVersion`을 붙인다.

```powershell
pwsh -NoProfile -File workflow/scripts/invoke-design-start.ps1 -ModuleId "<모듈>"
```

## 완료 후 보고

출력에서 다음을 읽는다.

- `MODULE=` 대상 모듈
- `DESIGN_VERSION=` 생성된 버전
- `DESIGN_DIR=` 디자인 폴더
- `BRIEF=` Codex 지시문 경로

**사용자에게 반드시 다음을 안내한다.**

1. 터미널에서 `codex`를 실행한다.
2. `@product design`으로 작업하며 `BRIEF=` 경로의 지시문을 참조시킨다.
3. 작업을 마치면 `/design-close <모듈>`로 검증한다.

지시문 파일의 내용을 요약하지 않는다. Codex가 직접 읽어야 하는 문서다.

## Claude가 하지 않는 일

- 디자인 산출물 작성 또는 수정
- `_meta.json` 수정
- 디자인 폴더 안의 어떤 파일도 편집하지 않음

디자인 산출물은 Codex 소유다. Claude는 나중에 `handoff.md`를 읽어 구현할 뿐이다.

## 실패 시

`stale` 또는 미확정 상태로 거부되면 오류 메시지를 그대로 전달하고 안내된 선행
명령을 알려준다. 우회하지 않는다.
