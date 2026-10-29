# Set-TgColorScheme.ps1 - Terminal.Gui v2 配色方案装配
# 职责: 把旧 ANSI 菜单的观感(取自 $script:Config.Colors)迁移到 PSTui 的
#       Out-ConsoleGridView 所使用的 Terminal.Gui v2 配色上。
#
# ============================ 关键实现决策 ============================
# 经对本仓库 Terminal.Gui 2.4.10 实测(非推测), "新增方案名 + 设 ThemeManager.Theme"
# 这条看似标准的路径**会破坏 SchemeManager 内部状态**:
#   1. SchemeManager.Schemes 是配置驱动的字典, 读取时按当前 Theme 重建;
#   2. 手工往 Schemes 塞入新 key 后再设 ThemeManager.Theme, 再次读取 Schemes
#      抛 "The given key '<名字>' was not present in the dictionary.";
#   3. 之后所有 GetScheme / GetSchemesForCurrentTheme 全部抛异常,
#      即配色没生效反而把整个 GridView 配色系统搞坏。
# 因此本实现采取"就地覆写"策略:
#   - 用 SchemeManager.GetScheme(<名字>) 取出**已存在的** Scheme 实例
#     (该实例引用稳定, 重复调用返回同一对象);
#   - 直接改写其 10 个槽位属性;
#   - 全程不新增方案名、不写 ThemeManager.Theme, 从根上避开上述缺陷。
# 目标方案名可通过 $script:Config.UI.Theme.Name 配置, 默认覆写内置 'Menu'
# (菜单语义最贴近); 若该名字不存在则回退到 'Base'。
# ======================================================================
#
# 降级契约: 颜色纯属视觉增强, 任何 TG 异常都不允许阻断菜单显示。
#   - Test-TgColorSchemeSupport 负责"类型不可用"这一层的静默降级(返回 $false);
#   - 其余异常向上抛, 由 Invoke-GridViewPrompt 的 try/catch 告警后继续弹菜单。

function New-TgColor {
    <#
    .SYNOPSIS
        把 'R,G,B' 字符串转换为 Terminal.Gui.Drawing.Color。

    .DESCRIPTION
        颜色值统一以 'R,G,B' 文本形式写在配置里(便于用户覆盖), 在此集中转换。
        Alpha 固定 255(不透明): 菜单背景需要稳定实色, 半透明在部分终端下会退化为默认色。

    .PARAMETER Rgb
        逗号分隔的 0-255 三元组字符串, 例如 '137,209,133'

    .OUTPUTS
        Terminal.Gui.Drawing.Color

    .EXAMPLE
        New-TgColor -Rgb '112,199,209'
    #>
    # 纯值构造函数: 无任何状态变更, 故不实现 ShouldProcess, 显式抑制该规则告警。
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Rgb
    )

    $parts = $Rgb.Split(',')
    if ($parts.Count -ne 3) {
        throw "Set-TgColorScheme: 非法的颜色值 '$Rgb', 应为 'R,G,B' 形式"
    }
    $r = [int]$parts[0]
    $g = [int]$parts[1]
    $b = [int]$parts[2]

    # Color 是 struct, 用 New-Object 而非 ::new(), 兼容 PowerShell 对值类型的构造绑定
    return (New-Object Terminal.Gui.Drawing.Color -ArgumentList $r, $g, $b, 255)
}

function New-TgAttribute {
    <#
    .SYNOPSIS
        由前景/背景颜色字符串构造 Terminal.Gui.Drawing.Attribute。

    .DESCRIPTION
        关键实现细节: Attribute 的构造函数以 ref Color 形参接收颜色,
        在 PowerShell 里必须用 [ref] 包装, 直接传值会抛
        "Cannot convert value to type Terminal.Gui.Drawing.Color&"。

    .PARAMETER Foreground
        前景色, 'R,G,B' 字符串

    .PARAMETER Background
        背景色, 'R,G,B' 字符串

    .OUTPUTS
        Terminal.Gui.Drawing.Attribute

    .EXAMPLE
        New-TgAttribute -Foreground '20,20,20' -Background '112,199,209'
    #>
    # 纯值构造函数: 同 New-TgColor, 无状态变更。
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Foreground,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Background
    )

    $fg = New-TgColor -Rgb $Foreground
    $bg = New-TgColor -Rgb $Background
    return (New-Object Terminal.Gui.Drawing.Attribute -ArgumentList ([ref]$fg), ([ref]$bg))
}

function Set-TgSchemeSlot {
    <#
    .SYNOPSIS
        就地覆写单个 Scheme 槽位的颜色。

    .DESCRIPTION
        槽位名若在当前 TG 版本上不存在或只读, 记一条 Verbose 后跳过,
        不抛错——配色部分生效优于完全不生效。

        **必须走 CLR 反射而不是 $obj.PSObject.Properties[$name]**:
        实测 PowerShell 对 .NET 对象的适配属性返回的 PSPropertyInfo 上
        `CanWrite` 恒为 $null(该成员在 PSPropertyInfo 上根本不存在),
        用它做可写性判断会导致所有槽位被静默跳过、配色完全不生效,
        但函数仍然返回成功。CLR 的 PropertyInfo.CanWrite 才是可靠来源。

        **写入前必须先比对当前值(已一致则跳过)**: 实测 TG 2.4.10 在把"与现值相同"
        的 Attribute 再写一遍时, 并非幂等 no-op, 而是触发一次 Scheme 重建,
        结果槽位被**打回内置默认配色**。表现是每调用一次就在
        "自定义配色" 与 "TG 默认配色" 之间来回翻转(实测 4 轮严格交替)。
        跳过等值写入既避免翻转, 也顺带让重复调用变廉价。

    .PARAMETER Scheme
        已存在的 Terminal.Gui.Drawing.Scheme 实例

    .PARAMETER Slot
        槽位名, 例如 'HotFocus'

    .PARAMETER Entry
        形如 @{ Fg = 'R,G,B'; Bg = 'R,G,B' } 的颜色定义

    .EXAMPLE
        Set-TgSchemeSlot -Scheme $scheme -Slot 'Normal' -Entry @{ Fg = '1,2,3'; Bg = '4,5,6' }
    #>
    # 纯赋值函数, 无外部状态变更。
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Scheme,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Slot,

        [Parameter(Mandatory = $true)]
        [hashtable]$Entry
    )

    $property = [Terminal.Gui.Drawing.Scheme].GetProperty($Slot)
    if ($null -eq $property -or -not $property.CanWrite) {
        Write-Verbose "Set-TgColorScheme: 跳过未知/只读槽位 '$Slot'"
        return $false
    }

    $current = $property.GetValue($Scheme, $null)
    $wanted = New-TgAttribute -Foreground $Entry.Fg -Background $Entry.Bg
    if ($current.Foreground -eq $wanted.Foreground -and $current.Background -eq $wanted.Background) {
        return $true
    }

    $property.SetValue($Scheme, $wanted, $null)
    return $true
}

function Get-TgTargetScheme {
    <#
    .SYNOPSIS
        取出待覆写的 Scheme 实例。

    .DESCRIPTION
        优先使用配置里指定的方案名(默认 'Menu'); 该名字在当前 TG 中不存在时
        回退到 'Base'。**只取已存在实例, 绝不新增方案名**——新增会触发
        Schemes 配置字典与 ThemeManager 之间的状态不一致(见文件头说明)。

    .PARAMETER Name
        期望的方案名

    .OUTPUTS
        Terminal.Gui.Drawing.Scheme, 或 $null(两者都取不到)

    .EXAMPLE
        Get-TgTargetScheme -Name 'Menu'
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Name = 'Base'
    )

    foreach ($candidate in @($Name, 'Base')) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        try {
            $scheme = [Terminal.Gui.Configuration.SchemeManager]::GetScheme($candidate)
            if ($scheme) { return $scheme }
        } catch {
            Write-Verbose "Set-TgColorScheme: 方案 '$candidate' 不可用: $($_.Exception.Message)"
        }
    }
    return $null
}

function Resolve-TgThemeName {
    <#
    .SYNOPSIS
        把配置里的 UI.Theme.Name 规范化成方案名列表。

    .DESCRIPTION
        真终端颜色指纹探针实测(PSTui 1.0.5 + TG 2.4.10.0): 表格主体取自
        Scheme 'Base', 底部状态栏取自 Scheme 'Menu'。只覆写其中一个必然
        "看起来没生效", 因此配置形态必须支持多 Scheme。

        **必须兼容两种旧/新形态**:
          - [string[]]@('Base','Menu') —— 当前默认形态;
          - 裸字符串 'Menu'            —— 用户既有配置文件里的形态。
        裸字符串经过 @() 包裹天然成为单元素数组, 此处再做逗号切分与去空白,
        任何形态都不会抛异常。空值 / 全空白时回退到 'Base'。

    .PARAMETER Name
        配置里的原始值, 允许为 $null / 单字符串 / 字符串数组

    .OUTPUTS
        [string[]] 已去重、去空白的方案名数组

    .EXAMPLE
        Resolve-TgThemeName -Name 'Menu'
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Name
    )

    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($item in @($Name)) {
        if ($null -eq $item) { continue }
        # 兼容 'Base,Menu' 这种被写成单个逗号分隔字符串的形态
        foreach ($piece in ([string]$item -split ',')) {
            $trimmed = $piece.Trim()
            if ($trimmed -and -not $names.Contains($trimmed)) {
                $names.Add($trimmed)
            }
        }
    }
    if ($names.Count -eq 0) {
        $names.Add('Base')
    }
    return $names.ToArray()
}

function Sync-TgSchemeSlot {
    <#
    .SYNOPSIS
        把整套槽位配色同步到**单个** Scheme 实例, 返回真正落地的槽位数。

    .DESCRIPTION
        从 Set-TgColorScheme 拆出, 保证入口函数不超过 80 行。
        逐槽位调用 Set-TgSchemeSlot(内含"先读后比、等值跳过"的幂等保护)。

    .PARAMETER Scheme
        已存在的 Terminal.Gui.Drawing.Scheme 实例

    .PARAMETER Slots
        形如 @{ Normal = @{ Fg = 'R,G,B'; Bg = 'R,G,B' } } 的槽位表

    .OUTPUTS
        [int] 成功应用的槽位数

    .EXAMPLE
        Sync-TgSchemeSlot -Scheme $scheme -Slots $script:Config.UI.Theme.Slots
    #>
    # 纯赋值同步, 状态变更由调用方 Set-TgColorScheme 的 ShouldProcess 统一把关。
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Scheme,

        [Parameter(Mandatory = $true)]
        [hashtable]$Slots
    )

    $applied = 0
    foreach ($slotName in $Slots.Keys) {
        if (Set-TgSchemeSlot -Scheme $Scheme -Slot $slotName -Entry $Slots[$slotName]) {
            $applied++
        }
    }
    return $applied
}

function Set-TgColorScheme {
    <#
    .SYNOPSIS
        就地覆写 Terminal.Gui 各内置 Scheme 的表格相关槽位(幂等)。

    .DESCRIPTION
        执行顺序:
          1. 读取 $script:Config.UI.Theme; Enabled 为假时直接返回 $false;
          2. 确认 Terminal.Gui 类型已加载(必要时 Add-Type), 不可用则返回 $false;
          3. 用 Resolve-TgThemeName 规范化出方案名列表(兼容旧单字符串配置);
          4. 逐个取到**已存在**的 Scheme 实例(单个名字不存在时回退 'Base'),
             再由 Sync-TgSchemeSlot 逐槽位覆写。

        幂等性依赖 Set-TgSchemeSlot 的"先读后比、等值跳过": TG 2.4.10
        把与现值相同的 Attribute 再写一遍会触发 Scheme 重建, 把槽位打回内置默认。
        本函数不吞异常: 由调用方的 try/catch 负责告警后继续弹菜单。

    .OUTPUTS
        [bool] $true = 至少一个槽位落地; $false = 配置禁用 / TG 未就绪 / 取不到 Scheme

    .EXAMPLE
        Set-TgColorScheme
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([bool])]
    param()

    $theme = $script:Config.UI.Theme
    if ($null -eq $theme -or -not $theme.Enabled) {
        return $false
    }

    if (-not (Test-TgColorSchemeSupport)) {
        return $false
    }

    $names = Resolve-TgThemeName -Name $theme.Name
    $target = "Terminal.Gui Scheme($($names -join ',') 槽位$($theme.Slots.Count)项)"
    if (-not $PSCmdlet.ShouldProcess($target, '覆写')) {
        return $false
    }

    # 统计真正落地的槽位数: 一个都没写成功时必须报 $false,
    # 否则调用方会误以为配色已生效(这正是 CanWrite 缺陷曾造成的静默失败)。
    $applied = 0
    $touched = [System.Collections.Generic.List[string]]::new()
    foreach ($name in $names) {
        $scheme = Get-TgTargetScheme -Name $name
        if ($null -eq $scheme) {
            Write-Verbose "Set-TgColorScheme: 未找到可覆写的 Scheme 实例 '$name', 跳过"
            continue
        }
        $hit = Sync-TgSchemeSlot -Scheme $scheme -Slots $theme.Slots
        if ($hit -gt 0) {
            $applied += $hit
            $touched.Add($name)
        }
    }

    if ($applied -eq 0) {
        Write-Verbose 'Set-TgColorScheme: 没有任何槽位写入成功, 沿用 Terminal.Gui 内置配色'
        return $false
    }
    Write-Verbose "Set-TgColorScheme: 已覆写 $($touched -join ',') 共 $applied 个槽位"
    return $true
}

function Test-TgColorSchemeSupport {
    <#
    .SYNOPSIS
        探测 Terminal.Gui 配色相关类型是否可用。

    .DESCRIPTION
        优先复用已加载的 TG 会话程序集(避免重复 Add-Type 抛
        "Assembly with same name is already loaded"); 只有在类型尚未出现时,
        才从仓库 Modules/PSTui/<version>/ 下按路径降序取 Terminal.Gui.dll 加载。
        路径完全由 $PSScriptRoot 相对推导, 不含任何硬编码绝对路径。

    .OUTPUTS
        [bool] $true = SchemeManager / Scheme / Color / Attribute 均可解析

    .EXAMPLE
        Test-TgColorSchemeSupport
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $requiredTypes = @(
        'Terminal.Gui.Configuration.SchemeManager'
        'Terminal.Gui.Drawing.Scheme'
        'Terminal.Gui.Drawing.Color'
        'Terminal.Gui.Drawing.Attribute'
    )

    # 已加载(PSTui 之前已拉起 TG)时直接返回, 不重复 Add-Type
    if ($requiredTypes | Where-Object { -not ($_ -as [type]) }) {
        $dll = Get-TgAssemblyPath
        if (-not $dll) { return $false }
        try {
            Add-Type -Path $dll -ErrorAction Stop
        } catch {
            Write-Verbose "Set-TgColorScheme: 加载 Terminal.Gui 失败: $($_.Exception.Message)"
            return $false
        }
    }

    foreach ($typeName in $requiredTypes) {
        if (-not ($typeName -as [type])) { return $false }
    }
    return $true
}

function Get-TgAssemblyPath {
    <#
    .SYNOPSIS
        定位仓库内的 Terminal.Gui.dll。

    .DESCRIPTION
        以 $PSScriptRoot(Private 目录)为基准上溯两层到仓库根, 再在
        Modules/PSTui/*/ 下按路径降序取最新的 Terminal.Gui.dll。
        找不到时返回 $null, 由调用方降级。

    .OUTPUTS
        [string] 绝对路径, 或 $null

    .EXAMPLE
        Get-TgAssemblyPath
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $repoRoot = (Get-Item -LiteralPath $PSScriptRoot).Parent.Parent.FullName
    $candidate = Get-ChildItem -Path (Join-Path $repoRoot 'Modules\PSTui') -Filter 'Terminal.Gui.dll' `
        -Recurse -File -ErrorAction SilentlyContinue |
        Sort-Object -Property FullName -Descending |
        Select-Object -First 1
    if ($candidate) { return $candidate.FullName }
    return $null
}
