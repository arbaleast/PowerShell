# Write-TmuxAvailabilityNotice.ps1 - tmux 探测结果的提示输出
# 职责: 把探测结果转成"可用 / 不可用"的控制台提示, 不影响主流程。

function Write-TmuxAvailabilityNotice {
    <#
    .SYNOPSIS
        输出远程 tmux 探测结果提示。

    .DESCRIPTION
        探测失败不再直接 fall through 到 ssh, 改成警告后仍进 SessionManager:
        之前 `sss <host>` 在远端没 tmux(或探测失败)时会跳过 UI 直接进 SSH TTY,
        违反 UI-first 原则; 现在改: 菜单 header 仍显示 `tmux?` 徽章,
        用户可手动选 `Ssh` 直连 / `Refresh` 重试 / `Exit` 退。

    .PARAMETER HostName
        远程主机名(用于提示文案)

    .PARAMETER AvailabilityInfo
        Get-TmuxAvailability 的返回值(.Available/.Version/.Error)

    .OUTPUTS
        void

    .EXAMPLE
        Write-TmuxAvailabilityNotice -HostName 'debian' -AvailabilityInfo $availInfo
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][object]$AvailabilityInfo
    )

    if ($AvailabilityInfo.Available) {
        Write-Host " [OK] 远程 tmux 可用 (版本: $($AvailabilityInfo.Version))" -ForegroundColor Green
        return
    }

    Write-Warning "远程主机 $HostName 未安装 tmux(或探测失败), 仍进入菜单,可选: Ssh 直连 / Refresh 重试 / Exit 退"
    $rawErr = $AvailabilityInfo.Error
    if ($rawErr) {
        Write-Host "     远程错误: $($rawErr.Trim())" -ForegroundColor DarkGray
    }
    Write-Host "     排查: 手动跑 `ssh $HostName 'command -v tmux; tmux -V'` 看输出" -ForegroundColor DarkGray
}
