#Requires -Version 7.0
<#
.SYNOPSIS
    PowerShell 启动性能分析脚本
.DESCRIPTION
    测量 profile 中各步骤的耗时，识别启动瓶颈
#>

$ErrorActionPreference = 'Continue'

Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "       PowerShell Profile 性能分析" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# 创建输出目录
$OutputDir = Join-Path $PSScriptRoot "output"
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# 细粒度计时函数
function Measure-Step {
    param(
        [string]$Name,
        [scriptblock]$ScriptBlock
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $result = & $ScriptBlock
    $sw.Stop()
    [PSCustomObject]@{
        Step      = $Name
        ElapsedMs = $sw.ElapsedMilliseconds
        Result    = $result
    }
}

# 基础路径
$ActualRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "▶ Step 1: 加载 Initialize-Config.ps1" -ForegroundColor Yellow
$step1 = Measure-Step "Initialize-Config.ps1" {
    . "$ActualRoot\ShellPrompt\Private\Initialize-Config.ps1"
}
Write-Host "  └─ $($step1.ElapsedMs) ms" -ForegroundColor Gray

Write-Host "▶ Step 2: 加载 Initialize-Environment.ps1" -ForegroundColor Yellow
$step2 = Measure-Step "Initialize-Environment.ps1" {
    . "$ActualRoot\ShellPrompt\Public\Initialize-Environment.ps1"
}
Write-Host "  └─ $($step2.ElapsedMs) ms" -ForegroundColor Gray

Write-Host "▶ Step 3: Show-UserScoopLogo" -ForegroundColor Yellow
$step3 = Measure-Step "Show-UserScoopLogo" {
    Show-UserScoopLogo
}
Write-Host "  └─ $($step3.ElapsedMs) ms" -ForegroundColor Gray

Write-Host "▶ Step 4: 别名设置 (ll, which)" -ForegroundColor Yellow
$step4 = Measure-Step "Set-Alias (ll, which)" {
    Set-Alias ll Get-ChildItem -ErrorAction SilentlyContinue
    Set-Alias which where.exe -ErrorAction SilentlyContinue
}
Write-Host "  └─ $($step4.ElapsedMs) ms" -ForegroundColor Gray

Write-Host "▶ Step 5: ShellPrompt 模块加载" -ForegroundColor Yellow
$step5 = Measure-Step "Import-Module ShellPrompt" {
    Import-Module "$ActualRoot\ShellPrompt\ShellPrompt.psd1" -ErrorAction SilentlyContinue
}
Write-Host "  └─ $($step5.ElapsedMs) ms" -ForegroundColor Gray

Write-Host "▶ Step 6: starship init powershell" -ForegroundColor Yellow
$step6 = Measure-Step "starship init" {
    if (Get-Command starship -ErrorAction SilentlyContinue) {
        $null = &starship init powershell 2>$null
        $true
    } else {
        $false
    }
}
Write-Host "  └─ $($step6.ElapsedMs) ms $(if(-not $step6.Result){'[SKIPPED - starship not found]'})" -ForegroundColor Gray

Write-Host "▶ Step 7: fnm env --use-on-cd" -ForegroundColor Yellow
$step7 = Measure-Step "fnm env" {
    if (Get-Command fnm -ErrorAction SilentlyContinue) {
        $null = &fnm env --use-on-cd --shell powershell 2>$null
        $true
    } else {
        $false
    }
}
Write-Host "  └─ $($step7.ElapsedMs) ms $(if(-not $step7.Result){'[SKIPPED - fnm not found]'})" -ForegroundColor Gray

Write-Host "▶ Step 8: PSReadLine 模块加载" -ForegroundColor Yellow
$step8 = Measure-Step "PSReadLine" {
    if (Get-Module PSReadLine -ListAvailable) {
        Import-Module PSReadLine -ErrorAction SilentlyContinue
        Set-PSReadLineOption -PredictionSource History -ErrorAction SilentlyContinue
        Set-PSReadLineOption -EditMode Windows -ErrorAction SilentlyContinue
        $true
    } else {
        $false
    }
}
Write-Host "  └─ $($step8.ElapsedMs) ms $(if(-not $step8.Result){'[SKIPPED - PSReadLine not available]'})" -ForegroundColor Gray

# 汇总报告
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "                 性能分析报告" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan

$allSteps = @($step1, $step2, $step3, $step4, $step5, $step6, $step7, $step8)
$totalMs = ($allSteps | Measure-Object -Property ElapsedMs -Sum).Sum

$allSteps | Sort-Object ElapsedMs -Descending | ForEach-Object {
    $pct = [math]::Round(($_.ElapsedMs / $totalMs) * 100, 1)
    $barLen = [math]::Round($pct / 2)
    $bar = "█" * $barLen
    $color = if ($_.ElapsedMs -gt 100) { "Red" } elseif ($_.ElapsedMs -gt 50) { "Yellow" } else { "Green" }
    Write-Host ("{0,-30} {1,6} ms ({2,5}%) {3}" -f $_.Step, $_.ElapsedMs, "$pct%", $bar) -ForegroundColor $color
}

Write-Host ""
Write-Host ("总耗时: {0} ms" -f $totalMs) -ForegroundColor White

# 瓶颈识别
$topBottlenecks = $allSteps | Where-Object { $_.ElapsedMs -gt 50 } | Sort-Object ElapsedMs -Descending
if ($topBottlenecks) {
    Write-Host ""
    Write-Host "⚠️  瓶颈识别 (>50ms):" -ForegroundColor Red
    foreach ($b in $topBottlenecks) {
        Write-Host "  • $($b.Step): $($b.ElapsedMs) ms" -ForegroundColor Yellow
    }
}

# 保存报告
$reportPath = Join-Path $OutputDir "profile-timing-report.txt"
$report = @"
PowerShell Profile 性能分析报告
生成时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
====================================

步骤耗时明细:
$($allSteps | Sort-Object ElapsedMs -Descending | ForEach-Object { "$($_.Step): $($_.ElapsedMs) ms" } | Out-String)

总耗时: $totalMs ms

瓶颈 (>50ms):
$($topBottlenecks | ForEach-Object { "- $($_.Step): $($_.ElapsedMs) ms" } | Out-String)
"@
$report | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host ""
Write-Host "📄 报告已保存: $reportPath" -ForegroundColor Gray
