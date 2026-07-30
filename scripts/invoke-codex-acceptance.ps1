[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RequirementPath
)

. "$PSScriptRoot\CodexWorkflow.Common.ps1"

Initialize-CodexWorkflowEncoding

$ProjectRoot = (
    Resolve-Path (Join-Path $PSScriptRoot "..")
).Path

$Config = Get-CodexWorkflowConfig `
    -ProjectRoot $ProjectRoot

$RequiredProperties = @(
    "acceptanceTestDirectory",
    "acceptanceReportDirectory",
    "acceptanceTestCommand"
)

foreach ($Property in $RequiredProperties) {
    Assert-ConfigProperty `
        -Config $Config `
        -PropertyName $Property
}

if (
    $Config.acceptanceTestCommand -eq
    "REPLACE_WITH_ACCEPTANCE_TEST_COMMAND"
) {
    throw ".codex-workflow.json의 acceptanceTestCommand를 설정하세요."
}

$RequirementFullPath = Resolve-CodexProjectPath `
    -ProjectRoot $ProjectRoot `
    -Path $RequirementPath

Assert-CleanGitWorkingTree `
    -ProjectRoot $ProjectRoot

$AcceptanceDirectory = Join-Path `
    $ProjectRoot `
    $Config.acceptanceTestDirectory

$ReportDirectory = Join-Path `
    $ProjectRoot `
    $Config.acceptanceReportDirectory

New-Item `
    -ItemType Directory `
    -Path $AcceptanceDirectory `
    -Force | Out-Null

New-Item `
    -ItemType Directory `
    -Path $ReportDirectory `
    -Force | Out-Null

$RequirementName = [System.IO.Path]::GetFileNameWithoutExtension(
    $RequirementFullPath
)

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

$ReportPath = Join-Path `
    $ReportDirectory `
    "$RequirementName-$Timestamp.md"

$UnitDirectories = @(
    $Config.unitTestDirectories
) -join ", "

$Prompt = @"
당신은 이 프로젝트의 인수 테스트 전담 엔지니어다.

# 기준 요구사항

$RequirementFullPath

# 인수 테스트 작성 경로

$($Config.acceptanceTestDirectory)

# Claude 소유 단위 테스트 경로

$UnitDirectories

# 반드시 실행할 테스트 명령

$($Config.acceptanceTestCommand)

# 수행 작업

1. AGENTS.md를 읽는다.
2. 모든 FR, NFR, AC ID를 확인한다.
3. 기존 인수 테스트를 확인한다.
4. 누락된 인수 테스트를 작성한다.
5. 잘못되거나 오래된 인수 테스트를 수정한다.
6. 지정된 테스트 명령을 실제로 실행한다.
7. 요구사항별 통과 여부를 판정한다.
8. 테스트 보고서를 작성한다.

# 수정 허용

- $($Config.acceptanceTestDirectory)

# 수정 금지

- 제품 코드
- $UnitDirectories
- 요구사항 문서
- 프로젝트 설정
- 의존성 파일
- Git 관련 파일

# 실패 분류

- PRODUCT_CODE_BUG
- TEST_OR_REQUIREMENT_SUSPECT
- BLOCKED_ENVIRONMENT

# 보고서 형식

# Codex 인수 테스트 결과: $RequirementName

## 1. 테스트 정보

- 요구사항 문서:
- 테스트 명령:
- 전체 결과: PASS / FAIL / BLOCKED
- 실패 분류:

## 2. 요구사항 추적표

| 요구사항 ID | 인수 조건 ID | 테스트 | 결과 |
|---|---|---|---|

## 3. 작성 또는 수정한 인수 테스트

## 4. 테스트 실행 결과

## 5. 실패 분석

- 관련 요구사항 ID
- 관련 인수 조건 ID
- 테스트 이름
- 기대 결과
- 실제 결과
- 오류 내용
- 실패 분류
- 분류 근거

## 6. Claude 제품 코드 수정 권장 사항

PRODUCT_CODE_BUG인 경우에만 작성한다.

## 7. Codex 재검토 필요 사항

TEST_OR_REQUIREMENT_SUSPECT인 경우에만 작성한다.

## 8. 미검증 요구사항

## 9. 최종 판정

최종 응답에는 완성된 Markdown 보고서만 출력한다.
"@

$Report = Invoke-CodexFinalMessage `
    -ProjectRoot $ProjectRoot `
    -Prompt $Prompt `
    -Sandbox "workspace-write"

Assert-OnlyAllowedPathsChanged `
    -ProjectRoot $ProjectRoot `
    -AllowedPaths @(
        $Config.acceptanceTestDirectory
    )

Write-Utf8NoBomFile `
    -Path $ReportPath `
    -Content $Report

$RelativeReport = [System.IO.Path]::GetRelativePath(
    $ProjectRoot,
    $ReportPath
)

Write-Output "REPORT=$RelativeReport"