# Get-HostSelectorStateText.ps1 - SSH 主机选择器 State 列文本生成器(纯函数)
#
# 职责:
#   - 把"是否 LastHost"映射成 State 列显示文本(纯字符串, 无副作用)
#   - P1.4 启用草案 B 钩子: LastHost 行用 '★ 最近'(语义更明确, 与 Get-TmuxSessionStateText 的
#     '● 已附着 N' 形态并列; 历史上是 '● last', 现在通过测试断言 -Match '● last|★ 最近'
#     双轨兼容)
#
# 调用方:
#   - Get-HostSelectorRow(主机选择表格行构造)
#
# 依赖:
#   - 无

function Get-HostSelectorStateText {
    <#
    .SYNOPSIS
        生成 SSH 主机选择器 State 列文本(纯函数封装)。

    .DESCRIPTION
        唯一决策因子:是否 LastHost。非 LastHost 返回空串(中性, 不污染未使用主机的视觉)。
        LastHost 时返回 '★ 最近'(P1.4 启用草案 B 钩子)。
        测试断言为 -Match '● last|★ 最近', 历史文本 '● last' 通过该模式继续兼容。

    .PARAMETER IsLast
        是否 LastHost

    .OUTPUTS
        [string] State 列文本

    .EXAMPLE
        Get-HostSelectorStateText -IsLast $true
        # → "★ 最近"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [bool]$IsLast = $false
    )

    if (-not $IsLast) {
        return ''
    }
    # P1.4 启用草案 B 钩子: LastHost 行改为 '★ 最近', 历史文本 '● last' 通过断言 -Match 兼容
    return '★ 最近'
}
