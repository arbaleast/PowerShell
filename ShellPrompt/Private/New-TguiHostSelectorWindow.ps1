# New-TguiHostSelectorWindow.ps1 - SSH 主机选择器的 **Terminal.Gui v2 整窗组装**(视图层)
#
# 背景 (2026-10-30 PSTui 移除 · 主机选择器迁移):
#   原 GridView 轨(PSTui Out-ConsoleGridView)删除后, SSH 主机选择器改由
#   ALC 原生 Terminal.Gui v2 承接, 与 sss 仪表盘共用同一套"组装层 + 编排层"
#   拆分(New-TguiHostSelectorWindow 只组装不进事件循环; Run 由调用方驱动)。
#
# 布局(全屏 Window, BorderStyle=$null, 绝对坐标 == 屏幕坐标):
#   行 0      标题 Label
#   行 1      过滤输入: Label '搜索: ' + TextField(初始焦点, 打字即过滤)
#   行 2..H-2 主机表格(TableView, 列 HOST / STATE)
#   行 H-1    提示 Label(Y=AnchorEnd)
#
# 2.4.10 实测 API(反射探针 p70-hostsel / 复用仪表盘轨既有事实):
#   TextField: Terminal.Gui.Views.TextField, 无参 ctor, Text 可写,
#     事件 TextChanged 存在; TableView 的 Source **构造后不可替换**
#     (无 SetSource/可写 Source 属性) ⇒ 过滤采用"TextChanged → RequestStop
#     → 编排层重建整窗"路径(与缩放重建同一条路), 不做来源热替换。
#   TableView 无 SelectedRow —— 选中读 `Value.SelectedCell`(Point).Y。
#   Esc: 应用级键表默认已绑定 Esc -> Quit(重复登记抛异常), 取消走内建路径;
#     Enter: 应用级 Shortcut(BindKeyToApplication=$true, Command=NotBound),
#     TextField 聚焦时恰好收到 1 次(先视图 Accepting、后 app 级)。
#   Shift/Terminal 中文宽度由 Wcwidth 处理(grapheme 感知, 探针实测)。
#
# 契约: 不进事件循环(无头可测), 不读配置/不拉业务数据 —— 输入行/过滤文本
# 均由编排层传入; 配色降级不阻断(与仪表盘同策略)。

function New-TguiHostSelectorWindow {
    <#
    .SYNOPSIS
        按过滤后的主机行构建主机选择器整窗(无头可测, 不 Run)。

    .DESCRIPTION
        布局: 行0 标题 / 行1 '搜索: '+TextField / 行2..H-2 主机表格 /
        行H-1 提示。初始选中行由 SelectedIndex 指定(过滤后行号)。

        返回 PSCustomObject: Window/Table/Source/FilterField/StatusBar/Shortcuts。

    .PARAMETER Title
        标题行文本(含主机数/weather 后缀, 由调用方拼接)。

    .PARAMETER Rows
        当前过滤态下的行数据(Get-HostSelectorRow 产物的过滤子集)。

    .PARAMETER Filter
        当前过滤文本(回填 TextField, 跨重建保持)。

    .PARAMETER WindowWidth
        终端宽度(默认 120)。

    .PARAMETER WindowHeight
        终端高度(默认 35)。

    .PARAMETER SelectedIndex
        初始选中行在 Rows 中的下标(-1 = 不预选)。

    .PARAMETER Dispatch
        动作回调: 接收 'Select'(Enter 确认)。Esc 取消走 TG 内建 Quit, 不经本回调。

    .OUTPUTS
        [PSCustomObject] Window/Table/Source/FilterField/StatusBar/Shortcuts

    .EXAMPLE
        $win = New-TguiHostSelectorWindow -Title '主机' -Rows $rows -Dispatch { param($a) }
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '')]
    # WindowWidth/WindowHeight 由编排层传入做入参校验; 布局本身用 Dim.Fill
    # 自适应(与仪表盘同策略), 两参数不直接进入几何, 显式抑制 PSSA 误报。
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'WindowWidth')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'WindowHeight')]
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Rows,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Filter = '',

        [Parameter(Mandatory = $false)]
        [ValidateRange(20, 1000)]
        [int]$WindowWidth = 120,

        [Parameter(Mandatory = $false)]
        [ValidateRange(6, 1000)]
        [int]$WindowHeight = 35,

        [Parameter(Mandatory = $false)]
        [int]$SelectedIndex = -1,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Dispatch
    )

    if ($PSCmdlet.ShouldProcess('TGUI 主机选择器窗口', 'Construct')) { } else { return $null }

    $tg = Get-TguiContext

    # ---- 布局工厂(与仪表盘同套路: 方法过滤, 不用 GetMethod(name) 直取重载) ----
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
    $dimFill = $dimType.GetMethods($factoryShared) |
        Where-Object { $_.Name -eq 'Fill' -and $_.GetParameters().Count -eq 0 } |
        Select-Object -First 1
    $dimFillMargin = $dimType.GetMethods($factoryShared) |
        Where-Object {
            $_.Name -eq 'Fill' -and $_.GetParameters().Count -eq 1 -and
            $_.GetParameters()[0].ParameterType.Name -eq 'Dim'
        } |
        Select-Object -First 1

    # ---- 整窗容器 (Window, 无边框) ----
    $window = [System.Activator]::CreateInstance($tg.Types.Window)
    $window.BorderStyle = $null

    # ---- 行 0: 标题 ----
    $labelType = $tg.Types.Label
    $ltTitle = [System.Activator]::CreateInstance($labelType)
    $ltTitle.Text = $Title

    # ---- 行 1: 过滤输入(初始打字目标) ----
    $ltPrompt = [System.Activator]::CreateInstance($labelType)
    $ltPrompt.Text = '搜索: '
    $filterType = $tg.Assembly.GetExportedTypes() |
        Where-Object { $_.FullName -eq 'Terminal.Gui.Views.TextField' } |
        Select-Object -First 1
    if ($null -eq $filterType) {
        throw 'TGUI 载入失败: 缺少 Terminal.Gui.Views.TextField。vendored 版本可能已变更。'
    }
    $field = [System.Activator]::CreateInstance($filterType)
    $field.Text = $Filter
    $field.CanFocus = $true

    # ---- 行 2..H-2: 主机表格 ----
    $columnDict = [System.Collections.Generic.Dictionary[ [string], [System.Func[ [object], [object] ] ] ]]::new()
    $columnDict['HOST']  = [System.Func[[object],[object]]]{ param($r) $r.Host }
    $columnDict['STATE'] = [System.Func[[object],[object]]]{ param($r) $r.State }

    $rowsForSource = [object[]]@($Rows)
    $sourceType = $tg.Assembly.GetExportedTypes() |
        Where-Object { $_.FullName -match '^Terminal.Gui.Views.EnumerableTableSource' } |
        Select-Object -First 1
    $genericSource = $sourceType.MakeGenericType([object])
    $sourceCtor = $genericSource.GetConstructors() |
        Where-Object {
            $p = $_.GetParameters()
            $p.Count -eq 2 -and $p[1].ParameterType.Name -in @('Dictionary`2', 'IDictionary`2')
        } |
        Select-Object -First 1
    if ($null -eq $sourceCtor) {
        throw 'TGUI EnumerableTableSource 构造器形状已变(期望 2 参: 行集合 + 列字典)'
    }
    $source = $sourceCtor.Invoke(@($rowsForSource, $columnDict))

    $tableCtor = $tg.Types.TableView.GetConstructors() |
        Where-Object {
            $p = $_.GetParameters()
            $p.Count -eq 1 -and $p[0].ParameterType.Name -eq 'ITableSource'
        } |
        Select-Object -First 1
    $table = $tableCtor.Invoke(@($source))
    # 摘掉 CollectionNavigator 字母 type-ahead(与仪表盘同根因: 吞字母键,
    # 且过滤开在 TextField, type-ahead 无意义)
    $table.CollectionNavigator = $null

    # ---- 行 H-1: 提示条 ----
    $ltHint = [System.Activator]::CreateInstance($labelType)
    $ltHint.Text = '↑↓ 选择 · Enter 确认 · Esc 取消 · Tab 切焦点'

    # ---- 几何装配(绝对坐标, 行分配见文件头) ----
    $ltTitle.X = $posAbsolute.Invoke($null, @(0))
    $ltTitle.Y = $posAbsolute.Invoke($null, @(0))
    $ltTitle.Width = $dimFill.Invoke($null, @())
    $ltTitle.Height = $dimAbsolute.Invoke($null, @(1))

    $ltPrompt.X = $posAbsolute.Invoke($null, @(0))
    $ltPrompt.Y = $posAbsolute.Invoke($null, @(1))
    $ltPrompt.Width = $dimAbsolute.Invoke($null, @(6))
    $ltPrompt.Height = $dimAbsolute.Invoke($null, @(1))

    $field.X = $posAbsolute.Invoke($null, @(6))
    $field.Y = $posAbsolute.Invoke($null, @(1))
    $field.Width = $dimFill.Invoke($null, @())
    $field.Height = $dimAbsolute.Invoke($null, @(1))

    $table.X = $posAbsolute.Invoke($null, @(0))
    $table.Y = $posAbsolute.Invoke($null, @(2))
    $table.Width = $dimFill.Invoke($null, @())
    $table.Height = $dimFillMargin.Invoke($null, @($dimAbsolute.Invoke($null, @(1))))

    $ltHint.X = $posAbsolute.Invoke($null, @(0))
    $ltHint.Y = $posAnchorEnd.Invoke($null, @())
    $ltHint.Width = $dimFill.Invoke($null, @())
    $ltHint.Height = $dimAbsolute.Invoke($null, @(1))

    # ---- 底栏 Shortcut: Enter 确认(应用级), Esc 仅展示(取消走 TG 内建 Quit) ----
    # 复用 New-TmuxTuiShortcutList 实测过的 Shortcut 装配契约: 4 参 ctor,
    # Command=NotBound, BindKeyToApplication=$true(BindApp), 空-helpText,
    # Title=纯标签(防"键 标签"双渲染)。动作值内联 + Dispatch 挂 global
    # (TG 事件循环换 runtime 会话, 闭包局部不可见 —— 既有实测结论)。
    $keyType = $tg.Types.Key
    $shortcutType = $tg.Types.Shortcut
    $shortcutCtor = $shortcutType.GetConstructors() |
        Where-Object { $_.GetParameters().Count -eq 4 } |
        Select-Object -First 1
    if ($null -eq $shortcutCtor) {
        throw 'TGUI 载入失败: Shortcut 缺少 (Key,commandText,Action,helpText) 四参构造。'
    }

    $global:TguiHostSelActionDispatch = $Dispatch
    $global:TguiHostSelWindowRef = $window
    $enterCode = '& $global:TguiHostSelActionDispatch ''Select'''
    $enterDelegate = [System.Action]([scriptblock]::Create($enterCode))
    $enterKey = $keyType.GetProperty('Enter').GetValue($null)
    $enterShortcut = [System.Activator]::CreateInstance(
        $shortcutType, @($enterKey, '确认', $enterDelegate, ''))
    $enterShortcut.Command = [Enum]::Parse($tg.Types.Command, 'NotBound')
    $enterShortcut.BindKeyToApplication = $true

    $escKey = $keyType.GetProperty('Esc').GetValue($null)
    $noOpDelegate = [System.Action]([scriptblock]::Create(''))
    $escShortcut = [System.Activator]::CreateInstance(
        $shortcutType, @($escKey, '取消', $noOpDelegate, ''))
    $escShortcut.Command = [Enum]::Parse($tg.Types.Command, 'NotBound')
    # Esc 不登记应用级键表: 应用级已有 Esc->Quit, 重复 AddApp 抛异常(实测)
    $escShortcut.BindKeyToApplication = $false

    # StatusBar ctor(IEnumerable<Shortcut>): Invoke 遇 List 会展开成元素 ——
    # 必须用 [object[]]::CreateInstance 建外层 object[1] 承载强类型 List。
    $shortcutTypeOf = $enterShortcut.GetType()
    $listType = [System.Collections.Generic.List`1].MakeGenericType($shortcutTypeOf)
    $typedList = [System.Activator]::CreateInstance($listType)
    foreach ($sc in @($escShortcut, $enterShortcut)) { $typedList.Add($sc) }
    $barCtor = $tg.Types.StatusBar.GetConstructors() |
        Where-Object {
            $p = $_.GetParameters()
            $p.Count -eq 1 -and $p[0].ParameterType.Name -eq 'IEnumerable`1'
        } |
        Select-Object -First 1
    $invokeArgs = [object[]]::CreateInstance([System.Object], 1)
    $invokeArgs[0] = $typedList
    $statusBar = $barCtor.Invoke($invokeArgs)
    $statusBar.Y = $posAnchorEnd.Invoke($null, @())
    $statusBar.X = $posAbsolute.Invoke($null, @(0))
    $statusBar.Width = $dimFill.Invoke($null, @())
    $statusBar.Height = $dimAbsolute.Invoke($null, @(1))

    # ---- 组装 ----
    foreach ($view in @($ltTitle, $ltPrompt, $field, $table, $ltHint, $statusBar)) {
        [void]$window.Add($view)
    }

    # ---- 初始选中行 ----
    if ($SelectedIndex -ge 0 -and $SelectedIndex -lt @($Rows).Count) {
        try {
            $point = [System.Drawing.Point]::new(0, $SelectedIndex)
            $selection = [System.Activator]::CreateInstance($tg.Types.TableSelection, @($point))
            $table.Value = $selection
        } catch {
            Write-Verbose "[New-TguiHostSelectorWindow] 预选行失败: $($_.Exception.Message)"
        }
    }

    # ---- 主题配色 + 方案绑定(策略与仪表盘一致) ----
    try {
        [void](Set-TguiTheme -Tgui $tg)
    } catch {
        Write-Verbose "[New-TguiHostSelectorWindow] ALC 主题配色失败(继续 TG 默认): $($_.Exception.Message)"
    }
    $bodyScheme = Resolve-TguiScheme -Tgui $tg -Names @('Base', 'Menu', 'Dialog')
    $barScheme = Resolve-TguiScheme -Tgui $tg -Names @('Menu', 'Base', 'Dialog')
    foreach ($view in @($window, $ltTitle, $ltPrompt, $field, $table, $ltHint)) {
        if ($null -eq $bodyScheme) { continue }
        try {
            [void]$view.SetScheme($bodyScheme)
        } catch {
            Write-Verbose "[New-TguiHostSelectorWindow] 子视图 SetScheme 失败: $($_.Exception.Message)"
        }
    }
    if ($null -ne $barScheme) {
        try {
            [void]$statusBar.SetScheme($barScheme)
        } catch {
            Write-Verbose "[New-TguiHostSelectorWindow] 底栏 SetScheme 失败: $($_.Exception.Message)"
        }
    }

    return [PSCustomObject]@{
        Window      = $window
        Table       = $table
        Source      = $source
        FilterField = $field
        StatusBar   = $statusBar
        Shortcuts   = @($escShortcut, $enterShortcut)
    }
}
