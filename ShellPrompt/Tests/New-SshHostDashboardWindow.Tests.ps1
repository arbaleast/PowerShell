# New-SshHostDashboardWindow.Tests.ps1 - SSH 主机仪表盘**整窗组装**的契约测试
#
# 覆盖 (2026-10-31 sss 仪表盘视图层):
#   1. 整窗组装: Window / ListView / DetailPanel / 分类栏 / 标题带 / 信息行 /
#      搜索框 / 底栏 全部到位(无头, 不进事件循环);
#   2. 窄屏响应式: < 72 列收起右侧详情, >= 72 列显示详情;
#   3. 分栏不溢出: 列表宽度 + 分隔线 + 详情宽度都落在 WindowWidth 之内;
#   4. 底部快捷键栏(纯展示 Label): 项集合固定、按宽度取舍, 渲染文本不超宽,
#      窄屏项数更少但永远 >= 1;
#   5. 分类栏: 由传入 Categories 构建, 当前分类用 CategoryActive 配色, 其余用
#      Category 配色;
#   6. 搜索态切换: SearchActive=$true 显示搜索提示 + 输入框并隐藏信息行;
#      $false 时反过来;
#   7. 行集合与 SelectedIndex 被列表视图如实承接。
#
# 说明: 底栏是**单个 Label**(不是 StatusBar+Shortcut) —— TG 2.4.10 的 Shortcut
#       用 Key.ToString() 渲染键名, 而 Key 没有 '/' 与 '↑↓' 这类符号/组合键的
#       静态属性, 用 StatusBar 会把 "↑↓ 选择主机" 渲染成 "Esc 选择主机"。
#       因此断言对象是 ShortcutBar(Label) / ShortcutDefs(实际渲染的项定义)。

Describe 'New-SshHostDashboardWindow: 整窗组装与响应式布局' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'

        # 行模型是纯数据, 在测试作用域构造后传入
        $script:makeRows = {
            @(
                [PSCustomObject]@{
                    Name = 'alpha'; HostName = 'a.example.com'; Port = 22; User = ''
                    Tags = @('web'); Group = ''; Provider = ''; Region = ''; IsLocal = $false
                    Status = 'Unknown'; StatusText = '未知'; StatusGlyph = [string][char]0x25CF
                    StatusRole = 'Unknown'; LastActive = $null; LastActiveText = [string][char]0x2014
                    HasActivity = $false; ConnectCount = 0; Indent = $false
                    DisplayName = 'alpha'; Value = 'alpha'
                }
                [PSCustomObject]@{
                    Name = 'beta'; HostName = 'b.example.com'; Port = 22; User = ''
                    Tags = @(); Group = ''; Provider = ''; Region = ''; IsLocal = $false
                    Status = 'Unknown'; StatusText = '未知'; StatusGlyph = [string][char]0x25CF
                    StatusRole = 'Unknown'; LastActive = $null; LastActiveText = [string][char]0x2014
                    HasActivity = $false; ConnectCount = 0; Indent = $false
                    DisplayName = 'beta'; Value = 'beta'
                }
            )
        }
    }

    It '整窗组装: Window / ListView / 分类栏 / 标题 / 信息行 / 搜索框 / 底栏全部到位' {
        $rows = & $script:makeRows
        $result = & $script:mod {
            param($r)
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $win = New-SshHostDashboardWindow -Rows $r -Title 'SSH 主机' -Categories @('All', 'AWS') `
                -ActiveCategory 'All' -SelectedIndex 0 -InfoText '共 2 台' -Theme $theme `
                -WindowWidth 120 -WindowHeight 30
            [PSCustomObject]@{
                HasWindow      = ($null -ne $win.Window)
                HasListView    = ($null -ne $win.ListView)
                HasDetailPanel = ($null -ne $win.DetailPanel)
                CategoryCount  = @($win.CategoryBar).Count
                HasTitle       = ($null -ne $win.TitleLabel)
                HasInfo        = ($null -ne $win.InfoLabel)
                HasSearch      = ($null -ne $win.SearchField)
                HasShortcutBar = ($null -ne $win.ShortcutBar)
                BarText        = [string]$win.ShortcutBar.Text
            }
        } $rows
        $result.HasWindow | Should -BeTrue
        $result.HasListView | Should -BeTrue
        $result.HasDetailPanel | Should -BeTrue
        $result.CategoryCount | Should -Be 2
        $result.HasTitle | Should -BeTrue
        $result.HasInfo | Should -BeTrue
        $result.HasSearch | Should -BeTrue
        $result.HasShortcutBar | Should -BeTrue
        $result.BarText | Should -Not -BeNullOrEmpty
    }

    It '窄屏(不足 72 列)收起右侧详情, 72 列及以上显示详情' {
        $rows = & $script:makeRows
        $result = & $script:mod {
            param($r)
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $out = @()
            foreach ($w in @(40, 60, 71, 72, 100, 120, 160)) {
                $win = New-SshHostDashboardWindow -Rows $r -Categories @('All') -ActiveCategory 'All' `
                    -Theme $theme -WindowWidth $w -WindowHeight 30
                $out += [PSCustomObject]@{ Width = $w; ShowDetail = [bool]$win.Layout.ShowDetail }
            }
            $out
        } $rows
        ($result | Where-Object Width -EQ 40).ShowDetail | Should -BeFalse
        ($result | Where-Object Width -EQ 60).ShowDetail | Should -BeFalse
        ($result | Where-Object Width -EQ 71).ShowDetail | Should -BeFalse
        ($result | Where-Object Width -EQ 72).ShowDetail | Should -BeTrue
        ($result | Where-Object Width -EQ 100).ShowDetail | Should -BeTrue
        ($result | Where-Object Width -EQ 120).ShowDetail | Should -BeTrue
        ($result | Where-Object Width -EQ 160).ShowDetail | Should -BeTrue
    }

    It '分栏不溢出: 列表 + 分隔线 + 详情都落在 WindowWidth 之内' {
        $rows = & $script:makeRows
        $result = & $script:mod {
            param($r)
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $out = @()
            foreach ($w in @(40, 60, 72, 100, 120, 160)) {
                $win = New-SshHostDashboardWindow -Rows $r -Categories @('All') -ActiveCategory 'All' `
                    -Theme $theme -WindowWidth $w -WindowHeight 30
                $l = $win.Layout
                $out += [PSCustomObject]@{
                    Width       = $w
                    ListWidth   = $l.ListWidth
                    DividerX    = $l.DividerX
                    DetailX     = $l.DetailX
                    DetailWidth = $l.DetailWidth
                    ShowDetail  = [bool]$l.ShowDetail
                }
            }
            $out
        } $rows
        foreach ($item in $result) {
            $item.ListWidth | Should -BeLessOrEqual $item.Width -Because "宽度 $($item.Width) 下列表不能溢出"
            if ($item.ShowDetail) {
                $item.DetailX | Should -BeGreaterThan 0
                ($item.DetailX + $item.DetailWidth) | Should -BeLessOrEqual $item.Width -Because "宽度 $($item.Width) 下详情不能溢出"
                $item.DetailX | Should -BeGreaterThan ($item.ListWidth + 1) -Because "详情应在分隔线右侧"
            }
        }
    }

    It '底栏: 快捷键项定义非空, 且包含 Enter 与 Esc' {
        $rows = & $script:makeRows
        $result = & $script:mod {
            param($r)
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $win = New-SshHostDashboardWindow -Rows $r -Categories @('All') -ActiveCategory 'All' `
                -Theme $theme -WindowWidth 160 -WindowHeight 30
            [PSCustomObject]@{
                Keys = @($win.ShortcutDefs | ForEach-Object { [string]$_.Key })
                Text = [string]$win.ShortcutBar.Text
            }
        } $rows
        @($result.Keys) | Should -Not -HaveCount 0
        @($result.Keys) | Should -Contain 'Enter'
        @($result.Keys) | Should -Contain 'Esc'
    }

    It '底栏: 宽屏显示完整文档键位集合(Enter / / / Tab / ↑↓ / Esc)' {
        $rows = & $script:makeRows
        $result = & $script:mod {
            param($r)
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $win = New-SshHostDashboardWindow -Rows $r -Categories @('All') -ActiveCategory 'All' `
                -Theme $theme -WindowWidth 160 -WindowHeight 30
            @($win.ShortcutDefs | ForEach-Object { [string]$_.Key })
        } $rows
        @($result) | Should -Contain 'Enter'
        @($result) | Should -Contain '/'
        @($result) | Should -Contain 'Tab'
        @($result) | Should -Contain ([string][char]0x2191 + [string][char]0x2193)
        @($result) | Should -Contain 'Esc'
    }

    It '底栏: 渲染文本包含每一项的键名与标签, 且显示宽度不超窗口宽度' {
        $rows = & $script:makeRows
        $result = & $script:mod {
            param($r)
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $out = @()
            foreach ($w in @(40, 72, 120, 160)) {
                $win = New-SshHostDashboardWindow -Rows $r -Categories @('All') -ActiveCategory 'All' `
                    -Theme $theme -WindowWidth $w -WindowHeight 30
                $text = [string]$win.ShortcutBar.Text
                $missing = @()
                foreach ($def in @($win.ShortcutDefs)) {
                    if (-not $text.Contains([string]$def.Key)) { $missing += [string]$def.Key }
                    if (-not $text.Contains([string]$def.Label)) { $missing += [string]$def.Label }
                }
                $out += [PSCustomObject]@{
                    Width      = $w
                    Missing    = $missing
                    TextWidth  = (Get-TguiTextWidth -Text $text)
                    ItemCount  = @($win.ShortcutDefs).Count
                    Text       = $text
                }
            }
            $out
        } $rows
        foreach ($item in $result) {
            @($item.Missing) | Should -HaveCount 0 -Because "宽度 $($item.Width) 的底栏必须含每一项的键名与标签"
            $item.TextWidth | Should -BeLessOrEqual $item.Width -Because "宽度 $($item.Width) 的底栏不能溢出"
            $item.ItemCount | Should -BeGreaterOrEqual 1
            $item.Text | Should -Not -BeNullOrEmpty
        }
    }

    It '底栏: 窄屏项数比宽屏少, 但永远 >= 1(不会退化成空栏)' {
        $rows = & $script:makeRows
        $result = & $script:mod {
            param($r)
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $out = @()
            foreach ($w in @(40, 60, 120, 160)) {
                $win = New-SshHostDashboardWindow -Rows $r -Categories @('All') -ActiveCategory 'All' `
                    -Theme $theme -WindowWidth $w -WindowHeight 30
                $out += [PSCustomObject]@{ Width = $w; Count = @($win.ShortcutDefs).Count }
            }
            $out
        } $rows
        $wide = ($result | Where-Object Width -EQ 160).Count
        $narrow = ($result | Where-Object Width -EQ 40).Count
        $wide | Should -BeGreaterThan $narrow
        foreach ($item in $result) {
            $item.Count | Should -BeGreaterOrEqual 1 -Because "宽度 $($item.Width) 的底栏不能没有可选项"
        }
    }

    It '分类栏: 由传入 Categories 构建, 当前分类用 CategoryActive, 其余用 Category' {
        $rows = & $script:makeRows
        $result = & $script:mod {
            param($r)
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $win = New-SshHostDashboardWindow -Rows $r -Categories @('All', 'AWS', 'Local') `
                -ActiveCategory 'AWS' -Theme $theme -WindowWidth 120 -WindowHeight 30
            $out = @()
            foreach ($entry in @($win.CategoryBar)) {
                $out += [PSCustomObject]@{
                    Name      = [string]$entry.Name
                    IsActive  = ($entry.Label.GetScheme() -eq $theme.CategoryActive)
                    IsNormal  = ($entry.Label.GetScheme() -eq $theme.Category)
                }
            }
            $out
        } $rows
        $result | Should -HaveCount 3
        ($result | Where-Object Name -EQ 'AWS').IsActive | Should -BeTrue
        ($result | Where-Object Name -EQ 'All').IsNormal | Should -BeTrue
        ($result | Where-Object Name -EQ 'Local').IsNormal | Should -BeTrue
    }

    It '搜索态: SearchActive=$true 时显示搜索提示与输入框, 隐藏信息行' {
        $rows = & $script:makeRows
        $result = & $script:mod {
            param($r)
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $win = New-SshHostDashboardWindow -Rows $r -Categories @('All') -ActiveCategory 'All' `
                -SearchActive $true -SearchText 'prod' -Theme $theme -WindowWidth 120 -WindowHeight 30
            [PSCustomObject]@{
                PromptVisible = [bool]$win.SearchPrompt.Visible
                FieldVisible  = [bool]$win.SearchField.Visible
                InfoVisible   = [bool]$win.InfoLabel.Visible
                FieldText     = [string]$win.SearchField.Text
            }
        } $rows
        $result.PromptVisible | Should -BeTrue
        $result.FieldVisible | Should -BeTrue
        $result.InfoVisible | Should -BeFalse
        $result.FieldText | Should -BeExactly 'prod'
    }

    It '搜索态: SearchActive=$false 时显示信息行, 隐藏搜索提示与输入框' {
        $rows = & $script:makeRows
        $result = & $script:mod {
            param($r)
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $win = New-SshHostDashboardWindow -Rows $r -Categories @('All') -ActiveCategory 'All' `
                -SearchActive $false -InfoText '共 2 台' -Theme $theme -WindowWidth 120 -WindowHeight 30
            [PSCustomObject]@{
                PromptVisible = [bool]$win.SearchPrompt.Visible
                FieldVisible  = [bool]$win.SearchField.Visible
                InfoVisible   = [bool]$win.InfoLabel.Visible
                InfoText      = [string]$win.InfoLabel.Text
            }
        } $rows
        $result.PromptVisible | Should -BeFalse
        $result.FieldVisible | Should -BeFalse
        $result.InfoVisible | Should -BeTrue
        $result.InfoText | Should -BeExactly '共 2 台'
    }

    It '列表视图承接传入的行集合与 SelectedIndex' {
        $rows = & $script:makeRows
        $result = & $script:mod {
            param($r)
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $win = New-SshHostDashboardWindow -Rows $r -Categories @('All') -ActiveCategory 'All' `
                -SelectedIndex 1 -Theme $theme -WindowWidth 120 -WindowHeight 30
            [PSCustomObject]@{
                RowCount      = @($win.ListView.Rows).Count
                SelectedIndex = $win.ListView.SelectedIndex
                Slot0Name     = [string]$win.ListView.Slots[0].Name.Text
                Slot1Name     = [string]$win.ListView.Slots[1].Name.Text
            }
        } $rows
        $result.RowCount | Should -Be 2
        $result.SelectedIndex | Should -Be 1
        $result.Slot0Name | Should -BeExactly 'alpha'
        $result.Slot1Name | Should -BeExactly 'beta'
    }
}
