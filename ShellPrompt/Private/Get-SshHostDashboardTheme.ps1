# Get-SshHostDashboardTheme.ps1 - **共享**语义 Theme(ALC 原生配色)
#
# 背景 (2026-10-31 sss 仪表盘重构):
#   两个仪表盘(SSH 主机仪表盘 / tmux 会话仪表盘)都需要按语义着色:
#     主色紫 · 在线绿 · 离线红 · 未知灰 · 次要文本深灰 · 选中行整行紫底。
#   旧实现把配色散落在各视图的 SetScheme 里(同名方案共用), 新界面需要"同一个
#   View 上同时出现多种角色色"(状态点绿 + 名称白 + 标签紫 + 时间灰), 因此本文件
#   统一构造一套**语义 Scheme** 供各视图直接 SetScheme。
#
#   ★ 本文件是**两个仪表盘共用**的一套主题(2026-10-31 tmux 侧并入):
#     函数名保留 Get-SshHostDashboardTheme 是历史命名, 实际内容与用途已是通用
#     语义主题; tmux 侧请用中性别名 Get-TuiDashboardTheme(同实现同缓存)。
#
# ★ 为什么用 ColorName16 而不是 RGB(2026-10-31 探针实测):
#   TG 的 'ansi' 驱动只发 16 色 SGR, RGB 会被量化到最近的 16 色锚点:
#     (88,58,158)  -> DarkGray(8)    ← 想要紫色背景, 结果变灰!
#     (128,0,128)  -> BrightMagenta(13)
#     (24,24,37)   -> Black(0)
#   量化是"欧氏距离最近锚点", 想靠调 RGB 表达紫色非常脆弱。直接构造
#   `Attribute(ColorName16, ColorName16)` 绕过量化 —— 发出去的就是确定的
#   16 色 SGR 码, Windows Terminal / conhost / 现代终端上都能稳定还原。
#   证据: .agent_cache/dash-probe/p16-cn16.ps1(锚点表见文件尾注释)。
#
# ★ 为什么 Scheme 实例可以自建(不写 SchemeManager):
#   TG 2.4.10 的 View.SetScheme 只做"属性赋值", 不要求方案已注册; 自建实例
#   不会被 SchemeManager 的字典/Theme 对账逻辑波及(那条约束只针对
#   GetScheme/ThemeManager 的既有方案覆写, 见 Set-TguiTheme.ps1)。因此
#   本文件的 Scheme **不注册**、只挂到视图上, 进程退出即释放。
#
# 契约: 纯构造(无副作用), 首次构造后缓存在 $script:SshHostDashboardThemeCache
#       (与 ALC 绑定, 进程级复用); 不读配置、不碰终端。

function Get-SshHostDashboardTheme {
    <#
    .SYNOPSIS
        构造(或复用)SSH 主机仪表盘的语义配色 Scheme 集合。

    .DESCRIPTION
        返回 PSCustomObject, 每个字段是一个 Terminal.Gui.Drawing.Scheme 实例:
          Text         正文(白 on 黑)
          Dim          次要文本(深灰 on 黑) —— 最后活跃时间 / 卡片次要字段
          Accent       强调(亮洋红 on 黑) —— 标题、标签、分类强调
          Online       在线(亮绿 on 黑)
          Offline      离线(亮红 on 黑)
          Unknown      未知(深灰 on 黑)
          Selected     选中行(白 on 洋红) —— 整行紫色背景
          SelectedDim  选中行内的次要文本(灰 on 洋红)
          SelectedMeta 选中行内的元信息(灰 on 洋红)
          TitleBand    标题带(亮洋红 on 黑)
          Category     分类项非激活(深灰 on 黑)
          CategoryActive 分类项激活(白 on 洋红)
          Card         卡片正文(白 on 黑)
          CardBorder   卡片边框(深灰 on 黑)
          Hint         底部提示(深灰 on 黑)
          EmptyHint    空态/加载态(深灰 on 黑)
          Attached     会话 Attached(亮绿 on 黑)
          Detached     会话 Detached(深灰 on 黑)
          AccentCyan   品牌/小标题/选中指示符(亮青 on 黑) —— 阶段一新增
          SelectionBg  选中行底(白 on 蓝) —— 阶段一新增(低对比, 不刺眼)
          SelectionBgText 选中行会话名/窗口数(白 on 蓝) —— 阶段一新增
          SelectionMeta   选中行次要文本(灰 on 蓝) —— 阶段一新增
          SelectionAttached 选中行 Attached(亮绿 on 蓝) —— 阶段一新增
          SelectionDetached 选中行 Detached(白 on 蓝) —— 阶段一新增
          SelectionDot      选中行首指示符(亮青 on 蓝) —— 阶段一新增
          SectionTitle      工作区区块小标题(亮青 on 黑) —— 阶段一新增
          AttachedText      列表内 Attached 文本(亮绿 on 黑) —— 阶段一新增
          Subtle            次要说明文字(灰 on 黑) —— 阶段一新增

        **只做构造**: 不调用 Application.Init, 无头可测(TG 静态初始化在
        Get-TguiContext 阶段完成)。

    .PARAMETER Tgui
        Get-TguiContext 的上下文对象(提供 ALC 内类型句柄)。

    .OUTPUTS
        [PSCustomObject] 见 .DESCRIPTION 的字段表。

    .EXAMPLE
        $theme = Get-SshHostDashboardTheme -Tgui (Get-TguiContext)
        $label.SetScheme($theme.Online)
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Tgui
    )

    # 进程级缓存: Theme 是纯值对象, 同一 ALC 内复用; 模块 -Force 重导入后
    # $script: 变量随模块实例重置, 会按新 ALC 重新构造(不会跨 ALC 串类型)。
    if ($null -ne $script:SshHostDashboardThemeCache) {
        return $script:SshHostDashboardThemeCache
    }

    $attrType = $Tgui.Types.Attribute
    $schemeType = $Tgui.Types.Scheme
    $cn16Type = $Tgui.Assembly.GetType('Terminal.Gui.Drawing.ColorName16')
    if ($null -eq $cn16Type) {
        throw 'TGUI 载入失败: Terminal.Gui.Drawing.ColorName16 缺失。vendored 版本可能已变更, 请核对 Get-TguiContext.ps1 头部的 API 面记录。'
    }

    # Attribute(ColorName16& fg, ColorName16& bg): 两参都是 byref。
    # PowerShell 的 [ref] 是 PSReference, 反射 Invoke 无法转 byref ——
    # 正确姿势是把**装箱后的枚举值**直接放进 args 数组, 由运行时取地址(同
    # Set-TguiTheme 里 Color& 的实测结论)。
    $attrCtor = $attrType.GetConstructors() |
        Where-Object {
            $p = $_.GetParameters()
            $p.Count -eq 2 -and $p[0].ParameterType.IsByRef -and
            $p[0].ParameterType.GetElementType().Name -eq 'ColorName16'
        } |
        Select-Object -First 1
    if ($null -eq $attrCtor) {
        throw 'TGUI 载入失败: Attribute 缺少 (ColorName16, ColorName16) 构造。vendored 版本可能已变更。'
    }

    function New-Cn16Attribute {
        param([string]$Foreground, [string]$Background)
        # 变量名不能叫 $args(PSSA: $args 是自动变量) —— 用 $attrArgs。
        $attrArgs = [object[]]::CreateInstance([object], 2)
        $attrArgs[0] = [Enum]::Parse($cn16Type, $Foreground)
        $attrArgs[1] = [Enum]::Parse($cn16Type, $Background)
        return $attrCtor.Invoke($attrArgs)
    }

    function New-Cn16Scheme {
        param([string]$Foreground, [string]$Background)
        $scheme = [System.Activator]::CreateInstance($schemeType)
        $attr = New-Cn16Attribute -Foreground $Foreground -Background $Background
        # 十个可视槽位全部填成同一份 Attribute —— 视图在不同状态(焦点/激活/
        # 只读)下都取到同一颜色, 不会因为"没设某个槽位"掉回 TG 内置方案
        # (内置 Base 是白对白, 会隐形)。
        $scheme.Normal = $attr
        $scheme.Focus = $attr
        $scheme.HotNormal = $attr
        $scheme.HotFocus = $attr
        $scheme.Active = $attr
        $scheme.HotActive = $attr
        $scheme.Highlight = $attr
        $scheme.Editable = $attr
        $scheme.ReadOnly = $attr
        $scheme.Disabled = $attr
        return $scheme
    }

    # ---- 16 色语义表(值 = ColorName16 名字, 注释 = 实际 SGR) ----
    # 白 97 / 灰 37 / 深灰 90 / 亮绿 92 / 亮红 91 / 洋红 35 / 亮洋红 95 / 黑 30
    $theme = [PSCustomObject]@{
        Text           = New-Cn16Scheme -Foreground 'White' -Background 'Black'
        Dim            = New-Cn16Scheme -Foreground 'DarkGray' -Background 'Black'
        Accent         = New-Cn16Scheme -Foreground 'BrightMagenta' -Background 'Black'
        Online         = New-Cn16Scheme -Foreground 'BrightGreen' -Background 'Black'
        Offline        = New-Cn16Scheme -Foreground 'BrightRed' -Background 'Black'
        Unknown        = New-Cn16Scheme -Foreground 'DarkGray' -Background 'Black'
        Selected       = New-Cn16Scheme -Foreground 'White' -Background 'Magenta'
        SelectedDim    = New-Cn16Scheme -Foreground 'Gray' -Background 'Magenta'
        SelectedMeta   = New-Cn16Scheme -Foreground 'Gray' -Background 'Magenta'
        SelectedOnline = New-Cn16Scheme -Foreground 'BrightGreen' -Background 'Magenta'
        SelectedOffline = New-Cn16Scheme -Foreground 'BrightRed' -Background 'Magenta'
        SelectedUnknown = New-Cn16Scheme -Foreground 'Gray' -Background 'Magenta'
        TitleBand      = New-Cn16Scheme -Foreground 'BrightMagenta' -Background 'Black'
        Category       = New-Cn16Scheme -Foreground 'DarkGray' -Background 'Black'
        CategoryActive = New-Cn16Scheme -Foreground 'White' -Background 'Magenta'
        Card           = New-Cn16Scheme -Foreground 'White' -Background 'Black'
        CardBorder     = New-Cn16Scheme -Foreground 'DarkGray' -Background 'Black'
        Hint           = New-Cn16Scheme -Foreground 'DarkGray' -Background 'Black'
        EmptyHint      = New-Cn16Scheme -Foreground 'DarkGray' -Background 'Black'
        # 选中行内状态点的选中变体(保持语义色, 只换底色)
        Divider        = New-Cn16Scheme -Foreground 'DarkGray' -Background 'Black'
        # tmux 会话状态(2026-10-31 tmux 侧并入): Attached = 有客户端连着 = 亮绿;
        # Detached = 空闲 = 暗灰(是**已知**状态, 不是"未知", 故不复用 Unknown 语义)
        Attached         = New-Cn16Scheme -Foreground 'BrightGreen' -Background 'Black'
        Detached         = New-Cn16Scheme -Foreground 'DarkGray' -Background 'Black'
        SelectedAttached = New-Cn16Scheme -Foreground 'BrightGreen' -Background 'Magenta'
        SelectedDetached = New-Cn16Scheme -Foreground 'Gray' -Background 'Magenta'

        # ================================================================
        # 2026-11-06 阶段一(tmux TUI 视觉层级重构)新增的语义角色
        # ================================================================
        # 背景: 真机取证发现选中行用 BrightMagenta 整行铺底时:
        #   - 行首绿点(●)与洋红底产生红绿眩光冲突;
        #   - 行内右侧 Attached/Detached 与窗口数仍是 DarkGray, 在洋红底上
        #     几乎不可读(暗字压亮底, 对比度不足);
        #   - 顶部统计与左侧列表的状态色各说各话(左暗右绿), 没有联动。
        # 对策: 选中行**不再用任何高饱和底色**, 改为"暗蓝灰底 + 强前景锚点";
        #      状态色在"未选中/选中"两态**保持同一语义色**(Attached 恒亮绿),
        #      只在选中态把 Detached 提亮到 White 以保证可读。
        #
        # 16 色映射表(阶段一新增角色; ColorName16 的实际枚举名:
        #   Black/Blue/Green/Cyan/Red/Magenta/Yellow/Gray/DarkGray/
        #   BrightBlue/BrightGreen/BrightCyan/BrightRed/BrightMagenta/BrightYellow/White
        #   —— 注意**没有** BrightWhite / DarkBlue: "最亮的白"就是 White,
        #      "最深的蓝"就是 Blue):
        #   AccentCyan      BrightCyan  on Black   —— 品牌/小标题/选中指示符
        #   SelectionBg     White       on Blue    —— 选中行底(低对比, 不刺眼)
        #   SelectionBgText White       on Blue    —— 选中行会话名/窗口数
        #   SelectionMeta   Gray        on Blue    —— 选中行次要文本
        #   SelectionAttached BrightGreen on Blue
        #   SelectionDetached White      on Blue
        #   SelectionDot    BrightCyan  on Blue   —— 选中行首指示符 ▎
        #   SectionTitle    BrightCyan  on Black   —— 工作区区块小标题
        #   AttachedText    BrightGreen  on Black  —— 列表内 Attached 文本(联动)
        #   Subtle          Gray        on Black   —— 次要说明文字
        AccentCyan          = New-Cn16Scheme -Foreground 'BrightCyan' -Background 'Black'
        SelectionBg         = New-Cn16Scheme -Foreground 'White' -Background 'Blue'
        SelectionBgText     = New-Cn16Scheme -Foreground 'White' -Background 'Blue'
        SelectionMeta       = New-Cn16Scheme -Foreground 'Gray' -Background 'Blue'
        SelectionAttached   = New-Cn16Scheme -Foreground 'BrightGreen' -Background 'Blue'
        SelectionDetached   = New-Cn16Scheme -Foreground 'White' -Background 'Blue'
        SelectionDot        = New-Cn16Scheme -Foreground 'BrightCyan' -Background 'Blue'
        SectionTitle        = New-Cn16Scheme -Foreground 'BrightCyan' -Background 'Black'
        AttachedText        = New-Cn16Scheme -Foreground 'BrightGreen' -Background 'Black'
        Subtle              = New-Cn16Scheme -Foreground 'Gray' -Background 'Black'

        # ================================================================
        # 2026-11-06 #9b871512 "Forest Matrix"(翡翠绿/竹青)主题新增角色
        # ================================================================
        # 背景: 阶段一的"选中行整行 Blue 铺底"在 Windows Terminal 上依然刺眼
        #   (纯蓝 0,0,255 大面积铺满一行, 对比度过载); 右侧区块标题又全部同色,
        #   没有层次。新主题的原则:
        #     - **全局深色背景**: 列表行背景一律 Black, 不再用任何饱和底色;
        #     - **翡翠绿(BrightGreen)做锚点**: 选中行序号徽标 ┃02┃、Attached 状态、
        #       活动窗口的 * 标记、底栏按键名 —— 这几处是"当前/活动"的语义;
        #     - **竹青(Cyan)做结构**: 品牌行与右侧区块小标题, 承担"分区"语义;
        #     - **灰阶做正文**: 会话名/描述 Gray, 路径/次要 DarkGray。
        #
        # 16 色映射(ColorName16 实际枚举名 —— 没有 BrightWhite, 最亮白就是 White):
        #   ForestAccent     Cyan        on Black —— 品牌行 / 区块小标题
        #   ForestBrand      BrightCyan  on Black —— 品牌主标识 "ShellPrompt TMUX"
        #   ForestHost       White       on Black —— 主机名
        #   ForestFrame      DarkGray    on Black —— 框线 ─ │ ╭ ╮ ╰ ╯
        #   ForestBadge      BrightGreen on Black —— 选中行 ┃02┃ 徽标
        #   ForestBadgeOff   DarkGray    on Black —— 未选中行序号 01
        #   ForestName       Gray        on Black —— 未选中行会话名
        #   ForestNameOn     White       on Black —— 选中行会话名
        #   ForestAttached   BrightGreen on Black —— ● Att / ● Attached
        #   ForestDetached   DarkGray    on Black —— 未选中 ○ Det
        #   ForestDetachedOn White       on Black —— 选中 ○ Det
        #   ForestWinCount   DarkGray    on Black —— 未选中 3w
        #   ForestWinCountOn White       on Black —— 选中 3w
        #   ForestActive     BrightGreen on Black —— 活动窗口的 * 标记
        #   ForestActiveName White       on Black —— 活动窗口名
        #   ForestPaneName   Gray        on Black —— 非活动窗口名
        #   ForestPath       DarkGray    on Black —— 窗口工作目录
        #   ForestPreview    Gray        on Black —— 终端预览正文
        #   ForestPreviewBox DarkGray    on Black —— 预览框线
        #   ForestSummaryKey DarkGray    on Black —— SUMMARY 键名
        #   ForestSummaryVal White       on Black —— SUMMARY 值
        ForestAccent       = New-Cn16Scheme -Foreground 'Cyan' -Background 'Black'
        ForestBrand        = New-Cn16Scheme -Foreground 'BrightCyan' -Background 'Black'
        ForestHost         = New-Cn16Scheme -Foreground 'White' -Background 'Black'
        ForestFrame        = New-Cn16Scheme -Foreground 'DarkGray' -Background 'Black'
        ForestBadge        = New-Cn16Scheme -Foreground 'BrightGreen' -Background 'Black'
        ForestBadgeOff     = New-Cn16Scheme -Foreground 'DarkGray' -Background 'Black'
        ForestName         = New-Cn16Scheme -Foreground 'Gray' -Background 'Black'
        ForestNameOn       = New-Cn16Scheme -Foreground 'White' -Background 'Black'
        ForestAttached     = New-Cn16Scheme -Foreground 'BrightGreen' -Background 'Black'
        ForestDetached     = New-Cn16Scheme -Foreground 'DarkGray' -Background 'Black'
        ForestDetachedOn   = New-Cn16Scheme -Foreground 'White' -Background 'Black'
        ForestWinCount     = New-Cn16Scheme -Foreground 'DarkGray' -Background 'Black'
        ForestWinCountOn   = New-Cn16Scheme -Foreground 'White' -Background 'Black'
        ForestActive       = New-Cn16Scheme -Foreground 'BrightGreen' -Background 'Black'
        ForestActiveName   = New-Cn16Scheme -Foreground 'White' -Background 'Black'
        ForestPaneName     = New-Cn16Scheme -Foreground 'Gray' -Background 'Black'
        ForestPath         = New-Cn16Scheme -Foreground 'DarkGray' -Background 'Black'
        ForestPreview      = New-Cn16Scheme -Foreground 'Gray' -Background 'Black'
        ForestPreviewBox   = New-Cn16Scheme -Foreground 'DarkGray' -Background 'Black'
        ForestSummaryKey   = New-Cn16Scheme -Foreground 'DarkGray' -Background 'Black'
        ForestSummaryVal   = New-Cn16Scheme -Foreground 'White' -Background 'Black'
    }

    $script:SshHostDashboardThemeCache = $theme
    return $theme
}

function Get-TuiDashboardTheme {
    <#
    .SYNOPSIS
        **共享**语义 Theme 的中性别名(两个仪表盘都用它)。

    .DESCRIPTION
        Get-SshHostDashboardTheme 是历史命名(建于 SSH 主机仪表盘), 但这套 Scheme
        已经是两个仪表盘(SSH 主机 / tmux 会话)共用的通用语义主题。本别名给
        tmux 侧一个不含"Host"字样的调用名, 实现与缓存与原函数完全一致 ——
        返回的是**同一个** Scheme 实例集(进程级缓存)。

    .PARAMETER Tgui
        Get-TguiContext 的上下文对象(提供 ALC 内类型句柄)。

    .OUTPUTS
        [PSCustomObject] 语义 Scheme 集合(见 Get-SshHostDashboardTheme 的字段表)。

    .EXAMPLE
        $theme = Get-TuiDashboardTheme -Tgui (Get-TguiContext)
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Tgui
    )

    return (Get-SshHostDashboardTheme -Tgui $Tgui)
}
