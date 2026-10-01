<#
.SYNOPSIS
重载 PowerShell 配置文件和 ShellPrompt 模块

.DESCRIPTION
卸载 ShellPrompt 模块并重新加载 $PROFILE，用于在修改 ShellPrompt 模块源码或 ~/.ShellPrompt/config.ps1
后快速应用更改,不必重启 PowerShell。

设计选择: 走"全量重载"路径(Remove-Module + dot-source $PROFILE),而不是 FileSystemWatcher 自动重载 —
后者在 PS 5.1 EventManager + ThreadPool + 跨 runspace SessionState 链路上需要 ~150 行复杂代码,远超
本项目"小而深"模块边界,且 Pester 测试覆盖虚高(PSScriptAnalyzer 抑制属性误用导致整个 watcher 早退)。

.EXAMPLE
Invoke-Reload
#>
function Invoke-Reload {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [switch]$Quiet
    )

    if (-not (Test-Path $PROFILE)) {
        if (-not $Quiet) { Write-Warning "[ShellPrompt] PROFILE not found: $PROFILE" }
        return
    }

    try {
        # 1. 卸载 ShellPrompt 模块(让 dot-source $PROFILE 时能干净地重新加载)
        Remove-Module ShellPrompt -Force -ErrorAction SilentlyContinue

        # 2. 重新加载 $PROFILE(其中 Ensure-ShellPrompt 会再次 Import-Module)
        . $PROFILE

        if (-not $Quiet) {
            Write-Host " [OK] PowerShell Profile + ShellPrompt Reloaded" -ForegroundColor Green
        }
    } catch {
        # 重载失败不抛 — 让调用方自己看错误;静默回退到原状态
        Write-Warning "[ShellPrompt] Reload failed: $($_.Exception.Message)"
    }
}
