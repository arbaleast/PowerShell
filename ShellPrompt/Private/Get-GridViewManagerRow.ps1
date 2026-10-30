# Get-GridViewManagerRow.ps1 - tmux 全局操作菜单的表格行构造
# 职责: 把全局动作集合(删除/创建/直连/刷新)转换为 GridView 行对象。
# 方案 A (2026-10-29): tmux 管理器主界面改为真实会话列表(Show-TmuxSessionList),
# 本菜单降阶为"轻量全局操作菜单"(用户从会话列表按 ESC 进入), 因此不再提供
# "附着/恢复"动作 -- 附着只能针对列表中明确选中的会话执行, 不作为独立菜单项。
# 会话为空时隐藏"删除"行(它只对真实选中的会话生效, 空列表无意义)。

function Get-GridViewManagerRow {
    <#
    .SYNOPSIS
        构造 tmux 全局操作菜单的 GridView 表格行。

    .DESCRIPTION
        因 PSTui 无行级配色, 删除动作的危险语义改由 State 列的 ⚠ 符号表达,
        并且真正的二次确认由 Remove-TmuxSession 用 Read-SpectreConfirm 阻断。
        方案 A: "附着/恢复"不再是菜单项, 只能从会话列表中选中会话执行;
        会话为空时隐藏"删除"行, 只保留 创建 / 直连 / 刷新。

    .PARAMETER HasSessions
        会话列表是否非空(为 $false 时隐藏"删除")

    .OUTPUTS
        PSCustomObject 数组(Action/State/Disabled/Value)

    .EXAMPLE
        $rows = Get-GridViewManagerRow -HasSessions $true
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)][bool]$HasSessions = $false
    )

    # State 列文本承担 Severity 语义(PSTui 无行级配色能力);
    # 危险 / 备选字面量经 Format-GridViewStateText 接驳到 Colors.Danger / Colors.Warning,
    # 中性文本保持纯文本以维持测试基线。
    $rows = [System.Collections.Generic.List[PSCustomObject]]::new()
    if ($HasSessions) {
        # 2026-10-19 P0: 删 Desc 列(与 Action 重复, 释放 ~16 字宽度)
        $rows.Add([PSCustomObject]@{
                Action   = '删除 tmux 会话'
                State    = Format-GridViewStateText -Text '⚠ 危险' -ColorKey 'Danger'
                Disabled = $false
                Value    = 'Remove'
            })
    }
    $rows.Add([PSCustomObject]@{
            Action   = '创建新 tmux 会话'
            State    = ''
            Disabled = $false
            Value    = 'New'
        })
    $rows.Add([PSCustomObject]@{
            Action   = '直接 SSH 登录'
            State    = Format-GridViewStateText -Text '⚠ 备选' -ColorKey 'Warning'
            Disabled = $false
            Value    = 'Ssh'
        })
    $rows.Add([PSCustomObject]@{
            Action   = '刷新会话列表'
            State    = ''
            Disabled = $false
            Value    = 'Refresh'
        })

    return $rows.ToArray()
}
