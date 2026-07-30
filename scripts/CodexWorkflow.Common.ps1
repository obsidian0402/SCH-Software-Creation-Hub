Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Initialize-CodexWorkflowEncoding {
    $Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

    [Console]::InputEncoding = $Utf8NoBom
    [Console]::OutputEncoding = $Utf8NoBom
    $script:OutputEncoding = $Utf8NoBom
}

function Assert-ExternalCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "필요한 명령을 찾을 수 없습니다: $Name"
    }
}

function Get-CodexWorkflowConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $ConfigPath = Join-Path `
        $ProjectRoot `
        ".codex-workflow.json"

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "설정 파일이 없습니다: $ConfigPath"
    }

    return Get-Content `
        -LiteralPath $ConfigPath `
        -Raw `
        -Encoding UTF8 |
        ConvertFrom-Json
}

function Assert-ConfigProperty {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName
    )

    $PropertyExists = (
        $Config.PSObject.Properties.Name -contains $PropertyName
    )

    if (-not $PropertyExists) {
        throw ".codex-workflow.json에 '$PropertyName' 설정이 없습니다."
    }

    $Value = $Config.$PropertyName

    if (
        $null -eq $Value -or
        [string]::IsNullOrWhiteSpace([string]$Value)
    ) {
        throw ".codex-workflow.json의 '$PropertyName' 값이 비어 있습니다."
    }
}

function Resolve-CodexProjectPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        $Candidate = $Path
    }
    else {
        $Candidate = Join-Path $ProjectRoot $Path
    }

    if (-not (Test-Path -LiteralPath $Candidate)) {
        throw "경로를 찾을 수 없습니다: $Candidate"
    }

    return (Resolve-Path -LiteralPath $Candidate).Path
}

function Write-Utf8NoBomFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Content
    )

    $ParentDirectory = Split-Path -Parent $Path

    if (-not (Test-Path -LiteralPath $ParentDirectory)) {
        New-Item `
            -ItemType Directory `
            -Path $ParentDirectory `
            -Force | Out-Null
    }

    $Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

    [System.IO.File]::WriteAllText(
        $Path,
        $Content,
        $Utf8NoBom
    )
}

function Invoke-CodexFinalMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,

        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [Parameter(Mandatory = $true)]
        [ValidateSet("read-only", "workspace-write")]
        [string]$Sandbox
    )

    Assert-ExternalCommand -Name "codex"

    $TemporaryOutput = Join-Path `
        ([System.IO.Path]::GetTempPath()) `
        "codex-$([guid]::NewGuid().ToString('N')).md"

    $Arguments = @(
        
        "--cd", $ProjectRoot,
        
        "--sandbox", $Sandbox,
        "--ask-for-approval", "never",
        "exec",
        "--ephemeral",
        "--output-last-message", $TemporaryOutput,
        "-"
    )

    try {
        $Prompt |
            & codex @Arguments 2>&1 |
            ForEach-Object {
                Write-Host $_
            }

        $ExitCode = $LASTEXITCODE

        if ($ExitCode -ne 0) {
            throw "Codex 실행 실패. 종료 코드: $ExitCode"
        }

        if (-not (Test-Path -LiteralPath $TemporaryOutput)) {
            throw "Codex 최종 응답 파일이 생성되지 않았습니다."
        }

        return Get-Content `
            -LiteralPath $TemporaryOutput `
            -Raw `
            -Encoding UTF8
    }
    finally {
        if (Test-Path -LiteralPath $TemporaryOutput) {
            Remove-Item `
                -LiteralPath $TemporaryOutput `
                -Force
        }
    }
}

function Assert-CleanGitWorkingTree {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    Assert-ExternalCommand -Name "git"

    $Status = @(
        & git -C $ProjectRoot `
            status `
            --porcelain=v1 `
            --untracked-files=all
    )

    if ($LASTEXITCODE -ne 0) {
        throw "Git 작업 상태를 확인할 수 없습니다."
    }

    if ($Status.Count -gt 0) {
        throw @"
Codex 인수 테스트 또는 재검토 전에는
Git 작업 트리가 깨끗해야 합니다.

현재 변경:

$($Status -join "`n")

변경사항을 확인하고 체크포인트 커밋한 뒤 다시 실행하세요.
"@
    }
}

function Convert-ToNormalizedGitPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $Normalized = $Path.Replace("\", "/")

    if ($Normalized.StartsWith("./")) {
        $Normalized = $Normalized.Substring(2)
    }

    return $Normalized.TrimEnd("/")
}

function Test-IsAllowedChangedPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ChangedPath,

        [Parameter(Mandatory = $true)]
        [string[]]$AllowedPaths
    )

    $NormalizedChanged = Convert-ToNormalizedGitPath $ChangedPath

    foreach ($AllowedPath in $AllowedPaths) {
        $NormalizedAllowed = Convert-ToNormalizedGitPath $AllowedPath

        if ($NormalizedChanged -eq $NormalizedAllowed) {
            return $true
        }

        if ($NormalizedChanged.StartsWith("$NormalizedAllowed/")) {
            return $true
        }
    }

    return $false
}

function Get-GitChangedPaths {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $Tracked = @(
        & git -C $ProjectRoot `
            -c core.quotepath=false `
            diff `
            --name-only
    )

    $Staged = @(
        & git -C $ProjectRoot `
            -c core.quotepath=false `
            diff `
            --cached `
            --name-only
    )

    $Untracked = @(
        & git -C $ProjectRoot `
            -c core.quotepath=false `
            ls-files `
            --others `
            --exclude-standard
    )

    return @(
        $Tracked
        $Staged
        $Untracked
    ) |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace($_)
        } |
        Sort-Object -Unique
}

function Restore-UnauthorizedGitChanges {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,

        [Parameter(Mandatory = $true)]
        [string[]]$UnauthorizedPaths
    )

    foreach ($RelativePath in $UnauthorizedPaths) {
        & git -C $ProjectRoot `
            ls-files `
            --error-unmatch `
            -- `
            $RelativePath *> $null

        $IsTracked = ($LASTEXITCODE -eq 0)

        if ($IsTracked) {
            & git -C $ProjectRoot `
                restore `
                --source=HEAD `
                --staged `
                --worktree `
                -- `
                $RelativePath

            if ($LASTEXITCODE -ne 0) {
                throw "파일 복원에 실패했습니다: $RelativePath"
            }
        }
        else {
            $FullPath = Join-Path `
                $ProjectRoot `
                $RelativePath

            if (Test-Path -LiteralPath $FullPath) {
                Remove-Item `
                    -LiteralPath $FullPath `
                    -Recurse `
                    -Force
            }
        }
    }
}

function Assert-OnlyAllowedPathsChanged {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,

        [Parameter(Mandatory = $true)]
        [string[]]$AllowedPaths
    )

    $ChangedPaths = @(
        Get-GitChangedPaths `
            -ProjectRoot $ProjectRoot
    )

    $UnauthorizedPaths = @(
        $ChangedPaths |
            Where-Object {
                -not (
                    Test-IsAllowedChangedPath `
                        -ChangedPath $_ `
                        -AllowedPaths $AllowedPaths
                )
            }
    )

    if ($UnauthorizedPaths.Count -gt 0) {
        Restore-UnauthorizedGitChanges `
            -ProjectRoot $ProjectRoot `
            -UnauthorizedPaths $UnauthorizedPaths

        throw @"
Codex가 허용되지 않은 경로를 수정했습니다.

다음 변경은 자동으로 복원했습니다.

$($UnauthorizedPaths -join "`n")

현재 Codex 실행 결과는 무효입니다.
"@
    }
}