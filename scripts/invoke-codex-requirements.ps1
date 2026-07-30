[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$FeatureName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Request
)

. "$PSScriptRoot\CodexWorkflow.Common.ps1"

Initialize-CodexWorkflowEncoding

$ProjectRoot = (
    Resolve-Path (Join-Path $PSScriptRoot "..")
).Path

$Config = Get-CodexWorkflowConfig `
    -ProjectRoot $ProjectRoot

Assert-ConfigProperty `
    -Config $Config `
    -PropertyName "requirementsDirectory"

$RequirementsDirectory = Join-Path `
    $ProjectRoot `
    $Config.requirementsDirectory

New-Item `
    -ItemType Directory `
    -Path $RequirementsDirectory `
    -Force | Out-Null

$SafeName = $FeatureName.Trim().ToLowerInvariant()
$SafeName = $SafeName -replace "[^\p{L}\p{N}._-]+", "-"
$SafeName = $SafeName.Trim("-")

if ([string]::IsNullOrWhiteSpace($SafeName)) {
    $SafeName = Get-Date -Format "yyyyMMdd-HHmmss"
}

$OutputPath = Join-Path `
    $RequirementsDirectory `
    "$SafeName.md"

$ExistingInstruction = if (Test-Path -LiteralPath $OutputPath) {
    @"
기존 요구사항 문서가 있다.

$OutputPath

기존 문서를 읽고 최신 요청을 반영하여 문서 전체를 갱신한다.
기존 요구사항과 인수 조건 ID는 의미가 유지되는 한 보존한다.
"@
}
else {
    "기존 요구사항 문서는 없다. 새로운 요구사항 문서를 작성한다."
}

$Prompt = @"
당신은 이 프로젝트의 전담 요구사항 엔지니어다.

요구사항과 관련된 다음 작업을 모두 담당한다.

- 사용자 요청 분석
- 요구사항 정의
- 요구사항 자체 검토
- 누락 및 충돌 확인
- 정상 흐름과 예외 흐름 정의
- 인수 조건 정의
- 테스트 관점 정의
- 기존 요구사항 수정

Claude는 요구사항을 검토하거나 수정하지 않는다.

# 프로젝트 루트

$ProjectRoot

# 기능 이름

$FeatureName

# 사용자 요청

$Request

# 기존 문서 상태

$ExistingInstruction

# 필수 수행 작업

1. AGENTS.md를 읽는다.
2. README와 기존 프로젝트 문서를 확인한다.
3. 관련 제품 코드와 구조를 읽는다.
4. 사용자 목적과 사용 시나리오를 정의한다.
5. 포함 범위와 제외 범위를 정의한다.
6. 기능 요구사항과 비기능 요구사항을 작성한다.
7. 정상 흐름과 예외 흐름을 작성한다.
8. 데이터와 인터페이스 영향을 작성한다.
9. 각 요구사항에 연결된 인수 조건을 작성한다.
10. 테스트 관점을 작성한다.
11. 불명확한 사항은 미결 질문으로 남긴다.

# 금지 사항

- 제품 코드 수정 금지
- 단위 테스트 수정 금지
- 인수 테스트 수정 금지
- 설정 파일 수정 금지
- 패키지 설치 금지
- Git 변경 금지
- 구현 코드 작성 금지

# 출력 형식

# 요구사항 명세: $FeatureName

## 1. 문서 정보

- 상태: 사용자 승인 대기
- 기능명: $FeatureName
- 작성 및 검토: Codex
- 구현 담당: Claude

## 2. 배경

## 3. 목표

## 4. 범위

### 4.1 포함 범위

### 4.2 제외 범위

## 5. 사용자 및 사용 사례

## 6. 기능 요구사항

| ID | 요구사항 | 우선순위 | 근거 |
|---|---|---|---|
| FR-001 | | 필수 | |

## 7. 비기능 요구사항

| ID | 요구사항 | 검증 방법 |
|---|---|---|
| NFR-001 | | |

## 8. 정상 흐름

## 9. 예외 및 오류 흐름

## 10. 데이터 및 인터페이스 영향

## 11. 기존 기능 영향

## 12. 인수 조건

| ID | 관련 요구사항 | Given | When | Then |
|---|---|---|---|---|
| AC-001 | FR-001 | | | |

## 13. 테스트 관점

## 14. 위험 요소

## 15. 가정

## 16. 미결 질문

## 17. 구현 전 확인 사항

최종 응답에는 완성된 Markdown 요구사항 문서만 출력한다.
"@

$Document = Invoke-CodexFinalMessage `
    -ProjectRoot $ProjectRoot `
    -Prompt $Prompt `
    -Sandbox "read-only"

Write-Utf8NoBomFile `
    -Path $OutputPath `
    -Content $Document

$RequirementHash = (
    Get-FileHash `
        -LiteralPath $OutputPath `
        -Algorithm SHA256
).Hash

$RelativeRequirementPath = (
    [System.IO.Path]::GetRelativePath(
        $ProjectRoot,
        $OutputPath
    )
).Replace("\", "/")

$DesignDirectory = "docs/design/$SafeName"
$DesignAssetsDirectory = "design-assets/$SafeName"

$StatePath = Join-Path `
    $ProjectRoot `
    ".codex-workflow-state.json"

$CurrentRevision = 0

if (Test-Path -LiteralPath $StatePath) {
    try {
        $ExistingState = Get-Content `
            -LiteralPath $StatePath `
            -Raw `
            -Encoding UTF8 |
            ConvertFrom-Json

        if (
            $null -ne $ExistingState.activeFeature -and
            $ExistingState.activeFeature.featureId -eq $SafeName
        ) {
            $CurrentRevision = [int]$ExistingState.activeFeature.requirementRevision
        }
    }
    catch {
        Write-Warning `
            "기존 워크플로 상태 파일을 읽지 못했습니다. 새로 생성합니다."
    }
}

$NewState = [ordered]@{
    activeFeature = [ordered]@{
        featureId             = $SafeName
        featureName           = $FeatureName
        requirementPath       = $RelativeRequirementPath
        requirementRevision   = $CurrentRevision + 1
        requirementHash       = $RequirementHash
        designDirectory       = $DesignDirectory
        designAssetsDirectory = $DesignAssetsDirectory
        status                = "requirements_ready"
        updatedAt             = (
            Get-Date
        ).ToString("o")
    }
}

$StateJson = $NewState |
    ConvertTo-Json -Depth 5
    
Write-Utf8NoBomFile `
    -Path $StatePath `
    -Content $StateJson


Write-Output "REQUIREMENT=$RelativeRequirementPath"
Write-Output "ACTIVE_FEATURE=$SafeName"
Write-Output "REVISION=$($CurrentRevision + 1)"