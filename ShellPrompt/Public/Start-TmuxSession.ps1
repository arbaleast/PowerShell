# Start-TmuxSession.ps1 - 远程 tmux 会话管理器
# 流程: 主机选择 -> tmux 检测 -> 会话管理 -> SSH 连接

$script:TmuxSessionPrefix = "tmux-"

<#
.SYNOPSIS
    生成随机 tmux 会话名称

.DESCRIPTION
    生成以 "tmux-" 为前缀的 6 位随机数字会话名。

.EXAMPLE
    New-RandomSessionName
#>
function New-RandomSessionName {
    [OutputType([string])]
    param()
    "$script:TmuxSessionPrefix$(Get-Random -Minimum 100000 -Maximum 999999)"
}

<#
.SYNOPSIS
    远程 tmux 会话交互式管理器

.DESCRIPTION
    通过交互式菜单管理远程主机上的 tmux 会话，支持主机选择、tmux 可用性探测、
    会话附着/创建/删除、直接 SSH 登录等操作。
    各操作分支已抽取到独立的 Private 函数: Connect-TmuxSession / New-TmuxSession / Remove-TmuxSession。

.PARAMETER HostName
    远程主机名（来自 ~/.ssh/config）。未指定时弹出交互式主机选择菜单。

.EXAMPLE
    Start-TmuxSession

    弹出交互式菜单选择主机并管理远程 tmux 会话。

.EXAMPLE
    Start-TmuxSession -HostName myserver

    直接连接指定主机的 tmux 管理器。
#>
function Start-TmuxSession {

    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$HostName
    )

    # 内部验证：使用 Test-SshHostName 统一校验规则
    if ($HostName -and -not (Test-SshHostName -HostName $HostName)) {
        throw "主机名 [$HostName] 包含非法字符，仅允许字母、数字、点、短横线和下划线"
    }

    if (-not $HostName) {
        $hosts = Get-SshConfigHosts
        if ($hosts.Count -eq 0) {
            Write-Warning "SSH 配置中未找到任何主机，请先在 ~/.ssh/config 中配置主机"
            return
        }

        if ($script:Config.SSH.LastHost -and ($hosts -contains $script:Config.SSH.LastHost)) {
            $hosts = @($script:Config.SSH.LastHost) + ($hosts | Where-Object { $_ -ne $script:Config.SSH.LastHost })
        }

        $hostOptions = [System.Collections.Generic.List[PSCustomObject]]::new($hosts.Count)
        foreach ($h in $hosts) {
            $desc = "SSH 远程主机"
            if ($script:Config.SSH.LastHost -and $h -eq $script:Config.SSH.LastHost) {
                $desc = "上次使用的主机"
            }
            $hostOptions.Add([PSCustomObject]@{ Label = $h; Desc = $desc })
        }

        $selected = Invoke-ConsoleMenu -Title "SSH 主机选择器" -Options $hostOptions -ExitLabel "退出"
        if ($null -eq $selected) {
            Clear-Host
            return
        }

        $HostName = $selected.Label
    }

    $script:Config.SSH.LastHost = $HostName

    Write-Host "`n [SSH] 目标主机: $HostName" -ForegroundColor Cyan

    Write-Host " [..] 正在检测远程 tmux..." -ForegroundColor DarkGray
    $availInfo = Get-TmuxAvailability -HostName $HostName
    $hasTmux = $availInfo.Available

    if (-not $hasTmux) {
        Write-Warning "远程主机 $HostName 未安装 tmux(或探测失败)"
        $rawErr = $availInfo.Error
        if ($rawErr) {
            Write-Host "     远程错误: $($rawErr.Trim())" -ForegroundColor DarkGray
        }
        Write-Host "     排查: 手动跑 `ssh $HostName 'command -v tmux; tmux -V'` 看输出" -ForegroundColor DarkGray
        Write-Host " [SSH] 直接连接..." -ForegroundColor Green
        Invoke-SshCommand -HostName $HostName -Interactive
        Write-Host "`n [OK] SSH 连接已关闭，回到本地 PowerShell" -ForegroundColor Cyan
        return
    }

    Write-Host " [OK] 远程 tmux 可用 (版本: $($availInfo.Version))" -ForegroundColor Green

    $sessionData = Get-TmuxSessions -HostName $HostName
    $sessions = $sessionData.Sessions

    if ($sessions.Count -eq 0) {
        Write-Warning "$HostName 上暂无现有 tmux 会话"
    }

    # 5 个动作的描述在循环中保持稳定,无需每轮重建
    $actionOptions = @(
        [PSCustomObject]@{ Label = "附着/恢复 tmux 会话"; Desc = "选择并附着到远程 tmux 会话" }
        [PSCustomObject]@{ Label = "创建新 tmux 会话"; Desc = "在远程主机上创建新的 tmux 会话" }
        [PSCustomObject]@{ Label = "删除 tmux 会话"; Desc = "删除远程主机上的 tmux 会话" }
        [PSCustomObject]@{ Label = "直接 SSH 登录"; Desc = "不使用 tmux，直接 SSH 登录" }
        [PSCustomObject]@{ Label = "刷新会话列表"; Desc = "重新获取远程 tmux 会话状态" }
    )

    while ($true) {
        # 每次菜单循环重新探测远端 tmux 会话状态，确保菜单始终显示最新数据
        $sessionData = Get-TmuxSessions -HostName $HostName -Force
        $sessions = $sessionData.Sessions

        $attachedCount = ($sessions | Where-Object { $_.Status -eq "attached" }).Count
        $detachedCount = ($sessions | Where-Object { $_.Status -eq "detached" }).Count
        $sessionSummary = "会话: $($sessions.Count) 个 (已附着=$attachedCount 已分离=$detachedCount)"

        $action = Invoke-ConsoleMenu -Title "TMUX 管理器 [$HostName] | $sessionSummary" -Options $actionOptions -ExitLabel "断开连接"

        if ($null -eq $action) {
            Clear-Host
            Write-Host " [OK] 已从 $HostName 断开连接" -ForegroundColor Cyan
            return
        }

        switch ($action.Label) {

            "附着/恢复 tmux 会话" {
                Connect-TmuxSession -HostName $HostName -Sessions $sessions
            }

            "创建新 tmux 会话" {
                New-TmuxSession -HostName $HostName
            }

            "删除 tmux 会话" {
                Remove-TmuxSession -HostName $HostName -Sessions $sessions
            }

            "直接 SSH 登录" {
                Write-Host " [SSH] 直接连接..." -ForegroundColor Green
                Invoke-SshCommand -HostName $HostName -Interactive
                Write-Host "`n [OK] SSH 连接已关闭，回到管理菜单" -ForegroundColor Cyan
            }

            "刷新会话列表" {
                Write-Host " [..] 正在刷新会话列表..." -ForegroundColor DarkGray
                # 显式带 -Force 绕过缓存,真正发起一次 SSH 探测获取最新会话状态
                $sessionData = Get-TmuxSessions -HostName $HostName -Force
                $sessions = $sessionData.Sessions
                $attachedCount = ($sessions | Where-Object { $_.Status -eq "attached" }).Count
                $detachedCount = ($sessions | Where-Object { $_.Status -eq "detached" }).Count
                Write-Host " [OK] 会话列表已刷新: $($sessions.Count) 个 (已附着=$attachedCount 已分离=$detachedCount)" -ForegroundColor Green
            }
        }
    }
}
