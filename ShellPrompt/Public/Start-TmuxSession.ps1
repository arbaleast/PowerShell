# Start-TmuxSession.ps1 - 远程 tmux 会话管理器
# 流程(2026-10-30 收口): 入口欢迎 banner -> 主机选择 -> 后台并行取数(SSH + 天气温
#              预取) -> 单一 Terminal.Gui v2 仪表盘(Show-TmuxTuiDashboard)。
#
# PSTui GridView 回退轨已按用户裁定移除(2026-10-30, 真机验收通过 `5d5daac` 之后):
#   UI.DashboardTuiEnabled 开关、Show-TmuxSessionDashboard / Show-TmuxActionBar /
#   Read-TmuxActionKey / Get-TmuxPlaceholderRow 及本函数内的 legacy 主循环
#   (Enter/Exit-TmuxAlternateScreen 备用屏管理) 同批删除。
#   PSTui 依赖本身已同日随 Modules/PSTui 删除 —— SSH 主机选择器改由
#   ALC 原生的 Terminal.Gui v2 轨(Invoke-TguiHostSelector)承接。
# 移除前的行为契约(备用屏交接/删除二次确认/键位分发)由 Terminal.Gui 轨完整承载:
#   - 状态对象/行序稳定/错误码: Invoke-TmuxSessionFetch / Get-TmuxSessionState;
#   - 附着/新建/删除/SSH 直连: Invoke-TmuxAttach / New-TmuxSession /
#     Remove-TmuxSession(经 Invoke-TmuxSessionDeletion 二次确认) / Invoke-SshCommand;
#   - 终端还原: Show-TmuxTuiDashboard 内 TG Init/Run/Shutdown 独占备用屏。

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
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([string])]
    param()

    # "New" 属于会改变系统状态的动词, 按 PSScriptAnalyzer 规则需支持 ShouldProcess
    if (-not $PSCmdlet.ShouldProcess('tmux session name', 'Generate random tmux session name')) {
        return ''
    }
    return "$script:TmuxSessionPrefix$(Get-Random -Minimum 100000 -Maximum 999999)"
}

<#
.SYNOPSIS
    远程 tmux 会话交互式管理器

.DESCRIPTION
    通过 Terminal.Gui v2 仪表盘管理远程主机上的 tmux 会话，支持主机选择、
    会话附着/创建/删除、直接 SSH 登录等操作。

    交互契约(TGUI 阶段 B 收口, 真机验收 5d5daac):
      - 顶部状态区(主机/连接状态/会话统计) + 会话表格 + 底部快捷键栏;
      - 表格内: ↑↓ 选择, Enter 附着/恢复所选会话;
      - 底栏快捷键: n 新建 / r 刷新 / s SSH / x 删除(二次确认) / q 退出 / Esc 退出;
      - 无会话时独立空态行(不伪造表格行), 附着与删除标注"不可用"。

    各操作分支已抽取到独立的 Private 函数:
    Invoke-TmuxAttach(附着执行) / New-TmuxSession(创建) / Invoke-TmuxSessionDeletion(删除, 含二次确认)。

.PARAMETER HostName
    远程主机名（来自 ~/.ssh/config）。未指定时弹出交互式主机选择菜单。

.EXAMPLE
    Start-TmuxSession

    弹出交互式菜单选择主机并管理远程 tmux 会话。

.EXAMPLE
    Start-TmuxSession -HostName myserver

    直接连接指定主机的 tmux 管理器。
#>
# 编排职责(2026-10-30 收口): 主机选择/LastHost 记忆/天气预取; 渲染与事件循环
# 全部在 Show-TmuxTuiDashboard。
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
    Write-TmuxWelcomeBanner

    # ---- 主机选择: 委托 Show-HostSelector(实时过滤 + LastHost 徽章) ----
    # 必须**先于**仪表盘渲染: 仪表盘需要一个确定的 HostName, 且 LastHost 记忆
    # 要在任何分支都写回。
    if (-not $HostName) {
        # P2-4: 包裹 spinner 保持 UX 一致性(缓存命中会一闪而过, 未命中会有动画)
        $hosts = Invoke-WithProgress -Message "加载主机列表" -ScriptBlock { Get-SshConfigHosts }
        $selected = Show-HostSelector -Hosts $hosts -LastHost $script:Config.SSH.LastHost
        if ($null -eq $selected) { return }
        $HostName = $selected.Value
    }

    $script:Config.SSH.LastHost = $HostName

    # ---- 天气温预取: 与随后的 SSH 探测在后台并行, 首屏不等网络 ----
    # 预取失败静默降级(标题区不显示天气), 不影响主流程。
    $null = Submit-WttrPrefetch

    # ---- 主视图: Terminal.Gui v2 仪表盘(唯一渲染路径) ----
    # 非交互终端/无 TTY 护栏在 Show-TmuxTuiDashboard 内部处理(直接返回 'Exit')。
    Show-TmuxTuiDashboard -HostName $HostName | Out-Null
    return
}
