# Claude Code 프로젝트 규칙

이 프로젝트는 요구사항·제품 디자인·모듈/시스템 테스트를 Codex가, 제품 코드
구현과 단위 테스트를 Claude가 담당하는 이중 에이전트 워크플로를 사용한다.

**전체 규칙은 아래 파일에 있다. 작업 전에 반드시 읽는다.**

@workflow/rules/claude.md

---

## 핵심 요약

Claude가 수정할 수 있는 영역

- `src/` 제품 코드
- `tests/unit/` 구현 세부 단위 테스트
- `workflow/` 워크플로 스크립트와 설정
- 구현에 필요한 빌드 및 실행 설정

Claude가 수정하지 않는 영역

- `docs/requirements/`
- `docs/design/`, `design-assets/`
- `tests/module/`, `tests/system/`
- `docs/test-reports/`

Claude가 하지 않는 일

- 요구사항 추가, 수정, 적절성 검토
- 모듈 분해 결정
- 인수 조건 추가 또는 수정
- 모듈 테스트 또는 시스템 테스트 작성, 수정, 기대값 변경
- Codex 테스트 결과를 임의로 통과 처리
- git 커밋 (커밋은 사용자가 직접 한다)

단위 테스트는 요구사항 추적 대상이 아니다. 요구사항 검증은 `tests/module/`과
`tests/system/`이 담당한다.

---

## 스택 불변조건

**Electron + TypeScript + React** (로컬 전용 데스크톱 앱, 메인 프로세스가 백엔드)

    src/core       순수 TypeScript. electron 을 import 하지 않는다
    src/main       창 생성, IPC 배선, OS 연동만
    src/preload    contextBridge 노출만
    src/renderer   React
    src/shared     IPC 채널 정의와 공용 타입

비즈니스 로직은 전부 `src/core`에 둔다. `src/core`에
`import ... from 'electron'`이 들어가면 잘못된 위치다.

`BrowserWindow`의 `webPreferences`는 항상 다음을 유지한다.

    contextIsolation: true    nodeIntegration: false
    sandbox: true             webSecurity: true

다음을 생성했다면 즉시 되돌린다. 학습 데이터에 남아 있는 폐기된 패턴이다.

- `nodeIntegration: true`, `contextIsolation: false`, `enableRemoteModule`
- `@electron/remote`, `require('electron').remote`
- 렌더러에서 `require()` 또는 Node API 직접 접근
- `contextBridge` 없이 `ipcRenderer`를 `window`에 노출
- `loadURL`에 원격 URL

IPC 채널과 타입은 `src/shared/ipc.ts` 한 파일에만 정의한다.

상세 규칙과 근거는 `workflow/rules/claude.md` 2절에 있다.

`workflow/scripts/invoke-*.ps1`은 사용자가 `/requirements`, `/design-start`,
`/design-close`, `/codex-test`, `/codex-recheck`를 명시적으로 호출했을 때만
실행한다. `check-codex-env.ps1`과 `init-workspace.ps1`은 예외로 자유롭게
실행할 수 있다.

요구사항이 부족해 구현 결정을 내릴 수 없으면 임의로 보완하지 말고 사용자에게
`/requirements`를 통한 Codex 보완 요청을 안내한다.
