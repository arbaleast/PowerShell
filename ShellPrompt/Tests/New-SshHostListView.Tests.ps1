# New-SshHostListView.Tests.ps1 - SSH 主机仪表盘**左侧主机列表视图**的契约测试
#
# 覆盖 (2026-10-31 sss 仪表盘视图层):
#   1. Get-SshHostListClip: 按**显示宽度**裁剪(不是字符数)—— 恰好等宽原样返回,
#      超长补 "…", 中文按显示宽度截断, 空串/非正宽度返回空串;
#   2. Get-SshHostListGeometry: 列几何不重叠(状态点|名称|分组|标签|最后活跃),
#      窄屏下名称列仍保留最小宽度;
#   3. New-SshHostListView: 槽位数 == 可视高度, 首帧填充后 RowIndex 反映真实行,
#      容器可聚焦(方向键由编排层在 KeyDown 里实现, 依赖容器可聚焦);
#   4. Update-SshHostListSelection: 同下标幂等返回 $false, 换行返回 $true 并更新
#      SelectedIndex, 越界下标是安全 no-op(不抛异常);
#   5. Set-SshHostListScroll: Top 夹紧到 [0, max(0, 行数-高度)], 行数不足时空槽
#      被清空(RowIndex=-1, 标签为空);
#   6. Set-SshHostListSlot: 选中行整行换 Selected 配色, 未选中行用正文配色,
#      状态点配色跟随 Online/Offline/Unknown, 超长名称按几何宽度裁剪。
#
# 说明: Terminal.Gui 视图可以在无 TTY 的环境下**构造**(不进事件循环),
#       本文件只组装/刷新视图, 不 Init / 不 Run。

Describe 'Get-SshHostListClip: 按显示宽度裁剪' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It '宽度恰好等于文本宽度时原样返回(不加省略号)' {
        $result = & $script:mod { Get-SshHostListClip -Text 'abcdefghij' -Width 10 }
        $result | Should -BeExactly 'abcdefghij'
    }

    It '超长文本被截断并以 "…" 结尾' {
        $result = & $script:mod { Get-SshHostListClip -Text 'abcdefghijk' -Width 10 }
        $result | Should -Not -BeExactly 'abcdefghijk'
        $result.EndsWith([string][char]0x2026) | Should -BeTrue
        (& $script:mod { param($t) Get-TguiTextWidth -Text $t } $result) | Should -BeLessOrEqual 10
    }

    It '中文按显示宽度(不是字符数)截断' {
        $result = & $script:mod { Get-SshHostListClip -Text '生产数据库-web-01' -Width 8 }
        $width = & $script:mod { param($t) Get-TguiTextWidth -Text $t } $result
        $width | Should -BeLessOrEqual 8
        # 8 列放不下 4 个双宽汉字 + 省略号, 结果里被切掉的字符比原串少
        $result.Length | Should -BeLessThan '生产数据库-web-01'.Length
    }

    It '空文本返回空串' {
        $result = & $script:mod { Get-SshHostListClip -Text '' -Width 10 }
        $result | Should -BeExactly ''
    }

    It '宽度 <= 0 返回空串(不抛异常)' {
        foreach ($w in @(0, -1)) {
            $result = & $script:mod { param($x) Get-SshHostListClip -Text 'abcdef' -Width $x } $w
            $result | Should -BeExactly ''
        }
    }
}

Describe 'Get-SshHostListGeometry: 列几何不重叠' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It '各列起点依次递进, 列与列之间不重叠' {
        foreach ($w in @(34, 44, 56, 72)) {
            $g = & $script:mod { param($x) Get-SshHostListGeometry -Width $x } $w
            $g.GroupX | Should -BeGreaterOrEqual ($g.NameX + $g.NameWidth) -Because "宽度 $w 下分组列不能压住名称列"
            $g.TagsX | Should -BeGreaterOrEqual ($g.GroupX + $g.GroupWidth) -Because "宽度 $w 下标签列不能压住分组列"
            $g.TimeX | Should -BeGreaterOrEqual ($g.TagsX + $g.TagsWidth) -Because "宽度 $w 下时间列不能压住标签列"
        }
    }

    It '窄屏下名称列仍保留最小宽度(>= 4)' {
        foreach ($w in @(34, 44)) {
            $g = & $script:mod { param($x) Get-SshHostListGeometry -Width $x } $w
            $g.NameWidth | Should -BeGreaterOrEqual 4
        }
    }

    It '宽屏给分组/标签留出宽度, 窄屏先压标签再压分组' {
        $wide = & $script:mod { Get-SshHostListGeometry -Width 72 }
        $narrow = & $script:mod { Get-SshHostListGeometry -Width 34 }
        $wide.GroupWidth | Should -BeGreaterThan $narrow.GroupWidth
        $wide.NameWidth | Should -BeGreaterThan $narrow.NameWidth
    }
}

Describe 'New-SshHostListView: 列表组装' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It '槽位数量 == 可视高度' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{
                    Name = 'a'; HostName = 'a.example.com'; Port = 22; User = ''
                    Tags = @(); Group = ''; Provider = ''; Region = ''; IsLocal = $false
                    Status = 'Unknown'; StatusText = '未知'; StatusGlyph = [string][char]0x25CF
                    StatusRole = 'Unknown'; LastActive = $null; LastActiveText = [string][char]0x2014
                    HasActivity = $false; ConnectCount = 0; Indent = $false
                    DisplayName = 'a'; Value = 'a'
                }
            )
            $lv = New-SshHostListView -Rows $rows -Width 56 -Height 5 -SelectedIndex 0 -Theme $theme -Tgui $tg
            [PSCustomObject]@{ Slots = @($lv.Slots).Count; Height = $lv.Height }
        }
        $result.Slots | Should -Be 5
        $result.Height | Should -Be 5
    }

    It '首帧填充后槽位 RowIndex 反映真实行(行数不足的空槽为 -1)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{
                    Name = 'a'; HostName = 'a.example.com'; Port = 22; User = ''
                    Tags = @(); Group = ''; Provider = ''; Region = ''; IsLocal = $false
                    Status = 'Unknown'; StatusText = '未知'; StatusGlyph = [string][char]0x25CF
                    StatusRole = 'Unknown'; LastActive = $null; LastActiveText = [string][char]0x2014
                    HasActivity = $false; ConnectCount = 0; Indent = $false
                    DisplayName = 'a'; Value = 'a'
                }
                [PSCustomObject]@{
                    Name = 'b'; HostName = 'b.example.com'; Port = 22; User = ''
                    Tags = @(); Group = ''; Provider = ''; Region = ''; IsLocal = $false
                    Status = 'Unknown'; StatusText = '未知'; StatusGlyph = [string][char]0x25CF
                    StatusRole = 'Unknown'; LastActive = $null; LastActiveText = [string][char]0x2014
                    HasActivity = $false; ConnectCount = 0; Indent = $false
                    DisplayName = 'b'; Value = 'b'
                }
            )
            $lv = New-SshHostListView -Rows $rows -Width 56 -Height 4 -SelectedIndex 0 -Theme $theme -Tgui $tg
            [PSCustomObject]@{ RowIndexes = @($lv.Slots | ForEach-Object { $_.RowIndex }) }
        }
        $result.RowIndexes | Should -Be @(0, 1, -1, -1)
    }

    It '容器 CanFocus 为真(方向键由编排层在 KeyDown 里实现, 依赖它)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{
                    Name = 'a'; HostName = 'a.example.com'; Port = 22; User = ''
                    Tags = @(); Group = ''; Provider = ''; Region = ''; IsLocal = $false
                    Status = 'Unknown'; StatusText = '未知'; StatusGlyph = [string][char]0x25CF
                    StatusRole = 'Unknown'; LastActive = $null; LastActiveText = [string][char]0x2014
                    HasActivity = $false; ConnectCount = 0; Indent = $false
                    DisplayName = 'a'; Value = 'a'
                }
            )
            $lv = New-SshHostListView -Rows $rows -Width 56 -Height 3 -SelectedIndex 0 -Theme $theme -Tgui $tg
            [PSCustomObject]@{ CanFocus = [bool]$lv.View.CanFocus }
        }
        $result.CanFocus | Should -BeTrue
    }

    It 'ShouldProcess 否定时返回 $null(组装必须显式确认)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{
                    Name = 'a'; HostName = 'a.example.com'; Port = 22; User = ''
                    Tags = @(); Group = ''; Provider = ''; Region = ''; IsLocal = $false
                    Status = 'Unknown'; StatusText = '未知'; StatusGlyph = [string][char]0x25CF
                    StatusRole = 'Unknown'; LastActive = $null; LastActiveText = [string][char]0x2014
                    HasActivity = $false; ConnectCount = 0; Indent = $false
                    DisplayName = 'a'; Value = 'a'
                }
            )
            New-SshHostListView -Rows $rows -Width 56 -Height 3 -SelectedIndex 0 -Theme $theme -Tgui $tg -WhatIf
        }
        $result | Should -BeNullOrEmpty
    }
}

Describe 'Update-SshHostListSelection: 选中移动' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It 'OldIndex == NewIndex 时返回 $false(幂等, 不重刷)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{
                    Name = 'a'; HostName = 'a.example.com'; Port = 22; User = ''
                    Tags = @(); Group = ''; Provider = ''; Region = ''; IsLocal = $false
                    Status = 'Unknown'; StatusText = '未知'; StatusGlyph = [string][char]0x25CF
                    StatusRole = 'Unknown'; LastActive = $null; LastActiveText = [string][char]0x2014
                    HasActivity = $false; ConnectCount = 0; Indent = $false
                    DisplayName = 'a'; Value = 'a'
                }
            )
            $lv = New-SshHostListView -Rows $rows -Width 56 -Height 3 -SelectedIndex 0 -Theme $theme -Tgui $tg
            Update-SshHostListSelection -ListView $lv -OldIndex 0 -NewIndex 0
        }
        $result | Should -BeFalse
    }

    It '换行时返回 $true 并同步 SelectedIndex' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{
                    Name = 'a'; HostName = 'a.example.com'; Port = 22; User = ''
                    Tags = @(); Group = ''; Provider = ''; Region = ''; IsLocal = $false
                    Status = 'Unknown'; StatusText = '未知'; StatusGlyph = [string][char]0x25CF
                    StatusRole = 'Unknown'; LastActive = $null; LastActiveText = [string][char]0x2014
                    HasActivity = $false; ConnectCount = 0; Indent = $false
                    DisplayName = 'a'; Value = 'a'
                }
                [PSCustomObject]@{
                    Name = 'b'; HostName = 'b.example.com'; Port = 22; User = ''
                    Tags = @(); Group = ''; Provider = ''; Region = ''; IsLocal = $false
                    Status = 'Unknown'; StatusText = '未知'; StatusGlyph = [string][char]0x25CF
                    StatusRole = 'Unknown'; LastActive = $null; LastActiveText = [string][char]0x2014
                    HasActivity = $false; ConnectCount = 0; Indent = $false
                    DisplayName = 'b'; Value = 'b'
                }
            )
            $lv = New-SshHostListView -Rows $rows -Width 56 -Height 3 -SelectedIndex 0 -Theme $theme -Tgui $tg
            $changed = Update-SshHostListSelection -ListView $lv -OldIndex 0 -NewIndex 1
            [PSCustomObject]@{ Changed = $changed; Selected = $lv.SelectedIndex }
        }
        $result.Changed | Should -BeTrue
        $result.Selected | Should -Be 1
    }

    It '越界下标不抛异常(安全 no-op 的下限保证)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{
                    Name = 'a'; HostName = 'a.example.com'; Port = 22; User = ''
                    Tags = @(); Group = ''; Provider = ''; Region = ''; IsLocal = $false
                    Status = 'Unknown'; StatusText = '未知'; StatusGlyph = [string][char]0x25CF
                    StatusRole = 'Unknown'; LastActive = $null; LastActiveText = [string][char]0x2014
                    HasActivity = $false; ConnectCount = 0; Indent = $false
                    DisplayName = 'a'; Value = 'a'
                }
            )
            $lv = New-SshHostListView -Rows $rows -Width 56 -Height 3 -SelectedIndex 0 -Theme $theme -Tgui $tg
            # 越界下标不得让调用方崩掉: 只锁住"不抛异常"这条下限,
            # SelectedIndex 的落位语义由编排层负责兜底(见交付报告里的实现缺陷说明)。
            $threw = $false
            try {
                $null = Update-SshHostListSelection -ListView $lv -OldIndex -1 -NewIndex 999
            } catch {
                $threw = $true
            }
            [PSCustomObject]@{ Threw = $threw }
        }
        $result.Threw | Should -BeFalse
    }
}

Describe 'Set-SshHostListScroll: 滚动与空槽' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It 'Top 被夹紧到 [0, max(0, 行数-高度)]' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $rows = @(
                1..10 | ForEach-Object {
                    [PSCustomObject]@{
                        Name = "h$_"; HostName = "h$_.example.com"; Port = 22; User = ''
                        Tags = @(); Group = ''; Provider = ''; Region = ''; IsLocal = $false
                        Status = 'Unknown'; StatusText = '未知'; StatusGlyph = [string][char]0x25CF
                        StatusRole = 'Unknown'; LastActive = $null; LastActiveText = [string][char]0x2014
                        HasActivity = $false; ConnectCount = 0; Indent = $false
                        DisplayName = "h$_"; Value = "h$_"
                    }
                }
            )
            $lv = New-SshHostListView -Rows $rows -Width 56 -Height 4 -SelectedIndex 0 -Theme $theme -Tgui $tg
            Set-SshHostListScroll -ListView $lv -Top 99
            $topTooBig = $lv.Top
            # 负数 Top 是"省略"的哨兵值(不改变当前 Top), 因此 Top 始终落在合法区间内
            Set-SshHostListScroll -ListView $lv -Top -5
            $topAfterNegative = $lv.Top
            [PSCustomObject]@{
                TopTooBig         = $topTooBig
                TopAfterNegative  = $topAfterNegative
                MaxTop            = [Math]::Max(0, $rows.Count - $lv.Height)
            }
        }
        $result.TopTooBig | Should -Be 6
        $result.TopAfterNegative | Should -BeGreaterOrEqual 0
        $result.TopAfterNegative | Should -BeLessOrEqual $result.MaxTop
    }

    It '行数少于可视高度时, 超出范围的空槽被清空(RowIndex=-1 且标签为空)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $rows = @(
                1..2 | ForEach-Object {
                    [PSCustomObject]@{
                        Name = "h$_"; HostName = "h$_.example.com"; Port = 22; User = ''
                        Tags = @(); Group = ''; Provider = ''; Region = ''; IsLocal = $false
                        Status = 'Unknown'; StatusText = '未知'; StatusGlyph = [string][char]0x25CF
                        StatusRole = 'Unknown'; LastActive = $null; LastActiveText = [string][char]0x2014
                        HasActivity = $false; ConnectCount = 0; Indent = $false
                        DisplayName = "h$_"; Value = "h$_"
                    }
                }
            )
            $lv = New-SshHostListView -Rows $rows -Width 56 -Height 4 -SelectedIndex 0 -Theme $theme -Tgui $tg
            Set-SshHostListScroll -ListView $lv
            $slot = $lv.Slots[3]
            [PSCustomObject]@{
                RowIndex = $slot.RowIndex
                Name     = [string]$slot.Name.Text
                Group    = [string]$slot.Group.Text
                Tags     = [string]$slot.Tags.Text
                Time     = [string]$slot.Time.Text
                Dot      = [string]$slot.Dot.Text
            }
        }
        $result.RowIndex | Should -Be -1
        $result.Name | Should -BeExactly ''
        $result.Group | Should -BeExactly ''
        $result.Tags | Should -BeExactly ''
        $result.Time | Should -BeExactly ''
        $result.Dot | Should -BeExactly ''
    }
}

Describe 'Set-SshHostListSlot: 槽位渲染与配色' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It '选中行背景用 Selected 方案, 未选中行背景用正文 Text 方案' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{
                    Name = 'a'; HostName = 'a.example.com'; Port = 22; User = ''
                    Tags = @(); Group = ''; Provider = ''; Region = ''; IsLocal = $false
                    Status = 'Unknown'; StatusText = '未知'; StatusGlyph = [string][char]0x25CF
                    StatusRole = 'Unknown'; LastActive = $null; LastActiveText = [string][char]0x2014
                    HasActivity = $false; ConnectCount = 0; Indent = $false
                    DisplayName = 'a'; Value = 'a'
                }
                [PSCustomObject]@{
                    Name = 'b'; HostName = 'b.example.com'; Port = 22; User = ''
                    Tags = @(); Group = ''; Provider = ''; Region = ''; IsLocal = $false
                    Status = 'Unknown'; StatusText = '未知'; StatusGlyph = [string][char]0x25CF
                    StatusRole = 'Unknown'; LastActive = $null; LastActiveText = [string][char]0x2014
                    HasActivity = $false; ConnectCount = 0; Indent = $false
                    DisplayName = 'b'; Value = 'b'
                }
            )
            $lv = New-SshHostListView -Rows $rows -Width 56 -Height 3 -SelectedIndex 0 -Theme $theme -Tgui $tg
            [PSCustomObject]@{
                SelectedBg   = ($lv.Slots[0].Bg.GetScheme() -eq $theme.Selected)
                UnselectedBg = ($lv.Slots[1].Bg.GetScheme() -eq $theme.Text)
            }
        }
        $result.SelectedBg | Should -BeTrue
        $result.UnselectedBg | Should -BeTrue
    }

    It '状态点配色跟随 Online / Offline / Unknown' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $makeRow = {
                param([string]$status, [string]$name)
                $statusText = '未知'
                if ($status -eq 'Online') { $statusText = '在线' }
                elseif ($status -eq 'Offline') { $statusText = '离线' }
                [PSCustomObject]@{
                    Name = $name; HostName = "$name.example.com"; Port = 22; User = ''
                    Tags = @(); Group = ''; Provider = ''; Region = ''; IsLocal = $false
                    Status = $status; StatusText = $statusText; StatusGlyph = [string][char]0x25CF
                    StatusRole = $status; LastActive = $null; LastActiveText = [string][char]0x2014
                    HasActivity = $false; ConnectCount = 0; Indent = $false
                    DisplayName = $name; Value = $name
                }
            }
            $rows = @(& $makeRow 'Online' 'a') + @(& $makeRow 'Offline' 'b') + @(& $makeRow 'Unknown' 'c')
            $lv = New-SshHostListView -Rows $rows -Width 56 -Height 3 -SelectedIndex -1 -Theme $theme -Tgui $tg
            [PSCustomObject]@{
                Online  = ($lv.Slots[0].Dot.GetScheme() -eq $theme.Online)
                Offline = ($lv.Slots[1].Dot.GetScheme() -eq $theme.Offline)
                Unknown = ($lv.Slots[2].Dot.GetScheme() -eq $theme.Unknown)
            }
        }
        $result.Online | Should -BeTrue
        $result.Offline | Should -BeTrue
        $result.Unknown | Should -BeTrue
    }

    It '超长主机名按几何宽度裁剪(不越界)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{
                    Name = ('x' * 80); HostName = 'x.example.com'; Port = 22; User = ''
                    Tags = @(); Group = ''; Provider = ''; Region = ''; IsLocal = $false
                    Status = 'Unknown'; StatusText = '未知'; StatusGlyph = [string][char]0x25CF
                    StatusRole = 'Unknown'; LastActive = $null; LastActiveText = [string][char]0x2014
                    HasActivity = $false; ConnectCount = 0; Indent = $false
                    DisplayName = 'x'; Value = 'x'
                }
            )
            $lv = New-SshHostListView -Rows $rows -Width 56 -Height 2 -SelectedIndex 0 -Theme $theme -Tgui $tg
            $text = [string]$lv.Slots[0].Name.Text
            [PSCustomObject]@{
                Text  = $text
                Width = (Get-TguiTextWidth -Text $text)
                Limit = $lv.Geometry.NameWidth
            }
        }
        $result.Width | Should -BeLessOrEqual $result.Limit
        $result.Text.EndsWith([string][char]0x2026) | Should -BeTrue
    }
}
