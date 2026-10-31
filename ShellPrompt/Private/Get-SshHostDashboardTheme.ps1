# Get-SshHostDashboardTheme.ps1 - SSH 主机仪表盘的**统一 Theme**(ALC 原生配色)
#
# 背景 (2026-10-31 sss 仪表盘重构):
#   新仪表盘顶部分类 / 左侧主机列表 / 右侧详情卡片 / 底部快捷键栏 需要按语义着色:
#     主色紫 · 在线绿 · 离线红 · 未知灰 · 次要文本深灰 · 选中行整行紫底。
#   旧实现把配色散落在各视图的 SetScheme 里(同名方案共用), 新界面需要"同一个
#   View 上同时出现多种角色色"(状态点绿 + 名称白 + 标签紫 + 时间灰), 因此本文件
#   统一构造一套**语义 Scheme** 供各视图直接 SetScheme。
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
    }

    $script:SshHostDashboardThemeCache = $theme
    return $theme
}
