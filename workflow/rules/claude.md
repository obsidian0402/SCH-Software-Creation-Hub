# Claude 규칙

Claude는 제품 코드 구현과 구현 세부 단위 테스트를 담당한다.

Codex는 요구사항, 제품 디자인, 모듈 및 시스템 테스트를 담당한다.

---

## 1. Claude 소유 영역

Claude가 작성하거나 수정할 수 있는 영역이다.

- `src/` 제품 코드
- `tests/unit/` 구현 세부 단위 테스트
- 빌드 및 실행 설정 중 구현에 필요한 파일
- `workflow/` 워크플로 스크립트와 설정

Claude는 `workflow/config.json`의 `commands.unitTest`를 실행할 수 있다.

단위 테스트의 목적은 다음과 같다.

- 함수 또는 메서드의 세부 동작 검증
- 클래스와 내부 모듈 검증
- 경계값과 오류 처리 검증
- 작은 단위의 데이터 변환 검증
- 구현 과정에서 발생한 회귀 방지

단위 테스트는 **요구사항 추적 대상이 아니다.** 단위 테스트는 구현 구조에
붙어 있어 리팩터링마다 바뀐다. 요구사항 ID에 매핑하면 추적 매트릭스가
계속 깨지므로 의도적으로 제외한다.

요구사항 검증 책임은 `tests/module/`과 `tests/system/`이 진다.

---

## 2. 구현 아키텍처 규칙

스택: **Electron + TypeScript + React** (로컬 전용 데스크톱 앱)

메인 프로세스가 백엔드 역할을 한다. 별도 서버는 없다.

스택이 바뀌면 이 절과 `workflow/presets.json`의 해당 프리셋을 함께 갱신한다.
아래 규칙의 기계 판독용 사본은 `presets.json`의
`electron-vitest-playwright.securityInvariants`에 있다.

### 2.1 디렉터리 구조

    src/core       순수 TypeScript. electron 을 import 하지 않는다.
                   Node 에서 그대로 실행된다.
    src/main       창 생성, IPC 배선, OS 연동만
    src/preload    contextBridge 노출만
    src/renderer   React
    src/shared     IPC 채널 정의와 공용 타입

**핵심 규칙: 메인 프로세스를 얇게 유지하고 비즈니스 로직은 전부 `src/core`에
둔다.**

이 규칙 하나가 세 가지를 해결한다.

- `tests/unit`이 Electron 부팅 없이 밀리초 단위로 돈다. 테스트 속도가 곧
  테스트를 실제로 돌리는지 여부를 결정한다.
- 3계층 테스트 분리의 전제가 된다.
- 프로세스 경계를 혼동해서 생기는 버그를 구조적으로 막는다.

판단 기준은 단순하다. `src/core`의 파일에 `import ... from 'electron'`이
들어가면 그 코드는 잘못된 위치에 있다.

### 2.2 보안 불변조건 (예외 없음)

Electron의 보안 API는 여러 번 바뀌었고 학습 데이터에는 폐기된 패턴이 대량으로
남아 있다. 그럴듯해 보여도 아래를 위반하면 잘못된 코드다.

`BrowserWindow`의 `webPreferences`는 항상 다음을 만족한다.

    contextIsolation: true
    nodeIntegration: false
    sandbox: true
    webSecurity: true      개발 중에도 끄지 않는다

다음 패턴을 생성했다면 즉시 되돌린다.

- `nodeIntegration: true`
- `contextIsolation: false`
- `enableRemoteModule`
- `@electron/remote` 또는 `require('electron').remote`
- 렌더러에서 `require()` 또는 Node API 직접 접근
- `contextBridge` 없이 `ipcRenderer`를 `window`에 노출
- `shell.openExternal`에 검증하지 않은 URL 전달
- `loadURL`에 원격 URL 지정 (로컬 전용 앱이다)

### 2.3 IPC 규칙

- 모든 IPC 채널 이름과 페이로드 타입은 `src/shared/ipc.ts` **한 파일에만**
  정의한다. 채널 이름 문자열을 여러 곳에 흩뿌리지 않는다.
- `preload`는 `contextBridge.exposeInMainWorld`로 **좁은 API만** 노출한다.
  `ipcRenderer` 자체를 노출하지 않는다.
- 메인 쪽 핸들러는 렌더러 입력을 신뢰하지 않고 검증한다.

IPC를 하나 추가할 때는 네 곳을 함께 갱신한다. 하나라도 빠지면 타입이 어긋난다.

    src/shared/ipc.ts  →  src/preload  →  src/main 핸들러  →  src/renderer

### 2.4 테스트 배치

| 경로 | 소유 | 도구 | 대상 |
|---|---|---|---|
| `tests/unit` | Claude | Vitest | `src/core` 순수 로직. Electron 미사용 |
| `tests/module` | Codex | Vitest + React Testing Library | 모듈별 동작 |
| `tests/system` | Codex | Playwright | 빌드된 앱 실제 구동 |

Claude는 `tests/unit`만 작성한다.

`src/main`이나 `src/preload`의 로직을 단위 테스트하고 싶어지면, 그 로직이
`src/core`에 있어야 한다는 신호다. 테스트를 억지로 만들지 말고 코드를 옮긴다.

### 2.5 빌드

`electron-vite`를 사용한다. 렌더러 HMR과 메인·preload 핫 리로드를 제공한다.

빌드 설정을 손으로 직접 구성하지 않는다. Electron Forge의 Vite 플러그인은
실험 단계이므로 쓰지 않는다.

---

## 3. Claude 수정 금지 영역

- `docs/requirements/`
- `docs/design/`
- `design-assets/`
- `tests/module/`
- `tests/system/`
- `docs/test-reports/`

Claude는 다음 작업을 하지 않는다.

- 요구사항 추가, 수정, 적절성 검토
- 모듈 분해 결정
- 인수 조건 추가 또는 수정
- 제품 디자인 산출물 작성 또는 수정
- 모듈 테스트 또는 시스템 테스트 작성, 수정, 기대값 변경
- Codex의 테스트 결과를 임의로 통과 처리

Claude가 위 경로를 수정하면 워크플로 가드가 아니라 이 규칙이 유일한
방어선이다. Codex 쪽에는 실행 후 git 가드와 해시 스냅샷 가드가 있지만
Claude 쪽에는 없다.

---

## 4. 요구사항 사용

Claude는 확정 요구사항을 구현 기준으로 읽는다.

- 시스템 요구사항: `docs/requirements/system/system.md`
- 모듈 요구사항: `docs/requirements/modules/<모듈>/requirements.md`
- 추적성: `docs/requirements/traceability.json`

구현 시 다음을 지킨다.

- 요구사항을 임의로 보완하거나 해석을 변경하지 않는다.
- 모듈 요구사항은 상위 시스템 요구사항 ID를 참조한다. 충돌이 보이면 구현을
  진행하지 않고 사용자에게 알린다.
- `workflow/state.json`에서 모듈 상태가 `proposed` 또는 `stale`이면 구현을
  시작하지 않는다.

구현에 필요한 사항이 요구사항에 없으면 사용자에게 다음을 안내한다.

> 현재 요구사항만으로 구현 결정을 내릴 수 없습니다.
> `/requirements`를 사용해 Codex에 요구사항 보완을 요청해 주세요.

---

## 5. Codex 호출 제한

Claude는 `workflow/scripts/` 아래의 `invoke-*.ps1`을 평소 작업 중 임의로
실행하지 않는다.

해당 스크립트는 사용자가 다음 Skill을 명시적으로 호출했을 때만 실행한다.

- `/requirements`
- `/design-start`
- `/design-close`
- `/codex-test`
- `/codex-recheck`

예외적으로 다음 두 스크립트는 진단 및 설정 목적이므로 사용자 요청 시
자유롭게 실행할 수 있다.

- `workflow/scripts/check-codex-env.ps1`
- `workflow/scripts/init-workspace.ps1`

---

## 6. 테스트 실패 처리

### 모듈 또는 시스템 테스트 보고서가 `PRODUCT_CODE_BUG`인 경우

1. 보고서를 읽는다.
2. 제품 코드 원인을 분석한다.
3. `src/`만 수정한다.
4. 필요하면 `tests/unit/`을 추가하거나 수정한다.
5. `commands.unitTest`를 실행한다.
6. 사용자에게 `/codex-test` 재실행을 안내한다.

### `TEST_OR_REQUIREMENT_SUSPECT`인 경우

1. 제품 코드를 테스트에 억지로 맞추지 않는다.
2. 모듈 및 시스템 테스트를 수정하지 않는다.
3. 요구사항을 수정하지 않는다.
4. 사용자에게 `/codex-recheck` 실행을 안내한다.

### 재검토 결과 처리

- `PRODUCT_CODE_BUG_CONFIRMED` → `src/`와 `tests/unit/`만 수정한다.
- `TEST_DEFECT` → Codex가 테스트를 수정한다. Claude는 대기한다.
- `REQUIREMENT_SUSPECT` → 사용자에게 `/requirements`를 통한 요구사항 변경을
  안내한다.
- `BLOCKED_ENVIRONMENT` → 보고서의 필요 환경을 사용자에게 전달한다.

---

## 7. 커밋

커밋은 사용자가 직접 한다. Claude는 커밋하지 않는다.

Codex 단계는 실행 전에 깨끗한 git 작업 트리를 요구한다. 구현을 마치면
사용자에게 체크포인트 커밋을 안내한다.

    git add -A; git commit -m "feat: <내용>"
