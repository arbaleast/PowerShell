# Show-TmuxSessionDashboard.ps1 - tmux 管理器的**唯一主视图**
# 职责: 渲染一个面板并返回用户选中的会话 —— 正常态是会话表格, 失败/空态是占位面板。
#
# 单一主视图(2026-10-30 TUI 重构):
#   旧流程有**两个**面板: 会话列表 + 全局操作菜单, 上下重复渲染同一批信息。
#   现在主视图只有一个: 有会话时列会话, 没会话/探测失败时列**占位面板**
#   (带错误码 + 降级指引), 全局动作收敛到底部单行动作条(Show-TmuxActionBar)。
#
# 渲染路径与既有单轨一致: 统一走 Invoke-GridViewPrompt(PSTui Out-ConsoleGridView),
# 不引入第二套渲染实现, 也不对 Terminal.Gui 做任何反射。

function Show-TmuxSessionDashboard {
    <#
    .SYNOPSIS
        渲染 tmux 会话主视图(正常态表格 / 失败态占位面板)。

    .DESCRIPTION
        标题行拼装顺序: 标题 + 主机名 + 状态摘要 + **单行工具条** + 天气后缀。
        工具条放在标题里, 因此表格打开期间用户也能看到可用键位。

        正常态: 行数据来自 Get-TmuxSessionGridRow(带序号/会话名/状态/窗口数);
        失败态: 行数据来自 Get-TmuxPlaceholderRow(错误码 + 降级指引), 与正常态同构,
                因此走同一条渲染路径。

        返回值: 归一化后的会话选择对象(与 Show-TmuxSessionList 同形状), 或 $null(用户 ESC /
                选中了占位行 —— 此时调用方应转入动作条)。

    .PARAMETER HostName
        远程主机名(显示在标题里)

    .PARAMETER State
        Get-TmuxSessionState 的返回值

    .PARAMETER Title
        标题主体, 默认 "TMUX 管理器"

    .OUTPUTS
        含 .Value/.RawName/.Label 的 PSCustomObject, 或 $null(未选中会话)

    .EXAMPLE
        $sel = Show-TmuxSessionDashboard -HostName 'debian' -State $state
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $true)]
        [object]$State,

        [Parameter(Mandatory = $false)]
        [string]$Title = 'TMUX 管理器'
    )

    Assert-ConsoleUiReady -Feature 'tmux 会话主视图'

    $sessions = @($State.Sessions)
    $hasSessions = $sessions.Count -gt 0
    $context = [string]$State.Context
    if ([string]::IsNullOrWhiteSpace($context)) { $context = 'Normal' }

    # 状态摘要: 有会话 -> 计数; 失败态 -> 错误码; 空态 -> 会话 0
    $statusText = if ($hasSessions) {
        (Get-TmuxSessionSummary -Sessions $sessions).TitleSuffix
    } elseif ($context -eq 'Error') {
        [string]$State.ErrorCode
    } else {
        '会话 0'
    }

    # 单行工具条(顶部工具条): 表格打开期间也可见, 键位不必猜
    $toolbar = Format-TmuxToolbarText -HasSessions $hasSessions -Context $context
    $tableTitle = "$Title [$HostName] - $statusText - $toolbar"

    # 标题区天气(失败时静默跳过, 绝不影响主视图)
    $wttrSuffix = Get-WttrTitleSuffix

    # ---- 第四轮修复 (2026-10-30): 全屏渲染, 取代上一轮的 MinUI + 自绘标题 ----
    # 真终端回归: MinUI + 自绘标题产生"标题重复/界面下沉/无底部提示/循环下拉"。
    # 现在统一交给 PSTui 的 -FullScreen(Terminal.Gui 全屏备用屏):
    #   - 每次弹出即整屏重绘(清屏 + 光标归位 Y=0), 不基于当前光标位置;
    #   - 折叠/展开/resize 由 Terminal.Gui 监听尺寸变化自动重排;
    #   - 底部状态条(Rows/Enter/Esc)由 PSTui 定位在最后一行, 不再与我们打架。
    # 标题只渲染一次(就是 PSTui 的 Window.Title), 自绘标题已删除。
    # 仪表盘是否全屏由 UI.DashboardFullScreen 控制(默认 $true);
    # 轻量菜单(主机选择器等)仍走内联, 不受影响。
    $dashFullScreen = $true
    if ($script:Config -and $script:Config.UI -and $script:Config.UI.PSObject.Properties['DashboardFullScreen']) {
        $dashFullScreen = [bool]$script:Config.UI.DashboardFullScreen
    }

    $rows = if ($hasSessions) {
        @(Get-TmuxSessionGridRow -Sessions $sessions -ShowStateBadge)
    } else {
        @(Get-TmuxPlaceholderRow -State $State)
    }

    $selected = Invoke-GridViewPrompt -Rows $rows -Title ($tableTitle + $wttrSuffix) `
        -HiddenColumns @{ Disabled = $false; Value = ''; Status = '' } -FullScreen:$dashFullScreen
    if ($null -eq $selected) {
        return $null
    }

    # 占位行 / 禁用行: 不是一次有效选择, 交给上层转动作条
    if ($selected.Disabled) {
        return $null
    }

    $sessionName = [string]$selected.Value
    if ([string]::IsNullOrWhiteSpace($sessionName)) {
        return $null
    }

    return ConvertTo-TmuxSessionSelection -Name $sessionName -Status ([string]$selected.Status)
}
