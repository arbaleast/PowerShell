# Get-TmuxSessionStateText.ps1 - tmux 会话状态文案的单一事实来源
#
# 背景: 会话状态文案此前在 GridView 主轨与 ANSI 降级轨各写一份字面量,
#       两边一旦漂移就会出现 "● 已附着 / ○ 已分离" 的语义不一致。
# 方案: 抽出本映射函数, 所有渲染层都调用它, 文案只有一处定义。
# 注: 自研 ANSI 降级轨已于 2026-10-18 移除, 现仅 GridView 主轨消费本函数。
# P1.4: 新增 -IsRefresh 参数, 把 '⟳ 重新拉取' 字面量也收编到本函数,
#       避免刷新行的 State 字面量与普通会话行 State 漂移。

function Get-TmuxSessionStateText {
    <#
    .SYNOPSIS
        把 tmux 会话状态映射为统一的状态文案。

    .DESCRIPTION
        所有菜单渲染层共用同一份文案, 保证 State 表达一致。
        -IsRefresh 开启时返回 '⟳ 重新拉取'(用户触发的刷新项标识);
        否则按 Status 取值:
            attached -> '● 已附着';
            其余(detached / 空 / 未知取值) -> '○ 已分离'。
        -IsRefresh 优先级高于 Status, 即 Status='attached' + -IsRefresh 仍返回刷新标识。

    .PARAMETER Status
        会话状态字符串(attached / detached)

    .PARAMETER IsRefresh
        是否渲染"刷新会话列表"行的 State(返回 '⟳ 重新拉取')

    .OUTPUTS
        string

    .EXAMPLE
        Get-TmuxSessionStateText -Status 'attached'
        # → "● 已附着"
    .EXAMPLE
        Get-TmuxSessionStateText -IsRefresh
        # → "⟳ 重新拉取"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Status,

        [Parameter(Mandatory = $false)]
        [switch]$IsRefresh
    )

    # P1.4: 刷新项优先级最高, 避免 attached 状态误标
    if ($IsRefresh) {
        return '⟳ 重新拉取'
    }
    if ($Status -eq 'attached') {
        return '● 已附着'
    }
    return '○ 已分离'
}
