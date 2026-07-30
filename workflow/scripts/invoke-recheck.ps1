<#
.SYNOPSIS
    Codex 에게 TEST_OR_REQUIREMENT_SUSPECT 판정 재검토를 위임한다.

.DESCRIPTION
    기존 테스트 보고서에서 의심 항목을 다시 검토해 원인을 확정한다.

    최종 판정은 다음 중 하나다.

      TEST_DEFECT                  테스트가 잘못됨 (Codex 가 테스트를 수정)
      REQUIREMENT_SUSPECT          요구사항이 잘못됨 (변경 제안만)
      PRODUCT_CODE_BUG_CONFIRMED   제품 코드 문제 확정 (Claude 가 수정)
      BLOCKED_ENVIRONMENT          환경 문제

.PARAMETER Scope
    module / system

.PARAMETER ReportPath
    기존 테스트 보고서 경로.
    생략하면 상태 파일에 기록된 마지막 보고서를 쓴다.

.PARAMETER ModuleId
    module 범위에서 대상 모듈. 생략하면 활성 모듈을 쓴다.

.EXAMPLE
    pwsh -NoProfile -File workflow/scripts/invoke-recheck.ps1 -Scope module -ModuleId AUTH

.EXAMPLE
    pwsh -NoProfile -File workflow/scripts/invoke-recheck.ps1 -Scope system -ReportPath docs/test-reports/system/system-20260730-120000.md
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet("module", "system")]
    [string]$Scope,

    [string]$ReportPath,
    [string]$ModuleId
)

. "$PSScriptRoot\Common.ps1"

Initialize-CodexEncoding

$Root = Get-CodexRoot
$Config = Get-CodexConfig -Root $Root
$State = Get-CodexState -Root $Root -Config $Config

$ProductCode = (@($Config.paths.productCode)) -join ", "

# ---------------------------------------------------------------
# 대상 결정
# ---------------------------------------------------------------

if ($Scope -eq "module") {
    $TargetId = Resolve-CodexModuleId -State $State -ModuleId $ModuleId
    $Module = Get-CodexModuleState -State $State -ModuleId $TargetId
    $ModuleLower = $TargetId.ToLowerInvariant()

    $EffectiveMode = Get-CodexMode -Config $Config -State $State -ModuleId $TargetId
    Write-CodexModeBanner -Mode $EffectiveMode -Stage "codex-recheck module" -ModuleId $TargetId

    $RequirementRelative = Get-CodexProperty -Object $Module -Name "requirementPath" -Default ""
    $RequirementFullPath = Resolve-CodexPath -Root $Root -Path $RequirementRelative -MustExist

    $TestCommand = (Assert-CodexCommand -Config $Config -Kind "moduleTest").Replace("{module}", $ModuleLower)
    $TestDirectory = "$($Config.paths.moduleTests)/$ModuleLower"
    $StageName = "recheck-module"
    $Stage = Get-CodexStageConfig -Config $Config -Stage $StageName -ModuleId $ModuleLower
    $ReportBaseName = "$ModuleLower-recheck"
    $Target = $TargetId

    if ([string]::IsNullOrWhiteSpace($ReportPath)) {
        $Tests = Get-CodexProperty -Object $Module -Name "tests" -Default $null
        $ModuleTests = Get-CodexProperty -Object $Tests -Name "module" -Default $null
        $ReportPath = Get-CodexProperty -Object $ModuleTests -Name "reportPath" -Default ""
    }
}
else {
    $TargetId = ""
    $ModuleLower = ""
    $EffectiveMode = Get-CodexMode -Config $Config -State $State
    Write-CodexModeBanner -Mode $EffectiveMode -Stage "codex-recheck system"

    $RequirementFullPath = Resolve-CodexPath -Root $Root -Path $State.system.requirementPath -MustExist

    $TestCommand = Assert-CodexCommand -Config $Config -Kind "systemTest"
    $TestDirectory = $Config.paths.systemTests
    $StageName = "recheck-system"
    $Stage = Get-CodexStageConfig -Config $Config -Stage $StageName
    $ReportBaseName = "system-recheck"
    $Target = "시스템"

    if ([string]::IsNullOrWhiteSpace($ReportPath)) {
        $SystemTests = Get-CodexProperty -Object $State.system -Name "tests" -Default $null
        $ReportPath = Get-CodexProperty -Object $SystemTests -Name "reportPath" -Default ""
    }
}

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    throw @"
재검토할 테스트 보고서를 찾을 수 없습니다.

-ReportPath 로 직접 지정하거나 /codex-test 를 먼저 실행하세요.
"@
}

$ReportFullPath = Resolve-CodexPath -Root $Root -Path $ReportPath -MustExist

Write-Host "  기존 보고서: $(ConvertTo-CodexRelativePath -Root $Root -Path $ReportFullPath)"

# ---------------------------------------------------------------
# 실행
# ---------------------------------------------------------------

$Prompt = Expand-CodexPlaceholder `
    -Template (Get-CodexPromptTemplate -Root $Root -Config $Config -FileName $Stage.PromptFile) `
    -Values @{
        ROOT                    = $Root
        SCOPE                   = $Scope
        TARGET                  = $Target
        REQUIREMENT_PATH        = (ConvertTo-CodexRelativePath -Root $Root -Path $RequirementFullPath)
        SYSTEM_REQUIREMENT_PATH = $State.system.requirementPath
        REPORT_PATH             = (ConvertTo-CodexRelativePath -Root $Root -Path $ReportFullPath)
        TEST_DIRECTORY          = $TestDirectory
        PRODUCT_CODE            = $ProductCode
        UNIT_TESTS              = $Config.paths.unitTests
        TEST_COMMAND            = $TestCommand
    }

$Guard = Start-CodexGuard -Root $Root -Config $Config -Mode $EffectiveMode `
    -AllowedPaths $Stage.AllowedPaths

$StageSlug = if ($Scope -eq "module") { "recheck-module-$ModuleLower" } else { "recheck-system" }

$Report = Invoke-CodexPrompt -Root $Root -Config $Config -Prompt $Prompt -Stage $StageSlug

Complete-CodexGuard -Guard $Guard

$Report = Remove-CodexCodeFence -Content $Report

$OutputPath = New-CodexReportPath -Root $Root -Directory $Stage.ReportDirectory -BaseName $ReportBaseName

Assert-CodexDocument `
    -Content $Report `
    -MinimumLength ([int]$Config.validation.minReportLength) `
    -RequiredMarkers @() `
    -RejectPath "$OutputPath.rejected"

Write-Utf8NoBomFile -Path $OutputPath -Content $Report

# ---------------------------------------------------------------
# 판정 추출
# ---------------------------------------------------------------

$Verdict = "UNKNOWN"

foreach ($Candidate in @("PRODUCT_CODE_BUG_CONFIRMED", "TEST_DEFECT", "REQUIREMENT_SUSPECT", "BLOCKED_ENVIRONMENT")) {
    if ($Report -like "*$Candidate*") {
        $Verdict = $Candidate
        break
    }
}

$RelativeOutput = ConvertTo-CodexRelativePath -Root $Root -Path $OutputPath

$RecheckRecord = [ordered]@{
    at         = (Get-Date).ToString("o")
    verdict    = $Verdict
    reportPath = $RelativeOutput
    sourceReport = (ConvertTo-CodexRelativePath -Root $Root -Path $ReportFullPath)
}

if ($Scope -eq "module") {
    $Tests = Get-CodexProperty -Object $Module -Name "tests" -Default $null

    if ($null -eq $Tests) { $Tests = [pscustomobject]@{} }

    Set-CodexProperty -Object $Tests -Name "recheck" -Value ([pscustomobject]$RecheckRecord)
    Set-CodexProperty -Object $Module -Name "tests" -Value $Tests
    Set-CodexProperty -Object $Module -Name "updatedAt" -Value ((Get-Date).ToString("o"))
    Add-CodexHistory -State $State -Stage "recheck-module" -ModuleId $TargetId -Detail $Verdict
}
else {
    $SystemTests = Get-CodexProperty -Object $State.system -Name "tests" -Default $null

    if ($null -eq $SystemTests) { $SystemTests = [pscustomobject]@{} }

    Set-CodexProperty -Object $SystemTests -Name "recheck" -Value ([pscustomobject]$RecheckRecord)
    Set-CodexProperty -Object $State.system -Name "tests" -Value $SystemTests
    Add-CodexHistory -State $State -Stage "recheck-system" -Detail $Verdict
}

Save-CodexState -Root $Root -Config $Config -State $State

# ---------------------------------------------------------------
# 안내
# ---------------------------------------------------------------

Write-Host ""
Write-Host "재검토 완료: $Verdict" -ForegroundColor Cyan
Write-Host "  보고서: $RelativeOutput"
Write-Host ""
Write-Host "다음 단계" -ForegroundColor Cyan

switch ($Verdict) {
    "TEST_DEFECT" {
        Write-Host "  Codex 가 테스트를 수정하고 재실행했습니다."
        Write-Host "  보고서의 재실행 결과를 확인하세요."
    }
    "REQUIREMENT_SUSPECT" {
        $Command = if ($Scope -eq "module") { "/requirements module $TargetId" } else { "/requirements system" }
        Write-Host "  보고서의 '요구사항 변경 제안' 을 검토한 뒤:"
        Write-Host "    $Command"
    }
    "PRODUCT_CODE_BUG_CONFIRMED" {
        Write-Host "  Claude 가 보고서를 읽고 src/ 를 수정합니다."
        $ScopeArg = if ($Scope -eq "module") { "module $TargetId" } else { "system" }
        Write-Host "  수정 후 /codex-test $ScopeArg"
    }
    "BLOCKED_ENVIRONMENT" {
        Write-Host "  보고서의 '사용자 조치' 항목을 확인하세요."
    }
    default {
        Write-Warning "보고서에서 판정을 추출하지 못했습니다. 직접 확인하세요."
    }
}

Write-Host ""
Write-Output "RECHECK_REPORT=$RelativeOutput"
Write-Output "VERDICT=$Verdict"
