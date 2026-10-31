# Set-TguiTheme.ps1 - Terminal.Gui v2 **独立 ALC** 的主题装配与方案可见性保障
#
# ============================ 为什么需要独立一套 ============================
# 交互式 UI 单轨 = 独立 ALC 的 Terminal.Gui v2(Get-TguiContext 载入
# Modules/Terminal.Gui/<ver>/Terminal.Gui.dll)。2026-10-30 起 PSTui 默认
# 加载上下文轨(Set-TgColorScheme 经 Add-Type)随 Modules/PSTui 删除一并移除,
# 配色装配只剩本文件这一条 ALC 原生路径。
# 注意PowerShell 类型身份隔离仍然是要点: 任何经 Add-Type 载入的 Terminal.Gui
# 副本(同名类型, 默认上下文)与本 ALC 的 Scheme/Color 互不兼容,
# 互相赋值会抛 "Cannot convert ... Scheme to ... Scheme"(真机实测)。
# ⇒ 所有 TGUI 视图的配色必须走本文件的 ALC 原生装配。
#
# ============================ 真机故障与根因 ============================
# 2026-10-30 真机验收(Windows Terminal): 仪表盘**只剩边框、内容全无**。
# 反射探针实测根因(证据 .agent_cache/tgui-probe/p51-scheme.ps1):
#   Terminal.Gui 2.4.10 内置 Scheme 'Base' 的 Normal 槽位 =
#     fg(255,255,255) bg(255,255,255)  ← **白对白, 文字隐形**
#   Scheme 'Menu' 的 Normal = fg(54,69,79) bg(173,216,230)(可见)。
#   视图默认方案: Window->'Base'、StatusBar->'Menu'、Label/TableView->''(回退 'Base')。
# 'ansi' 驱动不做终端颜色探测, 因此 Base 永远是白对白 ⇒ 仪表盘文本全隐形。
# 修法: 用仓库既有主题配置(UI.Theme.Slots)就地覆写 Base/Menu 的槽位,
#       并在绑定视图前**校验方案可见性**(前景 != 背景), 杜绝"绑了但看不见"。
#
# ============================ 关键实现约束 ============================
#   - 只取**已存在**的方案实例(SchemeManager.GetScheme(name))就地改写;
#     绝不新增方案名、绝不写 ThemeManager.Theme —— 该组合会打坏 SchemeManager
#     内部字典与 Theme 的对应关系(SchemeManager 内部实测记录, 2026-10)。
#   - 逐槽位"先读后比、等值跳过": TG 2.4.10 把与现值相同的 Attribute 再写一遍
#     不是幂等 no-op, 而是触发一次 Scheme 重建并把槽位打回内置默认
#     (实测 4 轮严格交替)。跳过等值写入同时避免翻转。
#   - Attribute 构造函数形参是 **Color&(byref)**: PowerShell 的 [ref]$c 造的是
#     PSReference, 反射 Invoke 时无法转成 Color&
#     (实测抛 "Object of type 'PSReference`1[Color]' cannot be converted to
#     type 'Color&'")。正确姿势是**直接把装箱后的 Color 放进 args 数组** ——
#     运行时会取数组元素的地址作为 byref 实参
#     (证据 .agent_cache/tgui-probe/p53-attribute-ctor.ps1 方案 A)。
#   - 颜色属视觉增强: 任何一步失败都不允许阻断仪表盘显示, 降级到 TG 内置配色。

function New-TguiColor {
    <#
    .SYNOPSIS
        由 'R,G,B' 文本构造 **本 ALC 内**的 Terminal.Gui.Drawing.Color。

    .DESCRIPTION
        必须反射构造: 类型字面量会解析到默认加载上下文的副本(跨程序集栅栏),
        构造出的 Color 与 ALC 内 Scheme 的 Color 属性不是同一个类型。

    .PARAMETER Tgui
        Get-TguiContext 的返回值(含 Types.Color)。

    .PARAMETER Rgb
        逗号分隔的 0-255 三元组字符串, 例如 '205,214,244'。

    .OUTPUTS
        ALC 所属的 Color 结构体实例。

    .EXAMPLE
        $c = New-TguiColor -Tgui $tg -Rgb '205,214,244'
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Tgui,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Rgb
    )

    $parts = $Rgb.Split(',')
    if ($parts.Count -ne 3) {
        throw "New-TguiColor: 非法的颜色值 '$Rgb', 应为 'R,G,B' 形式"
    }
    $r = [int]$parts[0]; $g = [int]$parts[1]; $b = [int]$parts[2]

    $colorType = $Tgui.Types.Color
    $ctor = $colorType.GetConstructors() |
        Where-Object {
            $p = $_.GetParameters()
            $p.Count -ge 3 -and $p[0].ParameterType.Name -eq 'Int32'
        } |
        Select-Object -First 1
    if ($null -eq $ctor) {
        throw 'New-TguiColor: Terminal.Gui.Drawing.Color 未找到 (Int32,Int32,Int32,Int32) 构造函数(ALC 装配结构与预期不符)。'
    }
    # Color(Int32 r, Int32 g, Int32 b, Int32 alpha): alpha 固定 255(不透明)
    $values = @([int]$r, [int]$g, [int]$b, [int]255)
    return $ctor.Invoke($values)
}

function New-TguiAttribute {
    <#
    .SYNOPSIS
        构造 **本 ALC 内**的 Terminal.Gui.Drawing.Attribute(前景/背景)。

    .DESCRIPTION
        ★ 关键坑: Attribute 的构造函数以 **Color&(byref)** 形参接收颜色。
        PowerShell 的 [ref]$color 是 PSReference, 反射 Invoke 无法转换成
        Color&(实测抛 "PSReference`1[Color] cannot be converted to type 'Color&'")。
        正确姿势: 把装箱后的 Color 直接放进 args 数组, 由运行时取其地址作为
        byref 实参(探针 p53 方案 A 实测通过)。

    .PARAMETER Tgui
        Get-TguiContext 的返回值。

    .PARAMETER FgRgb
        前景 'R,G,B' 文本。

    .PARAMETER BgRgb
        背景 'R,G,B' 文本。

    .OUTPUTS
        ALC 所属的 Attribute 实例。

    .EXAMPLE
        $a = New-TguiAttribute -Tgui $tg -FgRgb '205,214,244' -BgRgb '24,24,37'
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Tgui,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FgRgb,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$BgRgb
    )

    $fgColor = New-TguiColor -Tgui $Tgui -Rgb $FgRgb
    $bgColor = New-TguiColor -Tgui $Tgui -Rgb $BgRgb
    $attrType = $Tgui.Types.Attribute

    # 优先按值构造(若某个版本提供), 否则用 byref 构造(2.4.10 实测只有 byref)。
    $ctor = $attrType.GetConstructors() |
        Where-Object {
            $p = $_.GetParameters()
            $p.Count -eq 2 -and
            $p[0].ParameterType.GetElementType().Name -eq 'Color' -and
            $p[1].ParameterType.GetElementType().Name -eq 'Color'
        } |
        Select-Object -First 1
    if ($null -eq $ctor) {
        throw 'New-TguiAttribute: Terminal.Gui.Drawing.Attribute 未找到 (Color, Color) 构造函数。'
    }
    # byref 实参 = args 数组元素的地址(不是 PSReference)
    return $ctor.Invoke(@($fgColor, $bgColor))
}

function Set-TguiSlot {
    <#
    .SYNOPSIS
        就地改写 ALC Scheme 的单个槽位(先读后比, 等值跳过)。

    .DESCRIPTION
        幂等契约(ALC Scheme 实测): "写入与现值相同的 Attribute" 会触发
        Scheme 重建并把槽位打回内置默认(实测 4 轮交替翻转), 必须等值跳过。
        未知/只读槽位按 Verbose 跳过不抛错 —— 配色部分生效优于完全不生效。

    .PARAMETER Tgui
        Get-TguiContext 的返回值。

    .PARAMETER Scheme
        ALC Scheme 实例(SchemeManager.GetScheme('Menu'|'Base' ...))。

    .PARAMETER Slot
        槽位名(Normal/Focus/HotNormal ...)。

    .PARAMETER Entry
        @{ Fg = 'R,G,B'; Bg = 'R,G,B' }。

    .OUTPUTS
        [bool] $true = 槽位已是目标值或已写入; $false = 未知/只读槽位。

    .EXAMPLE
        Set-TguiSlot -Tgui $tg -Scheme $scheme -Slot 'Normal' -Entry @{ Fg = '205,214,244'; Bg = '24,24,37' }
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Tgui,

        [Parameter(Mandatory = $true)]
        [object]$Scheme,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Slot,

        [Parameter(Mandatory = $true)]
        [hashtable]$Entry
    )

    $schemeType = $Tgui.Types.Scheme
    $property = $schemeType.GetProperty($Slot)
    if ($null -eq $property -or -not $property.CanWrite) {
        Write-Verbose "[Set-TguiSlot] 跳过未知/只读槽位 '$Slot'"
        return $false
    }

    $current = $property.GetValue($Scheme, $null)
    $wanted = New-TguiAttribute -Tgui $Tgui -FgRgb $Entry.Fg -BgRgb $Entry.Bg
    if ($null -ne $current -and
        $current.Foreground.R -eq $wanted.Foreground.R -and
        $current.Foreground.G -eq $wanted.Foreground.G -and
        $current.Foreground.B -eq $wanted.Foreground.B -and
        $current.Background.R -eq $wanted.Background.R -and
        $current.Background.G -eq $wanted.Background.G -and
        $current.Background.B -eq $wanted.Background.B) {
        return $true
    }

    $property.SetValue($Scheme, $wanted, $null)
    return $true
}

function Set-TguiTheme {
    <#
    .SYNOPSIS
        把 UI.Theme 槽位集覆写到 ALC SchemeManager 的方案实例上(幂等)。

    .DESCRIPTION
        同约束(幂等 + 降级):
          - 只取**已存在**的方案实例(优先配置里的方案名, 缺失回退 'Base'),
            不新增方案名、不写 ThemeManager.Theme;
          - 逐槽位等值跳过(Sync-TgSchemeSlot 同语义);
          - 颜色属视觉增强: 配置 Enabled=$false 或全部槽位失败时返回 $false,
            调用方继续用 TG 内置配色(美感降级, 功能不破)。

        方案差异化(2026-10-31 UI 层次升级): UI.Theme.SchemeOverrides
        按**方案名**给出附加槽位, 在公共 Slots 之后覆写 —— 让不同方案
        (如 'Menu' 承载的边缘色带)与正文分层, 未列出的槽位沿用 Slots。

    .PARAMETER Tgui
        Get-TguiContext 的返回值(调用方持有, 避免 ALC 重复拉起)。

    .OUTPUTS
        [bool] $true = 至少一个槽位写入(或已是目标值); $false = 主题禁用/未配置/全部失败。

    .EXAMPLE
        $ok = Set-TguiTheme -Tgui (Get-TguiContext)
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Tgui
    )

    $theme = $script:Config.UI.Theme
    if ($null -eq $theme -or -not $theme.Enabled) {
        return $false
    }
    $schemeManagerType = $Tgui.Types.SchemeManager
    if ($null -eq $schemeManagerType) {
        return $false
    }

    # 方案名集合(与 Resolve-TguiThemeName 同语义: undefined->'Base'; 多名字支持)
    $names = Resolve-TguiThemeName -Name $theme.Name

    # GetScheme(string) 反射查找(不依赖类型字面量, 防跨程序集解析)
    $getScheme = $schemeManagerType.GetMethod('GetScheme', [type[]]@([string]))
    if ($null -eq $getScheme) {
        return $false
    }

    $applied = 0
    foreach ($name in $names) {
        try {
            $scheme = $getScheme.Invoke($null, @("$name"))
        } catch {
            Write-Verbose "Set-TguiTheme: 方案 '$name' 读取失败: $($_.Exception.InnerException.Message)"
            continue
        }
        if ($null -eq $scheme) {
            Write-Verbose "Set-TguiTheme: 方案 '$name' 不存在, 跳过"
            continue
        }
        foreach ($slotName in @($theme.Slots.Keys)) {
            $entry = $theme.Slots[$slotName]
            if ($null -eq $entry) { continue }
            try {
                if (Set-TguiSlot -Tgui $Tgui -Scheme $scheme -Slot $slotName -Entry $entry) {
                    $applied++
                }
            } catch {
                Write-Verbose "Set-TguiTheme: 槽位 '$slotName' 写入失败: $($_.Exception.Message)"
            }
        }
        # ---- 方案差异化槽位(按方案名的覆写, 未列出者沿用 Slots) ----
        # UI 域是 [ordered] OrderedDictionary(§2.7): 判键用 .Contains, 不是 PSObject.Properties
        $overrides = $null
        if ($theme.Contains('SchemeOverrides')) {
            $overrides = $theme['SchemeOverrides']
        }
        if ($null -ne $overrides -and $overrides.Contains("$name")) {
            $overrideSlots = $overrides["$name"]
            if ($null -ne $overrideSlots) {
                foreach ($slotName in @($overrideSlots.Keys)) {
                    $entry = $overrideSlots[$slotName]
                    if ($null -eq $entry) { continue }
                    try {
                        if (Set-TguiSlot -Tgui $Tgui -Scheme $scheme -Slot $slotName -Entry $entry) {
                            $applied++
                        }
                    } catch {
                        Write-Verbose "Set-TguiTheme: 差异化槽位 '$name'/'$slotName' 写入失败: $($_.Exception.Message)"
                    }
                }
            }
        }
    }
    return ($applied -gt 0)
}

function Test-TguiSchemeVisible {
    <#
    .SYNOPSIS
        判断一个 Scheme 实例的 Normal 槽位是否"看得见"(前景 != 背景)。

    .DESCRIPTION
        真机故障的判据: TG 内置 'Base' 的 Normal 是 fg=bg=255,255,255,
        文字与背景同色 ⇒ 完全隐形。本判定用于在**绑定视图之前**筛掉
        不可用方案, 避免"绑了方案但界面空白"。

    .PARAMETER Scheme
        ALC Scheme 实例。

    .OUTPUTS
        [bool] $true = Normal 前景与背景不同色(可见)。

    .EXAMPLE
        Test-TguiSchemeVisible -Scheme $scheme
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Scheme
    )

    if ($null -eq $Scheme) { return $false }
    try {
        $normal = $Scheme.Normal
        if ($null -eq $normal) { return $false }
        $fg = $normal.Foreground
        $bg = $normal.Background
        return -not ($fg.R -eq $bg.R -and $fg.G -eq $bg.G -and $fg.B -eq $bg.B)
    } catch {
        Write-Verbose "[Test-TguiSchemeVisible] 读取 Normal 失败: $($_.Exception.Message)"
        return $false
    }
}

function Resolve-TguiScheme {
    <#
    .SYNOPSIS
        取出一个**内容可见**的 Scheme 实例, 供仪表盘视图显式绑定。

    .DESCRIPTION
        按候选名顺序取 SchemeManager 里已存在的实例, 返回第一个
        Normal 前景 != 背景(可见)的那个; 全部不可见时返回第一个存在的实例
        并记 Verbose(此时界面可能不可读, 但不至于崩)。

        为什么要显式绑定: TG 2.4.10 的视图默认方案名不统一
        (Window->'Base'、StatusBar->'Menu'、Label/TableView->'' 回退 'Base'),
        显式绑定可让"同一份配色"覆盖全部视图, 不依赖 TG 内部默认值。

    .PARAMETER Tgui
        Get-TguiContext 的返回值。

    .PARAMETER Names
        候选方案名(按优先级)。

    .OUTPUTS
        ALC Scheme 实例, 或 $null(一个都取不到)。

    .EXAMPLE
        $scheme = Resolve-TguiScheme -Tgui $tg -Names @('Base', 'Menu')
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Tgui,

        [Parameter(Mandatory = $false)]
        [string[]]$Names = @('Base', 'Menu')
    )

    $schemeManagerType = $Tgui.Types.SchemeManager
    if ($null -eq $schemeManagerType) { return $null }
    $getScheme = $schemeManagerType.GetMethod('GetScheme', [type[]]@([string]))
    if ($null -eq $getScheme) { return $null }

    $fallback = $null
    foreach ($name in $Names) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        try {
            $scheme = $getScheme.Invoke($null, @("$name"))
        } catch {
            Write-Verbose "[Resolve-TguiScheme] 取方案 '$name' 失败: $($_.Exception.InnerException.Message)"
            continue
        }
        if ($null -eq $scheme) { continue }
        if ($null -eq $fallback) { $fallback = $scheme }
        if (Test-TguiSchemeVisible -Scheme $scheme) {
            return $scheme
        }
        Write-Verbose "[Resolve-TguiScheme] 方案 '$name' 前景=背景(不可见), 继续尝试下一个"
    }

    if ($null -ne $fallback) {
        Write-Verbose '[Resolve-TguiScheme] 所有候选方案都不可见, 退回第一个存在的实例'
    }
    return $fallback
}
