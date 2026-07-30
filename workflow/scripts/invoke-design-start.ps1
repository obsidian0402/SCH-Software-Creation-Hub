<#
.SYNOPSIS
    제품 디자인 작업 공간을 준비한다. Codex 를 호출하지 않는다.

.DESCRIPTION
    제품 디자인은 반복 대화가 필요하므로 일회성 codex exec 로 감싸지 않는다.
    이 스크립트는 앞단만 잡는다.

    1. 모듈 상태와 요구사항 신선도를 확인한다
    2. 다음 디자인 버전 번호를 정한다
    3. 세 공간(workflow / wireframe / ui) 폴더를 만든다
    4. _meta.json 에 기준 요구사항 개정과 해시를 고정한다
    5. BRIEF-FOR-CODEX.md 를 생성한다

    실제 디자인은 터미널에서 codex 를 열고 진행한다.
    완료 후 /design-close 로 검증한다.

.PARAMETER ModuleId
    대상 모듈. 생략하면 활성 모듈을 쓴다.

.PARAMETER NewVersion
    요구사항이 바뀌지 않았어도 새 버전을 강제로 만든다.

.EXAMPLE
    pwsh -NoProfile -File workflow/scripts/invoke-design-start.ps1 -ModuleId AUTH
#>

[CmdletBinding()]
param(
    [string]$ModuleId,
    [switch]$NewVersion
)

. "$PSScriptRoot\Common.ps1"

Initialize-CodexEncoding

$Root = Get-CodexRoot
$Config = Get-CodexConfig -Root $Root
$State = Get-CodexState -Root $Root -Config $Config

$TargetId = Resolve-CodexModuleId -State $State -ModuleId $ModuleId
$Module = Get-CodexModuleState -State $State -ModuleId $TargetId

$EffectiveMode = Get-CodexMode -Config $Config -State $State -ModuleId $TargetId
Write-CodexModeBanner -Mode $EffectiveMode -Stage "design-start" -ModuleId $TargetId

# ---------------------------------------------------------------
# 사전 조건
# ---------------------------------------------------------------

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

if ([string]::IsNullOrWhiteSpace($RequirementRelative)) {
    throw "모듈 '$TargetId' 의 요구사항 경로가 없습니다. /requirements module $TargetId 를 먼저 실행하세요."
}

$RequirementPath = Resolve-CodexPath -Root $Root -Path $RequirementRelative

if (-not (Test-Path -LiteralPath $RequirementPath)) {
    throw @"
모듈 요구사항 문서가 없습니다: $RequirementRelative

/requirements module $TargetId 를 먼저 실행하세요.
"@
}

# 상태 파일의 해시와 실제 파일이 일치하는지 확인한다.
$ActualHash = Get-CodexFileHash -Path $RequirementPath
$RecordedHash = Get-CodexProperty -Object $Module -Name "hash" -Default $null

if ($RecordedHash -and ($ActualHash -ne $RecordedHash)) {
    $Message = @"
모듈 요구사항 파일이 상태 파일 기록과 다릅니다.

기록된 해시: $RecordedHash
실제 해시:   $ActualHash

문서가 수작업으로 수정되었을 가능성이 있습니다.
/requirements module $TargetId 로 다시 생성하거나 변경을 되돌리세요.
"@

    if ($EffectiveMode -eq "strict") {
        throw $Message
    }

    Write-Warning $Message
}

# ---------------------------------------------------------------
# 버전 결정
# ---------------------------------------------------------------

$DesignRootRelative = "$($Config.paths.design)/$($TargetId.ToLowerInvariant())"
$AssetsRootRelative = "$($Config.paths.designAssets)/$($TargetId.ToLowerInvariant())"

$DesignRoot = Join-Path $Root ($DesignRootRelative -replace "/", "\")

$ExistingDesign = Get-CodexProperty -Object $Module -Name "design" -Default $null
$PreviousVersion = [int](Get-CodexProperty -Object $ExistingDesign -Name "version" -Default 0)

if ($EffectiveMode -eq "vibe" -and -not $NewVersion) {
    # vibe 모드는 버전을 늘리지 않고 draft 한 곳에서 반복한다.
    $VersionLabel = "draft"
    $VersionNumber = $PreviousVersion
    $Reason = "vibe 모드 - draft 폴더 재사용"
}
else {
    $PreviousHash = Get-CodexProperty -Object $ExistingDesign -Name "requirementHash" -Default $null
    $RequirementChanged = ($PreviousHash -ne $ActualHash)

    if ($PreviousVersion -eq 0) {
        $VersionNumber = 1
        $Reason = "첫 디자인"
    }
    elseif ($NewVersion) {
        $VersionNumber = $PreviousVersion + 1
        $Reason = "-NewVersion 지정"
    }
    elseif ($RequirementChanged) {
        $VersionNumber = $PreviousVersion + 1
        $Reason = "기준 요구사항 변경"
    }
    else {
        $VersionNumber = $PreviousVersion
        $Reason = "요구사항 변경 없음 - 기존 버전 계속"
    }

    $VersionLabel = "v{0:D3}" -f $VersionNumber
}

$DesignDirRelative = "$DesignRootRelative/$VersionLabel"
$AssetsDirRelative = "$AssetsRootRelative/$VersionLabel"

$DesignDir = Join-Path $Root ($DesignDirRelative -replace "/", "\")
$AssetsDir = Join-Path $Root ($AssetsDirRelative -replace "/", "\")

# ---------------------------------------------------------------
# 폴더 생성
# ---------------------------------------------------------------

$Spaces = @($Config.designSpaces)

foreach ($Space in $Spaces) {
    New-Item -ItemType Directory -Force -Path (Join-Path $DesignDir $Space.directory) | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $AssetsDir $Space.key) | Out-Null
}

# ---------------------------------------------------------------
# _meta.json 고정
# ---------------------------------------------------------------

$MetaPath = Join-Path $DesignDir "_meta.json"

$Meta = [ordered]@{
    moduleId            = $TargetId
    moduleName          = (Get-CodexProperty -Object $Module -Name "moduleName" -Default $TargetId)
    designVersion       = $VersionLabel
    requirementPath     = (ConvertTo-CodexRelativePath -Root $Root -Path $RequirementPath)
    requirementRevision = [int](Get-CodexProperty -Object $Module -Name "revision" -Default 0)
    requirementHash     = $ActualHash
    systemRevision      = [int]$State.system.revision
    mode                = $EffectiveMode
    createdAt           = (Get-Date).ToString("o")
}

if (Test-Path -LiteralPath $MetaPath) {
    $OldMeta = (Read-Utf8File -Path $MetaPath | ConvertFrom-Json)
    $Meta["previousCreatedAt"] = Get-CodexProperty -Object $OldMeta -Name "createdAt" -Default $null
}

Write-Utf8NoBomFile -Path $MetaPath -Content (($Meta | ConvertTo-Json -Depth 6))

# ---------------------------------------------------------------
# 요구사항 ID 수집
# ---------------------------------------------------------------

$RequirementText = Read-Utf8File -Path $RequirementPath
$Pattern = Get-CodexIdRegex -Config $Config
$Prefix = "MOD-$($TargetId.ToUpperInvariant())-"

$ModuleIdsFound = @(
    Get-CodexIdsFromText -Text $RequirementText -Pattern $Pattern |
        Where-Object { $_.StartsWith($Prefix) }
)

$IdSummary = if ($ModuleIdsFound.Count -eq 0) {
    "(요구사항 문서에서 ID 를 찾지 못했습니다. 문서를 직접 확인하세요.)"
}
else {
    ($ModuleIdsFound | ForEach-Object { "- $_" }) -join "`n"
}

# ---------------------------------------------------------------
# BRIEF-FOR-CODEX.md 생성
# ---------------------------------------------------------------

$BriefPath = Join-Path $DesignDir "BRIEF-FOR-CODEX.md"

$Brief = Expand-CodexPlaceholder `
    -Template (Get-CodexPromptTemplate -Root $Root -Config $Config -FileName "design-brief.md") `
    -Values @{
        MODULE_ID               = $TargetId
        MODULE_UPPER            = $TargetId.ToUpperInvariant()
        MODULE_NAME             = $Meta.moduleName
        DESIGN_VERSION          = $VersionLabel
        DESIGN_DIR              = $DesignDirRelative
        ASSETS_DIR              = $AssetsDirRelative
        BRIEF_PATH              = "$DesignDirRelative/BRIEF-FOR-CODEX.md"
        REQUIREMENT_PATH        = $Meta.requirementPath
        REQUIREMENT_REVISION    = [string]$Meta.requirementRevision
        REQUIREMENT_HASH        = $ActualHash
        REQUIREMENT_IDS         = $IdSummary
        SYSTEM_REQUIREMENT_PATH = $State.system.requirementPath
        SYSTEM_REVISION         = [string]$State.system.revision
        MODE                    = $EffectiveMode
    }

Write-Utf8NoBomFile -Path $BriefPath -Content $Brief

# ---------------------------------------------------------------
# 상태 기록
# ---------------------------------------------------------------

$DesignState = [ordered]@{
    version         = $VersionNumber
    versionLabel    = $VersionLabel
    path            = $DesignDirRelative
    assetsPath      = $AssetsDirRelative
    requirementHash = $ActualHash
    status          = "design_in_progress"
    startedAt       = (Get-Date).ToString("o")
    closedAt        = $null
}

Set-CodexProperty -Object $Module -Name "design" -Value ([pscustomobject]$DesignState)
Set-CodexProperty -Object $Module -Name "updatedAt" -Value ((Get-Date).ToString("o"))
Set-CodexProperty -Object $State -Name "activeModuleId" -Value $TargetId

Add-CodexHistory -State $State -Stage "design-start" -ModuleId $TargetId `
    -Detail "$VersionLabel ($Reason)"

Save-CodexState -Root $Root -Config $Config -State $State

# ---------------------------------------------------------------
# 안내
# ---------------------------------------------------------------

Write-Host ""
Write-Host "디자인 작업 공간 준비 완료" -ForegroundColor Green
Write-Host "  모듈:   $TargetId"
Write-Host "  버전:   $VersionLabel  ($Reason)"
Write-Host "  경로:   $DesignDirRelative"
Write-Host "  자료:   $AssetsDirRelative"
Write-Host ""
Write-Host "생성된 공간" -ForegroundColor Cyan

foreach ($Space in $Spaces) {
    Write-Host ("  {0,-14} {1}" -f $Space.directory, $Space.label)
}

Write-Host ""
Write-Host "이제 터미널에서 대화형으로 디자인 작업을 진행하세요." -ForegroundColor Cyan
Write-Host ""
Write-Host "  codex"
Write-Host "  > @product design 다음 지시문을 따라 작업한다:"
Write-Host "    $DesignDirRelative/BRIEF-FOR-CODEX.md"
Write-Host ""
Write-Host "작업을 마치면 검증합니다." -ForegroundColor Cyan
Write-Host "  /design-close $TargetId"
Write-Host ""

Write-Output "MODULE=$TargetId"
Write-Output "DESIGN_VERSION=$VersionLabel"
Write-Output "DESIGN_DIR=$DesignDirRelative"
Write-Output "BRIEF=$DesignDirRelative/BRIEF-FOR-CODEX.md"
