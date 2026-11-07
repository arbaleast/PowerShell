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
#   行分配: 0 标题 / 1 统计 / 2 辅助(空态或错误) / 3..H-2 主体 / H-1 快捷键栏。
#   主体用**绝对高度**而不是 Dim.Fill —— Fill 必然与贴底的 StatusBar 重叠 1 行。
#
# ★ 2026-11-06 阶段一(视觉层级与工作区布局重构):
#   真机取证暴露的缺陷与本文件的修复:
#     1. 顶部统计无重点 -> 统计行拆成 5 片, Attached 段在 Attached>0 时亮绿;
#     2. 标题带三段挤成一行同色 -> 拆成品牌(亮青)/ 主机(灰)/ 状态徽标(绿红);
#     3. 双重竖线 + 大空框 -> 右侧改无外框三段式工作区, 全窗只剩一条竖线;
#     4. 宽屏左侧固定 64 列 -> 分栏比例改由 New-TmuxTuiLayoutPlan 按断点算出。
#   详见 New-TmuxTuiLayoutPlan.ps1 的分栏断点表与
#   New-TmuxTuiSessionDetailPanel.ps1 的三段式结构说明。
#
# 契约: 不进事件循环(无头可测), 不做业务分发 —— Shortcut.Action 才是分发点。

function Get-TmuxTuiDetailRow {
    <#
    .SYNOPSIS
        取出指定会话的**完整**视图行(基础字段 + 详情字段合并, 纯函数)。

    .DESCRIPTION
        #9b871512: ViewModel 把数据分成两半 ——
          - SessionRows[i]   : 列表用的基础字段(No/Session/Status/Windows(int)/Name)
          - SessionDetails[i]: 详情字段(Created/Activity/WindowList/PreviewLines/
                               PaneCount)
        原因: SessionRows.Windows 是**窗口数(int)**, 是列表列 'WINDOWS' 的既有
        契约(老测试断言它是 int), 不能改成数组; 详情另放平行结构, 两边语义
        互不污染。

        右栏驾驶舱需要**两者都有**, 所以这里按下标合并成一个对象返回。
        合并是**纯内存**操作 —— 切换会话时零网络、零延迟(护栏 2)。

        向后兼容: ViewModel 没有 SessionDetails 时(老 Mock), 只返回基础行,
        详情字段缺失 -> 右栏优雅降级为 'N/A'(护栏: 不崩)。

    .PARAMETER ViewModel
        ConvertTo-TmuxTuiViewModel 的产物。

    .PARAMETER Index
        会话下标(-1 或越界 => 返回 $null)。

    .OUTPUTS
        [PSCustomObject] 合并后的会话行; 越界时 $null。

    .EXAMPLE
        $row = Get-TmuxTuiDetailRow -ViewModel $vm -Index 0
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$ViewModel,

        [Parameter(Mandatory = $false)]
        [int]$Index = -1
    )

    if ($null -eq $ViewModel) { return $null }
    $rows = @($ViewModel.SessionRows)
    if ($Index -lt 0 -or $Index -ge $rows.Count) { return $null }

    $base = $rows[$Index]
    $merged = [ordered]@{}
    foreach ($p in $base.PSObject.Properties) { $merged[$p.Name] = $p.Value }

    # 详情字段: 有 SessionDetails 就按下标合并, 没有就留空(右栏降级)
    $details = @()
    if ($null -ne $ViewModel.PSObject.Properties['SessionDetails']) {
        $details = @($ViewModel.SessionDetails)
    }
    if ($Index -lt $details.Count) {
        $detail = $details[$Index]
        if ($null -ne $detail) {
            foreach ($p in $detail.PSObject.Properties) {
                # SessionRows.Windows 是 int(窗口数), SessionDetails.Windows 是
                # 数组(拓扑) —— 名字冲突时**不覆盖**基础行的 int,
                # 拓扑另用 WindowList 取(两个名字都指向同一数组)。
                if ($p.Name -eq 'Windows' -and $merged.Contains('Windows')) { continue }
                $merged[$p.Name] = $p.Value
            }
        }
    }

    return [PSCustomObject]$merged
}

function New-TmuxTuiDashboardWindow {
    <#
    .SYNOPSIS
        按视图模型与会话表构建整窗仪表盘(无头可测, 不 Run)。

    .DESCRIPTION
        布局(绝对坐标, 由 New-TmuxTuiLayoutPlan 计算):
          行 0      标题带(阶段一: **三片**不重叠 Label)
                    左 = 品牌(亮青, 'ShellPrompt / TMUX MANAGER')
                    中 = 主机(灰, '· 主机 <HostName>')
                    右 = 连接状态徽标(右对齐; '● 已连接' 绿 / '○ 未连接' 红)
          行 1      统计(阶段一: **五片**不重叠 Label)
                    会话总数 / · / Attached(Attached>0 时亮绿) / · / Detached
          行 2      状态标题: 空态提示 或 错误码+原因(有会话时留空)
          行 3..H-2 主体: 左=会话列表 | 单条竖线 | 右=三段式会话工作区
                    空态/错误态改为**居中**的可执行指引(列表/工作区隐藏)
          行 H-1    底部快捷键栏(StatusBar, Pos.AnchorEnd())

        分栏断点(阶段一, 全部由 New-TmuxTuiLayoutPlan 算出):
          < 72 列    : 单栏(只显示列表, 右侧工作区整体隐藏)
          72 - 99 列 : 列表 42% / 工作区 58%
          100-139 列 : 列表 40% / 工作区 60%
          >= 140 列  : 列表封顶 50~54 列, 剩余全给右侧工作区

        缩放: 终端尺寸变化时由编排层用新尺寸重建整窗(纯函数负责几何, 重建开销低)。

        返回 PSCustomObject: Window/Table/Source/StatusBar/Shortcuts/CountLabels/
        StatsLabels/BrandLabel/HostLabel/StateLabel/GuidanceLabel/
        ShowSessionTable/ShowDetail/Layout。

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

    .PARAMETER Context
        渲染上下文文案档位: Normal(默认)/Error —— 只切换提示行与快捷键栏
        的**文案**(错误态 r=重试 s=直连), 键位与动作值不变。

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
    # 全局变量用途: TG 事件循环回调会换 runtime 会话, 闭包局部变量不可见,
    #   因此 KeyDown 处理器与既有 PendingAction 走同一条 global 载荷通路。
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'eventSource', Justification = 'TG 事件处理器固定签名 (sender, key); sender 本层用不到')]
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
        [ValidateSet('Normal', 'Error')]
        [string]$Context = 'Normal',

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

    # ---- 几何计划(纯函数): 行分配与列计划一次算出, 杜绝重叠 ----
    $layout = New-TmuxTuiLayoutPlan -Width $WindowWidth -Height $WindowHeight

    # ---- 整窗容器 (Window, 空构造) ----
    $window = [System.Activator]::CreateInstance($tg.Types.Window)
    # BorderStyle 置空: 有边框时 Window 内容区会被吃掉 2 行 2 列, 绝对坐标就与屏幕错位。
    $window.BorderStyle = $null

    # ---- 顶部状态区 (标题带 / 统计 / 辅助) ----
    $labelType = $tg.Types.Label
    $alignEnum = $labelType.GetProperty('TextAlignment').PropertyType
    $isErrorState = ($ViewModel.Mode -eq 'Error')

    # ---- 标题带(2026-10-31 UI 层次升级 / 2026-11-06 阶段一配色重构):
    #      左=品牌标识+主机, 右=连接状态徽标 ----
    # 之前标题/主机/连接状态挤在同一行同一个 Label 里:
    #   - 三者同色同字号, 没有任何层次(真机取证: 整行一个 SGR 属性);
    #   - 窄终端(40 列)整行被截断, **连接状态直接看不见**(用户无法判断是否连上)。
    # 现拆成两个不重叠的 Label: 左半产品标识(按可用宽度取长/中/短形态),
    # 右半连接状态(右对齐), 两者宽度由"状态文案宽"反推, 标题永不挤掉状态。
    #
    # ★ #9b871512 Forest Matrix: 顶栏改成"品牌 + 主机 + 会话计数"三段。
    #   品牌  ShellPrompt TMUX   Cyan(BrightCyan)
    #   主机  Host: debian       White
    #   计数  Sessions: 3 (1 Attached)  —— Attached > 0 时计数段亮绿
    #   连接  ● 已连接 / ○ 未连接  —— 绿/红, "符号 + 颜色"双重表达
    #
    # $ConnectionState 是编排层传进来的**状态文案**(默认 '已连接';
    # 失败态可传 '连接失败'), 它决定徽标是绿是红 —— 文案本身仍按
    # "符号 + 状态词"统一成形, 不再直接透传任意字符串(否则符号会丢)。
    $isConnected = (-not $isErrorState) -and ([string]$ConnectionState -ne '连接失败')
    $stateText = if ($isConnected) { '● 已连接' } else { '○ 未连接' }

    # 会话计数段(右侧, 紧挨连接徽标): "Sessions: 3 (1 Attached)"
    $attachedCount = [int]$ViewModel.Counts.Attached
    $totalCount = [int]$ViewModel.Counts.Total
    $countsText = "Sessions: $totalCount ($attachedCount Attached)"
    $countsWidth = (Get-TguiTextWidth -Text $countsText) + 2

    $stateWidth = (Get-TguiTextWidth -Text $stateText) + 2   # +2 = 右侧留白
    $rightWidth = $stateWidth + $countsWidth
    $leftWidth = $WindowWidth - $rightWidth
    if ($leftWidth -lt 0) {
        # 窄终端: 计数段先让位(连接状态更重要), 再让位品牌
        $countsWidth = 0
        $rightWidth = $stateWidth
        $leftWidth = $WindowWidth - $rightWidth
        if ($leftWidth -lt 0) { $leftWidth = 0 }
    }

    # 品牌段: "ShellPrompt TMUX" (Cyan) / 主机段: "Host: debian" (White)
    $brandText = if ($leftWidth -ge 30) { 'ShellPrompt TMUX' }
    elseif ($leftWidth -ge 16) { 'ShellPrompt' }
    else { 'sss' }
    $brandWidth = (Get-TguiTextWidth -Text $brandText) + 1
    if ($brandWidth -gt $leftWidth) { $brandWidth = $leftWidth }

    $hostText = ''
    if ($leftWidth -gt $brandWidth + 1) {
        $hostTail = "Host: $HostName"
        $hostBudget = $leftWidth - $brandWidth - 1
        $hostText = Get-SshHostListClip -Text $hostTail -Width $hostBudget
    }

    $lt1 = [System.Activator]::CreateInstance($labelType)
    $lt1.Text = $brandText
    $lt1.X = $posAbsolute.Invoke($null, @(0))
    $lt1.Y = $posAbsolute.Invoke($null, @($layout.TitleRow))
    $lt1.Width = $dimAbsolute.Invoke($null, @([Math]::Max(1, $brandWidth)))
    $lt1.Height = $dimAbsolute.Invoke($null, @(1))

    # 主机段: 与品牌段不重叠, 紧跟其后(阶段一新增的第三片)
    $lt6 = [System.Activator]::CreateInstance($labelType)
    $lt6.Text = $hostText
    $lt6.X = $posAbsolute.Invoke($null, @([Math]::Max(0, $brandWidth)))
    $lt6.Y = $posAbsolute.Invoke($null, @($layout.TitleRow))
    $lt6.Width = $dimAbsolute.Invoke($null, @([Math]::Max(1, $leftWidth - $brandWidth)))
    $lt6.Height = $dimAbsolute.Invoke($null, @(1))

    $lt4 = [System.Activator]::CreateInstance($labelType)
    $lt4.Text = $stateText
    $lt4.X = $posAbsolute.Invoke($null, @($leftWidth))
    $lt4.Y = $posAbsolute.Invoke($null, @($layout.TitleRow))
    $lt4.Width = $dimAbsolute.Invoke($null, @($stateWidth))
    $lt4.Height = $dimAbsolute.Invoke($null, @(1))
    $lt4.TextAlignment = [Enum]::Parse($alignEnum, 'End')

    # 会话计数段(#9b871512): 位于连接徽标左侧, 右对齐。
    # 窄终端放不下时整段隐藏(Width=0 => 不渲染)。
    $lt7 = [System.Activator]::CreateInstance($labelType)
    $lt7.Text = $countsText
    $lt7.X = $posAbsolute.Invoke($null, @([Math]::Max(0, $leftWidth - $countsWidth)))
    $lt7.Y = $posAbsolute.Invoke($null, @($layout.TitleRow))
    $lt7.Width = $dimAbsolute.Invoke($null, @([Math]::Max(1, $countsWidth)))
    $lt7.Height = $dimAbsolute.Invoke($null, @(1))
    $lt7.TextAlignment = [Enum]::Parse($alignEnum, 'End')

    $lt3 = [System.Activator]::CreateInstance($labelType)
    if ($isErrorState) {
        # 错误码与长错误文本**只进辅助行**, 不塞进会话表格行
        $lt3.Text = "连接失败 · $($ViewModel.ErrorCode) · $($ViewModel.ErrorMessage)"
    }
    elseif ($ViewModel.Mode -eq 'Empty') {
        $lt3.Text = '远端当前没有 tmux 会话'
    }
    else {
        $lt3.Text = ''
    }

    # ---- 统计行(阶段一 · 联动高亮) ----
    # 旧实现: "会话: N · Attached: N · Detached: N" 挤在**一个** Label 里,
    #   整行同色, 没有任何重点 —— 而左侧列表里 Attached 的会话是**亮绿**的,
    #   顶部统计却一点提示都没有, 两处没有视觉呼应。
    # 新实现: 拆成 4 片不重叠的 Label:
    #   [会话: N] [·] [Attached: N(亮绿)] [·] [Detached: N(暗灰)]
    #   Attached > 0 时该段显式高亮为亮绿, 与列表里的绿点/绿字形成联动。
    $totalText = "会话: $($ViewModel.Counts.Total)"
    $attachedText = "Attached: $($ViewModel.Counts.Attached)"
    $detachedText = "Detached: $($ViewModel.Counts.Detached)"
    $sepText = '·'

    $statsTotal = [System.Activator]::CreateInstance($labelType)
    $statsTotal.Text = $totalText
    $statsAttached = [System.Activator]::CreateInstance($labelType)
    $statsAttached.Text = $attachedText
    $statsDetached = [System.Activator]::CreateInstance($labelType)
    $statsDetached.Text = $detachedText
    $statsSep1 = [System.Activator]::CreateInstance($labelType)
    $statsSep1.Text = $sepText
    $statsSep2 = [System.Activator]::CreateInstance($labelType)
    $statsSep2.Text = $sepText

    $statsWidths = @(
        [PSCustomObject]@{ Label = $statsTotal;    Text = $totalText }
        [PSCustomObject]@{ Label = $statsSep1;     Text = $sepText }
        [PSCustomObject]@{ Label = $statsAttached; Text = $attachedText }
        [PSCustomObject]@{ Label = $statsSep2;     Text = $sepText }
        [PSCustomObject]@{ Label = $statsDetached; Text = $detachedText }
    )
    $statsX = 0
    foreach ($seg in $statsWidths) {
        $segWidth = (Get-TguiTextWidth -Text $seg.Text) + 1
        if ($statsX + $segWidth -gt $WindowWidth) { $segWidth = [Math]::Max(1, $WindowWidth - $statsX) }
        $seg.Label.X = $posAbsolute.Invoke($null, @($statsX))
        $seg.Label.Y = $posAbsolute.Invoke($null, @($layout.StatsRow))
        $seg.Label.Width = $dimAbsolute.Invoke($null, @([Math]::Max(1, $segWidth)))
        $seg.Label.Height = $dimAbsolute.Invoke($null, @(1))
        $statsX += $segWidth
        if ($statsX -ge $WindowWidth) { break }
    }

    # lt3 占满宽度(辅助行, 与统计行不同行, 不存在遮挡)
    $lt3.X = $posAbsolute.Invoke($null, @(0))
    $lt3.Y = $posAbsolute.Invoke($null, @($layout.HintRow))
    $lt3.Width = $dimFill.Invoke($null, @())
    $lt3.Height = $dimAbsolute.Invoke($null, @(1))

    # ---- 主体区居中指引(仅空态/错误态): 取代"空表格框"的破损观感 ----
    # 旧实现在空态/错误态仍画出表格边框 + 表头却没有数据行, 看起来像渲染坏了;
    # 现在隐藏表格, 主体区改为**居中**的一行可执行指引(文案来自动作定义)。
    $lt5 = [System.Activator]::CreateInstance($labelType)
    $lt5.Text = if ($ViewModel.Mode -eq 'Session') { '' } else { [string]$ViewModel.Hint }
    $guidanceRow = $layout.TableRow + [int][Math]::Floor(($layout.TableHeight - 1) / 2)
    if ($guidanceRow -lt $layout.TableRow) { $guidanceRow = $layout.TableRow }
    $lt5.X = $posAbsolute.Invoke($null, @(0))
    $lt5.Y = $posAbsolute.Invoke($null, @($guidanceRow))
    $lt5.Width = $dimFill.Invoke($null, @())
    $lt5.Height = $dimAbsolute.Invoke($null, @(1))
    $lt5.TextAlignment = [Enum]::Parse($alignEnum, 'Center')

    # ---- 中间主体区: 左=会话列表(自定义行) | 竖线 | 右=会话详情卡 ----
    # 2026-10-31: 原实现用 TG TableView 渲染会话表 —— TableView 每次选中变化
    # 都把**整张表**标脏(实测 1760 单元格), 是"上下键 100~200ms 延迟"的
    # 同一个根因(与 SSH 主机列表一致)。现改为自定义行列表: 移动选中只重刷
    # 旧/新两行; 并在右侧加会话详情卡, 建立"列表 <-> 详情"的信息层级。
    $theme = Get-TuiDashboardTheme -Tgui $tg

    # 分栏几何(2026-11-06 阶段一): **统一由 New-TmuxTuiLayoutPlan 算出**。
    # 旧实现在本文件里另算了一套(72 列起双栏 / 55% / >=100 列固定 64 列),
    # 与布局计划脱节, 造成"宽屏列表固定 64 列, 会话名与右侧状态跨度过大"。
    # 新断点(见 New-TmuxTuiLayoutPlan):
    #   < 72 列  : 单栏(只显示列表, 右侧工作区整体隐藏)
    #   72-99    : 列表 42% / 工作区 58%
    #   100-139  : 列表 40% / 工作区 60%
    #   >= 140   : 列表封顶 50~54 列, 剩余全给右侧工作区
    # 竖线只有**一条**(右侧工作区不再有 FrameView 外框), 竖线与工作区之间留 2 列呼吸间距。
    $showDetail = ($layout.SplitMode -eq 'Dual')
    $listWidth = $layout.ListWidth
    $dividerX = $layout.DividerX
    $detailX = $layout.DetailX
    $detailWidth = $layout.DetailWidth

    $sessionList = New-TmuxTuiSessionRowList -Rows @($ViewModel.SessionRows) -Width $listWidth `
        -Height $layout.TableHeight -SelectedIndex $SelectedIndex -Theme $theme -Tgui $tg
    $sessionList.View.X = $posAbsolute.Invoke($null, @(0))
    $sessionList.View.Y = $posAbsolute.Invoke($null, @($layout.TableRow))

    # ---- 竖向分隔线(只做视觉分区, 不参与焦点/键盘) ----
    # 全窗**唯一**的竖线: 旧实现左侧列表自带竖线 + 右侧 FrameView 边框, 双线并行。
    $divider = $null
    if ($dividerX -ge 0 -and $layout.TableHeight -gt 0) {
        $divider = [System.Activator]::CreateInstance($labelType)
        $divider.Text = (@([string][char]0x2502) * $layout.TableHeight) -join "`n"
        $divider.X = $posAbsolute.Invoke($null, @($dividerX))
        $divider.Y = $posAbsolute.Invoke($null, @($layout.TableRow))
        $divider.Width = $dimAbsolute.Invoke($null, @(1))
        $divider.Height = $dimAbsolute.Invoke($null, @($layout.TableHeight))
        # 分隔线也显式给方案(暗灰细线), 避免"没有 Scheme 的视图"在暗底上隐形
        [void]$divider.SetScheme($theme.Divider)
    }

    # ---- 右侧「会话工作区」(三段式, 无外框) ----
    $detailPanel = $null
    if ($showDetail) {
        $detailPanel = New-TmuxTuiSessionDetailPanel -Width $detailWidth -Height $layout.TableHeight `
            -HostName $HostName -Theme $theme -Tgui $tg
        $detailPanel.View.X = $posAbsolute.Invoke($null, @($detailX))
        $detailPanel.View.Y = $posAbsolute.Invoke($null, @($layout.TableRow))
        # 初始落位: 选中会话的真实字段(没有选中就全部 '—')
        $initialRow = Get-TmuxTuiDetailRow -ViewModel $ViewModel -Index $SelectedIndex
        Set-TmuxTuiSessionDetail -Panel $detailPanel -Row $initialRow
    }

    # ---- 方向键 + 取消兜底: 挂在**列表容器**上(窗口自洽, 不依赖编排层) ----
    # ★ 为什么必须放在窗口层而不是编排层(2026-10-31):
    #   TableView 自带方向键处理(改选中就整块重绘 —— 延迟根因), 换成自定义
    #   行列表后方向键必须由我们自己实现; 若只挂在编排层, **直接驱动这个窗口**
    #   的调用方(测试 / 未来的别的编排器)就收不到方向键, 表现为"界面出来了
    #   但 ↑↓ 没反应"。因此键位语义随窗口走, 编排层只读回选中结果。
    #
    #   载荷走 global: TG 事件循环回调会换 runtime 会话, 闭包局部变量不可见
    #   (与既有 PendingAction 同一条通路)。
    $global:TguiSessionList = $sessionList
    $global:TguiSessionDetail = $detailPanel
    # ViewModel 引用: 方向键切换会话时, 右栏驾驶舱要按它取**详情行**
    # (相对时间/窗口拓扑/预览快照都已预转换好 —— 切换是纯内存操作, 零网络)。
    $global:TguiSessionViewModel = $ViewModel
    $sessionList.View.add_KeyDown({
            param($eventSource, $key)
            try {
                if ($null -eq $key) { return }

                # ---- 取消双保险(2026-10-31 真机修复) ----
                # 真机取证(Diag-TguiKeys): Esc/Ctrl+C 到达焦点视图, 但 2.4.10
                # 应用级命令绑定在视图处理**之后**才轮到, 视图消费了 Esc 就永远
                # 到不了 Quit; Ctrl+C 在 TG 无 Quit 绑定。按"取消必须随时可达"
                # 契约在视图处理之前兜底: 直接置 Quit + RequestStop(幂等, 与
                # TG 内建 Esc->Quit 双路径重入无害)。
                if (Test-TguiQuitKey -Key $key) {
                    $global:TguiPendingAction = 'Quit'
                    if ($global:TguiWindowRef -and $global:TguiRequestStopMethod) {
                        $stopArgs = [object[]]::CreateInstance([System.Object], 1)
                        $stopArgs[0] = $global:TguiWindowRef
                        [void]$global:TguiRequestStopMethod.Invoke($null, $stopArgs)
                    }
                    return
                }

                # ---- 方向键: 上下移动选中(只重刷旧/新两行) ----
                # 语义与 TableView 一致: 到边界夹取、不循环。
                # Enter / n / r / s / x / q 仍由底部快捷键栏的 Shortcut 接管
                # (应用级键表), 因此这里**不消费** Enter。
                $code = [string]$key.KeyCode
                $delta = 0
                if ($code -eq 'CursorUp') { $delta = -1 }
                elseif ($code -eq 'CursorDown') { $delta = 1 }
                if ($delta -eq 0) { return }

                $list = $global:TguiSessionList
                if ($null -eq $list) { return }
                if (-not (Move-TmuxTuiSessionSelection -ListView $list -Delta $delta)) { return }

                # 选中行必须可见(2026-11 审计修复): 选中行移出可视区时必须滚动,
                # 否则 Update-TmuxTuiSessionSelection 会跳过越界槽位 —— 屏幕上
                # 没有任何一行处于选中态, 而右侧详情卡却已切到新会话(界面自相矛盾)。
                # 与 SSH 主机仪表盘的 Sync-SshHostDashboardScroll 同构。
                [void](Sync-TmuxTuiSessionScroll -ListView $list)

                # 选中行变了 -> 右侧驾驶舱同步(纯内存, **零网络** —— 护栏 2)
                # 详情行从 ViewModel 的平行数组里取(已预转换好相对时间/
                # 路径/窗口拓扑/预览快照), 这里只做文本更新, 不发请求。
                $panel = $global:TguiSessionDetail
                if ($null -ne $panel) {
                    $vmRef = $global:TguiSessionViewModel
                    $idx = [int]$list.SelectedIndex
                    $row = $null
                    if ($null -ne $vmRef) {
                        $row = Get-TmuxTuiDetailRow -ViewModel $vmRef -Index $idx
                    }
                    else {
                        # 兜底: 没有 ViewModel 引用时只用基础行(字段降级为 N/A)
                        $rows = @($list.Rows)
                        if ($idx -ge 0 -and $idx -lt $rows.Count) { $row = $rows[$idx] }
                    }
                    Set-TmuxTuiSessionDetail -Panel $panel -Row $row
                }
            }
            catch {
                Write-Verbose "[New-TmuxTuiDashboardWindow] 列表 KeyDown 处理失败: $($_.Exception.Message)"
            }
        })

    # ---- 空态/错误态: 隐藏列表(不再画"空框 + 表头 + 无数据行") ----
    # 真机取证(120x35 空态/错误态快照): 旧实现仍画出一个空表格框,
    # 看上去像渲染坏了而不是"没有会话"。现在列表隐藏, 主体区交给居中指引。
    $showSessionTable = ($ViewModel.Mode -eq 'Session')
    if (-not $showSessionTable) {
        try {
            $sessionList.View.Visible = $false
            if ($null -ne $divider) { $divider.Visible = $false }
            if ($null -ne $detailPanel) { $detailPanel.View.Visible = $false }
        }
        catch {
            Write-Verbose "[New-TmuxTuiDashboardWindow] 隐藏空态列表失败: $($_.Exception.Message)"
        }
    }

    # ---- 底部快捷键栏 (StatusBar, Y=AnchorEnd) ----
    # 传 WindowWidth: 响应式取舍(按可用列宽挑要显示的项, 见工厂注释);
    # Context 由编排层按状态传入(错误态文案换"重试/直连")。
    $shortcuts = New-TmuxTuiShortcutList -HasSessions $HasSessions -Dispatch $Dispatch `
        -WindowWidth $WindowWidth -Context $Context
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
    # 顺序 = 绘制顺序(后加的盖在上面): 标题带各片宽度不重叠, 不会互相遮挡。
    $bodyViews = [System.Collections.Generic.List[object]]::new()
    foreach ($v in @($lt1, $lt6, $lt7, $lt4, $lt3, $lt5, $sessionList.View)) { $bodyViews.Add($v) }
    foreach ($v in $statsWidths) { $bodyViews.Add($v.Label) }
    if ($null -ne $divider) { $bodyViews.Add($divider) }
    if ($null -ne $detailPanel) { $bodyViews.Add($detailPanel.View) }
    $bodyViews.Add($statusBar)
    foreach ($view in $bodyViews) {
        [void]$window.Add($view)
    }

    # ---- 主题配色 + 方案绑定(2026-10-30 真机验收补修; 2026-10-31 层次升级) ----
    # 真机现象: 仪表盘只剩边框、内容全无。根因(探针 p51 实测):
    #   TG 内置 'Base' 方案 Normal = fg(255,255,255) bg(255,255,255) —— **白对白**,
    #   文字与背景同色 ⇒ 完全隐形; 'ansi' 驱动不做终端颜色探测, Base 永远白对白。
    #   (2026-10-30 起 PSTui 默认加载上下文配色轨已删除, 配色只剩 ALC 原生的
    #   Set-TguiTheme 一条路径; 任何经 Add-Type 载入的 Terminal.Gui 副本与
    #   本 ALC 类型身份互不兼容, 不允许再引入。)
    # 另: 同名类型跨程序集(Add-Type 默认上下文 vs 本 ALC)互不兼容 ——
    #   跨程序集赋值抛 "Cannot convert ... Scheme to ... Scheme"。
    #   故必须用 ALC 原生的 Set-TguiTheme(同配置、同幂等契约)覆写槽位。
    # 绑定策略(2026-10-31 层次升级, 之前全部视图同绑 Base 无层次:
    #   PTY 取证里标题/表头/正文/底栏四者完全同色 —— 前/边缘没有色带):
    #   - 边缘带(强调色): **标题带** + **表头** 取 'Menu';
    #     主题 SchemeOverrides 给 Menu 的差异化槽位 —— Sky 字 + Surface0 底,
    #     与正文暗底分层; Menu.Focus 专供表头(与选中行的 Base.Focus 区分)。
    #   - 正文: 窗口/统计行/居中指引/表格/**底部快捷键栏**取 'Base';
    #   - 连接状态徽标: 成功取 'Dialog'(绿), 失败取 TG 内置 'Error'(红);
    #   - 空态/错误态标题: 空态取 'Menu'(与边缘带同色系), 错误态取 'Error';
    #   且绑定前用 Test-TguiSchemeVisible 过滤"前景=背景"的不可见方案。
    try {
        [void](Set-TguiTheme -Tgui $tg)
    } catch {
        Write-Verbose "[New-TmuxTuiDashboardWindow] ALC 主题配色失败(继续 TG 默认): $($_.Exception.Message)"
    }
    $bodyScheme = Resolve-TguiScheme -Tgui $tg -Names @('Base', 'Menu', 'Dialog')
    foreach ($view in @($window, $lt3, $lt5)) {
        if ($null -eq $bodyScheme) { continue }
        try {
            [void]$view.SetScheme($bodyScheme)
        } catch {
            Write-Verbose "[New-TmuxTuiDashboardWindow] 子视图 SetScheme 失败: $($_.Exception.Message)"
        }
    }
    # ---- #9b871512 Forest Matrix: 顶栏 / 统计行各段都走**语义 Scheme** ----
    # 全部 16 色直控(不依赖主题配置文件), "谁亮谁暗"是确定的:
    #   品牌 = BrightCyan(竹青), 主机 = White, 会话计数 = Gray,
    #   Attached 计数 = BrightGreen(状态联动), 其余统计 = DarkGray。
    try {
        [void]$lt1.SetScheme($theme.ForestBrand)
        [void]$lt6.SetScheme($theme.ForestHost)
        [void]$lt7.SetScheme($theme.ForestSummaryKey)
        [void]$statsTotal.SetScheme($theme.ForestName)
        [void]$statsSep1.SetScheme($theme.ForestFrame)
        [void]$statsSep2.SetScheme($theme.ForestFrame)
        [void]$statsDetached.SetScheme($theme.ForestDetached)
        # ★ 状态联动: Attached > 0 时该段显式高亮为亮绿, 与左侧列表里的
        #   绿点/绿字、右侧驾驶舱的绿徽标形成同一套视觉语言。
        if ($ViewModel.Counts.Attached -gt 0) {
            [void]$statsAttached.SetScheme($theme.ForestAttached)
        }
        else {
            [void]$statsAttached.SetScheme($theme.ForestDetached)
        }
    }
    catch {
        Write-Verbose "[New-TmuxTuiDashboardWindow] 品牌/统计行 SetScheme 失败: $($_.Exception.Message)"
    }
    # 底部快捷键栏取 **Base**: TG 的 StatusBar 用 HotNormal 画键名、Normal 画标签,
    # 于是"键名=Base.HotNormal(Sky 冰青)/ 标签=Base.Normal(亮白)" —— 键名跳出来、
    # 标签退后一步, 与标题带(Menu 冰青)、正文(亮白)构成同一套层次。
    # (绑 Menu 会让键名=Mocha绿(在 16 色终端里被量化成**亮黄**)且标签也变冰青,
    #  三个角色挤在同一色系里, 底栏反而比正文更抢眼。)
    if ($null -ne $bodyScheme) {
        try {
            [void]$statusBar.SetScheme($bodyScheme)
        } catch {
            Write-Verbose "[New-TmuxTuiDashboardWindow] 快捷键栏 SetScheme 失败: $($_.Exception.Message)"
        }
    }
    # ---- 连接状态徽标(标题带右半): 成功=亮绿, 失败=亮红 ----
    # 阶段一: 改用**语义 Scheme**(Attached 亮绿 / Offline 亮红), 不再依赖
    # TG 主题配置里的 'Dialog'/'Error' 槽位 —— "● 已连接" 的符号本身已能
    # 表达状态, 颜色只是加强, 两层都稳。
    if ($isConnected) {
        try { [void]$lt4.SetScheme($theme.ForestAttached) }
        catch { Write-Verbose "[New-TmuxTuiDashboardWindow] 状态徽标 SetScheme 失败: $($_.Exception.Message)" }
    }
    else {
        try { [void]$lt4.SetScheme($theme.Offline) }
        catch { Write-Verbose "[New-TmuxTuiDashboardWindow] 状态徽标 SetScheme 失败: $($_.Exception.Message)" }
    }
    # ---- 状态标题行(空态/错误态)方案绑定 ----
    # 只在有内容时换色: 有会话时留空, 绑 Base 恒定(行为不变)。
    if ($lt3.Text -and $lt3.Text.Length -gt 0) {
        $hintSchemeNames = @('Menu', 'Base', 'Dialog')
        if ($isErrorState) {
            # 错误态取 TG 内置 'Error' 方案(红字警示); 不可见时回退 Menu 边缘带
            $hintSchemeNames = @('Error', 'Menu', 'Base')
        }
        $hintScheme = Resolve-TguiScheme -Tgui $tg -Names $hintSchemeNames
        if ($null -ne $hintScheme) {
            try {
                [void]$lt3.SetScheme($hintScheme)
            } catch {
                Write-Verbose "[New-TmuxTuiDashboardWindow] 辅助行 SetScheme 失败: $($_.Exception.Message)"
            }
        }
    }

    return [PSCustomObject]@{
        Window      = $window
        # 2026-10-31: 会话表由 TG TableView 换成**自定义行列表** —— TableView
        #   每次选中变化都把整表标脏(1760 单元格), 是上下键延迟的根因。
        #   旧的 .Table / .Source 成员**保留**(指向同一容器 View), 以免
        #   外部/测试按旧形状取视图时拿到 $null。
        SessionList = $sessionList
        Table       = $sessionList.View
        Source      = $null
        DetailPanel = $detailPanel
        Divider     = $divider
        StatusBar   = $statusBar
        Shortcuts   = $shortcuts
        # 阶段一: 统计行拆成 5 片(总数/分隔/Attached/分隔/Detached),
        #   Attached 段在 Attached>0 时为亮绿(状态联动)。
        #   .StatsLabel 保留为"整行文本拼起来的视图"(旧调用方按 Text 取整行)。
        CountLabels = @($lt1, $lt3)
        StatsLabels = @($statsTotal, $statsSep1, $statsAttached, $statsSep2, $statsDetached)
        StatsLabel  = $statsAttached
        StatsAttachedLabel = $statsAttached
        BrandLabel  = $lt1
        HostLabel   = $lt6
        CountsLabel = $lt7
        # 2026-10-31 UI 升级新增: 标题带右半(连接状态徽标) 与 主体居中指引
        StateLabel     = $lt4
        GuidanceLabel  = $lt5
        ShowSessionTable = $showSessionTable
        ShowDetail       = $showDetail
        Layout      = $layout
    }
}
