# Get-TmuxPlaceholderRow.ps1 - 探测失败 / 空会话时的**占位面板**行
# 职责: 把 Get-TmuxSessionState 的状态渲染成一行占位数据, 由主视图用同一套表格渲染路径展示。
#
# 为什么是"占位行"而不是"空白列表"(2026-10-30 TUI 重构):
#   旧流程在探测失败时直接 Write-Warning 然后弹一个空表格(或干脆不弹), 用户看到的是
#   **留白的屏幕** —— 既不知道发生了什么, 也不知道下一步能做什么。
#   现在失败态直接渲染一行带错误码 + 降级指引的占位行, 与正常态共用同一个面板与同一套键位。

function Get-TmuxPlaceholderRow {
    <#
    .SYNOPSIS
        构造 tmux 主视图的占位面板行(失败态 / 空会话态)。

    .DESCRIPTION
        产出一行与 Get-TmuxSessionGridRow **完全同构**的数据(列名一致),
        因此可以走同一条 Invoke-GridViewPrompt 渲染路径, 不需要第二套渲染实现。

        列的语义:
          Session - 面向用户的一句话说明(如 "SSH 连接超时, 未能获取 tmux 会话列表")
          State   - 稳定错误码 + 降级指引(如 "E_SSH_TIMEOUT · 按 r 重试 · 按 s 直连 SSH")
          No/Windows/Status/Value - 留空(Value 为空串表示"这一行不是会话")

        Value 为空是关键: 主视图据此判定"用户选中的不是会话", 转而进入动作条。

    .PARAMETER State
        Get-TmuxSessionState 的返回值

    .OUTPUTS
        PSCustomObject(No/Session/State/Windows/Status/Disabled/Value)

    .EXAMPLE
        Get-TmuxPlaceholderRow -State $state
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$State
    )

    $errorCode = [string]$State.ErrorCode
    $message = [string]$State.ErrorMessage
    $hint = [string]$State.Hint

    if ([string]::IsNullOrWhiteSpace($message)) {
        $message = '未获取到 tmux 会话数据'
    }

    # State 列: 错误码 + 降级指引(有错误码才带指引, 空会话态只给操作提示)
    $stateText = if ($errorCode) {
        if ($hint) { "$errorCode · $hint" } else { $errorCode }
    } elseif ($hint) {
        $hint
    } else {
        'EMPTY'
    }

    return [PSCustomObject]@{
        No       = ''
        Session  = $message
        State    = $stateText
        Windows  = ''
        Status   = ''
        Disabled = $false
        Value    = ''
    }
}
