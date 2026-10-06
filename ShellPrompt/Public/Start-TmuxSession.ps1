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
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '')]
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
# 重构: 主机选择/动作选择/会话选择 三个 UI 全部委托给新组件,
# 仅保留业务编排(SSH 探测/LastHost 记忆/子动作分发)
function Start-TmuxSession {

    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$HostName
    )
    if ($PSCmdlet.ShouldProcess($HostName, 'Start tmux session manager')) { } else { return  }

    # 内部验证：使用 Test-SshHostName 统一校验规则
    if ($HostName -and -not (Test-SshHostName -HostName $HostName)) {
        throw "主机名 [$HostName] 包含非法字符，仅允许字母、数字、点、短横线和下划线"
    }

    # P2-6: 入口处显示欢迎 banner, 使用与 Show-UserScoopLogo 一致的样式
    # 预解析颜色后调用 New-WelcomeBanner(纯函数), I/O 调用方负责
    $wbColors = @{
        Primary = Get-CachedConfig -Section 'Colors' -Key 'FreshGreen' -Default "`e[38;2;137;209;133m"
        Accent  = Get-CachedConfig -Section 'Colors' -Key 'SageGreen'  -Default "`e[38;2;159;177;159m"
        Muted   = Get-CachedConfig -Section 'Colors' -Key 'MidGray'    -Default "`e[38;2;100;100;100m"
        Border  = Get-CachedConfig -Section 'Colors' -Key 'FreshGreen' -Default "`e[38;2;137;209;133m"
    }
    $wbQuotesPath = Get-CachedConfig -Section 'Paths' -Key 'Quotes' -Default ''
    $quote = Get-RandomQuote -QuotesPath $wbQuotesPath -Fallback 'SYSTEM READY'
    $bannerLines = New-WelcomeBanner -Title 'TMUX 远程会话' -Subtitle $quote -Width 49 -Colors $wbColors
    $bannerLines | ForEach-Object { [Console]::WriteLine($_) }

    # 主机选择: 委托 Show-HostSelector(实时过滤 + LastHost 徽章)
    if (-not $HostName) {
        # P2-4: 包裹 spinner 保持 UX 一致性(缓存命中会一闪而过, 未命中会有动画)
        $hosts = Invoke-WithProgress -Message "加载主机列表" -ScriptBlock { Get-SshConfigHosts }
        $selected = Show-HostSelector -Hosts $hosts -LastHost $script:Config.SSH.LastHost
        if ($null -eq $selected) { return }
        $HostName = $selected.Value
    }

    $script:Config.SSH.LastHost = $HostName

    Write-Host "`n [SSH] 目标主机: $HostName" -ForegroundColor Cyan

    # P2-4: SSH 探测是真正耗时的步骤(网络慢时 5-30s), spinner 是必须的
    $availInfo = Invoke-WithProgress -Message "检测远程 tmux (可能几秒)" -ScriptBlock { Get-TmuxAvailability -HostName $HostName }
    $hasTmux = $availInfo.Available

    # fix(sss): 探测失败不再直接 fall through 到 ssh, 改成警告后仍进 SessionManager。
    # 之前 `sss <host>` 在远端没 tmux(或探测失败)时会跳过 UI 直接进 SSH TTY,
    # 违反 UI-first 原则;现在改: 菜单 header 仍显示 `tmux?` 徽章
    # (Show-SessionManager 在 TmuxVersion='' 时已实现),用户可手动选 `Ssh` 直连、
    # `Refresh` 重试、`Exit` 退;网络错误下 `Refresh` 还能从 30s 缓存里快速恢复。
    if (-not $hasTmux) {
        Write-Warning "远程主机 $HostName 未安装 tmux(或探测失败), 仍进入菜单,可选: Ssh 直连 / Refresh 重试 / Exit 退"
        $rawErr = $availInfo.Error
        if ($rawErr) {
            Write-Host "     远程错误: $($rawErr.Trim())" -ForegroundColor DarkGray
        }
        Write-Host "     排查: 手动跑 `ssh $HostName 'command -v tmux; tmux -V'` 看输出" -ForegroundColor DarkGray
    } else {
        Write-Host " [OK] 远程 tmux 可用 (版本: $($availInfo.Version))" -ForegroundColor Green
    }

    # P2-5: 首次会话获取走 spinner(初次进入菜单前的预加载)。
    # 探测失败时 SessionData.Sessions 为空列表, 菜单靠 HasSessions=$false 隐藏
    # "附着/删除"项, 只剩 "创建新 tmux / 直接 SSH / 刷新", 与方案 A 体验一致。
    $sessionData = Invoke-WithProgress -Message "获取远程 tmux 会话" -ScriptBlock { Get-TmuxSessions -HostName $HostName }
    $sessions = $sessionData.Sessions

    while ($true) {
        # 每次菜单循环重新探测远端 tmux 会话状态,确保菜单始终显示最新数据(Q6=A)
        # P2-5: 同样走 spinner 包裹, 使 SSH 刷具有统一 UX
        $sessionData = Invoke-WithProgress -Message "获取远程 tmux 会话" -ScriptBlock { Get-TmuxSessions -HostName $HostName -Force }
        $sessions = $sessionData.Sessions
        $attachedCount = ($sessions | Where-Object { $_.Status -eq "attached" }).Count
        $detachedCount = ($sessions | Where-Object { $_.Status -eq "detached" }).Count

        # 动作选择: 委托 Show-SessionManager(动态帮助面板 + 状态徽章)
        $action = Show-SessionManager -HostName $HostName -TmuxVersion $availInfo.Version `
            -SessionCount $sessions.Count -AttachedCount $attachedCount -DetachedCount $detachedCount `
            -HasSessions ($sessions.Count -gt 0)

        if ($null -eq $action) {
            Write-Host " [OK] 已从 $HostName 断开连接" -ForegroundColor Cyan
            return
        }

        # 委托子函数执行具体动作
        switch ($action.Value) {
            "Attach"  { Connect-TmuxSession -HostName $HostName -Sessions $sessions }
            "New"     { New-TmuxSession -HostName $HostName }
            "Remove"  { Remove-TmuxSession -HostName $HostName -Sessions $sessions }
            "Ssh"     {
                Write-Host " [SSH] 直接连接..." -ForegroundColor Green
                Invoke-SshCommand -HostName $HostName -Interactive
                Write-Host "`n [OK] SSH 连接已关闭，回到管理菜单" -ForegroundColor Cyan
            }
            "Refresh" {
                # P2-5: Refresh 在菜单内部被选后, 会跳出菜单 -> while 顶部重新探测
                # 所以不需要在 Refresh 分支重复探测; 原代码是 P1-4 前的遗留, 现仅输出提示
                Write-Host " [OK] 下一次菜单循环会重新获取会话" -ForegroundColor DarkGray
            }
        }
    }
}
