# Get-GridViewManagerRow.ps1 - tmux 会话动作菜单的表格行构造
# 职责: 把动作集合(附着/创建/删除/直连/刷新)转换为 GridView 行对象。
# 会话为空时隐藏"附着"与"删除"行(与原 ANSI 菜单一致)。

function Get-GridViewManagerRow {
    <#
    .SYNOPSIS
        构造 tmux 会话动作菜单的 GridView 表格行。

    .DESCRIPTION
        因 PSTui 无行级配色, 删除动作的危险语义改由 State 列的 ⚠ 符号表达,
        并且真正的二次确认由 Remove-TmuxSession 用 Read-SpectreConfirm 阻断。
        会话为空时隐藏"附着/删除"行, 只保留 创建 / 直连 / 刷新。

    .PARAMETER HasSessions
        会话列表是否非空(为 $false 时隐藏"附着/删除")

    .PARAMETER AttachedCount
        已附着会话数(用于 State 列标注)

    .OUTPUTS
        PSCustomObject 数组(Action/State/Disabled/Value)

    .EXAMPLE
        $rows = Get-GridViewManagerRow -HasSessions $true -AttachedCount 1
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '')]
    param(
        [Parameter(Mandatory = $false)][bool]$HasSessions = $false,
        [Parameter(Mandatory = $false)][int]$AttachedCount = 0
    )

    # State 列文本承担 Severity 语义(PSTui 无行级配色能力);
    # 危险 / 备选字面量经 Format-GridViewStateText 接驳到 Colors.Danger / Colors.Warning,
    # 中性文本(如 ● 已附着 N / 空串)保持纯文本以维持 266 Pass 基线。
    $rows = [System.Collections.Generic.List[PSCustomObject]]::new()
    if ($HasSessions) {
        # 2026-10-19 P0: 删 Desc 列(与 Action 重复, 释放 ~16 字宽度)
        $rows.Add([PSCustomObject]@{
                Action   = '附着/恢复 tmux 会话'
                State    = if ($AttachedCount -gt 0) { "● 已附着 $AttachedCount" } else { '' }
                Disabled = $false
                Value    = 'Attach'
            })
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
