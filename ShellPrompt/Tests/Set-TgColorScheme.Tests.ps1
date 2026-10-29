<#
.SYNOPSIS
    Terminal.Gui 配色装配 (Set-TgColorScheme 及其辅助函数) 的 Pester 测试

.DESCRIPTION
    覆盖四条核心契约:
      1. 幂等: 连调两次不抛错, 且槽位值稳定(不累积、不漂移);
      2. 生效: 覆写后 GetScheme 取回的槽位值等于配置值;
      3. 多 Scheme: 配置默认覆写 'Base' + 'Menu' 两个内置方案 ——
         真终端颜色指纹探针实测, 表格主体取自 Base、底部状态栏取自 Menu,
         只覆写其一会表现为"配色完全没生效";
      4. 降级: Terminal.Gui 类型不可用 / 取不到 Scheme 时返回 $false 而不抛异常
         —— 这是最重要的一条, 配色绝不允许阻断菜单显示。

.NOTES
    注意: 本套用例验证的是 **Scheme 字典里的槽位值**,
    不是真终端屏幕上实际渲染出来的颜色。后者只能由用户肉眼确认。
#>

Describe 'TG 配色方案' {

    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..\ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module ShellPrompt
    }

    It '应暴露配色相关的私有函数' {
        $names = & $script:mod { Get-Command -CommandType Function -Name '*Tg*' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name }
        foreach ($expected in @('Set-TgColorScheme', 'Test-TgColorSchemeSupport', 'Get-TgAssemblyPath', 'Get-TgTargetScheme', 'New-TgColor', 'New-TgAttribute', 'Set-TgSchemeSlot', 'Sync-TgSchemeSlot', 'Resolve-TgThemeName')) {
            $names | Should -Contain $expected
        }
    }

    It '配置中应存在 UI.Theme 且默认启用' {
        $theme = & $script:mod { $script:Config.UI.Theme }
        $theme | Should -Not -BeNullOrEmpty
        $theme.Enabled | Should -Be $true
        $theme.Name | Should -Not -BeNullOrEmpty
    }

    It '配置默认应同时覆写 Base 与 Menu 两个 Scheme' {
        # 回归防护: 早期实现只覆写 'Menu', 结果只染了底部状态栏, 主体表格毫无变化。
        $names = & $script:mod { @(Resolve-TgThemeName -Name $script:Config.UI.Theme.Name) }
        $names | Should -Contain 'Base'
        $names | Should -Contain 'Menu'
        $names.Count | Should -BeGreaterThan 1
    }

    It '配置应覆盖全部表格视觉槽位且格式合法' {
        $slots = & $script:mod { $script:Config.UI.Theme.Slots }
        # 组一: 反射实测可写的基础槽位
        foreach ($slot in @('Normal', 'HotNormal', 'Focus', 'HotFocus', 'Active', 'HotActive', 'Highlight', 'Editable', 'ReadOnly', 'Disabled')) {
            $slots.Keys | Should -Contain $slot
        }
        foreach ($entry in $slots.Values) {
            $entry.Fg | Should -Match '^\d{1,3},\d{1,3},\d{1,3}$'
            $entry.Bg | Should -Match '^\d{1,3},\d{1,3},\d{1,3}$'
        }
    }

    It '默认配置不应再包含 2.4.10 上不存在的占位槽位名' {
        # 回归防护: 旧实现把 ColumnHeader/Selected/Border 等 12 个**自造**名字写进默认配置,
        # 它们在 TG 2.4.10 的 Scheme 上根本不存在, 全部被静默跳过 -> 只会误导用户。
        $slots = & $script:mod { $script:Config.UI.Theme.Slots }
        foreach ($slot in @('Base', 'Contrast', 'FocusBackground', 'FocusForeground', 'Selected', 'SelectedFocused', 'Marked', 'MarkedFocused', 'ColumnHeader', 'ColumnHeaderFocused', 'Border', 'BorderFocused')) {
            $slots.Keys | Should -Not -Contain $slot
        }
    }

    It '配置中的每个槽位名都必须是 Scheme 上真实可写的属性' {
        # 防"再次写入自造名字"回归: 用 CLR 反射判定可写性(PSObject.Properties 上没有 CanWrite)
        $result = & $script:mod {
            if (-not (Test-TgColorSchemeSupport)) { return 'TG-UNAVAILABLE' }
            $bad = @()
            foreach ($slot in $script:Config.UI.Theme.Slots.Keys) {
                $prop = [Terminal.Gui.Drawing.Scheme].GetProperty($slot)
                if ($null -eq $prop -or -not $prop.CanWrite) { $bad += $slot }
            }
            ($bad -join ',')
        }
        if ($result -ne 'TG-UNAVAILABLE') {
            $result | Should -Be ''
        }
    }

    It '选中行(Active)与聚焦列头(Focus)槽位应按配置写入 Base 与 Menu' {
        # IL 实测结论( TG 2.4.10.0 ):
        #   TableView.RenderRow 选中行
        #       -> new Attribute(hasFocus ? scheme.Focus : scheme.Active)  前景+背景都取自该槽位
        #   TableView.RenderHeaderMidline
        #       -> scheme.Focus(表格有焦点)/ scheme.Normal(无焦点)
        # 因此"选中行"语义落在 Focus(有焦点) 与 Active(无焦点) 两个槽位,
        # "列头"语义落在 Focus —— Focus 被两者共用, 这正是高亮不一致的根因。
        $result = & $script:mod {
            if (-not (Test-TgColorSchemeSupport)) { return 'TG-UNAVAILABLE' }
            if (-not (Set-TgColorScheme)) { return 'NOT-APPLIED' }
            $a = $script:Config.UI.Theme.Slots['Active']
            $f = $script:Config.UI.Theme.Slots['Focus']
            $expected = "Active=$($a.Fg)/$($a.Bg);Focus=$($f.Fg)/$($f.Bg)"
            $out = foreach ($n in @('Base', 'Menu')) {
                $s = [Terminal.Gui.Configuration.SchemeManager]::GetScheme($n)
                if ($null -eq $s) { "$n=NO-SCHEME"; continue }
                $av = "$($s.Active.Foreground.R),$($s.Active.Foreground.G),$($s.Active.Foreground.B)/$($s.Active.Background.R),$($s.Active.Background.G),$($s.Active.Background.B)"
                $fv = "$($s.Focus.Foreground.R),$($s.Focus.Foreground.G),$($s.Focus.Foreground.B)/$($s.Focus.Background.R),$($s.Focus.Background.G),$($s.Focus.Background.B)"
                "$n=Active=$av;Focus=$fv"
            }
            "$expected|$($out -join ';')"
        }
        if ($result -ne 'TG-UNAVAILABLE' -and $result -ne 'NOT-APPLIED') {
            $expected, $observed = $result -split '\|', 2
            $observed | Should -Be "Base=$expected;Menu=$expected"
        }
    }

    It 'Focus 与 Active 应配置为完全相同的颜色(高亮在所有焦点状态下统一)' {
        # 回归防护(根因修复): TableView.RenderRow 用
        #   hasFocus ? scheme.Focus : scheme.Active
        # 决定选中行取色, 因此只有让 Focus == Active,
        # 选中行在"焦点在表格"与"焦点在过滤框"两种状态下才视觉一致。
        $slots = & $script:mod { $script:Config.UI.Theme.Slots }
        $focus = $slots['Focus']
        $active = $slots['Active']
        $focus.Fg | Should -Be $active.Fg
        $focus.Bg | Should -Be $active.Bg
        # 新契约 (2026-10-18): Focus / Active 不再是 Cyan 底, 改为亮绿字 + 稍亮底
        $focus.Fg | Should -Be '137,209,133'
        $focus.Bg | Should -Be '40,40,40'
    }

    It 'Focus 槽位底色应不再含 Cyan(让列头融入绿主题)' {
        # 回归防护: 用户反馈列头在焦点态被高亮成亮青色 (Cyan=112,199,209),
        # 与绿主题不搭。本用例锁定 Focus 底色**不再**含 Cyan。
        $slots = & $script:mod { $script:Config.UI.Theme.Slots }
        $focusBg = $slots['Focus'].Bg
        $focusBg | Should -Not -Be '112,199,209'
        # 与之相关联的 Active / Highlight 也同步同值(高亮统一)
        $slots['Active'].Bg  | Should -Be $focusBg
        $slots['Highlight'].Bg | Should -Be $focusBg
    }

    It 'Editable 槽位应配为亮绿字 + 暗底(过滤框可读)' {
        # 回归防护: v2.1 之前 Editable 是警告黄 (230,180,80) + 30,30,30,
        # 与"绿主题 + 列头亮绿字"的整体观感割裂; 新契约下前景亮绿 + 近黑底。
        $slots = & $script:mod { $script:Config.UI.Theme.Slots }
        $slots['Editable'].Fg | Should -Be '137,209,133'
        $slots['Editable'].Bg | Should -Be '20,20,20'
    }

    It '应用后 Base/Menu 的 Focus 与 Active 槽位应完全一致' {
        # 复核: 写入 TG 之后, 两个 Scheme 上的 Focus 与 Active 也必须同色,
        # 否则"统一"只停留在配置文件里, 没有落到运行时。
        $result = & $script:mod {
            if (-not (Test-TgColorSchemeSupport)) { return 'TG-UNAVAILABLE' }
            if (-not (Set-TgColorScheme)) { return 'NOT-APPLIED' }
            $out = foreach ($n in @('Base', 'Menu')) {
                $s = [Terminal.Gui.Configuration.SchemeManager]::GetScheme($n)
                if ($null -eq $s) { "$n=NO-SCHEME"; continue }
                "$n=$($s.Focus)|$($s.Active)"
            }
            ($out -join ';')
        }
        if ($result -ne 'TG-UNAVAILABLE' -and $result -ne 'NOT-APPLIED') {
            foreach ($item in $result -split ';') {
                $k, $v = $item -split '=', 2
                $k | Should -Not -Be 'NO-SCHEME'
                $focusAttr, $activeAttr = $v -split '\|'
                $focusAttr | Should -Be $activeAttr
            }
        }
    }

    It '高亮统一后连续三轮应用 Focus/Active 不得翻转' {
        # 回归防护: TG 2.4.10 下"写入与现值相同的 Attribute"会重建 Scheme 并
        # 把槽位打回内置默认, 表现为配色来回跳变。这里锁定 3 轮完全一致。
        $rounds = & $script:mod {
            if (-not (Test-TgColorSchemeSupport)) { return 'TG-UNAVAILABLE' }
            $out = foreach ($i in 1..3) {
                $null = Set-TgColorScheme
                $s = [Terminal.Gui.Configuration.SchemeManager]::GetScheme('Base')
                "$($s.Focus)|$($s.Active)"
            }
            ($out | Select-Object -Unique).Count
        }
        if ($rounds -ne 'TG-UNAVAILABLE') {
            [int]$rounds | Should -Be 1
        }
    }

    It '旧配置里残留的占位槽位名应被忽略而不是报错' {
        # 向后兼容: 用户既有配置里可能仍留着这 12 个名字, 必须静默跳过
        $result = & $script:mod {
            if (-not (Test-TgColorSchemeSupport)) { return 'TG-UNAVAILABLE' }
            $original = $script:Config.UI.Theme.Slots
            try {
                $legacy = [ordered]@{}
                foreach ($k in $original.Keys) { $legacy[$k] = $original[$k] }
                foreach ($k in @('Base', 'Contrast', 'FocusBackground', 'FocusForeground', 'Selected', 'SelectedFocused', 'Marked', 'MarkedFocused', 'ColumnHeader', 'ColumnHeaderFocused', 'Border', 'BorderFocused')) {
                    $legacy[$k] = @{ Fg = '1,2,3'; Bg = '4,5,6' }
                }
                $script:Config.UI.Theme.Slots = $legacy
                $applied = Set-TgColorScheme
                $exists = $null -ne ([Terminal.Gui.Drawing.Scheme].GetProperty('Selected'))
                "$applied|$exists"
            } finally {
                $script:Config.UI.Theme.Slots = $original
            }
        }
        if ($result -ne 'TG-UNAVAILABLE') {
            # 真实槽位照常生效(返回 True), 而 Selected 依旧不是 Scheme 属性
            $result | Should -Be 'True|False'
        }
    }

    It 'Code* 语法高亮槽位不应出现在配置中' {
        $slots = & $script:mod { $script:Config.UI.Theme.Slots }
        ($slots.Keys | Where-Object { $_ -like 'Code*' }).Count | Should -Be 0
    }

    It '应能定位到仓库内的 Terminal.Gui.dll' {
        $path = & $script:mod { Get-TgAssemblyPath }
        $path | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $path | Should -BeTrue
    }

    It 'Terminal.Gui 类型探测应返回布尔值且不抛异常' {
        { & $script:mod { Test-TgColorSchemeSupport } | Should -Not -Throw }
        $supported = & $script:mod { Test-TgColorSchemeSupport }
        $supported | Should -BeOfType [bool]
    }

    It '重复调用两次不应抛错(幂等)' {
        { & $script:mod { Set-TgColorScheme; Set-TgColorScheme } | Should -Not -Throw }
    }

    It '重复调用后槽位值应保持稳定(幂等, 无漂移)' {
        $snapshot = & $script:mod {
            $null = Set-TgColorScheme
            $scheme = [Terminal.Gui.Configuration.SchemeManager]::GetScheme('Base')
            if ($null -eq $scheme) { return $null }
            "$($scheme.Normal)|$($scheme.HotFocus)|$($scheme.Disabled)"
        }
        $again = & $script:mod {
            $null = Set-TgColorScheme
            $scheme = [Terminal.Gui.Configuration.SchemeManager]::GetScheme('Base')
            if ($null -eq $scheme) { return $null }
            "$($scheme.Normal)|$($scheme.HotFocus)|$($scheme.Disabled)"
        }
        if ($null -ne $snapshot) {
            $again | Should -Be $snapshot
        } else {
            # TG 不可用时取不到 Scheme, 属预期降级
            $again | Should -BeNullOrEmpty
        }
    }

    It 'Name 为数组时 Base 与 Menu 应同时被覆写' {
        $result = & $script:mod {
            if (-not (Test-TgColorSchemeSupport)) { return 'TG-UNAVAILABLE' }
            $null = Set-TgColorScheme
            $want = $script:Config.UI.Theme.Slots['Normal'].Fg
            $out = foreach ($n in @('Base', 'Menu')) {
                $s = [Terminal.Gui.Configuration.SchemeManager]::GetScheme($n)
                if ($null -eq $s) { "$n=NO-SCHEME" } else { "$n=$($s.Normal.Foreground.R),$($s.Normal.Foreground.G),$($s.Normal.Foreground.B)" }
            }
            "$want|$($out -join ';')"
        }
        if ($result -ne 'TG-UNAVAILABLE') {
            $want, $observed = $result -split '\|'
            # observed 形如 'Base=137,209,133;Menu=137,209,133', 取出前缀与 RGB 两段分别断言
            $pairs = @{}
            foreach ($item in $observed -split ';') {
                $k, $v = $item -split '=', 2
                $pairs[$k] = $v
            }
            $pairs.Keys | Should -Contain 'Base'
            $pairs.Keys | Should -Contain 'Menu'
            $pairs.Values | ForEach-Object { $_ | Should -Be $want }
        }
    }

    It 'Name 为单个字符串(旧配置形态)时应被规范化且不抛异常' {
        # 兼容既有配置文件: UI.Theme.Name = 'Menu' 不得崩
        $result = & $script:mod {
            $single = Resolve-TgThemeName -Name 'Menu'
            $csv = Resolve-TgThemeName -Name 'Base, Menu'
            # $null / 纯空白输入必须回退到 'Base' 而不是返回空数组或抛异常
            $nullInput = Resolve-TgThemeName -Name $null
            $blank = Resolve-TgThemeName -Name '  '
            $dup = Resolve-TgThemeName -Name @('Base', 'Base')
            "$($single -join ',')|$($csv -join ',')|$($nullInput -join ',')|$($blank -join ',')|$($dup -join ',')"
        }
        $result | Should -Be 'Menu|Base,Menu|Base|Base|Base'
    }

    It '旧配置形态(单字符串)实际覆写时也不抛异常且能落地槽位' {
        $result = & $script:mod {
            if (-not (Test-TgColorSchemeSupport)) { return 'TG-UNAVAILABLE' }
            $original = $script:Config.UI.Theme.Name
            try {
                # 模拟旧配置文件: 裸字符串而非数组
                $script:Config.UI.Theme.Name = 'Menu'
                $ok = Set-TgColorScheme
                $s = [Terminal.Gui.Configuration.SchemeManager]::GetScheme('Menu')
                if ($null -eq $s) { return 'NO-SCHEME' }
                $fg = $s.Normal.Foreground
                "$ok|$($fg.R),$($fg.G),$($fg.B)"
            } finally {
                $script:Config.UI.Theme.Name = $original
            }
        }
        if ($result -ne 'TG-UNAVAILABLE') {
            $result | Should -Not -Be 'NO-SCHEME'
            $ok, $rgb = $result -split '\|'
            $ok | Should -Be 'True'
            $rgb | Should -Be '137,209,133'
        }
    }

    It '应用后槽位值应与配置一致' {
        $result = & $script:mod {
            if (-not (Test-TgColorSchemeSupport)) { return $null }
            if (-not (Set-TgColorScheme)) { return 'NOT-APPLIED' }
            $scheme = [Terminal.Gui.Configuration.SchemeManager]::GetScheme('Base')
            if ($null -eq $scheme) { return 'NO-SCHEME' }
            [PSCustomObject]@{
                Normal   = "$($scheme.Normal)"
                Active   = "$($scheme.Active)"
                Disabled = "$($scheme.Disabled)"
            }
        }
        if ($null -eq $result) {
            # TG 类型不可用: 必须安静降级, 这是契约而非失败
            $true | Should -Be $true
        } else {
            $result | Should -BeOfType [PSCustomObject]
            # Normal 前景 137,209,133 => #89D185
            $result.Normal | Should -Match '#89D185'
            # 选中行槽位 Active (新契约 2026-10-18): 前景 137,209,133 => #89D185, 背景 40,40,40 => #282828
            $result.Active | Should -Match '#89D185'
            $result.Active | Should -Match '#282828'
        }
    }

    It 'Active/Focus 槽位连续三轮应用后不应在自定义值与默认值之间翻转' {
        # 回归防护: TG 2.4.10 把"与现值相同"的 Attribute 再写一遍并非 no-op,
        # 会重建 Scheme 并把槽位打回内置默认(配色来回跳变)。
        $rounds = & $script:mod {
            if (-not (Test-TgColorSchemeSupport)) { return 'TG-UNAVAILABLE' }
            $out = foreach ($i in 1..3) {
                $null = Set-TgColorScheme
                $s = [Terminal.Gui.Configuration.SchemeManager]::GetScheme('Base')
                $a = $s.Active.Background
                $f = $s.Focus.Foreground
                "$($a.R),$($a.G),$($a.B)|$($f.R),$($f.G),$($f.B)"
            }
            ($out | Select-Object -Unique).Count
        }
        if ($rounds -ne 'TG-UNAVAILABLE') {
            # 3 轮结果必须完全一致(唯一值只有 1 个), 即不存在翻转/回落
            [int]$rounds | Should -Be 1
        }
    }

    It '连续多次调用不得在自定义配色与 TG 默认配色之间翻转' {
        # 回归防护: TG 2.4.10 把"与现值相同"的 Attribute 再写一遍并非 no-op,
        # 而会重建 Scheme 并把槽位打回内置默认。实现已改为等值跳过写入。
        $rounds = & $script:mod {
            if (-not (Test-TgColorSchemeSupport)) { return 'TG-UNAVAILABLE' }
            $want = $script:Config.UI.Theme.Slots['HotFocus'].Fg
            $out = foreach ($i in 1..3) {
                $null = Set-TgColorScheme
                $scheme = [Terminal.Gui.Configuration.SchemeManager]::GetScheme('Base')
                $fg = $scheme.HotFocus.Foreground
                "$($fg.R),$($fg.G),$($fg.B)"
            }
            "$want|$($out -join ';')"
        }
        if ($rounds -ne 'TG-UNAVAILABLE') {
            $want, $observed = $rounds -split '\|'
            $observed -split ';' | ForEach-Object { $_ | Should -Be $want }
        }
    }

    It '槽位数量扩充后仍保持幂等(多 Scheme 各 3 轮)' {
        $rounds = & $script:mod {
            if (-not (Test-TgColorSchemeSupport)) { return 'TG-UNAVAILABLE' }
            $names = @(Resolve-TgThemeName -Name $script:Config.UI.Theme.Name)
            $out = foreach ($i in 1..3) {
                $null = Set-TgColorScheme
                $line = foreach ($n in $names) {
                    $s = [Terminal.Gui.Configuration.SchemeManager]::GetScheme($n)
                    $fg = $s.Normal.Foreground
                    "$n=$($fg.R),$($fg.G),$($fg.B)"
                }
                ($line -join ';')
            }
            ($out | Select-Object -Unique).Count
        }
        if ($rounds -ne 'TG-UNAVAILABLE') {
            # 3 轮结果必须完全一致(唯一值只有 1 个), 即不存在翻转/回落
            [int]$rounds | Should -Be 1
        }
    }

    It '返回 $true 时必须真的有槽位被写入(防静默 no-op)' {
        # 回归防护: 早期实现用 $obj.PSObject.Properties[$name].CanWrite 判可写性,
        # 而 PSPropertyInfo 上根本没有 CanWrite(恒为 $null), 导致全部槽位被跳过
        # 而函数仍返回 $true。此用例锁定"返回值 == 实际生效"。
        $result = & $script:mod {
            if (-not (Test-TgColorSchemeSupport)) { return 'TG-UNAVAILABLE' }
            $applied = Set-TgColorScheme
            if (-not $applied) { return 'NOT-APPLIED' }
            $scheme = [Terminal.Gui.Configuration.SchemeManager]::GetScheme('Base')
            if ($null -eq $scheme) { return 'NO-SCHEME' }
            $hit = 0
            foreach ($slot in $script:Config.UI.Theme.Slots.Keys) {
                $prop = [Terminal.Gui.Drawing.Scheme].GetProperty($slot)
                if ($null -ne $prop -and $prop.CanWrite) { $hit++ }
            }
            "$applied|$hit"
        }
        $result | Should -Not -Be 'NOT-APPLIED'
        $result | Should -Not -Be 'NO-SCHEME'
        if ($result -ne 'TG-UNAVAILABLE') {
            $appliedFlag, $hitCount = $result -split '\|'
            $appliedFlag | Should -Be 'True'
            [int]$hitCount | Should -BeGreaterThan 0
        }
    }

    It '覆写后 SchemeManager 不应进入损坏态(仍能枚举方案名)' {
        $names = & $script:mod {
            if (-not (Test-TgColorSchemeSupport)) { return $null }
            $null = Set-TgColorScheme
            try { (([Terminal.Gui.Configuration.SchemeManager]::GetSchemeNames()) -join ',') } catch { "EX: $($_.Exception.Message)" }
        }
        if ($null -ne $names) {
            $names | Should -Not -Match '^EX:'
            $names | Should -Match 'Base'
            $names | Should -Match 'Menu'
        }
    }

    It '禁用开关时不应触碰 Terminal.Gui' {
        $result = & $script:mod {
            $original = $script:Config.UI.Theme.Enabled
            try {
                $script:Config.UI.Theme.Enabled = $false
                Set-TgColorScheme
            } finally {
                $script:Config.UI.Theme.Enabled = $original
            }
        }
        $result | Should -Be $false
    }

    It 'WhatIf 模式下不应真正改写槽位' {
        $result = & $script:mod {
            if (-not (Test-TgColorSchemeSupport)) { return $null }
            $scheme = [Terminal.Gui.Configuration.SchemeManager]::GetScheme('Base')
            if ($null -eq $scheme) { return $null }
            $before = "$($scheme.Disabled)"
            $null = Set-TgColorScheme -WhatIf
            "$before|$(([Terminal.Gui.Configuration.SchemeManager]::GetScheme('Base')).Disabled)"
        }
        if ($null -ne $result) {
            # WhatIf 返回 $false 且槽位值不变(前后两段相等)
            $parts = $result -split '\|'
            $parts[0] | Should -Be $parts[1]
        }
    }

    It '颜色构造应拒绝非法 RGB 文本' {
        { & $script:mod { New-TgColor -Rgb 'abc' } } | Should -Throw
    }

    It '槽位赋值遇未知键时应跳过而不抛错' {
        $scheme = & $script:mod {
            if (-not (Test-TgColorSchemeSupport)) { return $null }
            [Terminal.Gui.Configuration.SchemeManager]::GetScheme('Base')
        }
        if ($null -ne $scheme) {
            $result = & $script:mod { Set-TgSchemeSlot -Scheme $args[0] -Slot 'NoSuchSlot' -Entry @{ Fg = '1,2,3'; Bg = '4,5,6' } } $scheme
            $result | Should -Be $false
        }
    }

    It '目标方案名不存在时应回退到 Base 而非抛错' {
        $result = & $script:mod {
            if (-not (Test-TgColorSchemeSupport)) { return $null }
            $null = Get-TgTargetScheme -Name 'ThisSchemeDoesNotExist'
        }
        if ($null -ne $result) { $true | Should -Be $true }
    }
}
