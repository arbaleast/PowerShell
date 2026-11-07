# ConvertTo-TmuxTuiViewModel.ps1 - TGUI 仪表盘的**UI 数据模型**(纯函数, 阶段 A)
#
# 背景 (2026-10-30 TGUI 迁移 · 阶段 A):
#   Terminal.Gui v2 与 PowerShell 业务层之间需要一层可 Pester 全量覆盖的
#   视图模型转换 —— 会话行 / 统计计数 / 空态与错误态分型, 全部在这里一次
#   形成, UI 构建层(Get-TmuxTuiDashboardWindow)只负责把模型挂到视图上。
#
# 严格对应 Goal 三-1/3-2/3-4:
#   - 顶部状态区的统计: 会话总数 / Attached / Detached;
#   - 中间表格行: #(序号) / SESSION / STATUS / WINDOWS, Value 缺席防伪造;
#   - 空状态与错误状态分型: Mode = Session / Empty / Error, 错误态携带
#     ErrorCode/ErrorMessage/Hint —— 错误码与长错误文本**不进表格行**。
#
# 契约: 纯函数, 不触碰控制台和网络; 行序稳定(输入序即输出序)。
#
# 数据层扩展 (2026-11 TUI 右侧详情面板):
#   会话行额外携带"渲染右侧面板所需的全部信息", 且**不允许**在渲染时再发网络请求:
#     .Created / .Activity   相对时间文本(来自同一次 SSH 的 session_created/activity)
#     .CreatedEpoch / .ActivityEpoch  原始 unix 时间戳(0 = 未知)
#     .WindowList             该会话的窗口拓扑数组(元素形状见下方 .DESCRIPTION)
#     .PreviewLines           该会话的预览快照(纯文本, 已剥 ANSI, 最多 8 行)
#     .PaneCount              该会话的窗口分屏总数(用于 'Windows : 3 (4p)' 显示)
#   旧数据(没有这些字段的会话对象)**必须优雅降级**: Created/Activity = 'N/A',
#   WindowList/PreviewLines = 空数组, PaneCount = 0, 且绝不抛异常。

function ConvertTo-TmuxTuiViewModel {
    <#
    .SYNOPSIS
        把 Get-TmuxSessionState 的状态对象转换为 TGUI 仪表盘视图模型。

    .DESCRIPTION
        输出(PSCustomObject):
          .Mode          'Session' (有会话) / 'Empty' (确实无会话) / 'Error' (探测失败)
          .SessionRows   PSCustomObject 数组: {No=[int], Session=[string],
                         Status=['Attached'|'Detached'], Windows=[int], Name=[string],
                         Created=[string], Activity=[string],
                         CreatedEpoch=[long], ActivityEpoch=[long],
                         WindowList=[object[]], PreviewLines=[string[]], PaneCount=[int]};
                         空态/错误态恒为空数组 —— 不伪造占位行进表格。
          .Counts        {Total, Attached, Detached}
          .ErrorCode / .ErrorMessage / .Hint   仅 Mode='Error' 非空
          .SelectedSession                    上轮选中且本轮幸存的会话名(保留选中用),
                                              未保留时为 $null

    .PARAMETER State
        Get-TmuxSessionState 的返回值(Status/Sessions/ErrorCode/...)

    .PARAMETER PreviousSelected
        上一轮选中的会话名(刷新后尽量保留选中)。

    .PARAMETER HomePath
        远端用户 HOME 目录(可选)。用于把 pane_current_path 折叠成 '~/...'。
        缺省时优先取会话对象自带的 HomePath; 两者都没有则走"剥掉 /home/<name> 或
        /Users/<name> 段"的兜底启发式(见 ConvertTo-TmuxShortPath)。

    .OUTPUTS
        [PSCustomObject] 视图模型(Mode/SessionRows/Counts/ErrorCode/ErrorMessage/Hint/SelectedSession)

    .NOTES
        会话行里 .WindowList 的元素形状:
          {Index=[int], Name=[string], Active=[bool], Panes=[int],
           Command=[string], Path=[string], PathShort=[string]}
        PathShort 是 Path 的 '~' 折叠结果, 供窄面板直接显示。

    .EXAMPLE
        $vm = ConvertTo-TmuxTuiViewModel -State (Get-TmuxSessionState -SessionData $raw)
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$State,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$PreviousSelected = '',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$HomePath = ''
    )

    $sessions = @()
    if ($State -and $State.Sessions) {
        $sessions = @($State.Sessions | Where-Object { $null -ne $_ })
    }

    $mode = if ($State) { [string]$State.Status } else { 'Error' }
    # Status 由 Get-TmuxSessionState 保证为 Ok/Empty/Error —— 归一到这里
    $mode = switch ($mode) {
        'Ok'    { 'Session' }
        'Empty' { 'Empty' }
        default { 'Error' }
    }

    # ---- 会话行: 列设计 #(序号)/SESSION/STATUS/WINDOWS ----
    $rows = [System.Collections.Generic.List[PSCustomObject]]::new()
    $no = 0
    foreach ($s in $sessions) {
        $no++
        $statusText = if ([string]$s.Status -eq 'attached') { 'Attached' } else { 'Detached' }
        # Windows 数: try 语句不能当表达式用, 先算再进哈希表仓库的 parse 坑
        $windows = 0
        try { $windows = [int]$s.Windows } catch { $windows = 0 }

        # ---- 相对时间(2026-11): 老数据无时间戳时显示 'N/A', 绝不显示假时间 ----
        $createdEpoch = 0
        $activityEpoch = 0
        if ($null -ne $s.Created) { try { $createdEpoch = [long]$s.Created } catch { $createdEpoch = 0 } }
        if ($null -ne $s.Activity) { try { $activityEpoch = [long]$s.Activity } catch { $activityEpoch = 0 } }
        $createdText = ConvertTo-TmuxRelativeTime -Epoch $createdEpoch
        # 挂着的会话"此刻就有活动", 'Active now' 比一个具体分钟数更有信息量
        $activityText = if ([string]$s.Status -eq 'attached') { 'Active now' } else { ConvertTo-TmuxRelativeTime -Epoch $activityEpoch }

        # ---- 窗口拓扑 + 预览快照(2026-11): 全部来自同一次 SSH, 渲染期零网络 ----
        $homeDir = $HomePath
        if (-not $homeDir -and $null -ne $s.HomePath) { $homeDir = [string]$s.HomePath }
        $windowList = [System.Collections.Generic.List[PSCustomObject]]::new()
        $paneTotal = 0
        if ($null -ne $s.WindowList) {
            foreach ($w in @($s.WindowList | Where-Object { $null -ne $_ })) {
                $panes = 0
                try { $panes = [int]$w.Panes } catch { $panes = 0 }
                $paneTotal += $panes
                $wIndex = 0
                try { $wIndex = [int]$w.Index } catch { $wIndex = 0 }
                $path = ''
                if ($null -ne $w.Path) { $path = [string]$w.Path }
                $windowList.Add([PSCustomObject]@{
                        Index     = $wIndex
                        Name      = if ($null -ne $w.Name) { [string]$w.Name } else { '' }
                        Active    = [bool]$w.Active
                        Panes     = $panes
                        Command   = if ($null -ne $w.Command) { [string]$w.Command } else { '' }
                        Path      = $path
                        PathShort = (ConvertTo-TmuxShortPath -Path $path -HomePath $homeDir)
                    }) | Out-Null
            }
        }
        # 旧数据没有分屏信息时用窗口个数兜底, 避免显示 '0p'
        if ($paneTotal -eq 0) { $paneTotal = $windows }

        $previewLines = @()
        if ($null -ne $s.PreviewLines) {
            $previewLines = @($s.PreviewLines | Where-Object { $null -ne $_ } |
                    ForEach-Object { ConvertTo-TmuxPlainText -Text ([string]$_) })
        }

        $rows.Add([PSCustomObject]@{
                No            = $no
                Session       = [string]$s.Name
                Status        = $statusText
                Windows       = $windows
                Name          = [string]$s.Name
                Created       = $createdText
                Activity      = $activityText
                CreatedEpoch  = $createdEpoch
                ActivityEpoch = $activityEpoch
                WindowList    = $windowList.ToArray()
                PreviewLines  = $previewLines
                PaneCount     = $paneTotal
            }) | Out-Null
    }

    # ---- 统计: 会话总数 / Attached / Detached(顶部状态区) ----
    $attached = @($sessions | Where-Object { [string]$_.Status -eq 'attached' }).Count
    $counts = [PSCustomObject]@{
        Total    = $sessions.Count
        Attached = $attached
        Detached = $sessions.Count - $attached
    }

    # ---- 错误态只走独立区域, 不进表格行 ----
    $errorCode = ''
    $errorMessage = ''
    $hint = ''
    if ($mode -eq 'Error') {
        if ($State) {
            $errorCode = [string]$State.ErrorCode
            $errorMessage = [string]$State.ErrorMessage
            $hint = [string]$State.Hint
        }
        # $null/空兜底: 与 Get-TmuxErrorCode($null)->E_UNKNOWN 契约一致,
        # State.Status 缺失时(直接传原始 hashtable 老测试兼容)也走这里
        if ([string]::IsNullOrEmpty($errorCode)) {
            $errorCode = & { Get-TmuxErrorCode -SessionData $State }
        }
        if ([string]::IsNullOrEmpty($errorMessage)) {
            $errorMessage = '未能获取 tmux 会话列表'
        }
    }

    # ---- 提示行文案(Empty/Error): 由动作定义驱动(2026-10-31 UI 升级) ----
    # 此前 Empty 态提示写死 "n 新建会话 / r 刷新 / s 直连", 与底部快捷键栏的
    # Context='Normal' 文案(刷新 / SSH)不一致; 现以 Get-TmuxActionDefinition
    # 为唯一事实来源按上下文拼装(键位语义与键值完全不变, 只改展示文案来源),
    # 空态/错误态与快捷键栏的语境从此天然一致; $null 兜底错误态同样有指引。
    # 文案形如 "n 新建 · r 刷新 · s 直连" —— 与底部快捷键栏逐项同形, 居中一行
    # 就能读出"现在能按什么键", 不必在两处维护两套说法。
    if ($mode -in @('Empty', 'Error')) {
        $context = if ($mode -eq 'Error') { 'Error' } else { 'Normal' }
        $keys = if ($mode -eq 'Error') { @('r', 's') } else { @('n', 'r', 's') }
        $definitions = @(Get-TmuxActionDefinition -HasSessions $false -Context $context)
        $hintParts = foreach ($key in $keys) {
            $def = @($definitions | Where-Object { $_.Key -eq $key })[0]
            if ($null -ne $def) { "$($def.Key) $($def.Label)" }
        }
        if ($hintParts) { $hint = $hintParts -join ' · ' }
    }

    # ---- 刷新后尽量保留原选中 ----
    $selected = $null
    if ($PreviousSelected) {
        $match = @($rows | Where-Object { $_.Name -eq $PreviousSelected })
        if ($match.Count -gt 0) { $selected = $PreviousSelected }
    }

    # ---- 会话详情(并行结构): 右侧面板专用, 与 SessionRows 一一对应 ----
    # 为什么另起一个结构而不是把窗口数组塞进 SessionRows.Windows:
    #   SessionRows.Windows 是**窗口数(int)**, 是表格列 'WINDOWS' 的既有契约
    #   (老测试断言它是 int), 不能改成数组。因此详情字段放在平行的
    #   SessionDetails 里, 右面板按下标/名字对齐即可, 两边语义互不污染。
    $details = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($row in $rows) {
        $details.Add([PSCustomObject]@{
                No            = $row.No
                Name          = $row.Name
                Session       = $row.Session
                Status        = $row.Status
                Created       = $row.Created
                Activity      = $row.Activity
                CreatedEpoch  = $row.CreatedEpoch
                ActivityEpoch = $row.ActivityEpoch
                Windows       = $row.WindowList      # 窗口拓扑数组(元素: Index/Name/Active/Panes/Command/Path/PathShort)
                WindowList    = $row.WindowList      # 同上, 别名, 便于按名字取
                WindowCount   = $row.Windows          # 窗口数(int)
                PreviewLines  = $row.PreviewLines
                PaneCount     = $row.PaneCount
            }) | Out-Null
    }

    return [PSCustomObject]@{
        Mode            = $mode
        SessionRows     = $rows.ToArray()
        SessionDetails  = $details.ToArray()
        Counts          = $counts
        ErrorCode       = $errorCode
        ErrorMessage    = $errorMessage
        Hint            = $hint
        SelectedSession = $selected
    }
}
