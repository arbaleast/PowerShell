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

function ConvertTo-TmuxTuiViewModel {
    <#
    .SYNOPSIS
        把 Get-TmuxSessionState 的状态对象转换为 TGUI 仪表盘视图模型。

    .DESCRIPTION
        输出(PSCustomObject):
          .Mode          'Session' (有会话) / 'Empty' (确实无会话) / 'Error' (探测失败)
          .SessionRows   PSCustomObject 数组: {No=[int], Session=[string],
                         Status=['Attached'|'Detached'], Windows=[int], Name=[string]};
                         空态/错误态恒为空数组 —— 不伪造占位行进表格。
          .Counts        {Total, Attached, Detached}
          .ErrorCode / .ErrorMessage / .Hint   仅 Mode='Error' 非空
          .SelectedSession                    上轮选中且本轮幸存的会话名(保留选中用),
                                              未保留时为 $null

    .PARAMETER State
        Get-TmuxSessionState 的返回值(Status/Sessions/ErrorCode/...)

    .PARAMETER PreviousSelected
        上一轮选中的会话名(刷新后尽量保留选中)。

    .OUTPUTS
        [PSCustomObject] 视图模型(Mode/SessionRows/Counts/ErrorCode/ErrorMessage/Hint/SelectedSession)

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
        [string]$PreviousSelected = ''
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
        $rows.Add([PSCustomObject]@{
                No      = $no
                Session = [string]$s.Name
                Status  = $statusText
                Windows = $windows
                Name    = [string]$s.Name
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

    return [PSCustomObject]@{
        Mode            = $mode
        SessionRows     = $rows.ToArray()
        Counts          = $counts
        ErrorCode       = $errorCode
        ErrorMessage    = $errorMessage
        Hint            = $hint
        SelectedSession = $selected
    }
}
