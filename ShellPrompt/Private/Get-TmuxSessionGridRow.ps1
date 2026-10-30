# Get-TmuxSessionGridRow.ps1 - GridView 主轨的 tmux 会话表格行构造
# 职责: 把会话数组转换为 Out-ConsoleGridView 需要的行对象(会话行 + 可选刷新行)。
# 状态文案统一取自 Get-TmuxSessionStateText, 保证与其它渲染层完全一致。
# 方案 A (2026-10-29): 真实会话行补充 Windows 列(窗口数量), 数据来自
# Get-TmuxSessions 既有的 Name/Status/Windows 统一形状, 不新增远端调用。

function Get-TmuxSessionGridRow {
    <#
    .SYNOPSIS
        构造 GridView 主轨的 tmux 会话表格行集合。

    .DESCRIPTION
        跨模块解耦点: 表格列(No/Session/State/Windows/Status/Disabled/Value)
        由本函数唯一决定, Invoke-GridViewPrompt 依赖 Session 列作为唯一键列,
        因此 Session 值必须唯一。
        Windows 列为 tmux 会话的窗口数量, 直接取 Get-TmuxSessions 产出的
        .Windows 字段; 来源对象缺该字段(旧调用方手工构造的测试对象等)时置空。
        状态文案统一取自 Get-TmuxSessionStateText, 与其它渲染层完全一致。
        刷新行的 Value 使用哨兵值 $script:TmuxRefreshSignalValue, 上层据此重新拉取会话。

    .PARAMETER Sessions
        会话数组(元素含 Name 与 Status, 可含 Windows)

    .PARAMETER ShowStateBadge
        是否在 State 列显示 attached/detached 文本(删除场景可关掉以突出危险语义)

    .PARAMETER AllowRefresh
        是否追加"⟳ 刷新会话列表"行

    .OUTPUTS
        PSCustomObject 数组(No/Session/State/Windows/Status/Disabled/Value)

    .EXAMPLE
        $rows = Get-TmuxSessionGridRow -Sessions $sessions -AllowRefresh
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
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
        # Windows 字段缺失时置空而非猜测 0/1, 避免把不存在的数据伪装成"1 个窗口"
        $windows = $null
        if ($null -ne $s.PSObject.Properties['Windows'] -and $null -ne $s.Windows) {
            $windows = [string]$s.Windows
        }
        $rows.Add([PSCustomObject]@{
                No       = $index.ToString().PadLeft(2, '0')
                Session  = [string]$s.Name
                State    = $stateText
                Windows  = $windows
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
                Windows  = ''
                Status   = ''
                Disabled = $false
                Value    = $script:TmuxRefreshSignalValue
            })
    }

    return $rows.ToArray()
}
