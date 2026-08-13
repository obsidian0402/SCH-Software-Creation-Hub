<#
    Codex 워크플로 공용 함수.

    이 파일은 각 invoke-*.ps1 에서 dot-source 한다.

        . "$PSScriptRoot\Common.ps1"

    설계 원칙

    1. Codex 에게는 전권을 준다. 능력을 제한하지 않는다.
    2. 경계는 실행 후 git 기반 가드로 강제한다. (1겹)
    3. Claude 소유 트리는 해시 스냅샷으로 별도 검증한다. (2겹)
       gitignore 사각지대까지 잡기 위한 장치다.
    4. 한글은 프로세스 경계를 넘기지 않는다.
       프롬프트 전문은 UTF-8 파일로 쓰고 stdin 으로는 ASCII 한 줄만 보낸다.
#>

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"

# ===============================================================
# 인코딩
# ===============================================================

function Initialize-CodexEncoding {
    <#
        콘솔 핸들이 리다이렉트된 환경(Claude Code 가 pwsh 를 자동 실행하는 경우)
        에서는 [Console]::InputEncoding 대입이 IOException 을 던진다.
        ErrorActionPreference 가 Stop 이면 스크립트 전체가 죽으므로 개별 방어한다.
    #>

    $Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

    try { [Console]::OutputEncoding = $Utf8NoBom } catch { }
    try { [Console]::InputEncoding = $Utf8NoBom } catch { }

    # 네이티브 명령으로 파이프해 넣을 때 사용되는 값이므로 전역이어야 한다.
    $global:OutputEncoding = $Utf8NoBom
}

# ===============================================================
# 경로 및 파일
# ===============================================================

function Get-CodexRoot {
    <# workflow/scripts 의 두 단계 위가 프로젝트 루트다. #>
    return (Resolve-Path (Join-Path $PSScriptRoot ".." "..")).Path
}

function Get-CodexPropertyNames {
    <#
        객체의 속성 이름 목록을 안전하게 돌려준다.

        StrictMode 3.0 에서는 비어 있는 컬렉션에 멤버 열거를 하면
        "The property 'Name' cannot be found on this object." 예외가 난다.
        즉 $Object.PSObject.Properties.Name 은 속성이 하나도 없는 객체에서 실패한다.

        state.json 의 modules 는 첫 실행에서 {} 이므로 반드시 이 함수를 거친다.
    #>
    param(
        [Parameter(Mandatory)][AllowNull()]$Object
    )

    if ($null -eq $Object) {
        return ,@()
    }

    # 쉼표 연산자로 감싸지 않으면 PowerShell 이 반환 배열을 펼쳐서 내보낸다.
    # 원소가 0 개면 아무것도 출력되지 않아 호출부 변수가 $null 이 되고,
    # StrictMode 3.0 에서 이후 .Count 접근이 예외를 던진다.
    return ,@($Object.PSObject.Properties | ForEach-Object { $_.Name })
}

function Get-CodexProperty {
    <#
        StrictMode 3.0 에서는 없는 속성에 접근하면 예외가 난다.
        상태 파일은 스키마가 점진적으로 늘어나므로 안전한 조회가 필요하다.
    #>
    param(
        [Parameter(Mandatory)][AllowNull()]$Object,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    if ((Get-CodexPropertyNames -Object $Object) -notcontains $Name) {
        return $Default
    }

    $Value = $Object.$Name

    if ($null -eq $Value) {
        return $Default
    }

    return $Value
}

function Set-CodexProperty {
    <#
        PSCustomObject 는 존재하지 않는 속성에 대입할 수 없다.
        ConvertFrom-Json 결과에 새 필드를 추가할 때 반드시 필요하다.
    #>
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()]$Value
    )

    if ((Get-CodexPropertyNames -Object $Object) -contains $Name) {
        $Object.$Name = $Value
    }
    else {
        Add-Member -InputObject $Object -NotePropertyName $Name -NotePropertyValue $Value -Force
    }
}

function Write-Utf8NoBomFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )

    $ParentDirectory = Split-Path -Parent $Path

    if (-not [string]::IsNullOrWhiteSpace($ParentDirectory)) {
        if (-not (Test-Path -LiteralPath $ParentDirectory)) {
            New-Item -ItemType Directory -Path $ParentDirectory -Force | Out-Null
        }
    }

    [System.IO.File]::WriteAllText(
        $Path,
        $Content,
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Read-Utf8File {
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "파일을 찾을 수 없습니다: $Path"
    }

    return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
}

function ConvertTo-CodexRelativePath {
    <# 항상 슬래시로 정규화해 스크립트 간 출력 형식을 통일한다. #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path
    )

    return ([System.IO.Path]::GetRelativePath($Root, $Path)).Replace("\", "/")
}

function Resolve-CodexPath {
    <#
        상대 경로를 프로젝트 루트 기준으로 해석하고
        결과가 루트 밖으로 나가지 않는지 검증한다.
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path,
        [switch]$MustExist
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        $Candidate = $Path
    }
    else {
        $Candidate = Join-Path $Root $Path
    }

    $Full = [System.IO.Path]::GetFullPath($Candidate)
    $RootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd([System.IO.Path]::DirectorySeparatorChar)

    $IsInside = (
        $Full -eq $RootFull -or
        $Full.StartsWith($RootFull + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
    )

    if (-not $IsInside) {
        throw "프로젝트 루트 밖의 경로는 사용할 수 없습니다: $Path"
    }

    if ($MustExist -and -not (Test-Path -LiteralPath $Full)) {
        throw "경로를 찾을 수 없습니다: $Full"
    }

    return $Full
}

# ===============================================================
# 설정
# ===============================================================

function Get-CodexConfig {
    param(
        [Parameter(Mandatory)][string]$Root
    )

    $ConfigPath = Join-Path $Root "workflow\config.json"

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "설정 파일이 없습니다: $ConfigPath`n`nworkflow/scripts/init-workspace.ps1 을 먼저 실행하세요."
    }

    return (Read-Utf8File -Path $ConfigPath | ConvertFrom-Json)
}

function Test-CodexPlaceholder {
    param(
        [AllowEmptyString()][string]$Value = ""
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $true
    }

    return $Value.StartsWith("REPLACE_WITH_")
}

function Assert-CodexCommand {
    <#
        테스트 명령이 플레이스홀더로 남아 있는지 확인한다.
        acceptance 에만 있던 검사를 모든 단계로 통일한다.
    #>
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][ValidateSet("unitTest", "moduleTest", "systemTest")][string]$Kind
    )

    $Value = $Config.commands.$Kind

    if (Test-CodexPlaceholder -Value $Value) {
        throw @"
workflow/config.json 의 commands.$Kind 가 설정되지 않았습니다.

현재 값: $Value

workflow/scripts/init-workspace.ps1 을 실행해 스택 프리셋을 적용하거나
config.json 을 직접 수정하세요.
"@
    }

    return $Value
}

function Expand-CodexToken {
    <#
        config.json 안의 {paths} 토큰과 {module} 을 실제 값으로 치환한다.

        예)  "{moduleTests}/{module}"  ->  "tests/module/auth"
             "MOD-{MODULE}-AC"         ->  "MOD-AUTH-AC"
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Template,
        [Parameter(Mandatory)][object]$Config,
        [string]$ModuleId
    )

    $Result = $Template

    foreach ($Property in $Config.paths.PSObject.Properties) {
        if ($Property.Value -is [string]) {
            $Result = $Result.Replace("{$($Property.Name)}", $Property.Value)
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($ModuleId)) {
        $Result = $Result.Replace("{module}", $ModuleId.ToLowerInvariant())
        $Result = $Result.Replace("{MODULE}", $ModuleId.ToUpperInvariant())
    }

    return $Result
}

function Get-CodexStageConfig {
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][string]$Stage,
        [string]$ModuleId
    )

    $StageNames = $Config.stages.PSObject.Properties.Name

    if ($StageNames -notcontains $Stage) {
        throw "config.json 에 정의되지 않은 단계입니다: $Stage`n사용 가능: $($StageNames -join ', ')"
    }

    $Raw = $Config.stages.$Stage

    $Allow = @(
        $Raw.allow | ForEach-Object {
            Expand-CodexToken -Template $_ -Config $Config -ModuleId $ModuleId
        }
    )

    $ReportDirectory = $null

    if ($Raw.reportDirectory) {
        $ReportDirectory = Expand-CodexToken `
            -Template $Raw.reportDirectory -Config $Config -ModuleId $ModuleId
    }

    return [pscustomobject]@{
        Stage           = $Stage
        AllowedPaths    = $Allow
        ReportDirectory = $ReportDirectory
        PromptFile      = $Raw.prompt
    }
}

# ===============================================================
# 상태 파일
# ===============================================================

function Get-CodexState {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][object]$Config
    )

    $StatePath = Join-Path $Root ($Config.paths.state -replace "/", "\")

    if (-not (Test-Path -LiteralPath $StatePath)) {
        throw "상태 파일이 없습니다: $StatePath"
    }

    return (Read-Utf8File -Path $StatePath | ConvertFrom-Json)
}

function Save-CodexState {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$State
    )

    $StatePath = Join-Path $Root ($Config.paths.state -replace "/", "\")

    Write-Utf8NoBomFile `
        -Path $StatePath `
        -Content ($State | ConvertTo-Json -Depth 12)
}

function Get-CodexModuleState {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][string]$ModuleId
    )

    $Names = Get-CodexPropertyNames -Object $State.modules

    if ($Names -notcontains $ModuleId) {
        throw @"
상태 파일에 모듈이 없습니다: $ModuleId

등록된 모듈: $(if ($Names.Count -gt 0) { $Names -join ', ' } else { '(없음)' })

/requirements system 으로 모듈을 분해한 뒤
/requirements confirm-modules 로 확정하세요.
"@
    }

    return $State.modules.$ModuleId
}

function Get-CodexFileHash {
    param(
        [Parameter(Mandatory)][string]$Path
    )

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Assert-CodexModuleFresh {
    <#
        모듈 요구사항이 상위 시스템 요구사항 개정보다 뒤처졌는지 확인한다.
        요구 2번의 "서로에게 업데이트" 를 기계적으로 강제하는 지점이다.
    #>
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][string]$ModuleId
    )

    $Module = Get-CodexModuleState -State $State -ModuleId $ModuleId

    $Status = Get-CodexProperty -Object $Module -Name "status" -Default "unknown"

    if ($Status -eq "proposed") {
        throw @"
모듈 '$ModuleId' 은 아직 제안 상태입니다.

Codex 가 분해한 모듈 목록을 확인하고
/requirements confirm-modules 로 확정한 뒤 다시 실행하세요.
"@
    }

    $IsStale = Get-CodexProperty -Object $Module -Name "stale" -Default $false

    if ($IsStale -eq $true) {
        $Reason = Get-CodexProperty -Object $Module -Name "staleReason" -Default "(미기록)"
        $ParentRevision = Get-CodexProperty -Object $Module -Name "parentSystemRevision" -Default 0

        throw @"
모듈 '$ModuleId' 의 요구사항이 낡았습니다.

이유: $Reason

모듈 요구사항 기준 시스템 개정: $ParentRevision
현재 시스템 개정:                $($State.system.revision)

/requirements module $ModuleId 로 모듈 요구사항을 먼저 갱신하세요.
"@
    }
}

function Set-CodexModuleStale {
    <#
        시스템 요구사항이 바뀌면 이를 참조하는 모듈 전체를 stale 로 표시한다.
    #>
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][string]$Reason
    )

    $CurrentRevision = [int]$State.system.revision
    $Affected = @()

    foreach ($Property in $State.modules.PSObject.Properties) {
        $Module = $Property.Value

        $ParentRevision = [int](
            Get-CodexProperty -Object $Module -Name "parentSystemRevision" -Default 0
        )

        if ($ParentRevision -ne $CurrentRevision) {
            Set-CodexProperty -Object $Module -Name "stale" -Value $true
            Set-CodexProperty -Object $Module -Name "staleReason" -Value $Reason
            $Affected += $Property.Name
        }
    }

    return $Affected
}

# ===============================================================
# Codex 실행
# ===============================================================

function Resolve-CodexInvoker {
    <#
        codex 는 npm 전역 설치 시 codex.cmd / codex.ps1 / 확장자 없는 셔임으로 잡힌다.

        Start-Process 에 출력 리다이렉션을 주면 UseShellExecute=false 로
        CreateProcess 를 직접 호출하므로 셔임을 실행할 수 없다.
        (%1은(는) 올바른 Win32 응용 프로그램이 아닙니다)

        따라서 항상 "진짜 실행 파일" 을 FileName 으로 넘기고
        셔임은 인자로 전달한다.

            .exe        -> 그대로
            .ps1        -> pwsh -NoProfile -File <셔임>
            .cmd/.bat   -> cmd.exe /d /s /c <셔임>
    #>
    param(
        [string]$Prefer = ".ps1"
    )

    $Candidates = @(Get-Command codex -All -ErrorAction SilentlyContinue |
        Where-Object { $_.Source })

    if ($Candidates.Count -eq 0) {
        throw "codex CLI 를 찾을 수 없습니다. PATH 를 확인하세요."
    }

    function Select-ByExtension {
        param([object[]]$Items, [string]$Extension)

        return ($Items |
            Where-Object { [System.IO.Path]::GetExtension($_.Source) -ieq $Extension } |
            Select-Object -First 1)
    }

    # .exe 가 있으면 최우선. 없으면 선호 셔임, 그 다음 나머지.
    $Order = @(".exe", $Prefer, ".ps1", ".cmd", ".bat") | Select-Object -Unique
    $Chosen = $null

    foreach ($Extension in $Order) {
        $Chosen = Select-ByExtension -Items $Candidates -Extension $Extension
        if ($Chosen) { break }
    }

    if (-not $Chosen) {
        throw @"
실행 가능한 codex 형태를 찾지 못했습니다.

발견된 항목:
$(($Candidates | ForEach-Object { "  $($_.Source)" }) -join "`n")
"@
    }

    $ShimPath = $Chosen.Source
    $Extension = [System.IO.Path]::GetExtension($ShimPath)

    switch ($Extension.ToLowerInvariant()) {
        ".exe" {
            return [pscustomobject]@{
                FileName   = $ShimPath
                PrefixArgs = @()
                Kind       = "exe"
                ShimPath   = $ShimPath
            }
        }
        ".ps1" {
            $Pwsh = Get-Command pwsh -ErrorAction SilentlyContinue

            if (-not $Pwsh) {
                throw "codex.ps1 을 실행할 pwsh 를 찾을 수 없습니다."
            }

            return [pscustomobject]@{
                FileName   = $Pwsh.Source
                PrefixArgs = @("-NoProfile", "-File", $ShimPath)
                Kind       = "ps1"
                ShimPath   = $ShimPath
            }
        }
        default {
            return [pscustomobject]@{
                FileName   = $env:ComSpec
                PrefixArgs = @("/d", "/s", "/c", $ShimPath)
                Kind       = "cmd"
                ShimPath   = $ShimPath
            }
        }
    }
}

function Invoke-CodexPrompt {
    <#
        Codex 를 실행하고 최종 응답 본문을 반환한다.

        한글 인코딩 대책
          프롬프트 전문을 UTF-8 no BOM 파일로 쓰고
          stdin 으로는 ASCII 한 줄만 보낸다.
          한글이 argv 나 파이프를 통과하지 않으므로
          cmd.exe 경유나 PATHEXT 선택과 무관하게 안전하다.

        진단 대책
          stderr 를 파일로 남기고, 실패 시 프롬프트 파일을 보존한다.
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string]$Stage,
        [string]$Sandbox
    )

    if ([string]::IsNullOrWhiteSpace($Sandbox)) {
        $Sandbox = $Config.codex.sandbox
    }

    $TempDirectory = Join-Path $Root ($Config.paths.temp -replace "/", "\")
    New-Item -ItemType Directory -Path $TempDirectory -Force | Out-Null

    $Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $Slug = "$Stage-$Stamp"

    $PromptFile  = Join-Path $TempDirectory "prompt-$Slug.md"
    $StdInFile   = Join-Path $TempDirectory "stdin-$Slug.txt"
    $StdOutFile  = Join-Path $TempDirectory "stdout-$Slug.log"
    $StdErrFile  = Join-Path $TempDirectory "stderr-$Slug.log"
    $MessageFile = Join-Path $TempDirectory "lastmessage-$Slug.md"

    Write-Utf8NoBomFile -Path $PromptFile -Content $Prompt

    # stdin 은 순수 ASCII 만 담는다.
    $StdInLine = "Read the file $PromptFile and follow every instruction in it exactly."
    Write-Utf8NoBomFile -Path $StdInFile -Content $StdInLine

    $Invoker = Resolve-CodexInvoker -Prefer $Config.codex.preferShim

    $CodexArgs = @(
        "--cd", $Root
        "--sandbox", $Sandbox
        "--ask-for-approval", $Config.codex.askForApproval
        "exec"
        "--ephemeral"
        "--output-last-message", $MessageFile
        "-"
    )

    Write-Host "codex 실행 ($Stage / sandbox=$Sandbox)" -ForegroundColor Cyan
    Write-Host "  프롬프트: $PromptFile"
    Write-Host "  방식:     $($Invoker.Kind) -> $($Invoker.ShimPath)"

    $TimeoutSeconds = [int]$Config.codex.timeoutSeconds
    $Succeeded = $false

    try {
        $Process = Start-Process `
            -FilePath $Invoker.FileName `
            -ArgumentList ($Invoker.PrefixArgs + $CodexArgs) `
            -WorkingDirectory $Root `
            -NoNewWindow `
            -PassThru `
            -RedirectStandardInput $StdInFile `
            -RedirectStandardOutput $StdOutFile `
            -RedirectStandardError $StdErrFile

        if (-not $Process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $Process.Kill($true) } catch { }

            throw @"
codex 실행이 시간을 초과했습니다. ($TimeoutSeconds 초)

프롬프트: $PromptFile
표준출력: $StdOutFile
표준오류: $StdErrFile

config.json 의 codex.timeoutSeconds 를 늘리거나
작업 범위를 모듈 단위로 줄이세요.
"@
        }

        $ExitCode = $Process.ExitCode

        if ($ExitCode -ne 0) {
            $ErrorText = ""

            if (Test-Path -LiteralPath $StdErrFile) {
                $Raw = (Get-Content -LiteralPath $StdErrFile -Raw -ErrorAction SilentlyContinue)

                if (-not [string]::IsNullOrWhiteSpace($Raw)) {
                    $ErrorText = ($Raw -split "`r?`n" | Select-Object -Last 30) -join "`n"
                }
            }

            throw @"
codex 실행이 실패했습니다. 종료 코드: $ExitCode

프롬프트: $PromptFile
표준출력: $StdOutFile
표준오류: $StdErrFile

--- 표준오류 마지막 30줄 ---
$ErrorText
"@
        }

        if (-not (Test-Path -LiteralPath $MessageFile)) {
            throw @"
codex 최종 응답 파일이 생성되지 않았습니다.

프롬프트: $PromptFile
표준출력: $StdOutFile
표준오류: $StdErrFile
"@
        }

        $Message = Read-Utf8File -Path $MessageFile
        $Succeeded = $true

        return $Message
    }
    finally {
        if ($Succeeded) {
            # 성공 시에는 임시 파일을 정리한다.
            foreach ($Path in @($PromptFile, $StdInFile, $StdOutFile, $StdErrFile, $MessageFile)) {
                if (Test-Path -LiteralPath $Path) {
                    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
                }
            }
        }
        else {
            Write-Warning "진단을 위해 임시 파일을 보존했습니다: $TempDirectory"
        }
    }
}

# ===============================================================
# 응답 검증
# ===============================================================

function Assert-CodexDocument {
    <#
        Codex 응답을 파일에 쓰기 전에 검증한다.

        검증 없이 덮어쓰면 빈 응답이나 거부 메시지가
        기존 요구사항 문서를 파괴한다. 복구 수단이 없다.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
        [Parameter(Mandatory)][int]$MinimumLength,
        [string[]]$RequiredMarkers = @(),
        [Parameter(Mandatory)][string]$RejectPath
    )

    $Problems = @()

    if ([string]::IsNullOrWhiteSpace($Content)) {
        $Problems += "응답이 비어 있습니다."
    }
    elseif ($Content.Length -lt $MinimumLength) {
        $Problems += "응답이 너무 짧습니다. ($($Content.Length) < $MinimumLength 자)"
    }

    foreach ($Marker in $RequiredMarkers) {
        if ($Content -notlike "*$Marker*") {
            $Problems += "필수 구간이 없습니다: $Marker"
        }
    }

    if ($Problems.Count -eq 0) {
        return
    }

    Write-Utf8NoBomFile -Path $RejectPath -Content $Content

    throw @"
Codex 응답이 검증을 통과하지 못했습니다.
기존 파일은 덮어쓰지 않았습니다.

$($Problems -join "`n")

응답 원문: $RejectPath
"@
}

function Remove-CodexCodeFence {
    <# Codex 가 문서 전체를 코드 펜스로 감싸는 경우를 벗긴다. #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )

    $Trimmed = $Content.Trim()

    if ($Trimmed -match '^```[a-zA-Z]*\r?\n([\s\S]*?)\r?\n```$') {
        return $Matches[1]
    }

    return $Content
}

# ===============================================================
# 가드 1겹 : git 경로 허용 목록
# ===============================================================

function Assert-ExternalCommand {
    param(
        [Parameter(Mandatory)][string]$Name
    )

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "필요한 명령을 찾을 수 없습니다: $Name"
    }
}

function Assert-CleanGitWorkingTree {
    param(
        [Parameter(Mandatory)][string]$Root
    )

    Assert-ExternalCommand -Name "git"

    $Status = @(git -C $Root status --porcelain=v1 --untracked-files=all)

    if ($LASTEXITCODE -ne 0) {
        throw "git 작업 상태를 확인할 수 없습니다."
    }

    if ($Status.Count -eq 0) {
        return
    }

    throw @"
Codex 단계를 실행하기 전에 git 작업 트리가 깨끗해야 합니다.
가드가 "실행 전 상태" 를 기준으로 침범을 판정하기 때문입니다.

현재 변경 ($($Status.Count) 건):

$($Status -join "`n")

아래 명령으로 체크포인트를 만든 뒤 다시 실행하세요.

    git add -A; git commit -m "checkpoint: codex 단계 실행 전"
"@
}

function Convert-ToGitPath {
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $Normalized = $Path.Replace("\", "/")

    if ($Normalized.StartsWith("./")) {
        $Normalized = $Normalized.Substring(2)
    }

    return $Normalized.TrimEnd("/")
}

function Test-IsAllowedChangedPath {
    param(
        [Parameter(Mandatory)][string]$ChangedPath,
        [Parameter(Mandatory)][string[]]$AllowedPaths
    )

    $Changed = Convert-ToGitPath $ChangedPath

    foreach ($Allowed in $AllowedPaths) {
        $Normalized = Convert-ToGitPath $Allowed

        if ($Changed -eq $Normalized) { return $true }
        if ($Changed.StartsWith("$Normalized/")) { return $true }
    }

    return $false
}

function Get-GitChangedPaths {
    param(
        [Parameter(Mandatory)][string]$Root
    )

    $Tracked   = @(git -C $Root -c core.quotepath=false diff --name-only)
    $Staged    = @(git -C $Root -c core.quotepath=false diff --cached --name-only)
    $Untracked = @(git -C $Root -c core.quotepath=false ls-files --others --exclude-standard)

    return @($Tracked + $Staged + $Untracked) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object -Unique
}

function Test-IsPathInHead {
    <#
        HEAD 에 존재하는 경로인지 확인한다.

        기존 구현은 git ls-files --error-unmatch 를 썼는데
        이는 "인덱스에 있는가" 를 본다. Codex 가 새 파일을 git add 하면
        인덱스에는 있고 HEAD 에는 없어서 git restore --source=HEAD 가
        하드 실패하고 작업 트리가 더러운 채로 남았다.
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$RelativePath
    )

    git -C $Root cat-file -e "HEAD:$RelativePath" 2>$null

    return ($LASTEXITCODE -eq 0)
}

function Restore-UnauthorizedGitChanges {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string[]]$UnauthorizedPaths
    )

    $Failed = @()

    foreach ($RelativePath in $UnauthorizedPaths) {
        if (Test-IsPathInHead -Root $Root -RelativePath $RelativePath) {
            git -C $Root restore --source=HEAD --staged --worktree -- $RelativePath

            if ($LASTEXITCODE -ne 0) {
                $Failed += $RelativePath
            }
        }
        else {
            # HEAD 에 없는 새 파일. 인덱스에서 빼고 삭제한다.
            git -C $Root rm --cached --quiet --ignore-unmatch -- $RelativePath 2>$null | Out-Null

            $FullPath = Join-Path $Root $RelativePath

            if (Test-Path -LiteralPath $FullPath) {
                Remove-Item -LiteralPath $FullPath -Recurse -Force -ErrorAction SilentlyContinue
            }

            if (Test-Path -LiteralPath $FullPath) {
                $Failed += $RelativePath
            }
        }
    }

    if ($Failed.Count -gt 0) {
        throw @"
일부 파일을 복원하지 못했습니다. 수동 확인이 필요합니다.

$($Failed -join "`n")

    git status
    git restore --source=HEAD --staged --worktree -- <경로>
"@
    }
}

function Assert-OnlyAllowedPathsChanged {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string[]]$AllowedPaths
    )

    $Changed = @(Get-GitChangedPaths -Root $Root)

    $Unauthorized = @(
        $Changed | Where-Object {
            -not (Test-IsAllowedChangedPath -ChangedPath $_ -AllowedPaths $AllowedPaths)
        }
    )

    if ($Unauthorized.Count -eq 0) {
        return
    }

    Restore-UnauthorizedGitChanges -Root $Root -UnauthorizedPaths $Unauthorized

    throw @"
Codex 가 허용되지 않은 경로를 수정했습니다.

허용 경로:
$(($AllowedPaths | ForEach-Object { "  $_" }) -join "`n")

복원한 변경:
$(($Unauthorized | ForEach-Object { "  $_" }) -join "`n")

이번 실행 결과는 무효입니다.
"@
}

# ===============================================================
# 가드 2겹 : 보호 트리 해시 스냅샷
# ===============================================================

function Get-CodexTreeSnapshot {
    <#
        Claude 소유 트리의 파일별 해시를 기록한다.

        1겹 가드는 git ls-files --exclude-standard 를 쓰므로
        gitignore 된 파일의 변경을 보지 못한다.
        이 스냅샷은 git 을 거치지 않으므로 그 사각지대를 덮는다.
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string[]]$Trees
    )

    $Snapshot = @{}

    foreach ($Tree in $Trees) {
        $TreePath = Join-Path $Root ($Tree -replace "/", "\")

        if (-not (Test-Path -LiteralPath $TreePath)) {
            continue
        }

        $Files = @(Get-ChildItem -LiteralPath $TreePath -Recurse -File -Force -ErrorAction SilentlyContinue)

        foreach ($File in $Files) {
            $Key = ConvertTo-CodexRelativePath -Root $Root -Path $File.FullName
            $Snapshot[$Key] = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash
        }
    }

    return $Snapshot
}

function Assert-ProtectedTreesUnchanged {
    param(
        [Parameter(Mandatory)][hashtable]$Before,
        [Parameter(Mandatory)][hashtable]$After,
        [Parameter(Mandatory)][string[]]$Trees
    )

    $Added    = @($After.Keys  | Where-Object { -not $Before.ContainsKey($_) })
    $Removed  = @($Before.Keys | Where-Object { -not $After.ContainsKey($_) })
    $Modified = @(
        $Before.Keys |
            Where-Object { $After.ContainsKey($_) } |
            Where-Object { $Before[$_] -ne $After[$_] }
    )

    if ($Added.Count -eq 0 -and $Removed.Count -eq 0 -and $Modified.Count -eq 0) {
        return
    }

    $Lines = @()

    if ($Added.Count -gt 0)    { $Lines += "추가:";   $Lines += ($Added    | ForEach-Object { "  $_" }) }
    if ($Removed.Count -gt 0)  { $Lines += "삭제:";   $Lines += ($Removed  | ForEach-Object { "  $_" }) }
    if ($Modified.Count -gt 0) { $Lines += "수정:";   $Lines += ($Modified | ForEach-Object { "  $_" }) }

    throw @"
Codex 가 Claude 소유 보호 트리를 변경했습니다.

보호 트리: $($Trees -join ', ')

$($Lines -join "`n")

이번 실행 결과는 무효입니다.
수동으로 되돌리세요.

    git status
    git restore --source=HEAD --staged --worktree -- <경로>
"@
}

# ===============================================================
# 보고서 경로
# ===============================================================

function New-CodexReportPath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string]$BaseName
    )

    $Full = Join-Path $Root ($Directory -replace "/", "\")

    New-Item -ItemType Directory -Path $Full -Force | Out-Null

    $Stamp = Get-Date -Format "yyyyMMdd-HHmmss"

    return (Join-Path $Full "$BaseName-$Stamp.md")
}

function Get-CodexPromptTemplate {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][string]$FileName
    )

    $Path = Join-Path $Root ($Config.paths.prompts -replace "/", "\") $FileName

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "프롬프트 템플릿이 없습니다: $Path"
    }

    return (Read-Utf8File -Path $Path)
}

function Expand-CodexPlaceholder {
    <#
        프롬프트 템플릿의 {{KEY}} 를 치환한다.
        치환되지 않은 자리표시자가 남으면 오류로 처리한다.
    #>
    param(
        [Parameter(Mandatory)][string]$Template,
        [Parameter(Mandatory)][hashtable]$Values
    )

    $Result = $Template

    foreach ($Key in $Values.Keys) {
        $Replacement = if ($null -eq $Values[$Key]) { "" } else { [string]$Values[$Key] }
        $Result = $Result.Replace("{{$Key}}", $Replacement)
    }

    $Leftover = [regex]::Matches($Result, '\{\{[A-Z_]+\}\}')

    if ($Leftover.Count -gt 0) {
        $Names = ($Leftover | ForEach-Object { $_.Value } | Sort-Object -Unique) -join ", "
        throw "프롬프트 자리표시자가 치환되지 않았습니다: $Names"
    }

    return $Result
}

# ===============================================================
# 모드 (vibe / strict)
# ===============================================================

function Get-CodexMode {
    <#
        모듈별 설정이 있으면 그것을, 없으면 프로젝트 기본값을 쓴다.
    #>
    param(
        [Parameter(Mandatory)][object]$Config,
        [object]$State,
        [string]$ModuleId
    )

    $Mode = Get-CodexProperty -Object $Config -Name "mode" -Default "strict"

    if ($State -and -not [string]::IsNullOrWhiteSpace($ModuleId)) {
        $Names = Get-CodexPropertyNames -Object $State.modules

        if ($Names -contains $ModuleId) {
            $Override = Get-CodexProperty -Object $State.modules.$ModuleId -Name "mode" -Default $null

            if (-not [string]::IsNullOrWhiteSpace($Override)) {
                $Mode = $Override
            }
        }
    }

    if ($Mode -notin @("vibe", "strict")) {
        throw "알 수 없는 모드입니다: $Mode (vibe 또는 strict)"
    }

    return $Mode
}

function Write-CodexModeBanner {
    param(
        [Parameter(Mandatory)][string]$Mode,
        [Parameter(Mandatory)][string]$Stage,
        [string]$ModuleId
    )

    $Target = if ([string]::IsNullOrWhiteSpace($ModuleId)) { "(시스템)" } else { $ModuleId }
    $Color = if ($Mode -eq "strict") { "Cyan" } else { "Yellow" }

    Write-Host ""
    Write-Host "[$Stage] 대상 $Target / 모드 $Mode" -ForegroundColor $Color

    if ($Mode -eq "vibe") {
        Write-Host "  vibe 모드: 깨끗한 git 트리와 경로 허용 목록 가드를 생략합니다." -ForegroundColor Yellow
        Write-Host "  보호 트리(src, tests/unit) 해시 가드는 계속 동작합니다." -ForegroundColor Yellow
    }
}

# ===============================================================
# 가드 컨텍스트
# ===============================================================

function Start-CodexGuard {
    <#
        Codex 실행 전 가드를 준비한다.

        중요
          경로 허용 목록 가드는 "실행 전 트리가 깨끗함" 을 전제로 한다.
          더러운 트리에서 돌리면 사용자의 기존 작업을 Codex 변경으로 오인해
          자동 삭제한다. 그래서 두 검사를 하나의 컨텍스트로 묶어
          스크립트가 따로 호출할 수 없게 만든다.
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][string]$Mode,
        [Parameter(Mandatory)][string[]]$AllowedPaths
    )

    $UsePathGuard = ($Mode -eq "strict") -and
                    (Get-CodexProperty -Object $Config.guards -Name "requireCleanGitTree" -Default $true)

    if ($UsePathGuard) {
        Assert-CleanGitWorkingTree -Root $Root
    }

    $ProtectedTrees = @(
        Get-CodexProperty -Object $Config.guards -Name "protectedTrees" -Default @()
    )

    $Snapshot = @{}

    if ($ProtectedTrees.Count -gt 0) {
        $Snapshot = Get-CodexTreeSnapshot -Root $Root -Trees $ProtectedTrees
    }

    return [pscustomobject]@{
        Root           = $Root
        Mode           = $Mode
        UsePathGuard   = $UsePathGuard
        AllowedPaths   = $AllowedPaths
        ProtectedTrees = $ProtectedTrees
        Snapshot       = $Snapshot
    }
}

function Complete-CodexGuard {
    <# Codex 실행 후 소유권을 검증한다. #>
    param(
        [Parameter(Mandatory)][object]$Guard
    )

    # 2겹: 보호 트리 해시. git 과 무관하므로 두 모드 모두에서 동작한다.
    if ($Guard.ProtectedTrees.Count -gt 0) {
        $After = Get-CodexTreeSnapshot -Root $Guard.Root -Trees $Guard.ProtectedTrees

        Assert-ProtectedTreesUnchanged `
            -Before $Guard.Snapshot `
            -After $After `
            -Trees $Guard.ProtectedTrees
    }

    # 1겹: 경로 허용 목록. 깨끗한 트리를 전제로 하므로 strict 에서만.
    if ($Guard.UsePathGuard) {
        Assert-OnlyAllowedPathsChanged `
            -Root $Guard.Root `
            -AllowedPaths $Guard.AllowedPaths
    }
    else {
        Write-Host "경로 허용 목록 가드 생략 (vibe 모드)" -ForegroundColor Yellow
        Write-Host "  허용 예정 경로: $($Guard.AllowedPaths -join ', ')"
        Write-Host "  git diff 로 Codex 가 건드린 범위를 직접 확인하세요."
    }
}

# ===============================================================
# 요구사항 ID
# ===============================================================

function Get-CodexIdRegex {
    param(
        [Parameter(Mandatory)][object]$Config
    )

    return [regex]::new(
        (Get-CodexProperty -Object $Config.traceability -Name "idPattern" `
            -Default '(?i)\b(SYS|MOD)[-_][A-Z0-9_-]*?(FR|NFR|AC)[-_][0-9]{3}\b')
    )
}

function ConvertTo-CodexId {
    <# MOD_AUTH_AC_004 와 mod-auth-ac-004 를 MOD-AUTH-AC-004 로 정규화한다. #>
    param(
        [Parameter(Mandatory)][string]$Raw
    )

    return $Raw.Trim().ToUpperInvariant().Replace("_", "-")
}

function Get-CodexIdsFromText {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][regex]$Pattern
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ,@()
    }

    return ,@(
        $Pattern.Matches($Text) |
            ForEach-Object { ConvertTo-CodexId -Raw $_.Value } |
            Sort-Object -Unique
    )
}

# ===============================================================
# 마크다운 표 파서
# ===============================================================

function Read-CodexMarkdownTables {
    <#
        마크다운 표를 헤더 이름으로 열을 매핑해 객체 배열로 돌려준다.

        열 위치에 의존하지 않으므로 Codex 가 열 순서를 바꿔도 견딘다.
        각 행에는 다음 메타가 붙는다.

          _Heading   그 표 직전의 가장 가까운 제목
          _RawLine   원본 행 문자열
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Markdown
    )

    $Rows = [System.Collections.Generic.List[pscustomobject]]::new()

    if ([string]::IsNullOrWhiteSpace($Markdown)) {
        return $Rows
    }

    $Lines = $Markdown -split "`r?`n"
    $CurrentHeading = ""
    $Headers = $null

    foreach ($Line in $Lines) {
        $Trimmed = $Line.Trim()

        if ($Trimmed -match '^#{1,6}\s+(.+)$') {
            $CurrentHeading = $Matches[1].Trim()
            $Headers = $null
            continue
        }

        $IsTableRow = $Trimmed.StartsWith("|") -and $Trimmed.EndsWith("|") -and $Trimmed.Length -gt 2

        if (-not $IsTableRow) {
            $Headers = $null
            continue
        }

        # 구분선  |---|---|
        if ($Trimmed -match '^\|[\s\-:|]+\|$') {
            continue
        }

        $Cells = @(
            $Trimmed.Trim("|") -split '\|' | ForEach-Object { $_.Trim() }
        )

        if ($null -eq $Headers) {
            $Headers = $Cells
            continue
        }

        $Row = [ordered]@{
            _Heading = $CurrentHeading
            _RawLine = $Trimmed
        }

        for ($Index = 0; $Index -lt $Headers.Count; $Index++) {
            $Name = $Headers[$Index]

            if ([string]::IsNullOrWhiteSpace($Name)) { continue }
            if ($Row.Contains($Name)) { continue }

            $Row[$Name] = if ($Index -lt $Cells.Count) { $Cells[$Index] } else { "" }
        }

        $Rows.Add([pscustomobject]$Row)
    }

    return $Rows
}

function Get-CodexCell {
    <# 표 행에서 열 이름으로 값을 꺼낸다. 없으면 빈 문자열. #>
    param(
        [Parameter(Mandatory)][object]$Row,
        [Parameter(Mandatory)][string]$Column
    )

    return [string](Get-CodexProperty -Object $Row -Name $Column -Default "")
}

# ===============================================================
# 모듈 엔트리
# ===============================================================

function New-CodexModuleEntry {
    param(
        [Parameter(Mandatory)][string]$ModuleId,
        [Parameter(Mandatory)][string]$ModuleName,
        [Parameter(Mandatory)][string]$RequirementPath,
        [Parameter(Mandatory)][int]$SystemRevision,
        [string]$Responsibility = "",
        [string[]]$CoveredSystemRequirements = @()
    )

    return [pscustomobject]([ordered]@{
        moduleId                  = $ModuleId
        moduleName                = $ModuleName
        responsibility            = $Responsibility
        coveredSystemRequirements = @($CoveredSystemRequirements)
        requirementPath           = $RequirementPath
        revision                  = 0
        hash                      = $null
        parentSystemRevision      = $SystemRevision
        status                    = "proposed"
        stale                     = $false
        staleReason               = $null
        mode                      = $null
        design                    = $null
        tests                     = $null
        updatedAt                 = (Get-Date).ToString("o")
    })
}

function Add-CodexHistory {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][string]$Stage,
        [string]$ModuleId,
        [string]$Detail = ""
    )

    $Entry = [pscustomobject]([ordered]@{
        at       = (Get-Date).ToString("o")
        stage    = $Stage
        moduleId = $ModuleId
        detail   = $Detail
    })

    $Existing = @(Get-CodexProperty -Object $State -Name "history" -Default @())

    # 최근 200 건만 보관한다.
    $Combined = @($Existing) + @($Entry)

    if ($Combined.Count -gt 200) {
        $Combined = $Combined[($Combined.Count - 200)..($Combined.Count - 1)]
    }

    Set-CodexProperty -Object $State -Name "history" -Value @($Combined)
}

function Get-CodexModuleIds {
    param(
        [Parameter(Mandatory)][object]$State
    )

    # Get-CodexPropertyNames 는 쉼표 연산자로 배열을 감싸 단일 파이프라인
    # 객체로 반환한다. 그 반환값을 곧바로 Sort-Object 에 파이프하면
    # Sort-Object 가 "배열 하나"를 원소 하나로 취급해 정렬이 무력화된다.
    # 반드시 변수에 담아 펼친 뒤 정렬해야 한다.
    $Names = Get-CodexPropertyNames -Object $State.modules
    return ,@($Names | Sort-Object)
}

function Resolve-CodexModuleId {
    <#
        사용자가 대소문자를 섞어 입력해도 등록된 모듈에 맞춘다.
        생략하면 activeModuleId 를 쓴다.
    #>
    param(
        [Parameter(Mandatory)][object]$State,
        [string]$ModuleId
    )

    if ([string]::IsNullOrWhiteSpace($ModuleId)) {
        $Active = Get-CodexProperty -Object $State -Name "activeModuleId" -Default $null

        if ([string]::IsNullOrWhiteSpace($Active)) {
            throw @"
대상 모듈을 지정하지 않았고 활성 모듈도 없습니다.

등록된 모듈: $((Get-CodexModuleIds -State $State) -join ', ')
"@
        }

        return $Active
    }

    $Known = Get-CodexModuleIds -State $State
    $Match = $Known | Where-Object { $_ -ieq $ModuleId.Trim() } | Select-Object -First 1

    if ($Match) {
        return $Match
    }

    throw @"
등록되지 않은 모듈입니다: $ModuleId

등록된 모듈: $(if ($Known.Count -gt 0) { $Known -join ', ' } else { '(없음)' })
"@
}
