# Initialize-Config.ps1 - 模块配置初始化 & 配置访问助手
# 单一配置源: $script:Config 按域划分(Colors/Keys/Paths/SSH),
# 读取统一走 Get-CachedConfig;热路径键值预热到 $script:ColorCache
# 以减少菜单/Logo 渲染中的 4 段三层回退。

# 统一用 `[char]27` 别名避免 PowerShell 字符串转义歧义(0x1B = ESC)
$script:Esc = [char]27

# 1. 模块根路径（脚本级，不暴露为全局变量）
$script:ShellPromptRoot = (Get-Item $PSScriptRoot).Parent.Parent.FullName

# 2. 单一来源：模块级配置对象（按域划分：Colors / Keys / SSH / Paths）
$script:Config = [ordered]@{
    Paths  = [ordered]@{
        Quotes  = Join-Path $script:ShellPromptRoot 'data\quotes.txt'
        LogPath = Join-Path $env:TEMP 'ShellPrompt\shellprompt.log'
    }
    Colors = [ordered]@{
        FreshGreen = "$Esc[38;2;137;209;133m"
        SageGreen  = "$Esc[38;2;159;177;159m"
        DarkGray   = "$Esc[38;2;50;50;50m"
        MidGray    = "$Esc[38;2;100;100;100m"
        LightGray  = "$Esc[38;2;180;180;180m"
        White      = "$Esc[38;2;255;255;255m"
        # 标题色 (Cyan): 菜单 / 标题区主色, 提升与正文色的层级差
        Cyan       = "$Esc[38;2;112;199;209m"
        # 危险项色 (Red): 删除 / 不可逆操作提示
        Danger     = "$Esc[38;2;220;90;90m"
        # 警告项色 (Yellow): 非推荐路径 / 需二次确认操作
        Warning    = "$Esc[38;2;220;180;80m"
        # 选中态反色背景 (Cyan 底 + 黑字): 选中项高亮
        SelectedBg = "$Esc[48;2;112;199;209;30m$Esc[38;2;20;20;20m"
        # 危险项底色 (Danger 底 + 白字): 危险项的加强高亮(可选)
        BgDarker   = "$Esc[48;2;40;40;40m"
        Rst        = "$Esc[0m"
        Bold       = "$Esc[1m"
        Dim        = "$Esc[2m"
    }
    Keys   = [ordered]@{
        Up    = 38
        Down  = 40
        Enter = 13
        Esc   = 27
    }
    SSH    = [ordered]@{
        ConnectTimeout = 5
        ForceTTy       = $true
        LastHost       = $null   # 上次使用的 SSH 主机（模块作用域，用于菜单置顶）
    }
    # Weather 域: 交互菜单底栏 wttr 单行天气的渲染配置 (2026-10-18 起)
    # - Enabled : 总开关, $false 时 Write-GridViewHint 直接跳过天气片段拼接
    # - ExtraWeatherDescMap: 用户自定义 wttr.in weatherDesc 英文 → 中文映射
    #     键 = 英文短语(会被 Get-WttrTitleSuffix 做 .ToLower().Trim() 后查表),
    #     值 = 自定义中文。同名键会覆盖模块内置映射。
    Weather = [ordered]@{
        Enabled              = $true
        ExtraWeatherDescMap  = [ordered]@{}
    }
    # UI 域: 控制台 UI 主轨 (PSTui GridView) 行为配置
    # 注: 自研 ANSI 降级轨已于 2026-10-18 移除, 不再存在后端选择项;
    #     可用性由 Get-ConsoleUiBackend 现场检测, 不可用时抛明确错误。
    UI     = [ordered]@{
        # GridView 初始焦点: 'Table' = 光标在表格; 'Filter' = 光标在过滤输入框
        # (后者更接近旧版 Q1=A 打字即搜的手感, 但交互手感未在自动化环境验证)
        GridViewFocus   = 'Table'
        # GridView 是否以全屏方式渲染
        GridViewFullScreen = $true
        # GridView (Terminal.Gui v2) 配色: 让表格视觉尽量贴近旧 ANSI 菜单
        Theme   = [ordered]@{
            # 总开关: $false 时 Set-TgColorScheme 直接返回, 不碰 Terminal.Gui 静态 API
            Enabled = $true
            # 覆写目标(可多个): 依次取 [SchemeManager]::GetScheme(<名字>) 返回的
            # **已存在**实例并就地改写。刻意不新增方案名 + 不写 ThemeManager.Theme ——
            # 实测 TG 2.4.10 下该组合会让 SchemeManager 内部字典与 Theme 失配,
            # 之后所有 GetScheme 抛异常。
            #
            # 为什么必须多 Scheme: 真终端颜色指纹探针实测(PSTui 1.0.5 + TG 2.4.10.0)
            #   - 表格主体(正文/焦点行/边框/列头) 取自 Scheme 'Base';
            #   - 底部状态栏(Rows: n | Enter Accept | Esc Close) 取自 Scheme 'Menu';
            #   - ThemeManager.Theme = 'Default' 解析到的正是 'Base'。
            # 早期实现只覆写 'Menu', 结果只染了状态栏、主体毫无变化 —— 即"配色完全没生效"。
            # 单个名字不存在时自动回退 'Base'。
            #
            # 兼容旧配置: 既有配置里 Name 可能是单个字符串, 由 Resolve-TgThemeNames
            # 规范化成单元素数组, 不需要用户手工迁移。
            Name    = [string[]]@('Base', 'Menu')
            # 槽位配色: 键为 Terminal.Gui.Drawing.Scheme 的属性名,
            # 值为 @{ Fg = 'R,G,B'; Bg = 'R,G,B' }。
            # 取值全部来自上方 Colors 域同一套 RGB, 保证表格配色与其他 Spectre 输出观感一致。
            #
            # ---- 槽位清单(2026-10 IL 级实测, TG 2.4.10.0) --------------------------
            # 本清单**只保留反射实测可写的槽位名**。Scheme 在 2.4.10 上的 public
            # 实例属性共 23 个: 10 个可视槽位 + 13 个 Code* 语法高亮槽位。
            # Code* 是语法高亮, 菜单用不到, 保持 TG 内置默认, 不在此配置。
            #
            # ---- 表格各部位实际取色来源(IL 调用序列实测, 非推测) -------------------
            # 1) 正文单元格 —— TableView.RenderRow(全文 IL 逐条比对):
            #      bool hasFocus = this.HasFocus;
            #      整行背景: FullRowSelect && IsSelected
            #                 -> new Attribute(hasFocus ? scheme.Focus : scheme.Active)
            #                 否则   -> new Attribute(Enabled ? scheme.Normal : scheme.Active)
            #      单元格:   未选中 -> Enabled ? cellScheme.Normal : cellScheme.Disabled
            #                 已选中 -> hasFocus ? cellScheme.Focus : cellScheme.Active
            #                 (cellScheme = ColumnStyle.ColorGetter?.Invoke(..) ?? 行 scheme)
            #    => **焦点在表格时选中行取 Focus; 焦点离开表格时选中行取 Active。**
            #    该方法**从不读取 HotFocus / HotNormal / HotActive**。
            #    这就是上一轮"把 Cyan 底近黑字写进 HotFocus 却毫无变化"的根因:
            #    Hot* 系列在 TableView 渲染路径上根本不被读取。
            #
            # 2) 列头 —— TableView.RenderHeaderMidline:
            #      scheme = Style.HeaderScheme ?? GetScheme()
            #      列头文字 = scheme.Focus(表格有焦点) / scheme.Normal(表格无焦点)
            #    PSTui 的 OutGridViewWindow 构造函数硬编码
            #    set_SchemeName(SchemesToSchemeName(Schemes.Base)) = "Base",
            #    AddTableView 也从不给 TableStyle 赋 HeaderScheme(默认 $null),
            #    因此这里的 scheme 就是 'Base'。
            #    => **Focus 同时被"聚焦列头"和"有焦点时的选中行"共用**,
            #       这正是"前几项高亮与最后一项高亮不一致"的根因:
            #       焦点在表格 -> 选中行走 Focus(浅色); 焦点在过滤框 -> 选中行走 Active(青色)。
            #    => 解决方式(仅配置层): 让 Focus 与 Active 取**完全相同**的颜色,
            #       两种焦点状态下的选中行高亮即视觉统一。
            #    => 新契约 (2026-10-18 起): Focus / Active / Highlight 改为
            #       **亮绿字 (FreshGreen 137,209,133) + 稍亮底 (40,40,40)**。
            #       与 Normal 相比仅底色亮度差 1 级(30 -> 40), 列头与正文均为绿字,
            #       整张表与绿主题统一; 选中行高亮在两种焦点状态下也仍然一致。
            #       Editable 调整为**亮绿字 + 近黑底 (20,20,20)**, 即过滤框在
            #       焦点态下用暗底承托绿字, 确保输入文字始终可读。
            #
            # 3) 过滤输入框 —— TextField.OnGettingAttributeForRole:
            #      请求 role 0(Normal) 时**返回 role 2(Focus)**,
            #      且 OnDrawingContent 用 GetAttributeForRole(0) 绘制输入文字。
            #    => 过滤框文字取 Focus 槽位; 新契约下 Focus = 亮绿字 + 稍亮底,
            #       Editable 槽位则承载"输入区本身"的取色(亮绿字 + 近黑底),
            #       两种角色叠加后过滤框在焦点态下仍清晰可读。
            #
            # 4) 底部状态栏 —— 取自 Scheme 'Menu'(已由 Name 一并覆写), 不读 Focus/Active。
            #
            # 任何槽位若在某个 TG 版本上不可写, Set-TgSchemeSlot 会跳过而不报错,
            # 配色部分生效优于完全不生效。
            # ---------------------------------------------------------------------------
            Slots   = [ordered]@{
                # 正文单元格 + 无焦点时的列头 + 列间竖线
                Normal            = @{ Fg = '137,209,133'; Bg = '30,30,30' }  # 正文主色 FreshGreen + 暗背景
                HotNormal         = @{ Fg = '159,177,159'; Bg = '30,30,30' }  # 快捷键热区 SageGreen
                # 聚焦态列头 + **有焦点时的选中行**; 与 Active 保持一致以统一高亮
                Focus             = @{ Fg = '137,209,133'; Bg = '40,40,40' }   # 亮绿字 + 稍亮底(同 Active/Highlight)
                HotFocus          = @{ Fg = '20,20,20';   Bg = '130,215,220' } # 其他 View 的聚焦热区(TableView 不读取)
                # 选中行(焦点不在表格时): RenderRow 取 new Attribute(scheme.Active)
                Active            = @{ Fg = '137,209,133'; Bg = '40,40,40' }   # 选中行: 亮绿字 + 稍亮底(同 Focus)
                HotActive         = @{ Fg = '20,20,20';   Bg = '130,215,220' } # 激活项热区
                Highlight         = @{ Fg = '137,209,133'; Bg = '40,40,40' }   # 高亮标记(同 Focus/Active)
                Editable          = @{ Fg = '137,209,133'; Bg = '20,20,20' }   # 可编辑(过滤框) 亮绿字 + 近黑底
                ReadOnly          = @{ Fg = '159,177,159'; Bg = '30,30,30' }  # 只读行 弱化绿
                Disabled          = @{ Fg = '100,100,100'; Bg = '30,30,30' }  # 禁用行 MidGray
            }
        }
    }
}

# 4. 确保数据目录存在
try {
    $dataDir = Join-Path $script:ShellPromptRoot 'data'
    if (-not (Test-Path $dataDir)) {
        New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    }
} catch {
    Write-Verbose "初始化数据目录失败: $($_.Exception.Message)"
}

# 5. 预热热路径值到 $script 作用域,菜单/Logo 渲染时直接命中快路径,
#    避免在每次菜单绘制时重复执行回退查询 (每次重绘约 5-10 次)。
#    注: 仅缓存"非空字符串"键值;若用户配置在运行时被修改,请清除此缓存。
$script:ColorCache = @{
    'Colors|FreshGreen' = $script:Config.Colors.FreshGreen
    'Colors|SageGreen'  = $script:Config.Colors.SageGreen
    'Colors|MidGray'    = $script:Config.Colors.MidGray
    'Colors|Cyan'       = $script:Config.Colors.Cyan
    'Colors|Danger'     = $script:Config.Colors.Danger
    'Colors|Warning'    = $script:Config.Colors.Warning
    'Colors|SelectedBg' = $script:Config.Colors.SelectedBg
    'Colors|Rst'        = $script:Config.Colors.Rst
    'Keys|Up'           = $script:Config.Keys.Up
    'Keys|Down'         = $script:Config.Keys.Down
    'Keys|Enter'        = $script:Config.Keys.Enter
    'Keys|Esc'          = $script:Config.Keys.Esc
    'Paths|Quotes'      = $script:Config.Paths.Quotes
}

# 6. 统一配置读取入口: 优先命中 $script:ColorCache 预热键,
#    冷路径直接回退到 $script:Config。
function Get-CachedConfig {
    [CmdletBinding()]
    [OutputType([object])]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '')]
param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Paths', 'Colors', 'Keys', 'SSH', 'UI', 'Weather')]
        [string]$Section,

        [Parameter(Mandatory = $true)]
        [string]$Key,

        [Parameter(Mandatory = $false)]
        [object]$Default
    )
    $cacheKey = "${Section}|${Key}"
    if ($script:ColorCache.ContainsKey($cacheKey)) {
        $cached = $script:ColorCache[$cacheKey]
        if ($null -ne $cached -and "$cached" -ne '') { return $cached }
    }
    # 冷路径: 直接走 $script:Config,未命中则返回传入的 $Default
    if ($script:Config -and $script:Config[$Section] -and $null -ne $script:Config[$Section][$Key]) {
        return $script:Config[$Section][$Key]
    }
    return $Default
}
