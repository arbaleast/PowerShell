# Get-TmuxSessionGridRow.ps1 - GridView 主轨的 tmux 会话表格行构造
# 职责: 把会话数组转换为 Out-ConsoleGridView 需要的行对象(会话行 + 可选刷新行)。
# 状态文案统一取自 Get-TmuxSessionStateText, 保证与其它渲染层完全一致。

function Get-TmuxSessionGridRow {
    <#
    .SYNOPSIS
        构造 GridView 主轨的 tmux 会话表格行集合。

    .DESCRIPTION
        跨模块解耦点: 表格列(No/Session/State/Status/Disabled/Value)由本函数唯一决定,
        Invoke-GridViewPrompt 依赖 Session 列作为唯一键列, 因此 Session 值必须唯一。
        状态文案统一取自 Get-TmuxSessionStateText, 与其它渲染层完全一致。
        刷新行的 Value 使用哨兵值 $script:TmuxRefreshSignalValue, 上层据此重新拉取会话。

    .PARAMETER Sessions
        会话数组(元素含 Name 与 Status)

    .PARAMETER ShowStateBadge
        是否在 State 列显示 attached/detached 文本(删除场景可关掉以突出危险语义)

    .PARAMETER AllowRefresh
        是否追加"⟳ 刷新会话列表"行

    .OUTPUTS
        PSCustomObject 数组(No/Session/State/Status/Disabled/Value)

    .EXAMPLE
        $rows = Get-TmuxSessionGridRow -Sessions $sessions -AllowRefresh
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '')]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$Sessions,

        [Parameter(Mandatory = $false)]
        [switch]$ShowStateBadge,

        [Parameter(Mandatory = $false)]
        [switch]$AllowRefresh
    )

    $rows = [System.Collections.Generic.List[PSCustomObject]]::new($Sessions.Count + 1)
    $index = 0
    foreach ($s in $Sessions) {
        $index++
        $status = [string]$s.Status
        $stateText = if (-not $ShowStateBadge) { '' } else { Get-TmuxSessionStateText -Status $status }
        $rows.Add([PSCustomObject]@{
                No       = $index.ToString().PadLeft(2, '0')
                Session  = [string]$s.Name
                State    = $stateText
                Status   = $status
                Disabled = $false
                Value    = [string]$s.Name
            })
    }

    if ($AllowRefresh) {
        # 用户触发的刷新项: Value 用哨兵值, 上层据此重新拉取会话并原地重绘
        # P1.4: State 文案统一取自 Get-TmuxSessionStateText -IsRefresh, 避免与
        # 普通会话行的 ●/○ 徽章漂移。
        $rows.Add([PSCustomObject]@{
                No       = ''
                Session  = '⟳ 刷新会话列表'
                State    = Get-TmuxSessionStateText -IsRefresh
                Status   = ''
                Disabled = $false
                Value    = $script:TmuxRefreshSignalValue
            })
    }

    return $rows.ToArray()
}
