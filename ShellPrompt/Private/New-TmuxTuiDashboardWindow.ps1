# New-TmuxTuiDashboardWindow.ps1 - TGUI 仪表盘**整窗组装**(阶段 B 视图层)
#
# 背景 (2026-10-30 TGUI 迁移 · 阶段 B):
#   Goal 三: Window = 顶部状态区(产品标题/SSH 主机/连接状态/会话统计)
#     + 中间会话表格(New-TmuxTuiSessionTable)
#     + 底部 StatusBar(Shortcut 列表, New-TmuxTuiShortcutList)
#     + 空态/错误态独立 Label 区(不放表格行)。
#   Terminal.Gui 全部布局/绘制/缩放, 本函数是"组装层"。
#
# 2.4.10 实测 API(反射探针 .agent_cache/tgui-probe/REPORT.md):
#   Window: View.Add(View) / X/Y(=Pos) / Width/Height(=Dim) / BorderStyle(可置 $null)
#   Pos 静态工厂: Pos.Absolute(int) / Pos.AnchorEnd()
#   Dim 静态工厂: Dim.Fill() / Dim.Absolute(int)
#   Label: Text 可写
#   StatusBar: ctor(IEnumerable<Shortcut>)
#   TableView: 无 SelectedRow; 选中位置读 `Value.SelectedCell`(Point) 的 .Y
#
# 几何不变量(Goal 三-5, 由 New-TmuxTuiLayoutPlan 一次算出):
#   Window.BorderStyle = $null 时, Window 内容区 == 整个 Frame, 绝对坐标 == 屏幕坐标。
#   行分配: 0 标题 / 1 统计 / 2 辅助(空态或错误) / 3..H-2 表格 / H-1 快捷键栏。
#   表格用**绝对高度**而不是 Dim.Fill —— Fill 必然与贴底的 StatusBar 重叠 1 行。
#
# 契约: 不进事件循环(无头可测), 不做业务分发 —— Shortcut.Action 才是分发点。

function New-TmuxTuiDashboardWindow {
    <#
    .SYNOPSIS
        按视图模型与会话表构建整窗仪表盘(无头可测, 不 Run)。

    .DESCRIPTION
        布局(绝对坐标, 由 New-TmuxTuiLayoutPlan 计算):
          行 0      标题: ShellPrompt TMUX Manager + 主机 + 连接状态
          行 1      统计: 会话总数/Attached/Detached
          行 2      辅助: 空态提示 或 错误码+原因+可执行操作(有会话时留空)
          行 3..H-2 会话表格(绝对高度, 不与快捷键栏重叠)
          行 H-1    底部快捷键栏(StatusBar, Pos.AnchorEnd())

        缩放: 终端尺寸变化时由编排层用新尺寸重建整窗(纯函数负责几何, 重建开销低)。

        返回 PSCustomObject: Window/Table/Source/StatusBar/Shortcuts/CountLabels/Layout。

    .PARAMETER ViewModel
        ConvertTo-TmuxTuiViewModel 的产物

    .PARAMETER HostName
        当前 SSH 主机名

    .PARAMETER ConnectionState
        连接状态文案(默认 '已连接'; 失败态可传 '连接失败')

    .PARAMETER HasSessions
        是否存在会话(决定快捷键悬停/禁用态)

    .PARAMETER Dispatch
        业务回调脚本块: 接收动作值(Attach/New/Refresh/Ssh/Remove/Quit)

    .PARAMETER WindowWidth
        终端宽度(默认 120)

    .PARAMETER WindowHeight
        终端高度(默认 35)

    .PARAMETER SelectedIndex
        初始选中行在表格中的行号(-1 = 不预选)。刷新后据此恢复选中。

    .OUTPUTS
        [PSCustomObject] Window/Table/Source/StatusBar/Shortcuts/CountLabels/Layout

    .EXAMPLE
        $win = New-TmuxTuiDashboardWindow -ViewModel $vm -HostName 'deb' -Dispatch { param($a) }
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$ViewModel,

        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $false)]
        [string]$ConnectionState = '已连接',

        [Parameter(Mandatory = $false)]
        [bool]$HasSessions = $false,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Dispatch,

        [Parameter(Mandatory = $false)]
        [ValidateRange(20, 1000)]
        [int]$WindowWidth = 120,

        [Parameter(Mandatory = $false)]
        [ValidateRange(6, 1000)]
        [int]$WindowHeight = 35,

        [Parameter(Mandatory = $false)]
        [int]$SelectedIndex = -1
    )

    if ($PSCmdlet.ShouldProcess('TGUI 仪表盘窗口', 'Construct')) { } else { return $null }

    $tg = Get-TguiContext

    # ---- 布局工厂: Pos/Dim 静态方法反射调用 ----
    # (GetMethod(name, flags) 会因重载发生 Ambiguous, 一律用方法过滤)
    $posType = $tg.Types.Pos
    $dimType = $tg.Types.Dim
    $factoryShared = [System.Reflection.BindingFlags]'Public,Static'
    $posAbsolute = $posType.GetMethods($factoryShared) |
        Where-Object { $_.Name -eq 'Absolute' -and $_.GetParameters().Count -eq 1 } |
        Select-Object -First 1
    $posAnchorEnd = $posType.GetMethods($factoryShared) |
        Where-Object { $_.Name -eq 'AnchorEnd' -and $_.GetParameters().Count -eq 0 } |
        Select-Object -First 1
    $dimAbsolute = $dimType.GetMethods($factoryShared) |
        Where-Object { $_.Name -eq 'Absolute' -and $_.GetParameters().Count -eq 1 } |
        Select-Object -First 1
    # Dim.Fill(Dim margin): 撑满内容区并**扣掉 margin** —— 实测(lead/p8.ps1):
    #   内容高 H、视图 Y=3 时, Fill() 给 Height=H-3, Fill(Absolute(1)) 给 H-4。
    #   这正是"表格 3..H-2 + 快捷键栏 H-1"的零重叠零空档解,
    #   且**随终端缩放自动重算**(绝对高度做不到)。
    $dimFill = $dimType.GetMethods($factoryShared) |
        Where-Object { $_.Name -eq 'Fill' -and $_.GetParameters().Count -eq 0 } |
        Select-Object -First 1
    $dimFillMargin = $dimType.GetMethods($factoryShared) |
        Where-Object {
            $_.Name -eq 'Fill' -and $_.GetParameters().Count -eq 1 -and
            $_.GetParameters()[0].ParameterType.Name -eq 'Dim'
        } |
        Select-Object -First 1

    # ---- 几何计划(纯函数): 行分配与列计划一次算出, 杜绝重叠 ----
    $layout = New-TmuxTuiLayoutPlan -Width $WindowWidth -Height $WindowHeight

    # ---- 整窗容器 (Window, 空构造) ----
    $window = [System.Activator]::CreateInstance($tg.Types.Window)
    # BorderStyle 置空: 有边框时 Window 内容区会被吃掉 2 行 2 列, 绝对坐标就与屏幕错位。
    $window.BorderStyle = $null

    # ---- 顶部状态区 (标题 / 统计 / 辅助) ----
    $labelType = $tg.Types.Label
    $lt1 = [System.Activator]::CreateInstance($labelType)
    $lt1.Text = "ShellPrompt TMUX Manager  |  主机: $HostName  |  $ConnectionState"
    $lt2 = [System.Activator]::CreateInstance($labelType)
    $lt2.Text = "会话: $($ViewModel.Counts.Total)  Attached: $($ViewModel.Counts.Attached)  Detached: $($ViewModel.Counts.Detached)"
    $lt3 = [System.Activator]::CreateInstance($labelType)
    if ($ViewModel.Mode -eq 'Error') {
        # 错误码与长错误文本**只进辅助行**, 不塞进会话表格行
        $lt3.Text = "错误: $($ViewModel.ErrorCode)  $($ViewModel.ErrorMessage)  $($ViewModel.Hint)"
    }
    elseif ($ViewModel.Mode -eq 'Empty') {
        $lt3.Text = '远端当前没有 tmux 会话  (N 新建 / R 重试 / S 直连)'
    }
    else {
        $lt3.Text = ''
    }

    $labels = @($lt1, $lt2, $lt3)
    $labelRows = @($layout.TitleRow, $layout.StatsRow, $layout.HintRow)
    for ($i = 0; $i -lt $labels.Count; $i++) {
        $labels[$i].X = $posAbsolute.Invoke($null, @(0))
        $labels[$i].Y = $posAbsolute.Invoke($null, @($labelRows[$i]))
        $labels[$i].Width = $dimFill.Invoke($null, @())
        $labels[$i].Height = $dimAbsolute.Invoke($null, @(1))
    }

    # ---- 中间会话表格 (行 TableRow, 高度自适应且不压快捷键栏) ----
    $table = New-TmuxTuiSessionTable -ViewModel $ViewModel -ColumnPlan $layout.Columns

    $table.Table.X = $posAbsolute.Invoke($null, @(0))
    $table.Table.Y = $posAbsolute.Invoke($null, @($layout.TableRow))
    $table.Table.Width = $dimFill.Invoke($null, @())
    # 高度 = 内容高 - Y偏移(3) - 1 = H-4 => 行 3..H-2; 快捷键栏贴 H-1, 零重叠零空档
    $table.Table.Height = $dimFillMargin.Invoke($null, @($dimAbsolute.Invoke($null, @(1))))

    # ---- 初始选中行(刷新后保留选中): TableView 无 SelectedRow, 用 Value.SelectedCell ----
    $rowCount = 0
    if ($ViewModel.SessionRows) { $rowCount = @($ViewModel.SessionRows).Count }
    if ($SelectedIndex -ge 0 -and $SelectedIndex -lt $rowCount) {
        try {
            $selectionType = $tg.Types.TableSelection
            $point = [System.Drawing.Point]::new(0, $SelectedIndex)
            $selection = [System.Activator]::CreateInstance($selectionType, @($point))
            $table.Table.Value = $selection
        } catch {
            # 预选失败不致命: 表格仍可正常显示, 只是初始光标在第一行
            Write-Verbose "[New-TmuxTuiDashboardWindow] 预选行失败: $($_.Exception.Message)"
        }
    }

    # ---- 底部快捷键栏 (StatusBar, Y=AnchorEnd) ----
    $shortcuts = New-TmuxTuiShortcutList -HasSessions $HasSessions -Dispatch $Dispatch
    # StatusBar ctor 挂 IEnumerable<Shortcut>: PowerShell 的 .NET 绑定在
    # `..Invoke()` 里遇到 List 时**展开成 Shortcut 元素**(实测:
    # "Shortcut 不能转 IEnumerable<Shortcut>" 的根因) —— 必须用
    # **[object[]]::CreateInstance 建的外层 object[1]** 承载强类型
    # List[Shortcut], 让 Invoke 的 args 数组第一元素 = List 本体。
    $shortcutType = $shortcuts[0].GetType()
    $listType = [System.Collections.Generic.List`1].MakeGenericType($shortcutType)
    $typedList = [System.Activator]::CreateInstance($listType)
    for ($i = 0; $i -lt $shortcuts.Count; $i++) {
        $typedList.Add($shortcuts[$i])
    }
    $barCtor = $tg.Types.StatusBar.GetConstructors() |
        Where-Object {
            $p = $_.GetParameters()
            $p.Count -eq 1 -and $p[0].ParameterType.Name -eq 'IEnumerable`1'
        } |
        Select-Object -First 1
    # Invoke 参数数组必须 [object[]]::CreateInstance 建(@() 会按可枚举展开)
    $invokeArgs = [object[]]::CreateInstance([System.Object], 1)
    $invokeArgs[0] = $typedList
    $statusBar = $barCtor.Invoke($invokeArgs)
    $statusBar.Y = $posAnchorEnd.Invoke($null, @())
    $statusBar.X = $posAbsolute.Invoke($null, @(0))
    $statusBar.Width = $dimFill.Invoke($null, @())
    $statusBar.Height = $dimAbsolute.Invoke($null, @(1))

    # ---- 组装 ----
    if ($null -eq $window) {
        throw 'TGUI 组装失败: window 为 $null(异常路径)'
    }
    foreach ($view in @($lt1, $lt2, $lt3, $table.Table, $statusBar)) {
        [void]$window.Add($view)
    }

    # ---- 主题配色 + 方案绑定(2026-10-30 真机验收补修) ----
    # 真机现象: 仪表盘只剩边框、内容全无。根因(探针 p51 实测):
    #   TG 内置 'Base' 方案 Normal = fg(255,255,255) bg(255,255,255) —— **白对白**,
    #   文字与背景同色 ⇒ 完全隐形; 'ansi' 驱动不做终端颜色探测, Base 永远白对白。
    #   (2026-10-30 起 PSTui 默认加载上下文配色轨已删除, 配色只剩 ALC 原生的
    #   Set-TguiTheme 一条路径; 任何经 Add-Type 载入的 Terminal.Gui 副本与
    #   本 ALC 类型身份互不兼容, 不允许再引入。)
    # 另: 同名类型跨程序集(Add-Type 默认上下文 vs 本 ALC)互不兼容 ——
    #   跨程序集赋值抛 "Cannot convert ... Scheme to ... Scheme"。
    #   故必须用 ALC 原生的 Set-TguiTheme(同配置、同幂等契约)覆写槽位。
    # 绑定策略: 主体(窗口/状态行/表格)取 'Base', 快捷键栏取 'Menu'
    #   —— 与仓库配色契约一致(表格主体取 Base, 底部状态栏取 Menu);
    #   且绑定前用 Test-TguiSchemeVisible 过滤"前景=背景"的不可见方案。
    try {
        [void](Set-TguiTheme -Tgui $tg)
    } catch {
        Write-Verbose "[New-TmuxTuiDashboardWindow] ALC 主题配色失败(继续 TG 默认): $($_.Exception.Message)"
    }
    $bodyScheme = Resolve-TguiScheme -Tgui $tg -Names @('Base', 'Menu', 'Dialog')
    $barScheme = Resolve-TguiScheme -Tgui $tg -Names @('Menu', 'Base', 'Dialog')
    foreach ($view in @($window, $lt1, $lt2, $lt3, $table.Table)) {
        if ($null -eq $bodyScheme) { continue }
        try {
            [void]$view.SetScheme($bodyScheme)
        } catch {
            Write-Verbose "[New-TmuxTuiDashboardWindow] 子视图 SetScheme 失败: $($_.Exception.Message)"
        }
    }
    if ($null -ne $barScheme) {
        try {
            [void]$statusBar.SetScheme($barScheme)
        } catch {
            Write-Verbose "[New-TmuxTuiDashboardWindow] 快捷键栏 SetScheme 失败: $($_.Exception.Message)"
        }
    }

    return [PSCustomObject]@{
        Window      = $window
        Table       = $table.Table
        Source      = $table.Source
        StatusBar   = $statusBar
        Shortcuts   = $shortcuts
        CountLabels = @($lt1, $lt2, $lt3)
        Layout      = $layout
    }
}
