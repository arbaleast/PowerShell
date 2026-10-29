# Get-TmuxSessionSummary.ps1 - tmux 会话列表的计数汇总(双轨共享)
#
# 背景: "附 N / 分 M" 计数此前由各调用方自行 Where-Object 统计, 标题格式也各写一份,
#       导致主菜单、会话列表、删除列表三处标题的计数口径可能不一致。
# 方案: 抽出本汇总函数, 统一产出 总数 / 已附着 / 已分离 与标题后缀。

function Get-TmuxSessionSummary {
    <#
    .SYNOPSIS
        汇总 tmux 会话列表的数量与标题后缀。

    .DESCRIPTION
        以 attached 判定"已附着", 其余计入"已分离", 两数相加恒等于总数。
        TitleSuffix 统一为 "会话 N 附 X / 分 Y", 供主菜单与会话列表标题共用。

    .PARAMETER Sessions
        会话数组(元素含 Name 与 Status, 来自 Get-TmuxSessions)

    .OUTPUTS
        PSCustomObject(.Total/.Attached/.Detached/.TitleSuffix)

    .EXAMPLE
        $summary = Get-TmuxSessionSummary -Sessions $sessions
        $summary.TitleSuffix
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '')]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [array]$Sessions
    )

    # 按 Status 分组计数: attached 组计入"已附着", 其余组计入"已分离"
    # (分组名比较沿用 PowerShell 默认的不区分大小写语义, 与旧的 -eq 'attached' 判定一致)
    $groups = @($Sessions | Where-Object { $null -ne $_ } | Group-Object -Property Status)

    $total = if ($groups.Count -gt 0) { [int](($groups | Measure-Object -Property Count -Sum).Sum) } else { 0 }
    $attachedSum = ($groups | Where-Object { $_.Name -eq 'attached' } | Measure-Object -Property Count -Sum).Sum
    $attached = if ($null -ne $attachedSum) { [int]$attachedSum } else { 0 }
    $detached = $total - $attached

    return [PSCustomObject]@{
        Total       = $total
        Attached    = $attached
        Detached    = $detached
        TitleSuffix = "会话 $total 附 $attached / 分 $detached"
    }
}
