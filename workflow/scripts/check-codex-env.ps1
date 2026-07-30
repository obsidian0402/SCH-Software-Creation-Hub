<#
.SYNOPSIS
    Codex CLI 환경과 설정 반영 여부를 진단한다.

.DESCRIPTION
    다음 항목을 확인한다.

    1. codex 설치 및 버전
    2. CODEX_HOME 환경변수
    3. 홈 디렉터리 config.toml 존재 여부
    4. 프로젝트 .codex/config.toml 존재 여부
    5. codex exec 가 지원하는 플래그 목록
    6. 루트 위치 플래그 허용 여부
    7. 프로젝트 .codex/config.toml 이 실제로 읽히는지 (결정적 테스트)
    8. 샌드박스 정책 실효성 (-Deep 지정 시에만, 모델 호출 1회 발생)

    1~7 단계는 모델을 호출하지 않으므로 비용이 발생하지 않는다.

.PARAMETER Deep
    8단계 실효 권한 테스트를 함께 실행한다. 모델 호출이 1회 발생한다.

.EXAMPLE
    pwsh -NoProfile -File scripts/check-codex-env.ps1

.EXAMPLE
    pwsh -NoProfile -File scripts/check-codex-env.ps1 -Deep
#>

[CmdletBinding()]
param(
    [switch]$Deep,

    # 7단계 B상(모델 호출 1회)을 건너뛴다. 대신 판정이 미완료로 남는다.
    [switch]$NoModelCall
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Findings = [System.Collections.Generic.List[pscustomobject]]::new()

function Add-Finding {
    param(
        [Parameter(Mandatory)][string]$Step,
        [Parameter(Mandatory)][string]$Item,
        [AllowEmptyString()][string]$Value = "",
        [ValidateSet("OK", "WARN", "FAIL", "INFO")][string]$Verdict = "INFO"
    )

    $Findings.Add([pscustomobject]@{
        Step    = $Step
        Item    = $Item
        Value   = $Value
        Verdict = $Verdict
    })
}

function Invoke-Native {
    <#
        명령 또는 스크립트 셔임을 실행하고
        표준 출력, 표준 오류, 종료 코드를 함께 반환한다.

        Start-Process 는 출력을 리다이렉트하면 UseShellExecute=false 로
        CreateProcess 를 직접 호출하기 때문에 .cmd / .bat / .ps1 셔임을
        실행할 수 없다. npm 전역 설치된 codex 는 대개 셔임이므로
        여기서는 호출 연산자와 파일 리다이렉션을 사용한다.
    #>
    param(
        [Parameter(Mandatory)][string]$Command,
        [string[]]$Arguments = @(),
        [string]$StdIn
    )

    $OutFile = [System.IO.Path]::GetTempFileName()
    $ErrFile = [System.IO.Path]::GetTempFileName()

    # 진단 목적이므로 네이티브 명령의 stderr 나 비정상 종료 코드가
    # 예외로 승격되지 않게 잠시 완화한다.
    $PreviousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    $HasNativePreference = Test-Path `
        -LiteralPath "Variable:PSNativeCommandUseErrorActionPreference"

    $PreviousNativePreference = $null

    if ($HasNativePreference) {
        $PreviousNativePreference = $PSNativeCommandUseErrorActionPreference
        $PSNativeCommandUseErrorActionPreference = $false
    }

    try {
        $global:LASTEXITCODE = 0

        if ($PSBoundParameters.ContainsKey("StdIn")) {
            $StdIn | & $Command @Arguments > $OutFile 2> $ErrFile
        }
        else {
            & $Command @Arguments > $OutFile 2> $ErrFile
        }

        return [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            StdOut   = (Get-Content -LiteralPath $OutFile -Raw -ErrorAction SilentlyContinue)
            StdErr   = (Get-Content -LiteralPath $ErrFile -Raw -ErrorAction SilentlyContinue)
        }
    }
    catch {
        # 셔임 종류를 PowerShell 도 해석하지 못한 경우
        return [pscustomobject]@{
            ExitCode = -1
            StdOut   = ""
            StdErr   = $_.Exception.Message
        }
    }
    finally {
        $ErrorActionPreference = $PreviousErrorAction

        if ($HasNativePreference) {
            $PSNativeCommandUseErrorActionPreference = $PreviousNativePreference
        }

        foreach ($Path in @($OutFile, $ErrFile)) {
            if (Test-Path -LiteralPath $Path) {
                Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Select-CodexCommand {
    <#
        codex 가 여러 형태로 잡힐 수 있으므로
        .exe > .cmd/.bat > .ps1 순으로 선호도를 적용한다.
    #>
    param(
        [Parameter(Mandatory)][object[]]$Candidates
    )

    foreach ($Pattern in @('\.exe$', '\.(cmd|bat)$', '\.ps1$')) {
        $Selected = $Candidates |
            Where-Object { $_.Source -and ($_.Source -match $Pattern) } |
            Select-Object -First 1

        if ($Selected) {
            return $Selected
        }
    }

    return $Candidates[0]
}

Write-Host ""
Write-Host "Codex 환경 진단" -ForegroundColor Cyan
Write-Host "프로젝트 루트: $ProjectRoot"
Write-Host ""

# ---------------------------------------------------------------
# 1. codex 설치 및 버전
# ---------------------------------------------------------------

$CodexCandidates = @(Get-Command codex -All -ErrorAction SilentlyContinue)

if ($CodexCandidates.Count -eq 0) {
    Add-Finding -Step "1" -Item "codex 설치" -Value "찾을 수 없음" -Verdict "FAIL"

    $Findings | Format-Table -AutoSize
    Write-Host ""
    Write-Host "codex CLI 가 PATH 에 없습니다. 설치 후 다시 실행하세요." -ForegroundColor Red
    exit 1
}

$CodexCommand = Select-CodexCommand -Candidates $CodexCandidates
$CodexPath = $CodexCommand.Source

if ([string]::IsNullOrWhiteSpace($CodexPath)) {
    $CodexPath = $CodexCommand.Name
}

$CodexInvoke = $CodexPath
$Extension = [System.IO.Path]::GetExtension($CodexPath)
$IsWindowsHost = ($env:OS -eq "Windows_NT")

Add-Finding -Step "1" -Item "codex 경로" -Value $CodexPath -Verdict "INFO"

if ($CodexCandidates.Count -gt 1) {
    Add-Finding -Step "1" -Item "PATH 내 codex 개수" `
        -Value ("$($CodexCandidates.Count) 개 - " +
                (($CodexCandidates | ForEach-Object { $_.Source }) -join " | ")) `
        -Verdict "WARN"
}

# 확장자 없는 셔임은 Windows 에서 실행 방식이 불명확하다.
# 이 경우 형제 .cmd 파일을 우선 사용하도록 알린다.
if ($IsWindowsHost -and [string]::IsNullOrEmpty($Extension)) {
    Add-Finding -Step "1" -Item "셔임 형태" `
        -Value "확장자 없음 - .cmd 형제 파일 확인 필요" -Verdict "WARN"
}
elseif ($Extension -in @(".cmd", ".bat", ".ps1")) {
    Add-Finding -Step "1" -Item "셔임 형태" `
        -Value "$Extension 셔임 (한글 인코딩 주의)" -Verdict "WARN"
}
else {
    Add-Finding -Step "1" -Item "셔임 형태" -Value "실행 파일" -Verdict "OK"
}

$VersionResult = Invoke-Native -Command $CodexInvoke -Arguments @("--version")
$VersionText = ("$($VersionResult.StdOut)$($VersionResult.StdErr)").Trim()

Add-Finding -Step "1" -Item "codex 버전" `
    -Value $VersionText `
    -Verdict $(if ($VersionResult.ExitCode -eq 0) { "OK" } else { "FAIL" })

# ---------------------------------------------------------------
# 2. CODEX_HOME
# ---------------------------------------------------------------

$CodexHome = $env:CODEX_HOME

if ([string]::IsNullOrWhiteSpace($CodexHome)) {
    $CodexHome = Join-Path $HOME ".codex"
    Add-Finding -Step "2" -Item "CODEX_HOME" -Value "미설정 (기본값 사용)" -Verdict "INFO"
}
else {
    Add-Finding -Step "2" -Item "CODEX_HOME" -Value $CodexHome -Verdict "INFO"
}

Add-Finding -Step "2" -Item "해석된 홈" -Value $CodexHome -Verdict "INFO"

# ---------------------------------------------------------------
# 3. 홈 config.toml
# ---------------------------------------------------------------

$HomeConfig = Join-Path $CodexHome "config.toml"
$HomeConfigExists = Test-Path -LiteralPath $HomeConfig

Add-Finding -Step "3" -Item "홈 config.toml" `
    -Value $(if ($HomeConfigExists) { $HomeConfig } else { "없음: $HomeConfig" }) `
    -Verdict $(if ($HomeConfigExists) { "OK" } else { "WARN" })

if ($HomeConfigExists) {
    $HomeConfigBody = (Get-Content -LiteralPath $HomeConfig -Raw)

    foreach ($Key in @("approval_policy", "sandbox_mode")) {
        $Match = [regex]::Match(
            $HomeConfigBody,
            "(?m)^\s*$Key\s*=\s*(.+)$"
        )

        Add-Finding -Step "3" -Item "홈 $Key" `
            -Value $(if ($Match.Success) { $Match.Groups[1].Value.Trim() } else { "미지정" }) `
            -Verdict "INFO"
    }
}

# ---------------------------------------------------------------
# 4. 프로젝트 .codex/config.toml
# ---------------------------------------------------------------

$ProjectConfig = Join-Path $ProjectRoot ".codex\config.toml"
$ProjectConfigExists = Test-Path -LiteralPath $ProjectConfig

Add-Finding -Step "4" -Item "프로젝트 config.toml" `
    -Value $(if ($ProjectConfigExists) { $ProjectConfig } else { "없음" }) `
    -Verdict $(if ($ProjectConfigExists) { "INFO" } else { "WARN" })

# ---------------------------------------------------------------
# 5. 플래그 지원 위치 확인
# ---------------------------------------------------------------
# 플래그는 루트에만, exec 에만, 또는 양쪽에 있을 수 있다.
# 중요한 것은 "존재하는가" 가 아니라
# "래퍼가 두는 위치에 존재하는가" 이다.

$ExecHelp = Invoke-Native -Command $CodexInvoke -Arguments @("exec", "--help")
$ExecHelpText = "$($ExecHelp.StdOut)$($ExecHelp.StdErr)"

$RootHelp = Invoke-Native -Command $CodexInvoke -Arguments @("--help")
$RootHelpText = "$($RootHelp.StdOut)$($RootHelp.StdErr)"

# WrapperPosition = Common.ps1 의 Invoke-CodexPrompt 가 플래그를 두는 위치
$FlagChecks = @(
    [pscustomobject]@{ Flag = "--cd";                  WrapperPosition = "root" }
    [pscustomobject]@{ Flag = "--sandbox";             WrapperPosition = "root" }
    [pscustomobject]@{ Flag = "--ask-for-approval";    WrapperPosition = "root" }
    [pscustomobject]@{ Flag = "--output-last-message"; WrapperPosition = "exec" }
    [pscustomobject]@{ Flag = "--ephemeral";           WrapperPosition = "exec" }
)

foreach ($Check in $FlagChecks) {
    $FoundIn = @()

    if ($RootHelpText -like "*$($Check.Flag)*") { $FoundIn += "root" }
    if ($ExecHelpText -like "*$($Check.Flag)*") { $FoundIn += "exec" }

    if ($FoundIn.Count -eq 0) {
        Add-Finding -Step "5" -Item $Check.Flag `
            -Value "루트/exec 어디에도 없음 - 이름 변경 또는 제거됨" -Verdict "FAIL"
    }
    elseif ($FoundIn -contains $Check.WrapperPosition) {
        Add-Finding -Step "5" -Item $Check.Flag `
            -Value "$($FoundIn -join '+') 지원 / 래퍼 위치 $($Check.WrapperPosition) 일치" `
            -Verdict "OK"
    }
    else {
        Add-Finding -Step "5" -Item $Check.Flag `
            -Value "$($FoundIn -join '+') 전용인데 래퍼는 $($Check.WrapperPosition) 에 둠 - 이동 필요" `
            -Verdict "FAIL"
    }
}

# 표준 입력으로 프롬프트를 넘기는 방식
$StdinSupported = $ExecHelpText -match '(?m)^\s*-\s|stdin|standard input'

Add-Finding -Step "5" -Item "exec 표준입력(-)" `
    -Value $(if ($StdinSupported) { "언급 있음" } else { "언급 없음 (수동 확인 필요)" }) `
    -Verdict $(if ($StdinSupported) { "OK" } else { "WARN" })

# ---------------------------------------------------------------
# 6. 권한 제어 수단 조사
# ---------------------------------------------------------------
# 프로젝트 config 를 못 쓰는 경우 대안이 무엇인지 파악한다.

$CombinedHelp = "$RootHelpText`n$ExecHelpText"

# --sandbox 가 받는 값 목록
$SandboxValues = [regex]::Match(
    $CombinedHelp,
    '(?is)--sandbox.{0,400}?\[possible values:\s*([^\]]+)\]'
)

Add-Finding -Step "6" -Item "--sandbox 허용값" `
    -Value $(if ($SandboxValues.Success) {
                ($SandboxValues.Groups[1].Value -replace '\s+', ' ').Trim()
             } else { "help 에서 추출 실패 - 수동 확인" }) `
    -Verdict $(if ($SandboxValues.Success) { "OK" } else { "WARN" })

# 설정을 CLI 로 덮어쓰는 수단 (이식성 있는 권한 제어 방법)
$HasConfigOverride = $CombinedHelp -match '(?m)^\s*-c[,\s]|--config(\s|=|<)'

Add-Finding -Step "6" -Item "-c / --config 덮어쓰기" `
    -Value $(if ($HasConfigOverride) { "지원 - 래퍼에서 설정 주입 가능" } else { "미지원" }) `
    -Verdict $(if ($HasConfigOverride) { "OK" } else { "WARN" })

$HasBypass = $CombinedHelp -like "*--dangerously-bypass-approvals-and-sandbox*"

Add-Finding -Step "6" -Item "전권 바이패스 플래그" `
    -Value $(if ($HasBypass) { "--dangerously-bypass-approvals-and-sandbox 지원" } else { "없음" }) `
    -Verdict $(if ($HasBypass) { "OK" } else { "WARN" })

$HasFullAuto = $CombinedHelp -like "*--full-auto*"

Add-Finding -Step "6" -Item "--full-auto" `
    -Value $(if ($HasFullAuto) { "지원" } else { "없음" }) -Verdict "INFO"

# ---------------------------------------------------------------
# 7. 프로젝트 config.toml 이 실제로 읽히는가
# ---------------------------------------------------------------
# 고의로 문법이 깨진 config 를 심고 codex 를 실행한다.
#
#   A상 (--version) : clap 이 --version 을 config 로드 전에 처리하고
#                     종료하므로 "정상 종료" 는 증거가 되지 못한다.
#                     오류가 났을 때만 의미가 있다.
#
#   B상 (exec)      : 실제로 config 를 로드하는 경로다. 깨진 config 로
#                     정상 실행되면 무시된다는 결정적 증거가 된다.
#                     모델 호출 1회가 발생한다.

function Get-Excerpt {
    param(
        [AllowEmptyString()][string]$Text,
        [int]$Length = 180
    )

    $Flat = ($Text -replace '\s+', ' ').Trim()

    if ($Flat.Length -le $Length) {
        return $Flat
    }

    return $Flat.Substring(0, $Length) + "..."
}

if (-not $ProjectConfigExists) {
    Add-Finding -Step "7" -Item "프로젝트 config 반영" `
        -Value "프로젝트 config 가 없어 건너뜀" -Verdict "WARN"
}
else {
    $Backup = "$ProjectConfig.diagnostic-backup"

    Copy-Item -LiteralPath $ProjectConfig -Destination $Backup -Force

    try {
        # TOML 문법 위반: 닫히지 않은 테이블 헤더와 문자열
        [System.IO.File]::WriteAllText(
            $ProjectConfig,
            "[[[ codex diagnostic invalid toml`nkey = `"unterminated`n",
            [System.Text.UTF8Encoding]::new($false)
        )

        # --- A상 ---------------------------------------------------
        $ProbeA = Invoke-Native `
            -Command $CodexInvoke `
            -Arguments @("--cd", $ProjectRoot, "--version")

        $TextA = "$($ProbeA.StdOut)$($ProbeA.StdErr)"
        $ConfigErrorA = $TextA -match 'toml|parse|invalid|config'

        if ($ProbeA.ExitCode -ne 0 -or $ConfigErrorA) {
            Add-Finding -Step "7" -Item "A상 (--version)" `
                -Value "오류 발생 - config 를 읽는다는 증거" -Verdict "OK"
            Add-Finding -Step "7" -Item "A상 출력" `
                -Value (Get-Excerpt -Text $TextA) -Verdict "INFO"
            $Decided = "READ"
        }
        else {
            Add-Finding -Step "7" -Item "A상 (--version)" `
                -Value "정상 종료 - 판정 불가 (config 로드 전 처리됨)" -Verdict "INFO"
            $Decided = $null
        }

        # --- B상 ---------------------------------------------------
        if ($Decided -eq "READ") {
            Add-Finding -Step "7" -Item "B상 (exec)" `
                -Value "A상에서 판정됨 - 생략" -Verdict "INFO"
        }
        elseif ($NoModelCall) {
            Add-Finding -Step "7" -Item "B상 (exec)" `
                -Value "건너뜀 - -NoModelCall 지정. 판정 미완료" -Verdict "WARN"
        }
        else {
            $ProbeB = Invoke-Native `
                -Command $CodexInvoke `
                -Arguments @(
                    "--cd", $ProjectRoot
                    "--sandbox", "read-only"
                    "exec"
                    "--ephemeral"
                    "-"
                ) `
                -StdIn "ok 라고만 답하고 즉시 종료한다."

            $TextB = "$($ProbeB.StdOut)$($ProbeB.StdErr)"
            $ConfigErrorB = $TextB -match 'toml|failed to parse|invalid.*config|config.*invalid'
            $AuthError = $TextB -match 'login|auth|unauthor|api key|credential|sign in'

            if ($ConfigErrorB) {
                Add-Finding -Step "7" -Item "프로젝트 config 반영" `
                    -Value "읽힘 - 깨진 config 에서 파싱 오류" -Verdict "OK"
            }
            elseif ($AuthError) {
                Add-Finding -Step "7" -Item "프로젝트 config 반영" `
                    -Value "판정 불가 - 인증 문제로 중단됨. codex login 후 재실행" -Verdict "WARN"
            }
            elseif ($ProbeB.ExitCode -eq 0) {
                Add-Finding -Step "7" -Item "프로젝트 config 반영" `
                    -Value "무시됨 - 깨진 config 인데도 exec 정상 완료 (결정적)" -Verdict "FAIL"
            }
            else {
                Add-Finding -Step "7" -Item "프로젝트 config 반영" `
                    -Value "판정 불가 - config 무관 오류로 종료 (코드 $($ProbeB.ExitCode))" `
                    -Verdict "WARN"
            }

            Add-Finding -Step "7" -Item "B상 출력" `
                -Value (Get-Excerpt -Text $TextB) -Verdict "INFO"
        }
    }
    finally {
        Move-Item -LiteralPath $Backup -Destination $ProjectConfig -Force
        Add-Finding -Step "7" -Item "config 원복" -Value "완료" -Verdict "OK"
    }
}

# ---------------------------------------------------------------
# 8. 샌드박스 실효성 (-Deep)
# ---------------------------------------------------------------

if (-not $Deep) {
    Add-Finding -Step "8" -Item "샌드박스 실효 테스트" `
        -Value "건너뜀 (-Deep 으로 실행하면 수행)" -Verdict "INFO"
}
else {
    $ProbeFileName = "codex-sandbox-probe.txt"
    $ProbeFile = Join-Path $ProjectRoot $ProbeFileName

    if (Test-Path -LiteralPath $ProbeFile) {
        Remove-Item -LiteralPath $ProbeFile -Force
    }

    $Prompt = @"
다음 작업만 수행하고 즉시 종료한다.

프로젝트 루트에 $ProbeFileName 파일을 만들고 내용으로 ok 를 쓴다.

성공했으면 WROTE, 실패했으면 BLOCKED 만 답한다.
"@

    try {
        $Sandboxed = Invoke-Native `
            -Command $CodexInvoke `
            -Arguments @(
                "exec"
                "--cd", $ProjectRoot
                "--sandbox", "read-only"
                "-"
            ) `
            -StdIn $Prompt

        $Wrote = Test-Path -LiteralPath $ProbeFile

        Add-Finding -Step "8" -Item "read-only 샌드박스" `
            -Value $(if ($Wrote) { "쓰기 성공 - 샌드박스 미적용" } else { "쓰기 차단 - 정상" }) `
            -Verdict $(if ($Wrote) { "FAIL" } else { "OK" })

        Add-Finding -Step "8" -Item "exec 종료 코드" `
            -Value ([string]$Sandboxed.ExitCode) `
            -Verdict $(if ($Sandboxed.ExitCode -eq 0) { "OK" } else { "WARN" })
    }
    finally {
        if (Test-Path -LiteralPath $ProbeFile) {
            Remove-Item -LiteralPath $ProbeFile -Force
        }
    }
}

# ---------------------------------------------------------------
# 결과 출력
# ---------------------------------------------------------------

Write-Host ""
$Findings | Format-Table -AutoSize -Property Step, Verdict, Item, Value
Write-Host ""

$FailCount = @($Findings | Where-Object { $_.Verdict -eq "FAIL" }).Count
$WarnCount = @($Findings | Where-Object { $_.Verdict -eq "WARN" }).Count

Write-Host "판정: FAIL $FailCount / WARN $WarnCount" -ForegroundColor $(
    if ($FailCount -gt 0) { "Red" } elseif ($WarnCount -gt 0) { "Yellow" } else { "Green" }
)

Write-Host ""
Write-Host "해석 지침" -ForegroundColor Cyan
Write-Host "  5단계 FAIL  래퍼가 플래그를 잘못된 위치에 둡니다."
Write-Host "              Common.ps1 의 Invoke-CodexPrompt 안 CodexArgs 배치를 고치세요."
Write-Host ""
Write-Host "  7단계 FAIL  프로젝트 .codex/config.toml 이 무시됩니다."
Write-Host "              권한은 홈 config 또는 래퍼 CLI 플래그로 통제하세요."
Write-Host "  7단계 WARN  판정 미완료입니다. -NoModelCall 없이 재실행하거나"
Write-Host "              codex login 상태를 확인하세요."
Write-Host ""
Write-Host "  6단계       사용 가능한 권한 제어 수단 목록입니다."
Write-Host "              --sandbox 허용값과 -c 지원 여부를 보고 방식을 정합니다."
Write-Host ""

exit $(if ($FailCount -gt 0) { 1 } else { 0 })
