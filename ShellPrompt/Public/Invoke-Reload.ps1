<#
.SYNOPSIS
    重载 PowerShell 配置文件和 ShellPrompt 模块

.DESCRIPTION
    卸载 ShellPrompt 模块并重新加载 $PROFILE，用于在修改配置后快速应用更改而不必重启 PowerShell。

.EXAMPLE
    Invoke-Reload
#>
function Invoke-Reload {
    [CmdletBinding()]
    [OutputType([void])]
    param()
    if (Test-Path $PROFILE) {
        Remove-Module ShellPrompt -Force -ErrorAction SilentlyContinue
        . $PROFILE
        Write-Host " [OK] PowerShell Profile Reloaded" -ForegroundColor Green
    }
}
