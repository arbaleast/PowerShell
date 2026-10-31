# Set-TguiTheme.Tests.ps1 - ALC 原生主题装配与方案可见性契约测试
#
# 覆盖(2026-10-30 真机验收补修):
#   1. Color/Attribute 的 ALC 内构造(byref 形参陷阱的回归防护);
#   2. Set-TguiTheme 把 UI.Theme.Slots 覆写到 ALC 的 Base/Menu 方案实例;
#   3. 幂等性: 连续两次覆写不被 TG 2.4.10 打回内置默认(实测 4 轮交替翻转);
#   4. 可见性判定: 前景==背景 → 不可见(真机"只剩边框"的判据);
#   5. Resolve-TguiScheme 优先返回可见方案;
#   6. 主题被禁用时仍返回**可见**方案(界面不许空白)。
# 说明: 无头构造(不 Init/不 Run); 反射实测 API 驱动。

Describe 'ALC 原生主题装配 (Set-TguiTheme)' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
        $script:tg = & $script:mod { Get-TguiContext }
    }

    It 'New-TguiColor 在本 ALC 内构造出正确的 RGB 值' {
        $color = & $script:mod {
            param($t) New-TguiColor -Tgui $t -Rgb '205,214,244'
        } $script:tg

        $color | Should -Not -BeNullOrEmpty
        $color.R | Should -Be 205
        $color.G | Should -Be 214
        $color.B | Should -Be 244
        # 类型必须来自本 ALC(与视图的 Scheme 同源), 不能是默认上下文的副本
        $color.GetType().Assembly | Should -Be $script:tg.Assembly
    }

    It 'New-TguiAttribute 正确设置前景与背景(byref 形参回归)' {
        $attr = & $script:mod {
            param($t) New-TguiAttribute -Tgui $t -FgRgb '205,214,244' -BgRgb '24,24,37'
        } $script:tg

        $attr | Should -Not -BeNullOrEmpty
        $attr.Foreground.R | Should -Be 205
        $attr.Foreground.G | Should -Be 214
        $attr.Foreground.B | Should -Be 244
        $attr.Background.R | Should -Be 24
        $attr.Background.G | Should -Be 24
        $attr.Background.B | Should -Be 37
        $attr.GetType().Assembly | Should -Be $script:tg.Assembly
    }

    It 'Set-TguiTheme 把配置槽位覆写到 ALC 的 Base/Menu 方案实例' {
        $result = & $script:mod {
            param($t)
            $applied = Set-TguiTheme -Tgui $t
            $getScheme = $t.Types.SchemeManager.GetMethod('GetScheme', [type[]]@([string]))
            $base = $getScheme.Invoke($null, @('Base'))
            $menu = $getScheme.Invoke($null, @('Menu'))
            $dialog = $getScheme.Invoke($null, @('Dialog'))
            [PSCustomObject]@{
                Applied     = $applied
                BaseFg      = "$($base.Normal.Foreground.R),$($base.Normal.Foreground.G),$($base.Normal.Foreground.B)"
                BaseBg      = "$($base.Normal.Background.R),$($base.Normal.Background.G),$($base.Normal.Background.B)"
                MenuFg      = "$($menu.Normal.Foreground.R),$($menu.Normal.Foreground.G),$($menu.Normal.Foreground.B)"
                DialogFg    = "$($dialog.Normal.Foreground.R),$($dialog.Normal.Foreground.G),$($dialog.Normal.Foreground.B)"
                Expected    = $script:Config.UI.Theme.Slots.Normal
                MenuExpect  = $script:Config.UI.Theme.SchemeOverrides['Menu'].Normal
                MenuFocus   = "$($menu.Focus.Foreground.R),$($menu.Focus.Foreground.G),$($menu.Focus.Foreground.B)"
                MenuFocusExpect = $script:Config.UI.Theme.SchemeOverrides['Menu'].Focus
                DialogExpect = $script:Config.UI.Theme.SchemeOverrides['Dialog'].Normal
            }
        } $script:tg

        $result.Applied | Should -BeTrue
        $result.BaseFg | Should -Be $result.Expected.Fg
        $result.BaseBg | Should -Be $result.Expected.Bg
        # Menu 走差异化槽位(边缘带: Sky 冰青字), 不是正文色 —— 标题带/表头/底栏因此与正文分层
        $result.MenuFg | Should -Be $result.MenuExpect.Fg
        # 表头专用的 Focus 槽位: 与 Base.Focus(选中行)前景色不同, 表头/选中行才分得开
        $result.MenuFocus | Should -Be $result.MenuFocusExpect.Fg
        $result.MenuFocus | Should -Not -Be $result.Expected.Fg
        # Dialog = 连接状态徽标(成功态绿字)
        $result.DialogFg | Should -Be $result.DialogExpect.Fg
    }

    It '重复覆写不翻转槽位(TG 2.4.10 写同值会重建 Scheme 并打回默认)' {
        $stable = & $script:mod {
            param($t)
            $getScheme = $t.Types.SchemeManager.GetMethod('GetScheme', [type[]]@([string]))
            $first = $null
            foreach ($round in 1..3) {
                [void](Set-TguiTheme -Tgui $t)
                $base = $getScheme.Invoke($null, @('Base'))
                $fg = "$($base.Normal.Foreground.R),$($base.Normal.Foreground.G),$($base.Normal.Foreground.B)"
                if ($null -eq $first) { $first = $fg }
                elseif ($fg -ne $first) { return $false }
            }
            $true
        } $script:tg

        $stable | Should -BeTrue
    }

    It 'Test-TguiSchemeVisible: 前景==背景判为不可见' {
        $visible = & $script:mod {
            param($t)
            $getScheme = $t.Types.SchemeManager.GetMethod('GetScheme', [type[]]@([string]))
            $base = $getScheme.Invoke($null, @('Base'))
            $menu = $getScheme.Invoke($null, @('Menu'))
            # 白对白的槽位(人为构造)必须判为不可见
            $white = New-TguiAttribute -Tgui $t -FgRgb '255,255,255' -BgRgb '255,255,255'
            [PSCustomObject]@{
                BaseAfterTheme = Test-TguiSchemeVisible -Scheme $base
                MenuVisible    = Test-TguiSchemeVisible -Scheme $menu
                WhiteOnWhite   = Test-TguiSchemeVisible -Scheme $white
            }
        } $script:tg

        $visible.BaseAfterTheme | Should -BeTrue
        $visible.MenuVisible | Should -BeTrue
        $visible.WhiteOnWhite | Should -BeFalse
    }

    It 'Resolve-TguiScheme 优先返回可见方案, 主题禁用时也不返回空白界面' {
        $result = & $script:mod {
            param($t)
            $before = Resolve-TguiScheme -Tgui $t -Names @('Base', 'Menu')
            $savedEnabled = $script:Config.UI.Theme.Enabled
            $script:Config.UI.Theme.Enabled = $false
            try {
                $disabledApplied = Set-TguiTheme -Tgui $t
                # 主题禁用后 Base 仍是白对白 -> Resolve 必须改挑可见方案
                $after = Resolve-TguiScheme -Tgui $t -Names @('Base', 'Menu', 'Dialog')
                [PSCustomObject]@{
                    BeforeVisible = Test-TguiSchemeVisible -Scheme $before
                    DisabledApplied = $disabledApplied
                    AfterVisible  = Test-TguiSchemeVisible -Scheme $after
                    AfterNotNull  = $null -ne $after
                }
            } finally {
                $script:Config.UI.Theme.Enabled = $savedEnabled
            }
        } $script:tg

        $result.BeforeVisible | Should -BeTrue
        $result.DisabledApplied | Should -BeFalse
        $result.AfterNotNull | Should -BeTrue
        # 主题禁用时若 Base 不可见, Resolve 仍必须给出可见方案(界面不许空白)
        $result.AfterVisible | Should -BeTrue
    }
}
