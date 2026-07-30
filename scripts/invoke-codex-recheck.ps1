[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RequirementPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TestReportPath
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
    "recheckReportDirectory",
    "acceptanceTestCommand"
)

foreach ($Property in $RequiredProperties) {
    Assert-ConfigProperty `
        -Config $Config `
        -PropertyName $Property
}

$RequirementFullPath = Resolve-CodexProjectPath `
    -ProjectRoot $ProjectRoot `
    -Path $RequirementPath

$TestReportFullPath = Resolve-CodexProjectPath `
    -ProjectRoot $ProjectRoot `
    -Path $TestReportPath

Assert-CleanGitWorkingTree `
    -ProjectRoot $ProjectRoot

$RecheckDirectory = Join-Path `
    $ProjectRoot `
    $Config.recheckReportDirectory

New-Item `
    -ItemType Directory `
    -Path $RecheckDirectory `
    -Force | Out-Null

$RequirementName = [System.IO.Path]::GetFileNameWithoutExtension(
    $RequirementFullPath
)

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

$RecheckPath = Join-Path `
    $RecheckDirectory `
    "$RequirementName-recheck-$Timestamp.md"

$UnitDirectories = @(
    $Config.unitTestDirectories
) -join ", "

$Prompt = @"
당신은 요구사항 및 인수 테스트 재검토 담당자다.

# 요구사항 문서

$RequirementFullPath

# 기존 인수 테스트 보고서

$TestReportFullPath

# 인수 테스트 경로

$($Config.acceptanceTestDirectory)

# 단위 테스트 경로

$UnitDirectories

# 인수 테스트 명령

$($Config.acceptanceTestCommand)

# 재검토 최종 판정

다음 중 하나로 판정한다.

1. TEST_DEFECT
2. REQUIREMENT_SUSPECT
3. PRODUCT_CODE_BUG_CONFIRMED
4. BLOCKED_ENVIRONMENT

# TEST_DEFECT 처리

- 잘못된 인수 테스트만 수정한다.
- 인수 테스트 명령을 다시 실행한다.
- 제품 코드, 단위 테스트, 요구사항은 수정하지 않는다.

# REQUIREMENT_SUSPECT 처리

- 요구사항 문서를 직접 수정하지 않는다.
- 문제가 되는 요구사항과 변경 제안을 보고한다.

# PRODUCT_CODE_BUG_CONFIRMED 처리

- 제품 코드와 테스트를 수정하지 않는다.
- Claude가 제품 코드를 수정할 수 있도록 근거를 작성한다.

# 수정 허용

- $($Config.acceptanceTestDirectory)

# 수정 금지

- 제품 코드
- $UnitDirectories
- 요구사항 문서
- 프로젝트 설정
- 의존성 파일

# 보고서 형식

# Codex 재검토 결과: $RequirementName

## 1. 재검토 대상

- 요구사항:
- 기존 보고서:
- 테스트 명령:

## 2. 최종 판정

## 3. 판정 근거

## 4. 인수 테스트 검토

## 5. 요구사항 및 인수 조건 검토

## 6. 수정한 인수 테스트

## 7. 테스트 재실행 결과

## 8. 요구사항 변경 제안

## 9. Claude 제품 코드 수정 권장 사항

## 10. 사용자 조치

최종 응답에는 완성된 Markdown 재검토 보고서만 출력한다.
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
    -Path $RecheckPath `
    -Content $Report

$RelativeReport = [System.IO.Path]::GetRelativePath(
    $ProjectRoot,
    $RecheckPath
)

Write-Output "RECHECK_REPORT=$RelativeReport"