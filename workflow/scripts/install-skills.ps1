<#
.SYNOPSIS
    workflow/skills 의 스킬을 .claude/skills 로 설치하고 구 자산을 정리한다.

.DESCRIPTION
    스킬 정본은 workflow/skills 에 둔다. 이렇게 하면 프레임워크 폴더 하나만
    복사해도 스킬까지 함께 이식된다.

    이 스크립트는 다음을 수행한다.

    1. workflow/skills/* 를 .claude/skills/ 로 복사
    2. 이전 구조의 스킬 폴더 제거 (codex-acceptance 등)
    3. 이전 구조의 스크립트와 설정 제거
       - scripts/CodexWorkflow.Common.ps1
       - scripts/invoke-codex-*.ps1
       - .codex-workflow.json
       - .codex/  (codex CLI 가 읽지 않음이 확인됨)

    구 스킬이 구 스크립트를 참조하므로 둘을 함께 정리해야 중간에
    깨진 상태가 생기지 않는다.

.PARAMETER KeepLegacy
    구 자산을 남긴다. 스킬만 설치한다.

.PARAMETER WhatIfOnly
    실제로 바꾸지 않고 수행할 작업만 보여준다.

.EXAMPLE
    pwsh -NoProfile -File workflow/scripts/install-skills.ps1

.EXAMPLE
    pwsh -NoProfile -File workflow/scripts/install-skills.ps1 -WhatIfOnly
#>

[CmdletBinding()]
param(
    [switch]$KeepLegacy,
    [switch]$WhatIfOnly
)

. "$PSScriptRoot\Common.ps1"

Initialize-CodexEncoding

$Root = Get-CodexRoot

$SourceRoot = Join-Path $Root "workflow" "skills"
$TargetRoot = Join-Path $Root ".claude" "skills"

if (-not (Test-Path -LiteralPath $SourceRoot)) {
    throw "스킬 원본을 찾을 수 없습니다: $SourceRoot"
}

Write-Host ""
Write-Host "스킬 설치" -ForegroundColor Cyan
Write-Host "  원본: workflow/skills"
Write-Host "  대상: .claude/skills"

if ($WhatIfOnly) {
    Write-Host "  (WhatIfOnly - 실제로 변경하지 않습니다)" -ForegroundColor Yellow
}

Write-Host ""

# ---------------------------------------------------------------
# 1. 스킬 복사
# ---------------------------------------------------------------

$Skills = @(Get-ChildItem -LiteralPath $SourceRoot -Directory)

if ($Skills.Count -eq 0) {
    throw "workflow/skills 에 스킬이 없습니다."
}

foreach ($Skill in $Skills) {
    $SkillFile = Join-Path $Skill.FullName "SKILL.md"

    if (-not (Test-Path -LiteralPath $SkillFile)) {
        Write-Warning "SKILL.md 가 없어 건너뜁니다: $($Skill.Name)"
        continue
    }

    $Destination = Join-Path $TargetRoot $Skill.Name

    if ($WhatIfOnly) {
        Write-Host "  설치 예정: $($Skill.Name)"
        continue
    }

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null

    Copy-Item `
        -Path (Join-Path $Skill.FullName "*") `
        -Destination $Destination `
        -Recurse -Force

    Write-Host "  설치: $($Skill.Name)" -ForegroundColor Green
}

# ---------------------------------------------------------------
# 2. 구 자산 정리
# ---------------------------------------------------------------

if ($KeepLegacy) {
    Write-Host ""
    Write-Host "구 자산을 남깁니다 (-KeepLegacy)" -ForegroundColor Yellow
}
else {
    $InstalledNames = @($Skills | ForEach-Object { $_.Name })

    $LegacySkills = @("codex-acceptance", "codex-recheck", "requirements", "codex-design") |
        Where-Object { $InstalledNames -notcontains $_ }

    $LegacyPaths = @()

    foreach ($Name in $LegacySkills) {
        $LegacyPaths += (Join-Path $TargetRoot $Name)
    }

    $LegacyPaths += (Join-Path $Root "scripts")
    $LegacyPaths += (Join-Path $Root ".codex-workflow.json")
    $LegacyPaths += (Join-Path $Root ".codex-workflow-state.json")
    $LegacyPaths += (Join-Path $Root ".codex")

    $Found = @($LegacyPaths | Where-Object { Test-Path -LiteralPath $_ })

    if ($Found.Count -eq 0) {
        Write-Host ""
        Write-Host "정리할 구 자산이 없습니다." -ForegroundColor Green
    }
    else {
        Write-Host ""
        Write-Host "구 자산 정리" -ForegroundColor Cyan

        foreach ($Path in $Found) {
            $Relative = ConvertTo-CodexRelativePath -Root $Root -Path $Path

            if ($WhatIfOnly) {
                Write-Host "  제거 예정: $Relative"
                continue
            }

            Remove-Item -LiteralPath $Path -Recurse -Force
            Write-Host "  제거: $Relative" -ForegroundColor Yellow
        }
    }
}

# ---------------------------------------------------------------
# 3. settings.local.json 점검
# ---------------------------------------------------------------

$LocalSettings = Join-Path $Root ".claude" "settings.local.json"

if (Test-Path -LiteralPath $LocalSettings) {
    $Body = Read-Utf8File -Path $LocalSettings

    if ($Body -like "*invoke-codex-*" -or $Body -like "*req_body*") {
        Write-Host ""
        Write-Warning ".claude/settings.local.json 에 구 스크립트를 참조하는 항목이 있습니다."
        Write-Host "  이 파일은 gitignore 대상이며 일회용 승인 기록입니다."
        Write-Host "  다음 명령으로 정리하고 새 스킬 실행 시 다시 승인하는 편이 깔끔합니다."
        Write-Host ""
        Write-Host "    Remove-Item .claude/settings.local.json"
    }
}

# ---------------------------------------------------------------
# 안내
# ---------------------------------------------------------------

Write-Host ""

if ($WhatIfOnly) {
    Write-Host "실제로 적용하려면 -WhatIfOnly 없이 다시 실행하세요." -ForegroundColor Yellow
    Write-Host ""
    exit 0
}

Write-Host "설치 완료" -ForegroundColor Green
Write-Host ""
Write-Host "사용 가능한 스킬" -ForegroundColor Cyan

foreach ($Skill in $Skills) {
    Write-Host "  /$($Skill.Name)"
}

Write-Host ""
Write-Host "Claude Code 를 다시 시작하면 스킬 목록이 갱신됩니다." -ForegroundColor Cyan
Write-Host ""
Write-Host "다음 단계" -ForegroundColor Cyan
Write-Host "  1. git add -A; git commit -m 'chore: 워크플로 스킬 설치'"
Write-Host "  2. /requirements system '<전체 프로그램 요청>'"
Write-Host ""
