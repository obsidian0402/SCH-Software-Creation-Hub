<#
.SYNOPSIS
    Codex 에게 요구사항 작성을 위임한다.

.DESCRIPTION
    세 가지 모드가 있다.

    system           전체 프로그램 요구사항 작성 + 모듈 분해 제안
    module           모듈 하나의 요구사항 작성
    confirm-modules  제안된 모듈 목록을 사용자가 확정

.PARAMETER Mode
    system / module / confirm-modules

.PARAMETER ModuleId
    module 모드에서 대상 모듈. 생략하면 활성 모듈을 쓴다.

.PARAMETER Request
    사용자 요청 원문.

.PARAMETER RequestFile
    사용자 요청이 담긴 파일 경로.
    긴 다국어 요청은 인자 대신 이 방식을 쓴다.

.PARAMETER ModuleIds
    confirm-modules 모드에서 확정할 모듈 목록.
    생략하면 제안된 전체를 확정한다.
    목록을 주면 빠진 모듈은 보관 처리된다.

.EXAMPLE
    pwsh -NoProfile -File workflow/scripts/invoke-requirements.ps1 -Mode system -RequestFile req.md

.EXAMPLE
    pwsh -NoProfile -File workflow/scripts/invoke-requirements.ps1 -Mode confirm-modules -ModuleIds AUTH,CART

.EXAMPLE
    pwsh -NoProfile -File workflow/scripts/invoke-requirements.ps1 -Mode module -ModuleId AUTH
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet("system", "module", "confirm-modules")]
    [string]$Mode,

    [string]$ModuleId,
    [string]$Request,
    [string]$RequestFile,
    [string[]]$ModuleIds
)

. "$PSScriptRoot\Common.ps1"

Initialize-CodexEncoding

$Root = Get-CodexRoot
$Config = Get-CodexConfig -Root $Root
$State = Get-CodexState -Root $Root -Config $Config

$SystemRequirementPath = $State.system.requirementPath

# ---------------------------------------------------------------
# 요청 본문 확보
# ---------------------------------------------------------------

function Get-RequestText {
    if (-not [string]::IsNullOrWhiteSpace($RequestFile)) {
        $Path = Resolve-CodexPath -Root $Root -Path $RequestFile -MustExist
        return (Read-Utf8File -Path $Path)
    }

    if (-not [string]::IsNullOrWhiteSpace($Request)) {
        return $Request
    }

    return ""
}

# ===============================================================
# confirm-modules
# ===============================================================

if ($Mode -eq "confirm-modules") {
    $Proposed = @(
        $State.modules.PSObject.Properties |
            Where-Object { (Get-CodexProperty -Object $_.Value -Name "status" -Default "") -eq "proposed" } |
            ForEach-Object { $_.Name }
    )

    if ($Proposed.Count -eq 0) {
        Write-Host "확정할 제안 모듈이 없습니다." -ForegroundColor Yellow
        Write-Host "등록된 모듈: $((Get-CodexModuleIds -State $State) -join ', ')"
        exit 0
    }

    $Keep = if ($null -eq $ModuleIds -or $ModuleIds.Count -eq 0) {
        $Proposed
    }
    else {
        @($ModuleIds | ForEach-Object { $_.Trim().ToUpperInvariant() })
    }

    $Unknown = @($Keep | Where-Object { $Proposed -notcontains $_ })

    if ($Unknown.Count -gt 0) {
        throw @"
제안 목록에 없는 모듈을 확정할 수 없습니다: $($Unknown -join ', ')

제안된 모듈: $($Proposed -join ', ')

새 모듈을 추가하려면 /requirements system 으로 모듈 분해를 다시 받으세요.
"@
    }

    $Archive = @($Proposed | Where-Object { $Keep -notcontains $_ })
    $ArchiveRoot = Join-Path $Root ($Config.paths.moduleRequirements -replace "/", "\") "_archived"

    foreach ($Id in $Keep) {
        Set-CodexProperty -Object $State.modules.$Id -Name "status" -Value "confirmed"
        Set-CodexProperty -Object $State.modules.$Id -Name "updatedAt" -Value ((Get-Date).ToString("o"))
        Write-Host "확정: $Id" -ForegroundColor Green
    }

    foreach ($Id in $Archive) {
        $Entry = $State.modules.$Id
        $SourceDirectory = Join-Path $Root ((Get-CodexProperty -Object $Entry -Name "requirementPath" -Default "") -replace "/", "\")
        $SourceDirectory = Split-Path -Parent $SourceDirectory

        if ((-not [string]::IsNullOrWhiteSpace($SourceDirectory)) -and (Test-Path -LiteralPath $SourceDirectory)) {
            New-Item -ItemType Directory -Path $ArchiveRoot -Force | Out-Null
            $Destination = Join-Path $ArchiveRoot $Id

            if (Test-Path -LiteralPath $Destination) {
                $Destination = "$Destination-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            }

            Move-Item -LiteralPath $SourceDirectory -Destination $Destination -Force
            Write-Host "보관: $Id -> $(ConvertTo-CodexRelativePath -Root $Root -Path $Destination)" -ForegroundColor Yellow
        }

        $State.modules.PSObject.Properties.Remove($Id)
    }

    if ([string]::IsNullOrWhiteSpace((Get-CodexProperty -Object $State -Name "activeModuleId" -Default ""))) {
        Set-CodexProperty -Object $State -Name "activeModuleId" -Value $Keep[0]
    }

    Add-CodexHistory -State $State -Stage "confirm-modules" `
        -Detail "확정 $($Keep -join ',') / 보관 $($Archive -join ',')"

    Save-CodexState -Root $Root -Config $Config -State $State

    Write-Host ""
    Write-Host "모듈 확정 완료" -ForegroundColor Green
    Write-Host "다음 단계: /requirements module <모듈>"
    Write-Host ""
    Write-Output "CONFIRMED=$($Keep -join ',')"
    Write-Output "ARCHIVED=$($Archive -join ',')"
    exit 0
}

# ===============================================================
# system
# ===============================================================

if ($Mode -eq "system") {
    $EffectiveMode = Get-CodexMode -Config $Config -State $State
    Write-CodexModeBanner -Mode $EffectiveMode -Stage "requirements system"

    $OutputPath = Resolve-CodexPath -Root $Root -Path $SystemRequirementPath
    $Exists = Test-Path -LiteralPath $OutputPath

    $Existing = if ($Exists) {
        @"
기존 시스템 요구사항 문서가 있다.

$OutputPath

기존 문서를 읽고 최신 요청을 반영해 문서 전체를 갱신한다.
기존 요구사항 및 인수 조건 ID 는 의미가 유지되는 한 보존한다.
기존 모듈 ID 도 보존한다.
"@
    }
    else {
        "기존 시스템 요구사항 문서는 없다. 새로 작성한다."
    }

    $KnownModules = Get-CodexModuleIds -State $State
    $KnownText = if ($KnownModules.Count -eq 0) { "(없음)" } else { $KnownModules -join ", " }

    $Prompt = Expand-CodexPlaceholder `
        -Template (Get-CodexPromptTemplate -Root $Root -Config $Config -FileName "requirements-system.md") `
        -Values @{
            ROOT          = $Root
            REQUEST       = (Get-RequestText)
            EXISTING      = $Existing
            KNOWN_MODULES = $KnownText
        }

    $Stage = Get-CodexStageConfig -Config $Config -Stage "requirements-system"

    $Guard = Start-CodexGuard -Root $Root -Config $Config -Mode $EffectiveMode `
        -AllowedPaths $Stage.AllowedPaths

    $Document = Invoke-CodexPrompt -Root $Root -Config $Config `
        -Prompt $Prompt -Stage "requirements-system"

    Complete-CodexGuard -Guard $Guard

    $Document = Remove-CodexCodeFence -Content $Document

    Assert-CodexDocument `
        -Content $Document `
        -MinimumLength ([int]$Config.validation.minRequirementLength) `
        -RequiredMarkers @($Config.validation.requiredRequirementMarkers) `
        -RejectPath "$OutputPath.rejected"

    Write-Utf8NoBomFile -Path $OutputPath -Content $Document

    $Hash = Get-CodexFileHash -Path $OutputPath
    $NewRevision = [int]$State.system.revision + 1

    Set-CodexProperty -Object $State.system -Name "revision" -Value $NewRevision
    Set-CodexProperty -Object $State.system -Name "hash" -Value $Hash
    Set-CodexProperty -Object $State.system -Name "status" -Value "requirements_ready"
    Set-CodexProperty -Object $State.system -Name "updatedAt" -Value ((Get-Date).ToString("o"))

    # 기존 모듈을 stale 로 전파
    $Stale = @(Set-CodexModuleStale -State $State `
        -Reason "시스템 요구사항이 개정 $NewRevision 으로 변경되었습니다.")

    # 모듈 분해 표 파싱
    $Heading = Get-CodexProperty -Object $Config.traceability -Name "moduleDecompositionHeading" -Default "모듈 분해"
    $Columns = $Config.traceability.columns
    $Rows = Read-CodexMarkdownTables -Markdown $Document

    $ModuleRows = @(
        $Rows | Where-Object {
            $_._Heading -like "*$Heading*" -and
            (Get-CodexCell -Row $_ -Column $Columns.moduleId) -match '^[A-Z][A-Z0-9-]*$'
        }
    )

    $Added = @()
    $ModuleRootRelative = $Config.paths.moduleRequirements

    foreach ($Row in $ModuleRows) {
        $Id = (Get-CodexCell -Row $Row -Column $Columns.moduleId).ToUpperInvariant()
        $Name = Get-CodexCell -Row $Row -Column $Columns.moduleName
        $Responsibility = Get-CodexCell -Row $Row -Column $Columns.responsibility
        $Covered = Get-CodexIdsFromText `
            -Text (Get-CodexCell -Row $Row -Column $Columns.coveredSystemRequirements) `
            -Pattern (Get-CodexIdRegex -Config $Config)

        if ([string]::IsNullOrWhiteSpace($Name)) { $Name = $Id }

        $RelativePath = "$ModuleRootRelative/$($Id.ToLowerInvariant())/requirements.md"

        if ((Get-CodexModuleIds -State $State) -contains $Id) {
            # 기존 모듈은 메타만 갱신한다. 상태와 개정은 건드리지 않는다.
            $Entry = $State.modules.$Id
            Set-CodexProperty -Object $Entry -Name "moduleName" -Value $Name
            Set-CodexProperty -Object $Entry -Name "responsibility" -Value $Responsibility
            Set-CodexProperty -Object $Entry -Name "coveredSystemRequirements" -Value @($Covered)
            continue
        }

        $NewEntry = New-CodexModuleEntry `
            -ModuleId $Id `
            -ModuleName $Name `
            -RequirementPath $RelativePath `
            -SystemRevision $NewRevision `
            -Responsibility $Responsibility `
            -CoveredSystemRequirements $Covered

        Set-CodexProperty -Object $State.modules -Name $Id -Value $NewEntry
        $Added += $Id
    }

    Add-CodexHistory -State $State -Stage "requirements-system" `
        -Detail "개정 $NewRevision / 신규 모듈 $($Added -join ',') / stale $($Stale -join ',')"

    Save-CodexState -Root $Root -Config $Config -State $State

    Write-Host ""
    Write-Host "시스템 요구사항 작성 완료" -ForegroundColor Green
    Write-Host "  문서:     $(ConvertTo-CodexRelativePath -Root $Root -Path $OutputPath)"
    Write-Host "  개정:     $NewRevision"

    if ($ModuleRows.Count -eq 0) {
        Write-Warning "모듈 분해 표를 찾지 못했습니다. '$Heading' 제목 아래 표 헤더를 확인하세요."
    }
    else {
        Write-Host "  제안 모듈: $($ModuleRows.Count) 개"
    }

    if ($Added.Count -gt 0) {
        Write-Host ""
        Write-Host "제안된 신규 모듈 (확정 대기)" -ForegroundColor Cyan

        foreach ($Id in $Added) {
            $Entry = $State.modules.$Id
            Write-Host ("  {0,-10} {1}" -f $Id, $Entry.moduleName)
        }

        Write-Host ""
        Write-Host "모듈 목록을 검토한 뒤 확정하세요." -ForegroundColor Cyan
        Write-Host "  /requirements confirm-modules"
        Write-Host "  /requirements confirm-modules AUTH,CART   (일부만 확정)"
    }

    if ($Stale.Count -gt 0) {
        Write-Host ""
        Write-Warning "다음 모듈이 stale 로 표시되었습니다: $($Stale -join ', ')"
        Write-Host "  /requirements module <모듈> 로 갱신해야 후속 단계가 열립니다."
    }

    Write-Host ""
    Write-Output "REQUIREMENT=$(ConvertTo-CodexRelativePath -Root $Root -Path $OutputPath)"
    Write-Output "REVISION=$NewRevision"
    Write-Output "PROPOSED=$($Added -join ',')"
    Write-Output "STALE=$($Stale -join ',')"
    exit 0
}

# ===============================================================
# module
# ===============================================================

$TargetId = Resolve-CodexModuleId -State $State -ModuleId $ModuleId
$Module = Get-CodexModuleState -State $State -ModuleId $TargetId

$EffectiveMode = Get-CodexMode -Config $Config -State $State -ModuleId $TargetId
Write-CodexModeBanner -Mode $EffectiveMode -Stage "requirements module" -ModuleId $TargetId

$Status = Get-CodexProperty -Object $Module -Name "status" -Default "proposed"

if ($Status -eq "proposed") {
    if ($EffectiveMode -eq "strict") {
        throw @"
모듈 '$TargetId' 이 아직 확정되지 않았습니다.

/requirements confirm-modules 로 모듈 목록을 확정한 뒤 다시 실행하세요.
"@
    }

    Write-Warning "모듈 '$TargetId' 이 미확정 상태입니다. vibe 모드이므로 계속 진행합니다."
}

if ([int]$State.system.revision -eq 0) {
    throw @"
시스템 요구사항이 아직 없습니다.

/requirements system '<전체 프로그램 요청>' 을 먼저 실행하세요.
"@
}

$RelativeRequirementPath = Get-CodexProperty -Object $Module -Name "requirementPath" `
    -Default "$($Config.paths.moduleRequirements)/$($TargetId.ToLowerInvariant())/requirements.md"

$OutputPath = Resolve-CodexPath -Root $Root -Path $RelativeRequirementPath
$Exists = Test-Path -LiteralPath $OutputPath

$Existing = if ($Exists) {
    @"
기존 모듈 요구사항 문서가 있다.

$OutputPath

기존 문서를 읽고 최신 시스템 요구사항과 요청을 반영해 문서 전체를 갱신한다.
기존 요구사항 및 인수 조건 ID 는 의미가 유지되는 한 보존한다.
"@
}
else {
    "기존 모듈 요구사항 문서는 없다. 새로 작성한다."
}

$Covered = @(Get-CodexProperty -Object $Module -Name "coveredSystemRequirements" -Default @())

$Prompt = Expand-CodexPlaceholder `
    -Template (Get-CodexPromptTemplate -Root $Root -Config $Config -FileName "requirements-module.md") `
    -Values @{
        ROOT                        = $Root
        MODULE_ID                   = $TargetId
        MODULE_UPPER                = $TargetId.ToUpperInvariant()
        MODULE_NAME                 = (Get-CodexProperty -Object $Module -Name "moduleName" -Default $TargetId)
        RESPONSIBILITY              = (Get-CodexProperty -Object $Module -Name "responsibility" -Default "(미기록)")
        COVERED_SYSTEM_REQUIREMENTS = $(if ($Covered.Count -gt 0) { $Covered -join ", " } else { "(미기록 - 시스템 요구사항에서 직접 판단한다)" })
        SYSTEM_REQUIREMENT_PATH     = (Resolve-CodexPath -Root $Root -Path $SystemRequirementPath)
        SYSTEM_REVISION             = [string]$State.system.revision
        REQUEST                     = (Get-RequestText)
        EXISTING                    = $Existing
    }

$Stage = Get-CodexStageConfig -Config $Config -Stage "requirements-module" -ModuleId $TargetId.ToLowerInvariant()

$Guard = Start-CodexGuard -Root $Root -Config $Config -Mode $EffectiveMode `
    -AllowedPaths $Stage.AllowedPaths

$Document = Invoke-CodexPrompt -Root $Root -Config $Config `
    -Prompt $Prompt -Stage "requirements-module-$($TargetId.ToLowerInvariant())"

Complete-CodexGuard -Guard $Guard

$Document = Remove-CodexCodeFence -Content $Document

Assert-CodexDocument `
    -Content $Document `
    -MinimumLength ([int]$Config.validation.minRequirementLength) `
    -RequiredMarkers @($Config.validation.requiredRequirementMarkers) `
    -RejectPath "$OutputPath.rejected"

Write-Utf8NoBomFile -Path $OutputPath -Content $Document

$Hash = Get-CodexFileHash -Path $OutputPath
$NewRevision = [int](Get-CodexProperty -Object $Module -Name "revision" -Default 0) + 1

Set-CodexProperty -Object $Module -Name "requirementPath" `
    -Value (ConvertTo-CodexRelativePath -Root $Root -Path $OutputPath)
Set-CodexProperty -Object $Module -Name "revision" -Value $NewRevision
Set-CodexProperty -Object $Module -Name "hash" -Value $Hash
Set-CodexProperty -Object $Module -Name "parentSystemRevision" -Value ([int]$State.system.revision)
Set-CodexProperty -Object $Module -Name "status" -Value "requirements_ready"
Set-CodexProperty -Object $Module -Name "stale" -Value $false
Set-CodexProperty -Object $Module -Name "staleReason" -Value $null
Set-CodexProperty -Object $Module -Name "updatedAt" -Value ((Get-Date).ToString("o"))

Set-CodexProperty -Object $State -Name "activeModuleId" -Value $TargetId

Add-CodexHistory -State $State -Stage "requirements-module" -ModuleId $TargetId `
    -Detail "개정 $NewRevision / 시스템 개정 $($State.system.revision)"

Save-CodexState -Root $Root -Config $Config -State $State

Write-Host ""
Write-Host "모듈 요구사항 작성 완료" -ForegroundColor Green
Write-Host "  모듈:     $TargetId"
Write-Host "  문서:     $(ConvertTo-CodexRelativePath -Root $Root -Path $OutputPath)"
Write-Host "  개정:     $NewRevision"
Write-Host "  시스템 개정: $($State.system.revision)"
Write-Host ""
Write-Host "다음 단계" -ForegroundColor Cyan
Write-Host "  /design-start $TargetId    제품 디자인"
Write-Host "  또는 곧바로 구현 후 /codex-test module $TargetId"
Write-Host ""

Write-Output "REQUIREMENT=$(ConvertTo-CodexRelativePath -Root $Root -Path $OutputPath)"
Write-Output "MODULE=$TargetId"
Write-Output "REVISION=$NewRevision"
