# Get-GridViewManagerRow.ps1 - tmux 全局操作菜单的表格行构造
# 职责: 把全局动作集合(创建/刷新/直连/删除)转换为 GridView 行对象。
# 方案 A (2026-10-29): tmux 管理器主界面改为真实会话列表(Show-TmuxSessionList),
# 本菜单降阶为"轻量全局操作菜单"(用户从会话列表按 ESC 进入), 因此不再提供
# "附着/恢复"动作 -- 附着只能针对列表中明确选中的会话执行, 不作为独立菜单项。
# 会话为空时隐藏"删除"行(它只对真实选中的会话生效, 空列表无意义)。
# 防呆语序 (2026-10-30): 安全高频动作置顶, 高危动作垫底 --
#   PSTui 默认 Focus='Table' 且无行级配色, 行序本身就是唯一的"防误触"层次:
#   第 0 行(默认焦点 + Enter 直达)必须是创建这种可逆动作, 删除只出现在最后一行。

function Get-GridViewManagerRow {
    <#
    .SYNOPSIS
        构造 tmux 全局操作菜单的 GridView 表格行。

    .DESCRIPTION
        因 PSTui 无行级配色, 删除动作的危险语义改由 State 列的 ⚠ 符号表达,
        并且真正的二次确认由 Remove-TmuxSession 用 Read-SpectreConfirm 阻断。
        方案 A: "附着/恢复"不再是菜单项, 只能从会话列表中选中会话执行;
        会话为空时隐藏"删除"行, 只保留 创建 / 刷新 / 直连。
        防呆语序: 创建置顶(默认焦点), 删除垫底(仅最后一行)。

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
    # State 对齐 (2026-10-30): 三类非删除动作补齐同构的「符号 + 两个汉字」中性徽章,
    # 与 '⚠ 危险' 等宽对齐, 消除表格右侧整列空洞; 删除行垫底。
    $rows = [System.Collections.Generic.List[PSCustomObject]]::new()
    # 第 0 行 = 默认焦点 = Enter 直达, 必须是最安全的常用动作
    $rows.Add([PSCustomObject]@{
            Action   = '创建新 tmux 会话'
            State    = '✓ 推荐'
            Disabled = $false
            Value    = 'New'
        })
    $rows.Add([PSCustomObject]@{
            Action   = '刷新会话列表'
            State    = '⟳ 手动'
            Disabled = $false
            Value    = 'Refresh'
        })
    $rows.Add([PSCustomObject]@{
            Action   = '直接 SSH 登录'
            State    = Format-GridViewStateText -Text '⚠ 备选' -ColorKey 'Warning'
            Disabled = $false
            Value    = 'Ssh'
        })
    if ($HasSessions) {
        # 2026-10-19 P0: 删 Desc 列(与 Action 重复, 释放 ~16 字宽度)
        # 高危动作垫底: 只在有会话时追加在最后一行, 连按 Enter 也碰不到它
        $rows.Add([PSCustomObject]@{
                Action   = '删除 tmux 会话'
                State    = Format-GridViewStateText -Text '⚠ 危险' -ColorKey 'Danger'
                Disabled = $false
                Value    = 'Remove'
            })
    }

    return $rows.ToArray()
}
