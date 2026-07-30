<#
.SYNOPSIS
    제품 디자인 산출물을 검증하고 추적성을 생성한다. Codex 를 호출하지 않는다.

.DESCRIPTION
    1. 세 공간(workflow / wireframe / ui) 에 산출물이 있는지 확인한다
    2. _meta.json 의 기준 해시와 현재 요구사항이 일치하는지 확인한다
    3. FLOW / SCREEN / STATE / COMP 항목이 상위 요구사항을 참조하는지 검증한다
    4. 존재하지 않는 ID 참조와 고아 항목을 검출한다
    5. traceability.md 와 traceability.json 을 생성한다
    6. 상태를 design_ready 로 기록한다

    strict 모드에서는 위반이 있으면 실패한다. vibe 모드에서는 경고한다.

.PARAMETER ModuleId
    대상 모듈. 생략하면 활성 모듈을 쓴다.

.EXAMPLE
    pwsh -NoProfile -File workflow/scripts/invoke-design-close.ps1 -ModuleId AUTH
#>

[CmdletBinding()]
param(
    [string]$ModuleId
)

. "$PSScriptRoot\Common.ps1"

Initialize-CodexEncoding

$Root = Get-CodexRoot
$Config = Get-CodexConfig -Root $Root
$State = Get-CodexState -Root $Root -Config $Config

$TargetId = Resolve-CodexModuleId -State $State -ModuleId $ModuleId
$Module = Get-CodexModuleState -State $State -ModuleId $TargetId

$EffectiveMode = Get-CodexMode -Config $Config -State $State -ModuleId $TargetId
Write-CodexModeBanner -Mode $EffectiveMode -Stage "design-close" -ModuleId $TargetId

$Design = Get-CodexProperty -Object $Module -Name "design" -Default $null

if ($null -eq $Design) {
    throw "모듈 '$TargetId' 에 디자인 작업 기록이 없습니다. /design-start $TargetId 를 먼저 실행하세요."
}

$DesignDirRelative = Get-CodexProperty -Object $Design -Name "path" -Default ""
$DesignDir = Resolve-CodexPath -Root $Root -Path $DesignDirRelative -MustExist

$Problems = [System.Collections.Generic.List[string]]::new()
$Warnings = [System.Collections.Generic.List[string]]::new()

# ---------------------------------------------------------------
# 1. 기준 요구사항 해시 확인
# ---------------------------------------------------------------

$MetaPath = Join-Path $DesignDir "_meta.json"

if (-not (Test-Path -LiteralPath $MetaPath)) {
    $Problems.Add("_meta.json 이 없습니다. /design-start 를 다시 실행하세요.")
    $Meta = $null
}
else {
    $Meta = (Read-Utf8File -Path $MetaPath | ConvertFrom-Json)
    $RequirementPath = Resolve-CodexPath -Root $Root -Path $Meta.requirementPath

    if (-not (Test-Path -LiteralPath $RequirementPath)) {
        $Problems.Add("기준 요구사항 문서를 찾을 수 없습니다: $($Meta.requirementPath)")
    }
    else {
        $CurrentHash = Get-CodexFileHash -Path $RequirementPath

        if ($CurrentHash -ne $Meta.requirementHash) {
            $Problems.Add(@"
디자인 작업 도중 기준 요구사항이 변경되었습니다.

  기준 해시: $($Meta.requirementHash)
  현재 해시: $CurrentHash

/design-start $TargetId 로 새 버전을 만들어 다시 작업해야 합니다.
"@)
        }
    }
}

# ---------------------------------------------------------------
# 2. 세 공간 산출물 존재 확인
# ---------------------------------------------------------------

$Spaces = @($Config.designSpaces)
$SpaceFiles = [ordered]@{}

foreach ($Space in $Spaces) {
    $SpaceDir = Join-Path $DesignDir $Space.directory

    $Files = @()

    if (Test-Path -LiteralPath $SpaceDir) {
        $Files = @(
            Get-ChildItem -LiteralPath $SpaceDir -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Length -gt 0 }
        )
    }

    $SpaceFiles[$Space.key] = $Files

    if ($Files.Count -eq 0) {
        $Problems.Add("$($Space.label) 공간이 비어 있습니다: $($Space.directory)/")
    }
}

# ---------------------------------------------------------------
# 3. 디자인 ID 추적성 검증
# ---------------------------------------------------------------

$Pattern = Get-CodexIdRegex -Config $Config
$Columns = $Config.traceability.columns

# 모듈 요구사항 문서의 유효 ID 집합
$ValidIds = @()

if ($Meta -and (Test-Path -LiteralPath (Join-Path $Root ($Meta.requirementPath -replace "/", "\")))) {
    $ReqText = Read-Utf8File -Path (Join-Path $Root ($Meta.requirementPath -replace "/", "\"))
    $ValidIds = @(Get-CodexIdsFromText -Text $ReqText -Pattern $Pattern)
}

$DesignIdKinds = @(
    [pscustomobject]@{ Key = "designFlow";      Prefix = $Config.ids.designFlow }
    [pscustomobject]@{ Key = "designScreen";    Prefix = $Config.ids.designScreen }
    [pscustomobject]@{ Key = "designState";     Prefix = $Config.ids.designState }
    [pscustomobject]@{ Key = "designComponent"; Prefix = $Config.ids.designComponent }
)

$DesignItems = [System.Collections.Generic.List[pscustomobject]]::new()

$AllDesignFiles = @(
    Get-ChildItem -LiteralPath $DesignDir -Recurse -File -Filter "*.md" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne "BRIEF-FOR-CODEX.md" }
)

foreach ($File in $AllDesignFiles) {
    $Text = Read-Utf8File -Path $File.FullName
    $Rows = Read-CodexMarkdownTables -Markdown $Text
    $RelativeFile = ConvertTo-CodexRelativePath -Root $Root -Path $File.FullName

    foreach ($Row in $Rows) {
        $Id = (Get-CodexCell -Row $Row -Column $Columns.id).Trim().ToUpperInvariant()

        if ([string]::IsNullOrWhiteSpace($Id)) { continue }

        $Kind = $DesignIdKinds | Where-Object { $Id -match "^$($_.Prefix)-[0-9]{3}$" } | Select-Object -First 1

        if (-not $Kind) { continue }

        $ParentText = Get-CodexCell -Row $Row -Column $Columns.parent
        $Parents = @(Get-CodexIdsFromText -Text $ParentText -Pattern $Pattern)

        $DesignItems.Add([pscustomobject]@{
            id      = $Id
            kind    = $Kind.Prefix
            file    = $RelativeFile
            parents = $Parents
            dangling = @($Parents | Where-Object { $ValidIds -notcontains $_ })
        })
    }
}

$Orphans = @($DesignItems | Where-Object { $_.parents.Count -eq 0 })
$Dangling = @($DesignItems | Where-Object { $_.dangling.Count -gt 0 })

if ($DesignItems.Count -eq 0) {
    $Problems.Add("디자인 항목(FLOW / SCREEN / STATE / COMP)을 하나도 찾지 못했습니다. 표 헤더가 '$($Columns.id)' 와 '$($Columns.parent)' 인지 확인하세요.")
}

foreach ($Item in $Orphans) {
    $Problems.Add("고아 항목: $($Item.id) 에 상위 요구사항이 없습니다. ($($Item.file))")
}

foreach ($Item in $Dangling) {
    $Problems.Add("존재하지 않는 요구사항 참조: $($Item.id) -> $($Item.dangling -join ', ') ($($Item.file))")
}

# 요구사항 쪽 커버리지는 경고로만 다룬다. 디자인이 모든 요구사항을 다룰 필요는 없다.
$Covered = @($DesignItems | ForEach-Object { $_.parents } | Sort-Object -Unique)
$Uncovered = @($ValidIds | Where-Object { $_ -notmatch '-AC-[0-9]{3}$' } | Where-Object { $Covered -notcontains $_ })

foreach ($Id in $Uncovered) {
    $Warnings.Add("디자인에서 다루지 않은 요구사항: $Id")
}

# ---------------------------------------------------------------
# 판정
# ---------------------------------------------------------------

Write-Host ""
Write-Host "산출물 확인" -ForegroundColor Cyan

foreach ($Space in $Spaces) {
    $Count = $SpaceFiles[$Space.key].Count
    $Mark = if ($Count -gt 0) { "OK  " } else { "비어있음" }
    Write-Host ("  {0,-8} {1,-14} {2} 개 파일" -f $Mark, $Space.directory, $Count)
}

Write-Host ""
Write-Host "디자인 항목: $($DesignItems.Count) 개" -ForegroundColor Cyan

foreach ($Kind in $DesignIdKinds) {
    $Count = @($DesignItems | Where-Object { $_.kind -eq $Kind.Prefix }).Count
    Write-Host ("  {0,-8} {1} 개" -f $Kind.Prefix, $Count)
}

if ($Warnings.Count -gt 0) {
    Write-Host ""
    foreach ($Warning in $Warnings) {
        Write-Warning $Warning
    }
}

if ($Problems.Count -gt 0) {
    Write-Host ""

    $Message = @"
디자인 검증에서 $($Problems.Count) 건의 위반이 발견되었습니다.

$(($Problems | ForEach-Object { "- $_" }) -join "`n")
"@

    if ($EffectiveMode -eq "strict") {
        throw $Message
    }

    Write-Warning $Message
    Write-Host "vibe 모드이므로 계속 진행합니다." -ForegroundColor Yellow
}

# ---------------------------------------------------------------
# 추적성 파일 생성
# ---------------------------------------------------------------

$TraceJsonPath = Join-Path $DesignDir "traceability.json"
$TraceMdPath = Join-Path $DesignDir "traceability.md"

$TraceData = [ordered]@{
    moduleId        = $TargetId
    designVersion   = (Get-CodexProperty -Object $Design -Name "versionLabel" -Default "")
    requirementPath = $(if ($Meta) { $Meta.requirementPath } else { "" })
    requirementHash = $(if ($Meta) { $Meta.requirementHash } else { "" })
    generatedAt     = (Get-Date).ToString("o")
    mode            = $EffectiveMode
    itemCount       = $DesignItems.Count
    items           = @($DesignItems)
    orphans         = @($Orphans | ForEach-Object { $_.id })
    danglingRefs    = @($Dangling | ForEach-Object { [ordered]@{ id = $_.id; refs = $_.dangling } })
    uncoveredRequirements = @($Uncovered)
}

Write-Utf8NoBomFile -Path $TraceJsonPath -Content ($TraceData | ConvertTo-Json -Depth 8)

$MdLines = [System.Collections.Generic.List[string]]::new()
$MdLines.Add("# 디자인 추적성: $TargetId")
$MdLines.Add("")
$MdLines.Add("이 파일은 /design-close 가 생성했다. 직접 수정하지 않는다.")
$MdLines.Add("")
$MdLines.Add("| 항목 | 값 |")
$MdLines.Add("|---|---|")
$MdLines.Add("| 모듈 | $TargetId |")
$MdLines.Add("| 디자인 버전 | $($TraceData.designVersion) |")
$MdLines.Add("| 기준 요구사항 | $($TraceData.requirementPath) |")
$MdLines.Add("| 생성 시각 | $($TraceData.generatedAt) |")
$MdLines.Add("| 모드 | $EffectiveMode |")
$MdLines.Add("")
$MdLines.Add("## 디자인 항목에서 요구사항으로")
$MdLines.Add("")
$MdLines.Add("| 디자인 ID | 종류 | 상위 요구사항 | 문서 |")
$MdLines.Add("|---|---|---|---|")

foreach ($Item in ($DesignItems | Sort-Object kind, id)) {
    $ParentText = if ($Item.parents.Count -gt 0) { $Item.parents -join ", " } else { "**없음**" }
    $MdLines.Add("| $($Item.id) | $($Item.kind) | $ParentText | $($Item.file) |")
}

$MdLines.Add("")
$MdLines.Add("## 요구사항에서 디자인 항목으로")
$MdLines.Add("")
$MdLines.Add("| 요구사항 ID | 디자인 항목 |")
$MdLines.Add("|---|---|")

foreach ($Id in ($ValidIds | Where-Object { $_ -notmatch '-AC-[0-9]{3}$' } | Sort-Object)) {
    $Linked = @($DesignItems | Where-Object { $_.parents -contains $Id } | ForEach-Object { $_.id })
    $LinkText = if ($Linked.Count -gt 0) { $Linked -join ", " } else { "**없음**" }
    $MdLines.Add("| $Id | $LinkText |")
}

if ($Problems.Count -gt 0 -or $Warnings.Count -gt 0) {
    $MdLines.Add("")
    $MdLines.Add("## 검증 결과")
    $MdLines.Add("")

    foreach ($Problem in $Problems) {
        $MdLines.Add("- 위반: $($Problem -replace "`r?`n", ' ')")
    }

    foreach ($Warning in $Warnings) {
        $MdLines.Add("- 경고: $Warning")
    }
}

$MdLines.Add("")
Write-Utf8NoBomFile -Path $TraceMdPath -Content ($MdLines -join "`n")

# ---------------------------------------------------------------
# 상태 기록
# ---------------------------------------------------------------

Set-CodexProperty -Object $Design -Name "status" -Value "design_ready"
Set-CodexProperty -Object $Design -Name "closedAt" -Value ((Get-Date).ToString("o"))
Set-CodexProperty -Object $Design -Name "itemCount" -Value $DesignItems.Count
Set-CodexProperty -Object $Design -Name "violations" -Value $Problems.Count

$CurrentStatus = Get-CodexProperty -Object $Module -Name "status" -Default "requirements_ready"

if ($CurrentStatus -eq "requirements_ready") {
    Set-CodexProperty -Object $Module -Name "status" -Value "design_ready"
}

Set-CodexProperty -Object $Module -Name "updatedAt" -Value ((Get-Date).ToString("o"))

Add-CodexHistory -State $State -Stage "design-close" -ModuleId $TargetId `
    -Detail "$($TraceData.designVersion) / 항목 $($DesignItems.Count) / 위반 $($Problems.Count)"

Save-CodexState -Root $Root -Config $Config -State $State

Write-Host ""
Write-Host "디자인 검증 완료" -ForegroundColor Green
Write-Host "  추적성: $(ConvertTo-CodexRelativePath -Root $Root -Path $TraceMdPath)"
Write-Host "          $(ConvertTo-CodexRelativePath -Root $Root -Path $TraceJsonPath)"
Write-Host ""
Write-Host "다음 단계" -ForegroundColor Cyan
Write-Host "  handoff.md 를 근거로 Claude 가 src/ 를 구현합니다."
Write-Host "  구현 후 /codex-test module $TargetId"
Write-Host ""

Write-Output "MODULE=$TargetId"
Write-Output "DESIGN_VERSION=$($TraceData.designVersion)"
Write-Output "ITEMS=$($DesignItems.Count)"
Write-Output "VIOLATIONS=$($Problems.Count)"
