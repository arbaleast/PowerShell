# Initialize-Config.ps1 - 模块配置初始化 & 配置访问助手
# 单一配置源: $script:Config 按域划分(Colors/Paths/SSH/UI/Weather),
# 读取统一走 Get-CachedConfig;热路径键值预热到 $script:ColorCache
# 以减少菜单/Logo 渲染中的 4 段三层回退。
#
# 加载顺序(不可调换): 默认值 -> Get-CachedConfig -> 用户配置(config.ps1) -> 预热缓存。
# 用户配置必须早于预热, 否则预热快照会盖掉用户覆盖(见文件末尾步骤 6/7 的说明)。
#
# 2026-10-29 清理: 删除无消费方的配置键(Paths.LogPath / SSH.ConnectTimeout /
# SSH.ForceTTy / 整个 Keys 域 / Colors.LightGray|White|BgDarker|Bold|Dim)。
# 判定依据: 这些键既不在 $script:ColorSemanticMap 里, 也没有任何直接读取点。
# 用户若在 ~/.ShellPrompt/config.ps1 里配过它们, 现在会被忽略(不会报错)。

# 统一用 `[char]27` 别名避免 PowerShell 字符串转义歧义(0x1B = ESC)
$script:Esc = [char]27

# 1. 模块根路径（脚本级，不暴露为全局变量）
$script:ShellPromptRoot = (Get-Item $PSScriptRoot).Parent.Parent.FullName

# 2. 单一来源：模块级配置对象（按域划分：Colors / Paths / SSH / UI / Weather）
$script:Config = [ordered]@{
    Paths  = [ordered]@{
        Quotes  = Join-Path $script:ShellPromptRoot 'data\quotes.txt'
    }
    Colors = [ordered]@{
        FreshGreen = "$Esc[38;2;137;209;133m"
        SageGreen  = "$Esc[38;2;159;177;159m"
        DarkGray   = "$Esc[38;2;50;50;50m"
        MidGray    = "$Esc[38;2;100;100;100m"
        # 标题色 (Cyan): 菜单 / 标题区主色, 提升与正文色的层级差
        Cyan       = "$Esc[38;2;112;199;209m"
        # 危险项色 (Red): 删除 / 不可逆操作提示
        Danger     = "$Esc[38;2;220;90;90m"
        # 警告项色 (Yellow): 非推荐路径 / 需二次确认操作
        Warning    = "$Esc[38;2;220;180;80m"
        # 选中态反色背景 (Cyan 底 + 黑字): 选中项高亮
        SelectedBg = "$Esc[48;2;112;199;209;30m$Esc[38;2;20;20;20m"
        Rst        = "$Esc[0m"
    }
    SSH    = [ordered]@{
        LastHost       = $null   # 上次使用的 SSH 主机（模块作用域，用于菜单置顶）
    }
    # Weather 域: 交互菜单底栏 wttr 单行天气的渲染配置 (2026-10-18 起)
    # - Enabled : 总开关, $false 时 Get-WttrTitleSuffix 直接跳过天气后缀拼接
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
        # GridView 是否以全屏(alternate screen)方式渲染。
        # 2026-10-30 起默认 $false: 3~4 行的轻量全局操作菜单全屏渲染会产生
        # 大面积黑底空洞; PSTui 1.0.5 的 Out-ConsoleGridView 默认内联渲染且未暴露
        # -Width/-Height 尺寸参数(README 实测), 关闭全屏即天然紧凑弹窗。
        # 需要"沉浸式铺满"的用户可在 $HOME/.ShellPrompt/config.ps1 里改回 $true。
        GridViewFullScreen = $false
        # TGUI 迁移(阶段 B): sss 仪表盘渲染后端。
        # = $true (默认): 走 Terminal.Gui v2 独立仪表盘(Show-TmuxTuiDashboard,
        #   真正的全屏 TUI: 状态区/会话表/快捷键栏/空错误辅助区)。
        # = $false: 回退老 PSTui GridView 主循环(Show-TmuxSessionDashboard +
        #   Show-TmuxActionBar), 阶段 C 真机验收稳定后再评估移除。
        DashboardTuiEnabled = $true
        # tmux 仪表盘(Show-TmuxSessionDashboard)显式全屏渲染(PSTui -FullScreen):
        # Terminal.Gui 全屏备用屏自带 清屏 + Y=0 锚定 + 尺寸变化自动重绘 +
        # 底部状态条定位在最后一行。2026-10-30 第四轮修复: 上一轮的 MinUI +
        # 自绘标题在真终端产生"标题重复/界面下沉/无底部提示"回归, 全部由
        # 本开关取代。改 $false 应回退内联渲染(不推荐, 为兼容保留)。
        DashboardFullScreen = $true
        # GridView (Terminal.Gui v2) 配色
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
            # 单个名字不存在时自动回退 'Base'。
            #
            # 兼容旧配置: 既有配置里 Name 可能是单个字符串, 由 Resolve-TgThemeNames
            # 规范化成单元素数组, 不需要用户手工迁移。
            Name    = [string[]]@('Base', 'Menu')
            # 槽位配色: 键为 Terminal.Gui.Drawing.Scheme 的属性名,
            # 值为 @{ Fg = 'R,G,B'; Bg = 'R,G,B' }。
            #
            # ---- 槽位清单(2026-10 IL 级实测, TG 2.4.10.0) --------------------------
            # 本清单**只保留反射实测可写的槽位名**。Scheme 在 2.4.10 上的 public
            # 实例属性共 23 个: 10 个可视槽位 + 13 个 Code* 语法高亮槽位。
            # Code* 是语法高亮, 菜单用不到, 保持 TG 内置默认, 不在此配置。
            #
            # ---- 表格各部位实际取色来源(IL 调用序列实测, 非推测) -------------------
            # 1) 正文单元格 —— TableView.RenderRow(全文 IL 逐条比对):
            #      焦点在表格 -> 选中行取 Focus; 焦点离开表格时选中行取 Active。
            #    该方法**从不读取 HotFocus / HotNormal / HotActive**。
            #
            # 2) 列头 —— TableView.RenderHeaderMidline:
            #      列头文字 = scheme.Focus(表格有焦点) / scheme.Normal(表格无焦点)。
            #    => **Focus 同时被"聚焦列头"和"有焦点时的选中行"共用**,
            #       边框/标题不必因此迁就 —— 列头本身就该比正文醒目。
            #    => 新契约 (2026-10-30 起): 配色从"满屏单一亮绿"迁移到
            #       Catppuccin Mocha 风格暗色分层(PSTui 内联弹窗自带深色底,
            #       统一背景色即可消除斑马纹观感)。
            #
            # 3) 过滤输入框 —— TextField 输入文字取 Focus 槽位;
            #    Editable 槽位承载输入区取色, 用深一档底色承托正文色, 保证可读。
            #
            # 4) 底部状态栏 —— 取自 Scheme 'Menu'(已由 Name 一并覆写), 不读 Focus/Active。
            #
            # 任何槽位若在某个 TG 版本上不可写, Set-TgSchemeSlot 会跳过而不报错,
            # 配色部分生效优于完全不生效。
            # ---------------------------------------------------------------------------
            Slots   = [ordered]@{
                # 正文单元格 + 无焦点时的列头 + 列间竖线
                Normal            = @{ Fg = '205,214,244'; Bg = '24,24,37' }  # 正文主色 Mocha Text + Base 暗灰蓝底
                HotNormal         = @{ Fg = '137,220,235'; Bg = '24,24,37' }  # 标题/表头强调 Sky 冰青
                # 聚焦态列头 + **有焦点时的选中行**; 与 Active 保持一致以统一高亮
                Focus             = @{ Fg = '255,255,255'; Bg = '69,71,90' }  # 亮白字 + Surface1 高亮条(同 Active/Highlight)
                HotFocus          = @{ Fg = '166,227,161'; Bg = '69,71,90' } # 其他 View 的聚焦热区(TableView 不读取)
                # 选中行(焦点不在表格时): RenderRow 取 new Attribute(scheme.Active)
                Active            = @{ Fg = '255,255,255'; Bg = '69,71,90' }  # 选中行: 亮白字 + 高亮条(同 Focus)
                HotActive         = @{ Fg = '166,227,161'; Bg = '69,71,90' } # 激活项热区(同 HotFocus)
                Highlight         = @{ Fg = '255,255,255'; Bg = '69,71,90' }  # 高亮标记(同 Focus/Active)
                Editable          = @{ Fg = '205,214,244'; Bg = '49,50,68' }   # 可编辑(过滤框) 正文字 + Surface0 深一档底
                ReadOnly          = @{ Fg = '127,132,156'; Bg = '24,24,37' }  # 只读行 Overlay1 弱化灰紫
                Disabled          = @{ Fg = '108,112,134'; Bg = '24,24,37' }  # 禁用行 Overlay0 暗灰
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

# 5. 统一配置读取入口: 优先命中 $script:ColorCache 预热键,
#    冷路径直接回退到 $script:Config。
function Get-CachedConfig {
    [CmdletBinding()]
    [OutputType([object])]
param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Paths', 'Colors', 'SSH', 'UI', 'Weather')]
        [string]$Section,

        [Parameter(Mandatory = $true)]
        [string]$Key,

        [Parameter(Mandatory = $false)]
        [object]$Default
    )
    $cacheKey = "${Section}|${Key}"
    # 空判断: 用户配置在预热之前加载, 若配置里调用了 Get-CachedConfig, 此时
    # $script:ColorCache 还不存在(见文件末尾步骤 6/7 的顺序说明)。
    if ($script:ColorCache -and $script:ColorCache.ContainsKey($cacheKey)) {
        $cached = $script:ColorCache[$cacheKey]
        if ($null -ne $cached -and "$cached" -ne '') { return $cached }
    }
    # 冷路径: 直接走 $script:Config,未命中则返回传入的 $Default
    if ($script:Config -and $script:Config[$Section] -and $null -ne $script:Config[$Section][$Key]) {
        return $script:Config[$Section][$Key]
    }
    return $Default
}

# 6. 用户配置覆盖 ($HOME/.ShellPrompt/config.ps1)
#    加载点必须在**预热之前**: $script:ColorCache 是"预热那一刻"的值快照, 而
#    Get-CachedConfig 优先命中缓存 —— 用户配置若晚于预热生效, 覆盖会被缓存静默
#    遮蔽。2026-10-29 修正: 原实现里用户配置由 ShellPrompt.psm1 在本文件**之后**
#    加载, 于是 config.ps1 里的颜色/路径覆盖全部不生效(用户改了没反应)。
#    收进本文件后同时修好两处: 模块内读取, 以及 profile 启动期的欢迎语渲染
#    (profile 同样 dot-source 本文件, 拿到的是同一份已合并用户配置的值)。
$userConfigPath = Join-Path (Join-Path $HOME '.ShellPrompt') 'config.ps1'
if (Test-Path -LiteralPath $userConfigPath -PathType Leaf) {
    try {
        . $userConfigPath
    } catch {
        Write-Warning "[ShellPrompt] 用户配置加载失败 ($userConfigPath): $($_.Exception.Message)"
    }
}

# 7. 预热热路径值到 $script 作用域,菜单/Logo 渲染时直接命中快路径,
#    避免在每次菜单绘制时重复执行回退查询 (每次重绘约 5-10 次)。
#    注: 仅缓存"非空字符串"键值;若用户配置在运行时被修改,请清除此缓存。
#    顺序要求: 必须排在上面的用户配置加载之后(见步骤 6 的说明)。
$script:ColorCache = @{
    'Colors|FreshGreen' = $script:Config.Colors.FreshGreen
    'Colors|SageGreen'  = $script:Config.Colors.SageGreen
    'Colors|MidGray'    = $script:Config.Colors.MidGray
    'Colors|Cyan'       = $script:Config.Colors.Cyan
    'Colors|Danger'     = $script:Config.Colors.Danger
    'Colors|Warning'    = $script:Config.Colors.Warning
    'Colors|SelectedBg' = $script:Config.Colors.SelectedBg
    'Colors|Rst'        = $script:Config.Colors.Rst
    'Paths|Quotes'      = $script:Config.Paths.Quotes
}
