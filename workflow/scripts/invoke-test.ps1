<#
.SYNOPSIS
    Codex 에게 모듈 테스트 또는 시스템 테스트를 위임한다.

.DESCRIPTION
    module  모듈 하나의 요구사항과 인수 조건을 검증
    system  시스템 인수 조건과 모듈 간 통합을 검증

    Codex 는 전권 샌드박스로 실행되지만 담당 테스트 경로 밖의 변경은
    실행 후 가드가 되돌린다.

.PARAMETER Scope
    module / system

.PARAMETER ModuleId
    module 범위에서 대상 모듈. 생략하면 활성 모듈을 쓴다.

.EXAMPLE
    pwsh -NoProfile -File workflow/scripts/invoke-test.ps1 -Scope module -ModuleId AUTH

.EXAMPLE
    pwsh -NoProfile -File workflow/scripts/invoke-test.ps1 -Scope system
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet("module", "system")]
    [string]$Scope,

    [string]$ModuleId
)

. "$PSScriptRoot\Common.ps1"

Initialize-CodexEncoding

$Root = Get-CodexRoot
$Config = Get-CodexConfig -Root $Root
$State = Get-CodexState -Root $Root -Config $Config

$Preset = $null
$PresetsPath = Join-Path $Root "workflow" "presets.json"

if (Test-Path -LiteralPath $PresetsPath) {
    $Presets = (Read-Utf8File -Path $PresetsPath | ConvertFrom-Json)
    $PresetKey = Get-CodexProperty -Object $Config.stack -Name "preset" -Default ""

    if ($Presets.presets.PSObject.Properties.Name -contains $PresetKey) {
        $Preset = $Presets.presets.$PresetKey
    }
}

$IdConvention = if ($Preset) {
    $Convention = Get-CodexProperty -Object $Preset -Name "idConvention" -Default $null
    if ($Convention) {
        "$(Get-CodexProperty -Object $Convention -Name 'example' -Default '')`n$(Get-CodexProperty -Object $Convention -Name 'hint' -Default '')"
    }
    else { "테스트 이름 맨 앞에 인수 조건 ID 를 넣는다." }
}
else {
    "테스트 이름 맨 앞에 인수 조건 ID 를 넣는다."
}

$ProductCode = (@($Config.paths.productCode)) -join ", "

# ===============================================================
# 공통 준비
# ===============================================================

if ($Scope -eq "module") {
    $TargetId = Resolve-CodexModuleId -State $State -ModuleId $ModuleId
    $Module = Get-CodexModuleState -State $State -ModuleId $TargetId
    $ModuleLower = $TargetId.ToLowerInvariant()

    $EffectiveMode = Get-CodexMode -Config $Config -State $State -ModuleId $TargetId
    Write-CodexModeBanner -Mode $EffectiveMode -Stage "codex-test module" -ModuleId $TargetId

    if ($EffectiveMode -eq "strict") {
        Assert-CodexModuleFresh -State $State -ModuleId $TargetId
    }
    else {
        try {
            Assert-CodexModuleFresh -State $State -ModuleId $TargetId
        }
        catch {
            Write-Warning "사전 조건 미충족 (vibe 모드이므로 계속 진행)"
            Write-Host $_.Exception.Message -ForegroundColor Yellow
        }
    }

    $RequirementRelative = Get-CodexProperty -Object $Module -Name "requirementPath" -Default ""
    $RequirementPath = Resolve-CodexPath -Root $Root -Path $RequirementRelative -MustExist

    $TestCommand = (Assert-CodexCommand -Config $Config -Kind "moduleTest").Replace("{module}", $ModuleLower)
    $JunitPath = ([string]$Config.junit.moduleTest).Replace("{module}", $ModuleLower)
    $TestDirectory = "$($Config.paths.moduleTests)/$ModuleLower"

    $StageName = "test-module"
    $Stage = Get-CodexStageConfig -Config $Config -Stage $StageName -ModuleId $ModuleLower
    $PromptFileName = $Stage.PromptFile
    $ReportBaseName = $TargetId.ToLowerInvariant()

    $Values = @{
        ROOT                    = $Root
        MODULE_ID               = $TargetId
        MODULE_UPPER            = $TargetId.ToUpperInvariant()
        MODULE_NAME             = (Get-CodexProperty -Object $Module -Name "moduleName" -Default $TargetId)
        REQUIREMENT_PATH        = (ConvertTo-CodexRelativePath -Root $Root -Path $RequirementPath)
        SYSTEM_REQUIREMENT_PATH = $State.system.requirementPath
        TEST_DIRECTORY          = $TestDirectory
        PRODUCT_CODE            = $ProductCode
        UNIT_TESTS              = $Config.paths.unitTests
        TEST_COMMAND            = $TestCommand
        JUNIT_PATH              = $JunitPath
        ID_CONVENTION           = $IdConvention
    }
}
else {
    $TargetId = ""
    $EffectiveMode = Get-CodexMode -Config $Config -State $State
    Write-CodexModeBanner -Mode $EffectiveMode -Stage "codex-test system"

    if ([int]$State.system.revision -eq 0) {
        throw "시스템 요구사항이 없습니다. /requirements system 을 먼저 실행하세요."
    }

    $RequirementPath = Resolve-CodexPath -Root $Root -Path $State.system.requirementPath -MustExist

    $Unready = @(
        $State.modules.PSObject.Properties |
            Where-Object {
                $Status = Get-CodexProperty -Object $_.Value -Name "status" -Default "proposed"
                $Status -in @("proposed", "confirmed")
            } |
            ForEach-Object { $_.Name }
    )

    if ($Unready.Count -gt 0) {
        $Message = @"
요구사항이 아직 작성되지 않은 모듈이 있습니다: $($Unready -join ', ')

시스템 테스트는 모듈 간 통합을 검증하므로 모든 모듈의 요구사항이 필요합니다.
/requirements module <모듈> 로 채우세요.
"@
        if ($EffectiveMode -eq "strict") {
            throw $Message
        }

        Write-Warning $Message
    }

    $ModuleTableLines = @("| 모듈 ID | 이름 | 상태 | 요구사항 |", "|---|---|---|---|")

    foreach ($Property in ($State.modules.PSObject.Properties | Sort-Object Name)) {
        $Entry = $Property.Value
        $ModuleTableLines += "| $($Property.Name) | $(Get-CodexProperty -Object $Entry -Name 'moduleName' -Default '') | $(Get-CodexProperty -Object $Entry -Name 'status' -Default '') | $(Get-CodexProperty -Object $Entry -Name 'requirementPath' -Default '') |"
    }

    $TestCommand = Assert-CodexCommand -Config $Config -Kind "systemTest"
    $JunitPath = [string]$Config.junit.systemTest
    $TestDirectory = $Config.paths.systemTests

    $StageName = "test-system"
    $Stage = Get-CodexStageConfig -Config $Config -Stage $StageName
    $PromptFileName = $Stage.PromptFile
    $ReportBaseName = "system"

    $Values = @{
        ROOT             = $Root
        REQUIREMENT_PATH = (ConvertTo-CodexRelativePath -Root $Root -Path $RequirementPath)
        SYSTEM_REVISION  = [string]$State.system.revision
        MODULE_TABLE     = ($ModuleTableLines -join "`n")
        TEST_DIRECTORY   = $TestDirectory
        PRODUCT_CODE     = $ProductCode
        UNIT_TESTS       = $Config.paths.unitTests
        MODULE_TESTS     = $Config.paths.moduleTests
        TEST_COMMAND     = $TestCommand
        JUNIT_PATH       = $JunitPath
        ID_CONVENTION    = $IdConvention
    }
}

# ===============================================================
# 실행
# ===============================================================

New-Item -ItemType Directory -Force `
    -Path (Join-Path $Root ($TestDirectory -replace "/", "\")) | Out-Null

New-Item -ItemType Directory -Force `
    -Path (Split-Path -Parent (Join-Path $Root ($JunitPath -replace "/", "\"))) | Out-Null

$Prompt = Expand-CodexPlaceholder `
    -Template (Get-CodexPromptTemplate -Root $Root -Config $Config -FileName $PromptFileName) `
    -Values $Values

$Guard = Start-CodexGuard -Root $Root -Config $Config -Mode $EffectiveMode `
    -AllowedPaths $Stage.AllowedPaths

$StageSlug = if ($Scope -eq "module") { "test-module-$ModuleLower" } else { "test-system" }

$Report = Invoke-CodexPrompt -Root $Root -Config $Config -Prompt $Prompt -Stage $StageSlug

Complete-CodexGuard -Guard $Guard

$Report = Remove-CodexCodeFence -Content $Report

$ReportPath = New-CodexReportPath -Root $Root -Directory $Stage.ReportDirectory -BaseName $ReportBaseName

Assert-CodexDocument `
    -Content $Report `
    -MinimumLength ([int]$Config.validation.minReportLength) `
    -RequiredMarkers @() `
    -RejectPath "$ReportPath.rejected"

Write-Utf8NoBomFile -Path $ReportPath -Content $Report

# ---------------------------------------------------------------
# 판정 추출
# ---------------------------------------------------------------

$Verdict = "UNKNOWN"

if ($Report -match '(?m)^\s*-?\s*전체\s*결과\s*:\s*\**\s*(PASS|FAIL|BLOCKED)') {
    $Verdict = $Matches[1]
}
elseif ($Report -match '\b(PASS|FAIL|BLOCKED)\b') {
    $Verdict = $Matches[1]
}

$Classification = ""

foreach ($Candidate in @("PRODUCT_CODE_BUG", "TEST_OR_REQUIREMENT_SUSPECT", "BLOCKED_ENVIRONMENT")) {
    if ($Report -like "*$Candidate*") {
        $Classification = $Candidate
        break
    }
}

# ---------------------------------------------------------------
# 상태 기록
# ---------------------------------------------------------------

$RelativeReport = ConvertTo-CodexRelativePath -Root $Root -Path $ReportPath

$TestRecord = [ordered]@{
    lastRun    = (Get-Date).ToString("o")
    result     = $Verdict
    classification = $Classification
    reportPath = $RelativeReport
    command    = $TestCommand
    stale      = $false
}

if ($Scope -eq "module") {
    $Tests = Get-CodexProperty -Object $Module -Name "tests" -Default $null

    if ($null -eq $Tests) {
        $Tests = [pscustomobject]@{}
    }

    Set-CodexProperty -Object $Tests -Name "module" -Value ([pscustomobject]$TestRecord)
    Set-CodexProperty -Object $Module -Name "tests" -Value $Tests

    if ($Verdict -eq "PASS") {
        Set-CodexProperty -Object $Module -Name "status" -Value "verified"
    }
    elseif ((Get-CodexProperty -Object $Module -Name "status" -Default "") -eq "design_ready") {
        Set-CodexProperty -Object $Module -Name "status" -Value "implemented"
    }

    Set-CodexProperty -Object $Module -Name "updatedAt" -Value ((Get-Date).ToString("o"))
    Add-CodexHistory -State $State -Stage "test-module" -ModuleId $TargetId -Detail "$Verdict $Classification"
}
else {
    Set-CodexProperty -Object $State.system -Name "tests" -Value ([pscustomobject]$TestRecord)
    Set-CodexProperty -Object $State.system -Name "updatedAt" -Value ((Get-Date).ToString("o"))
    Add-CodexHistory -State $State -Stage "test-system" -Detail "$Verdict $Classification"
}

Save-CodexState -Root $Root -Config $Config -State $State

# ---------------------------------------------------------------
# 안내
# ---------------------------------------------------------------

$Color = switch ($Verdict) {
    "PASS"    { "Green" }
    "FAIL"    { "Red" }
    "BLOCKED" { "Yellow" }
    default   { "Yellow" }
}

Write-Host ""
Write-Host "테스트 완료: $Verdict" -ForegroundColor $Color
Write-Host "  보고서: $RelativeReport"

if ($Classification) {
    Write-Host "  분류:   $Classification"
}

Write-Host ""
Write-Host "다음 단계" -ForegroundColor Cyan

switch ($Classification) {
    "PRODUCT_CODE_BUG" {
        Write-Host "  Claude 가 보고서를 읽고 src/ 를 수정합니다."
        Write-Host "  수정 후 다시 이 명령을 실행하세요."
    }
    "TEST_OR_REQUIREMENT_SUSPECT" {
        $ScopeArg = if ($Scope -eq "module") { "module $TargetId" } else { "system" }
        Write-Host "  /codex-recheck $ScopeArg `"$RelativeReport`""
    }
    "BLOCKED_ENVIRONMENT" {
        Write-Host "  보고서의 '사용자 조치' 항목을 확인하세요."
    }
    default {
        if ($Verdict -eq "PASS") {
            Write-Host "  추적성 갱신: workflow/scripts/build-traceability.ps1"
        }
        else {
            Write-Host "  보고서를 확인하세요."
        }
    }
}

Write-Host ""
Write-Output "REPORT=$RelativeReport"
Write-Output "RESULT=$Verdict"
Write-Output "CLASSIFICATION=$Classification"
