<#
.SYNOPSIS
    새 프로젝트에 이 워크플로를 이식하고 초기화한다.

.DESCRIPTION
    다음 작업을 수행한다.

    1. 스택 프리셋을 골라 config.json 의 commands / junit 을 채운다
    2. 필요한 디렉터리를 생성한다
    3. state.json 을 초기화한다
    4. ~/.codex/config.toml 에 전권 설정을 추가한다 (선택)

    이 스크립트는 제품 코드를 건드리지 않는다.
    config.json 의 paths 를 먼저 프로젝트 구조에 맞게 수정한 뒤 실행해도 된다.

.PARAMETER Preset
    workflow/presets.json 의 프리셋 키.
    생략하면 목록을 보여주고 입력을 받는다.

.PARAMETER SkipHomeConfig
    ~/.codex/config.toml 패치를 건너뛴다.

.PARAMETER Force
    이미 초기화된 config.json / state.json 을 덮어쓴다.

.EXAMPLE
    pwsh -NoProfile -File workflow/scripts/init-workspace.ps1

.EXAMPLE
    pwsh -NoProfile -File workflow/scripts/init-workspace.ps1 -Preset python-pytest
#>

[CmdletBinding()]
param(
    [string]$Preset,
    [switch]$SkipHomeConfig,
    [switch]$Force
)

. "$PSScriptRoot\Common.ps1"

Initialize-CodexEncoding

$Root = Get-CodexRoot

Write-Host ""
Write-Host "워크플로 초기화" -ForegroundColor Cyan
Write-Host "프로젝트 루트: $Root"
Write-Host ""

# ---------------------------------------------------------------
# 1. 프리셋 선택
# ---------------------------------------------------------------

$PresetsPath = Join-Path $Root "workflow\presets.json"
$Presets = (Read-Utf8File -Path $PresetsPath | ConvertFrom-Json)
$PresetNames = @($Presets.presets.PSObject.Properties.Name)

if ([string]::IsNullOrWhiteSpace($Preset)) {
    Write-Host "사용 가능한 스택 프리셋" -ForegroundColor Cyan

    for ($Index = 0; $Index -lt $PresetNames.Count; $Index++) {
        $Name = $PresetNames[$Index]
        Write-Host ("  {0}. {1,-16} {2}" -f ($Index + 1), $Name, $Presets.presets.$Name.label)
    }

    Write-Host ""
    $Answer = Read-Host "번호 또는 이름을 입력하세요"

    if ($Answer -match '^\d+$') {
        $Selected = [int]$Answer - 1

        if ($Selected -lt 0 -or $Selected -ge $PresetNames.Count) {
            throw "범위를 벗어난 번호입니다: $Answer"
        }

        $Preset = $PresetNames[$Selected]
    }
    else {
        $Preset = $Answer.Trim()
    }
}

if ($PresetNames -notcontains $Preset) {
    throw "알 수 없는 프리셋입니다: $Preset`n사용 가능: $($PresetNames -join ', ')"
}

$Chosen = $Presets.presets.$Preset

Write-Host "선택: $Preset ($($Chosen.label))" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------------
# 2. config.json 채우기
# ---------------------------------------------------------------

$ConfigPath = Join-Path $Root "workflow\config.json"
$Config = (Read-Utf8File -Path $ConfigPath | ConvertFrom-Json)

$AlreadyConfigured = -not (Test-CodexPlaceholder -Value $Config.stack.preset)

if ($AlreadyConfigured -and -not $Force) {
    throw @"
config.json 이 이미 초기화되어 있습니다. (stack.preset = $($Config.stack.preset))

덮어쓰려면 -Force 를 지정하세요.
"@
}

$Config.stack.preset = $Preset

$Config.commands.unitTest   = $Chosen.commands.unitTest
$Config.commands.moduleTest = $Chosen.commands.moduleTest
$Config.commands.systemTest = $Chosen.commands.systemTest

$Config.junit.moduleTest = $Chosen.junit.moduleTest
$Config.junit.systemTest = $Chosen.junit.systemTest

Write-Utf8NoBomFile `
    -Path $ConfigPath `
    -Content ($Config | ConvertTo-Json -Depth 12)

Write-Host "config.json 갱신" -ForegroundColor Green
Write-Host "  unit   : $($Config.commands.unitTest)"
Write-Host "  module : $($Config.commands.moduleTest)"
Write-Host "  system : $($Config.commands.systemTest)"
Write-Host ""

# ---------------------------------------------------------------
# 3. 디렉터리 생성
# ---------------------------------------------------------------

$Directories = @()
$Directories += @($Config.paths.productCode)
$Directories += @(
    $Config.paths.unitTests
    $Config.paths.moduleTests
    $Config.paths.systemTests
    $Config.paths.systemRequirements
    $Config.paths.moduleRequirements
    $Config.paths.design
    $Config.paths.designAssets
    $Config.paths.moduleTestReports
    $Config.paths.systemTestReports
    $Config.paths.recheckReports
    $Config.paths.prompts
    $Config.paths.rules
    $Config.paths.temp
)

$Created = 0

foreach ($Directory in $Directories) {
    if ([string]::IsNullOrWhiteSpace($Directory)) { continue }

    $Full = Join-Path $Root ($Directory -replace "/", "\")

    if (-not (Test-Path -LiteralPath $Full)) {
        New-Item -ItemType Directory -Path $Full -Force | Out-Null
        $Created++
    }
}

Write-Host "디렉터리 확인 완료 (신규 $Created 개)" -ForegroundColor Green

# ---------------------------------------------------------------
# 4. state.json 초기화
# ---------------------------------------------------------------

$StatePath = Join-Path $Root ($Config.paths.state -replace "/", "\")
$StateExists = Test-Path -LiteralPath $StatePath
$NeedsInit = $true

if ($StateExists) {
    try {
        $Existing = (Read-Utf8File -Path $StatePath | ConvertFrom-Json)
        $HasModules = (Get-CodexPropertyNames -Object $Existing.modules).Count -gt 0
        $HasSystem = [int]$Existing.system.revision -gt 0

        if (($HasModules -or $HasSystem) -and -not $Force) {
            Write-Host "state.json 에 기존 작업 이력이 있어 보존합니다." -ForegroundColor Yellow
            $NeedsInit = $false
        }
    }
    catch {
        Write-Warning "state.json 을 읽을 수 없어 새로 만듭니다."
    }
}

if ($NeedsInit) {
    $State = [ordered]@{
        schemaVersion  = 2
        activeModuleId = $null
        system         = [ordered]@{
            requirementPath = (Convert-ToGitPath (Join-Path $Config.paths.systemRequirements "system.md"))
            revision        = 0
            hash            = $null
            status          = "empty"
            updatedAt       = $null
        }
        modules        = [ordered]@{}
        history        = @()
    }

    Write-Utf8NoBomFile `
        -Path $StatePath `
        -Content ($State | ConvertTo-Json -Depth 12)

    Write-Host "state.json 초기화" -ForegroundColor Green
}

Write-Host ""

# ---------------------------------------------------------------
# 5. 홈 config.toml 패치
# ---------------------------------------------------------------
# 프로젝트 .codex/config.toml 은 codex CLI 가 읽지 않는다 (0.146.0 확인).
# 대화형 product design 세션의 권한은 홈 config 로만 결정된다.
# 스킬이 실행하는 단계는 래퍼가 CLI 플래그로 직접 제어하므로
# 이 패치와 무관하게 동작한다.

if ($SkipHomeConfig) {
    Write-Host "홈 config 패치 건너뜀 (-SkipHomeConfig)" -ForegroundColor Yellow
}
else {
    $CodexHome = $env:CODEX_HOME

    if ([string]::IsNullOrWhiteSpace($CodexHome)) {
        $CodexHome = Join-Path $HOME ".codex"
    }

    $HomeConfigPath = Join-Path $CodexHome "config.toml"

    New-Item -ItemType Directory -Path $CodexHome -Force | Out-Null

    $Existing = ""

    if (Test-Path -LiteralPath $HomeConfigPath) {
        $Existing = Read-Utf8File -Path $HomeConfigPath

        $BackupPath = "$HomeConfigPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -LiteralPath $HomeConfigPath -Destination $BackupPath -Force

        Write-Host "홈 config 백업: $BackupPath"
    }

    $DesiredSettings = [ordered]@{
        approval_policy = '"never"'
        sandbox_mode    = '"danger-full-access"'
    }

    $Lines = if ([string]::IsNullOrWhiteSpace($Existing)) {
        @()
    }
    else {
        @($Existing -split "`r?`n")
    }

    $Changed = $false

    foreach ($Key in $DesiredSettings.Keys) {
        $Value = $DesiredSettings[$Key]
        $Pattern = "^\s*$Key\s*="
        $FoundAt = -1

        for ($Index = 0; $Index -lt $Lines.Count; $Index++) {
            if ($Lines[$Index] -match $Pattern) {
                $FoundAt = $Index
                break
            }
        }

        if ($FoundAt -ge 0) {
            if ($Lines[$FoundAt].Trim() -ne "$Key = $Value") {
                Write-Host "  기존 설정 유지: $($Lines[$FoundAt].Trim())" -ForegroundColor Yellow
                Write-Host "    (원하는 값: $Key = $Value / 직접 수정하세요)"
            }
            else {
                Write-Host "  이미 적용됨: $Key = $Value"
            }
        }
        else {
            $Lines += "$Key = $Value"
            $Changed = $true
            Write-Host "  추가: $Key = $Value" -ForegroundColor Green
        }
    }

    if ($Changed) {
        Write-Utf8NoBomFile `
            -Path $HomeConfigPath `
            -Content (($Lines -join "`n").TrimEnd() + "`n")

        Write-Host "홈 config 갱신: $HomeConfigPath" -ForegroundColor Green
    }
}

# ---------------------------------------------------------------
# 안내
# ---------------------------------------------------------------

Write-Host ""
Write-Host "초기화 완료" -ForegroundColor Green
Write-Host ""
Write-Host "다음 단계" -ForegroundColor Cyan
Write-Host "  1. workflow/scripts/check-codex-env.ps1 로 환경을 확인합니다."
Write-Host "  2. README.md 에 프로젝트 개요를 작성합니다."
Write-Host "     Codex 가 요구사항을 쓸 때 읽는 유일한 맥락입니다."
Write-Host "  3. git add -A; git commit -m 'chore: 워크플로 초기화'"
Write-Host "  4. /requirements system '<전체 프로그램 요청>' 으로 시작합니다."
Write-Host ""
Write-Host "ID 규칙" -ForegroundColor Cyan
Write-Host "  시스템 : SYS-FR-001 / SYS-NFR-001 / SYS-AC-001"
Write-Host "  모듈   : MOD-<모듈>-FR-001 / -NFR-001 / -AC-001"
Write-Host "  테스트 이름에 해당 AC ID 를 넣어야 추적성이 잡힙니다."
Write-Host "  예시   : $($Chosen.idConvention.example)"
Write-Host ""
