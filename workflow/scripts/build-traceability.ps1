<#
.SYNOPSIS
    요구사항과 테스트 사이의 추적성을 생성하고 검증한다. Codex 를 호출하지 않는다.

.DESCRIPTION
    세 소스를 조인한다.

      1. 시스템 요구사항 문서의 표
      2. 모듈 요구사항 문서의 표
      3. 테스트 소스에 박힌 ID + JUnit XML 실행 결과

    추적성을 LLM 이 표로 적어주는 방식은 신뢰할 수 없다. 표는 얼마든지
    그럴듯하게 채워지기 때문이다. 이 스크립트는 기계적으로 파싱해 조인한다.

    검출하는 위반

      고아 모듈 요구사항   상위 시스템 요구사항이 없음
      고아 시스템 요구사항 구현 모듈이 없음
      끊긴 참조           존재하지 않는 ID 를 참조
      미검증 인수 조건     테스트가 하나도 없음
      고아 테스트         존재하지 않는 ID 를 참조하는 테스트
      낡은 테스트         요구사항 개정 이후 수정되지 않음

    strict 모드에서는 위반이 있으면 종료 코드 1 로 실패한다.
    vibe 모드에서는 경고만 하고 0 으로 끝난다.

.PARAMETER FailOnViolation
    모드와 무관하게 위반 시 실패시킨다.

.PARAMETER Quiet
    콘솔 요약을 줄인다.

.EXAMPLE
    pwsh -NoProfile -File workflow/scripts/build-traceability.ps1
#>

[CmdletBinding()]
param(
    [switch]$FailOnViolation,
    [switch]$Quiet
)

. "$PSScriptRoot\Common.ps1"

Initialize-CodexEncoding

$Root = Get-CodexRoot
$Config = Get-CodexConfig -Root $Root
$State = Get-CodexState -Root $Root -Config $Config

$Mode = Get-CodexMode -Config $Config -State $State
$Pattern = Get-CodexIdRegex -Config $Config
$Columns = $Config.traceability.columns

$Violations = [System.Collections.Generic.List[pscustomobject]]::new()

function Add-Violation {
    param(
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][string]$Subject,
        [Parameter(Mandatory)][string]$Detail
    )

    $Violations.Add([pscustomobject]@{
        kind    = $Kind
        subject = $Subject
        detail  = $Detail
    })
}

Write-Host ""
Write-Host "추적성 생성 (모드 $Mode)" -ForegroundColor Cyan

# ===============================================================
# 1. 시스템 요구사항 파싱
# ===============================================================

$SystemRequirements = [ordered]@{}
$SystemAcceptance = [ordered]@{}

$SystemPath = Join-Path $Root ($State.system.requirementPath -replace "/", "\")

if (-not (Test-Path -LiteralPath $SystemPath)) {
    throw @"
시스템 요구사항 문서가 없습니다: $($State.system.requirementPath)

/requirements system 을 먼저 실행하세요.
"@
}

$SystemRows = Read-CodexMarkdownTables -Markdown (Read-Utf8File -Path $SystemPath)

foreach ($Row in $SystemRows) {
    $Id = (Get-CodexCell -Row $Row -Column $Columns.id).Trim().ToUpperInvariant()

    if ($Id -notmatch '^SYS-(FR|NFR|AC)-[0-9]{3}$') { continue }

    if ($Id -match '^SYS-AC-') {
        $Related = @(Get-CodexIdsFromText `
            -Text (Get-CodexCell -Row $Row -Column $Columns.relatedRequirement) -Pattern $Pattern)

        $SystemAcceptance[$Id] = [pscustomobject]@{
            id      = $Id
            related = $Related
        }
        continue
    }

    $ModuleText = Get-CodexCell -Row $Row -Column $Columns.implementedBy

    $Modules = @(
        $ModuleText -split '[,/]' |
            ForEach-Object { $_.Trim().ToUpperInvariant() } |
            Where-Object { $_ -match '^[A-Z][A-Z0-9-]*$' }
    )

    $SystemRequirements[$Id] = [pscustomobject]@{
        id              = $Id
        implementedBy   = $Modules
        modules         = @()
        acceptance      = @()
    }
}

if ($SystemRequirements.Count -eq 0) {
    Add-Violation -Kind "PARSE" -Subject "시스템 요구사항" `
        -Detail "표에서 SYS-FR / SYS-NFR 을 찾지 못했습니다. 헤더가 '$($Columns.id)' 와 '$($Columns.implementedBy)' 인지 확인하세요."
}

foreach ($Entry in $SystemAcceptance.Values) {
    foreach ($Ref in $Entry.related) {
        if ($SystemRequirements.Contains($Ref)) {
            $SystemRequirements[$Ref].acceptance += $Entry.id
        }
        else {
            Add-Violation -Kind "DANGLING_REF" -Subject $Entry.id `
                -Detail "존재하지 않는 시스템 요구사항 참조: $Ref"
        }
    }

    if ($Entry.related.Count -eq 0) {
        Add-Violation -Kind "ORPHAN_AC" -Subject $Entry.id `
            -Detail "'$($Columns.relatedRequirement)' 열이 비어 있습니다."
    }
}

# ===============================================================
# 2. 모듈 요구사항 파싱
# ===============================================================

$ModuleRequirements = [ordered]@{}
$ModuleAcceptance = [ordered]@{}
$ModuleSummaries = [System.Collections.Generic.List[pscustomobject]]::new()

$KnownModules = Get-CodexModuleIds -State $State

foreach ($Id in $KnownModules) {
    $Entry = $State.modules.$Id
    $Status = Get-CodexProperty -Object $Entry -Name "status" -Default "proposed"
    $RelativePath = Get-CodexProperty -Object $Entry -Name "requirementPath" -Default ""
    $FullPath = if ([string]::IsNullOrWhiteSpace($RelativePath)) { "" } else { Join-Path $Root ($RelativePath -replace "/", "\") }

    $Summary = [pscustomobject]@{
        moduleId        = $Id
        moduleName      = (Get-CodexProperty -Object $Entry -Name "moduleName" -Default $Id)
        status          = $Status
        stale           = (Get-CodexProperty -Object $Entry -Name "stale" -Default $false)
        revision        = (Get-CodexProperty -Object $Entry -Name "revision" -Default 0)
        requirementPath = $RelativePath
        requirementCount = 0
        acceptanceCount  = 0
    }

    $ModuleSummaries.Add($Summary)

    if ($Status -in @("proposed", "confirmed")) {
        if ($Mode -eq "strict") {
            Add-Violation -Kind "MODULE_NOT_READY" -Subject $Id `
                -Detail "상태가 $Status 입니다. 요구사항이 아직 작성되지 않았습니다."
        }
        continue
    }

    if ([string]::IsNullOrWhiteSpace($FullPath) -or -not (Test-Path -LiteralPath $FullPath)) {
        Add-Violation -Kind "MISSING_DOCUMENT" -Subject $Id `
            -Detail "요구사항 문서를 찾을 수 없습니다: $RelativePath"
        continue
    }

    $Rows = Read-CodexMarkdownTables -Markdown (Read-Utf8File -Path $FullPath)
    $Prefix = "MOD-$($Id.ToUpperInvariant())-"

    foreach ($Row in $Rows) {
        $RowId = (Get-CodexCell -Row $Row -Column $Columns.id).Trim().ToUpperInvariant()

        if (-not $RowId.StartsWith($Prefix)) { continue }
        if ($RowId -notmatch '-(FR|NFR|AC)-[0-9]{3}$') { continue }

        if ($RowId -match '-AC-[0-9]{3}$') {
            $Related = @(Get-CodexIdsFromText `
                -Text (Get-CodexCell -Row $Row -Column $Columns.relatedRequirement) -Pattern $Pattern)

            $ModuleAcceptance[$RowId] = [pscustomobject]@{
                id       = $RowId
                moduleId = $Id
                related  = $Related
            }

            $Summary.acceptanceCount++
            continue
        }

        $Parents = @(Get-CodexIdsFromText `
            -Text (Get-CodexCell -Row $Row -Column $Columns.parent) -Pattern $Pattern |
            Where-Object { $_ -match '^SYS-' })

        $ModuleRequirements[$RowId] = [pscustomobject]@{
            id         = $RowId
            moduleId   = $Id
            parents    = $Parents
            acceptance = @()
        }

        $Summary.requirementCount++

        if ($Parents.Count -eq 0) {
            Add-Violation -Kind "ORPHAN_MODULE_REQ" -Subject $RowId `
                -Detail "'$($Columns.parent)' 열에 시스템 요구사항 ID 가 없습니다."
        }

        foreach ($Parent in $Parents) {
            if ($SystemRequirements.Contains($Parent)) {
                $SystemRequirements[$Parent].modules += $RowId
            }
            else {
                Add-Violation -Kind "DANGLING_REF" -Subject $RowId `
                    -Detail "존재하지 않는 시스템 요구사항 참조: $Parent"
            }
        }
    }
}

foreach ($Entry in $ModuleAcceptance.Values) {
    foreach ($Ref in $Entry.related) {
        if ($ModuleRequirements.Contains($Ref)) {
            $ModuleRequirements[$Ref].acceptance += $Entry.id
        }
        elseif (-not $SystemRequirements.Contains($Ref)) {
            Add-Violation -Kind "DANGLING_REF" -Subject $Entry.id `
                -Detail "존재하지 않는 요구사항 참조: $Ref"
        }
    }

    if ($Entry.related.Count -eq 0) {
        Add-Violation -Kind "ORPHAN_AC" -Subject $Entry.id `
            -Detail "'$($Columns.relatedRequirement)' 열이 비어 있습니다."
    }
}

# 시스템 요구사항 쪽 역방향 검증
foreach ($Entry in $SystemRequirements.Values) {
    if ($Entry.implementedBy.Count -eq 0) {
        Add-Violation -Kind "ORPHAN_SYSTEM_REQ" -Subject $Entry.id `
            -Detail "'$($Columns.implementedBy)' 열이 비어 있습니다."
    }

    foreach ($ModuleId in $Entry.implementedBy) {
        if ($KnownModules -notcontains $ModuleId) {
            Add-Violation -Kind "DANGLING_REF" -Subject $Entry.id `
                -Detail "등록되지 않은 모듈 참조: $ModuleId"
        }
    }
}

# ===============================================================
# 3. 테스트 소스 스캔
# ===============================================================

$Tests = [System.Collections.Generic.List[pscustomobject]]::new()
$TestDirectories = @(
    Get-CodexProperty -Object $Config.traceability -Name "testSourceDirectories" -Default @()
)

foreach ($Directory in $TestDirectories) {
    $FullDirectory = Join-Path $Root ($Directory -replace "/", "\")

    if (-not (Test-Path -LiteralPath $FullDirectory)) { continue }

    $Files = @(
        Get-ChildItem -LiteralPath $FullDirectory -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Length -gt 0 -and $_.Length -lt 2MB }
    )

    foreach ($File in $Files) {
        $Text = ""

        try { $Text = Read-Utf8File -Path $File.FullName } catch { continue }

        $Ids = @(Get-CodexIdsFromText -Text $Text -Pattern $Pattern)
        $Relative = ConvertTo-CodexRelativePath -Root $Root -Path $File.FullName

        if ($Ids.Count -eq 0) {
            # 헬퍼나 픽스처 파일일 수 있으므로 위반이 아니라 정보로 둔다.
            continue
        }

        $Tier = if ($Directory -eq $Config.paths.systemTests) { "system" } else { "module" }

        $Tests.Add([pscustomobject]@{
            file         = $Relative
            tier         = $Tier
            ids          = $Ids
            lastModified = $File.LastWriteTimeUtc.ToString("o")
        })
    }
}

# 테스트가 참조하는 ID 유효성
$AllValidIds = @($SystemRequirements.Keys) + @($SystemAcceptance.Keys) +
               @($ModuleRequirements.Keys) + @($ModuleAcceptance.Keys)

$CoverageMap = @{}

foreach ($Test in $Tests) {
    foreach ($Id in $Test.ids) {
        if ($AllValidIds -notcontains $Id) {
            Add-Violation -Kind "ORPHAN_TEST" -Subject $Test.file `
                -Detail "존재하지 않는 요구사항 ID 참조: $Id"
            continue
        }

        if (-not $CoverageMap.ContainsKey($Id)) {
            $CoverageMap[$Id] = [System.Collections.Generic.List[string]]::new()
        }

        if (-not $CoverageMap[$Id].Contains($Test.file)) {
            $CoverageMap[$Id].Add($Test.file)
        }
    }
}

# ===============================================================
# 4. JUnit XML 결과 조인
# ===============================================================

$Results = @{}

function Import-JunitResults {
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) { return }

    try {
        [xml]$Xml = Get-Content -LiteralPath $Path -Raw
    }
    catch {
        Write-Warning "JUnit XML 을 읽을 수 없습니다: $Path"
        return
    }

    foreach ($Case in $Xml.SelectNodes("//testcase")) {
        $Name = "$($Case.classname) $($Case.name)"
        $Ids = @(Get-CodexIdsFromText -Text $Name -Pattern $Pattern)

        if ($Ids.Count -eq 0) { continue }

        $Status = "passed"

        if ($Case.SelectSingleNode("failure")) { $Status = "failed" }
        elseif ($Case.SelectSingleNode("error")) { $Status = "error" }
        elseif ($Case.SelectSingleNode("skipped")) { $Status = "skipped" }

        foreach ($Id in $Ids) {
            if (-not $Results.ContainsKey($Id)) {
                $Results[$Id] = [System.Collections.Generic.List[pscustomobject]]::new()
            }

            $Results[$Id].Add([pscustomobject]@{
                testName = $Case.name
                status   = $Status
            })
        }
    }
}

$JunitCandidates = @()
$JunitCandidates += (Join-Path $Root ([string]$Config.junit.systemTest -replace "/", "\"))

foreach ($Id in $KnownModules) {
    $JunitCandidates += (Join-Path $Root (([string]$Config.junit.moduleTest).Replace("{module}", $Id.ToLowerInvariant()) -replace "/", "\"))
}

foreach ($Candidate in ($JunitCandidates | Sort-Object -Unique)) {
    Import-JunitResults -Path $Candidate
}

# ===============================================================
# 5. 미검증 인수 조건
# ===============================================================

$AllAcceptance = @($SystemAcceptance.Keys) + @($ModuleAcceptance.Keys)
$Unverified = @($AllAcceptance | Where-Object { -not $CoverageMap.ContainsKey($_) })

foreach ($Id in $Unverified) {
    Add-Violation -Kind "UNVERIFIED_AC" -Subject $Id -Detail "이 인수 조건을 검증하는 테스트가 없습니다."
}

# 낡은 테스트: 요구사항 문서보다 오래된 테스트 파일
foreach ($Summary in $ModuleSummaries) {
    if ([string]::IsNullOrWhiteSpace($Summary.requirementPath)) { continue }

    $DocPath = Join-Path $Root ($Summary.requirementPath -replace "/", "\")
    if (-not (Test-Path -LiteralPath $DocPath)) { continue }

    $DocTime = (Get-Item -LiteralPath $DocPath).LastWriteTimeUtc
    $Prefix = "MOD-$($Summary.moduleId.ToUpperInvariant())-"

    $ModuleTests = @($Tests | Where-Object { @($_.ids | Where-Object { $_.StartsWith($Prefix) }).Count -gt 0 })

    foreach ($Test in $ModuleTests) {
        if ([datetime]::Parse($Test.lastModified) -lt $DocTime) {
            Add-Violation -Kind "STALE_TEST" -Subject $Test.file `
                -Detail "$($Summary.moduleId) 요구사항이 이 테스트보다 나중에 수정되었습니다."
        }
    }
}

# ===============================================================
# 6. 출력
# ===============================================================

$JsonRelative = $Config.traceability.output.json
$MarkdownRelative = $Config.traceability.output.markdown

$Data = [ordered]@{
    generatedAt    = (Get-Date).ToString("o")
    mode           = $Mode
    systemRevision = [int]$State.system.revision
    summary        = [ordered]@{
        systemRequirements = $SystemRequirements.Count
        systemAcceptance   = $SystemAcceptance.Count
        moduleRequirements = $ModuleRequirements.Count
        moduleAcceptance   = $ModuleAcceptance.Count
        modules            = $ModuleSummaries.Count
        testFiles          = $Tests.Count
        coveredAcceptance  = @($AllAcceptance | Where-Object { $CoverageMap.ContainsKey($_) }).Count
        unverifiedAcceptance = $Unverified.Count
        violations         = $Violations.Count
    }
    modules        = @($ModuleSummaries)
    systemRequirements = @(
        $SystemRequirements.Values | ForEach-Object {
            [ordered]@{
                id                 = $_.id
                implementedBy      = @($_.implementedBy)
                moduleRequirements = @($_.modules | Sort-Object -Unique)
                acceptance         = @($_.acceptance | Sort-Object -Unique)
            }
        }
    )
    moduleRequirements = @(
        $ModuleRequirements.Values | ForEach-Object {
            [ordered]@{
                id         = $_.id
                moduleId   = $_.moduleId
                parents    = @($_.parents)
                acceptance = @($_.acceptance | Sort-Object -Unique)
            }
        }
    )
    acceptance     = @(
        $AllAcceptance | Sort-Object | ForEach-Object {
            $TestFiles = if ($CoverageMap.ContainsKey($_)) { @($CoverageMap[$_]) } else { @() }
            $Runs = if ($Results.ContainsKey($_)) { @($Results[$_]) } else { @() }

            $Outcome = if ($Runs.Count -eq 0) { "not-run" }
                elseif (@($Runs | Where-Object { $_.status -in @("failed", "error") }).Count -gt 0) { "failed" }
                elseif (@($Runs | Where-Object { $_.status -eq "passed" }).Count -gt 0) { "passed" }
                else { "skipped" }

            [ordered]@{
                id        = $_
                testFiles = $TestFiles
                runs      = $Runs
                outcome   = $Outcome
            }
        }
    )
    tests          = @($Tests)
    violations     = @($Violations)
}

Write-Utf8NoBomFile `
    -Path (Join-Path $Root ($JsonRelative -replace "/", "\")) `
    -Content ($Data | ConvertTo-Json -Depth 12)

# --- Markdown ---

$Md = [System.Collections.Generic.List[string]]::new()
$Md.Add("# 요구사항 추적성")
$Md.Add("")
$Md.Add("이 파일은 build-traceability.ps1 이 생성했다. 직접 수정하지 않는다.")
$Md.Add("전체 매트릭스는 ``$JsonRelative`` 에 있다.")
$Md.Add("")
$Md.Add("| 항목 | 값 |")
$Md.Add("|---|---|")
$Md.Add("| 생성 시각 | $($Data.generatedAt) |")
$Md.Add("| 모드 | $Mode |")
$Md.Add("| 시스템 개정 | $($Data.systemRevision) |")
$Md.Add("| 시스템 요구사항 | $($Data.summary.systemRequirements) |")
$Md.Add("| 시스템 인수 조건 | $($Data.summary.systemAcceptance) |")
$Md.Add("| 모듈 | $($Data.summary.modules) |")
$Md.Add("| 모듈 요구사항 | $($Data.summary.moduleRequirements) |")
$Md.Add("| 모듈 인수 조건 | $($Data.summary.moduleAcceptance) |")
$Md.Add("| 검증된 인수 조건 | $($Data.summary.coveredAcceptance) / $($AllAcceptance.Count) |")
$Md.Add("| 위반 | $($Violations.Count) |")
$Md.Add("")

$Md.Add("## 모듈 현황")
$Md.Add("")
$Md.Add("| 모듈 | 이름 | 상태 | 개정 | 요구사항 | 인수 조건 | stale |")
$Md.Add("|---|---|---|---|---|---|---|")

foreach ($Summary in ($ModuleSummaries | Sort-Object moduleId)) {
    $StaleMark = if ($Summary.stale) { "**예**" } else { "아니오" }
    $Md.Add("| $($Summary.moduleId) | $($Summary.moduleName) | $($Summary.status) | $($Summary.revision) | $($Summary.requirementCount) | $($Summary.acceptanceCount) | $StaleMark |")
}

$Md.Add("")
$Md.Add("## 시스템 요구사항에서 모듈로")
$Md.Add("")
$Md.Add("| 시스템 요구사항 | 구현 모듈 | 모듈 요구사항 | 인수 조건 |")
$Md.Add("|---|---|---|---|")

foreach ($Entry in ($SystemRequirements.Values | Sort-Object id)) {
    $ModuleText = if ($Entry.implementedBy.Count -gt 0) { $Entry.implementedBy -join ", " } else { "**없음**" }
    $ReqText = if ($Entry.modules.Count -gt 0) { (@($Entry.modules | Sort-Object -Unique) -join ", ") } else { "-" }
    $AcText = if ($Entry.acceptance.Count -gt 0) { (@($Entry.acceptance | Sort-Object -Unique) -join ", ") } else { "-" }
    $Md.Add("| $($Entry.id) | $ModuleText | $ReqText | $AcText |")
}

$Md.Add("")
$Md.Add("## 인수 조건 검증 상태")
$Md.Add("")
$Md.Add("| 인수 조건 | 결과 | 테스트 파일 |")
$Md.Add("|---|---|---|")

foreach ($Entry in $Data.acceptance) {
    $FileText = if ($Entry.testFiles.Count -gt 0) { $Entry.testFiles -join "<br>" } else { "**없음**" }
    $Mark = switch ($Entry.outcome) {
        "passed"  { "통과" }
        "failed"  { "**실패**" }
        "skipped" { "건너뜀" }
        default   { "미실행" }
    }
    $Md.Add("| $($Entry.id) | $Mark | $FileText |")
}

if ($Violations.Count -gt 0) {
    $Md.Add("")
    $Md.Add("## 위반 목록")
    $Md.Add("")
    $Md.Add("| 종류 | 대상 | 내용 |")
    $Md.Add("|---|---|---|")

    foreach ($Violation in ($Violations | Sort-Object kind, subject)) {
        $Md.Add("| $($Violation.kind) | $($Violation.subject) | $($Violation.detail) |")
    }
}

$Md.Add("")

Write-Utf8NoBomFile `
    -Path (Join-Path $Root ($MarkdownRelative -replace "/", "\")) `
    -Content ($Md -join "`n")

# ===============================================================
# 7. 콘솔 요약과 판정
# ===============================================================

if (-not $Quiet) {
    Write-Host ""
    Write-Host "요약" -ForegroundColor Cyan
    Write-Host "  시스템 요구사항  $($Data.summary.systemRequirements)"
    Write-Host "  모듈             $($Data.summary.modules)"
    Write-Host "  모듈 요구사항    $($Data.summary.moduleRequirements)"
    Write-Host "  인수 조건        $($AllAcceptance.Count) (검증됨 $($Data.summary.coveredAcceptance))"
    Write-Host "  테스트 파일      $($Tests.Count)"
    Write-Host ""
    Write-Host "  $MarkdownRelative"
    Write-Host "  $JsonRelative"
}

if ($Violations.Count -eq 0) {
    Write-Host ""
    Write-Host "위반 없음" -ForegroundColor Green
    Write-Host ""
    Write-Output "VIOLATIONS=0"
    exit 0
}

$Grouped = $Violations | Group-Object kind | Sort-Object Name

Write-Host ""
Write-Host "위반 $($Violations.Count) 건" -ForegroundColor Yellow

foreach ($Group in $Grouped) {
    Write-Host ("  {0,-20} {1} 건" -f $Group.Name, $Group.Count)

    foreach ($Item in ($Group.Group | Select-Object -First 5)) {
        Write-Host "      $($Item.subject): $($Item.detail)"
    }

    if ($Group.Count -gt 5) {
        Write-Host "      ... 나머지 $($Group.Count - 5) 건은 $MarkdownRelative 참조"
    }
}

Write-Host ""
Write-Output "VIOLATIONS=$($Violations.Count)"

if ($FailOnViolation -or $Mode -eq "strict") {
    Write-Host "strict 모드: 위반이 있어 실패로 처리합니다." -ForegroundColor Red
    Write-Host ""
    exit 1
}

Write-Host "vibe 모드: 경고로만 처리합니다." -ForegroundColor Yellow
Write-Host ""
exit 0
