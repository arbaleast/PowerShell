# Format-TmuxToolbarText.ps1 - tmux 管理器的单行工具条/状态栏文案
# 职责: 把 Get-TmuxActionDefinition 的动作集合渲染成**一行**文本, 例如:
#       [a]附着  [n]新建  [r]刷新  [s]SSH  [x]删除  [q]退出
#
# 为什么是"单行"(2026-10-30 TUI 重构):
#   原"全局操作菜单"是一个独立表格面板, 与会话列表上下重复渲染, 屏幕信息密度过高。
#   全局动作降级为一行提示文本后, 主界面只剩**一个**会话面板, 动作入口从
#   "翻菜单 + 方向键 + Enter" 变成 "按一个字母键"。
#
# 两个消费点:
#   - Show-TmuxSessionDashboard: 拼进 PSTui 窗口标题(顶部工具条), 表格打开期间也可见;
#   - Show-TmuxActionBar        : 打印到底部单行状态栏, 作为单键事件循环的提示行。

function Format-TmuxToolbarText {
    <#
    .SYNOPSIS
        渲染 tmux 管理器的单行工具条文案。

    .DESCRIPTION
        输出形如 `[a]附着  [n]新建  [r]刷新  [s]SSH  [x]删除  [q]退出` 的单行文本。
        动作集合来自 Get-TmuxActionDefinition(键位契约的唯一事实来源), 本函数只负责排版。

        -HighlightDanger 开启时, "删除"项用 Format-GridViewStateText 染成危险色:
        动作条是纯控制台输出(不走 Terminal.Gui 表格), 内联 ANSI 序列在这里**能**被终端解析,
        与 GridView 表格(单元格内联 ANSI 会被剥离)不同。

    .PARAMETER HasSessions
        当前是否存在 tmux 会话。为 $false 时不渲染"附着/删除"。

    .PARAMETER Context
        渲染上下文: Normal(默认) / Error(失败降级态, r=重试 s=直连)

    .PARAMETER Separator
        动作之间的分隔符, 默认两个空格。

    .PARAMETER HighlightDanger
        是否把"删除"项染成危险色(仅对纯控制台渲染有效)

    .OUTPUTS
        [string] 单行工具条文本

    .EXAMPLE
        Format-TmuxToolbarText -HasSessions $true
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [bool]$HasSessions = $false,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Normal', 'Error')]
        [string]$Context = 'Normal',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Separator = '  ',

        [Parameter(Mandatory = $false)]
        [switch]$HighlightDanger
    )

    $definitions = @(Get-TmuxActionDefinition -HasSessions $HasSessions -Context $Context)

    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($definition in $definitions) {
        $text = "[$($definition.Key)]$($definition.Label)"
        if ($HighlightDanger -and $definition.Value -eq 'Remove') {
            # 危险动作着色: 动作条不走 GridView, 内联 ANSI 在控制台里真实生效
            $text = Format-GridViewStateText -Text $text -ColorKey 'Danger'
        }
        $parts.Add($text) | Out-Null
    }

    return ($parts -join $Separator)
}
