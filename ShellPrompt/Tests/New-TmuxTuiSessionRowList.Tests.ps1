# New-TmuxTuiSessionRowList.Tests.ps1 - tmux 会话仪表盘**左侧会话行列表**的契约测试
#
# 覆盖 (2026-11-06 #9b871512 "Forest Matrix"(翡翠绿/竹青)重构):
#   1. Get-TmuxTuiStateShort: 状态简写纯函数 —— Attached -> "● Att",
#      Detached/空 -> "○ Det"; 绝不用字母 o 充当图标;
#   2. Get-TmuxTuiSessionRowGeometry: 新列几何(序号徽标 6 列 / 会话名 / 状态 6 列 /
#      窗口数 4 列), 响应式断点 <26 藏状态+窗口数 / <34 藏窗口数 / >=34 三列全留,
#      列与列之间永不重叠, 会话名列宽恒 >= 4;
#   3. New-TmuxTuiSessionRowList: 槽位数 == 可视高度, 容器 CanFocus 为真,
#      首帧槽位 RowIndex 反映真实行, 选中槽位 Selected 为真;
#   4. Set-TmuxTuiSessionSlot: **选中行不铺任何饱和底色**(背景恒 Black, 与未选中
#      行同底), 序号徽标 ┃02┃ / "  01  " 各 6 列, 状态简写 "● Att"/"○ Det",
#      Attached **恒亮绿**(选中与否同源), 窗口数 "3w" 形态, 选中行任何文本片段
#      都不是 DarkGray 前景(暗字压黑底不可读);
#   5. Update-TmuxTuiSessionSelection: 同下标幂等返回 $false, 换行返回 $true
#      并同步 SelectedIndex, **只重写旧/新两行**(性能契约: 脏区只两行);
#   6. Set-TmuxTuiSessionScroll: Top 夹紧到 [0, max(0, 行数-高度)], 超出末行的
#      槽位被清空, 内容未变的槽位不被重写;
#   7. Move-TmuxTuiSessionSelection: 边界夹取(不环绕), 中间移动恰好一行。
#
# 说明: Terminal.Gui 视图可以在无 TTY 的环境下**构造**(不进事件循环),
#       本文件只组装/刷新视图, 不 Init / 不 Run。

Describe 'Get-TmuxTuiStateShort: 状态简写(纯函数)' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It 'Attached -> 恰好 "● Att"(U+25CF 实心圆点 + 空格 + Att)' {
        $result = & $script:mod { Get-TmuxTuiStateShort -Status 'Attached' }
        $result | Should -BeExactly ('{0} Att' -f [string][char]0x25CF)
    }

    It 'Detached -> 恰好 "○ Det"(U+25CB 空心圆点 + 空格 + Det)' {
        $result = & $script:mod { Get-TmuxTuiStateShort -Status 'Detached' }
        $result | Should -BeExactly ('{0} Det' -f [string][char]0x25CB)
    }

    It '大小写不敏感: attached / ATTACHED / detached 都走同一套简写' {
        $result = & $script:mod {
            [PSCustomObject]@{
                LowerAttached = Get-TmuxTuiStateShort -Status 'attached'
                UpperAttached = Get-TmuxTuiStateShort -Status 'ATTACHED'
                LowerDetached = Get-TmuxTuiStateShort -Status 'detached'
            }
        }
        $result.LowerAttached | Should -BeExactly ('{0} Att' -f [string][char]0x25CF)
        $result.UpperAttached | Should -BeExactly ('{0} Att' -f [string][char]0x25CF)
        $result.LowerDetached | Should -BeExactly ('{0} Det' -f [string][char]0x25CB)
    }

    It '空/未知状态按空闲处理 -> "○ Det"(不伪造状态, 不抛异常)' {
        $result = & $script:mod {
            [PSCustomObject]@{
                Empty   = Get-TmuxTuiStateShort -Status ''
                Missing = Get-TmuxTuiStateShort -Status $null
                Unknown = Get-TmuxTuiStateShort -Status 'weird'
            }
        }
        $result.Empty | Should -BeExactly ('{0} Det' -f [string][char]0x25CB)
        $result.Missing | Should -BeExactly ('{0} Det' -f [string][char]0x25CB)
        $result.Unknown | Should -BeExactly ('{0} Det' -f [string][char]0x25CB)
    }

    It '简写里绝不含 ASCII 字母 o(严禁用字母 o 充当图标)' {
        $result = & $script:mod {
            @(
                (Get-TmuxTuiStateShort -Status 'Attached')
                (Get-TmuxTuiStateShort -Status 'Detached')
                (Get-TmuxTuiStateShort -Status '')
            )
        }
        foreach ($s in $result) {
            $s | Should -Not -Match 'o' -Because '图标必须是 ●/○ 这类正规 Unicode 符号, 不能拿字母 o 顶替'
        }
        # 结构上: 1 个符号 + 空格 + 3 个字母
        foreach ($s in $result) {
            $s | Should -Match ('^[{0}{1}] [A-Za-z]{{3}}$' -f [string][char]0x25CF, [string][char]0x25CB)
        }
    }
}

Describe 'Get-TmuxTuiSessionRowGeometry: 列几何的响应式取舍' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It '列几何常量: DotX=1 / DotWidth=6 / NameX=7 / StatusWidth=6 / WindowsWidth=4' {
        $g = & $script:mod { Get-TmuxTuiSessionRowGeometry -Width 60 }
        $g.DotX | Should -Be 1 -Because '最左列是序号徽标, 左边留 1 列空隙'
        $g.DotWidth | Should -Be 6 -Because '徽标列固定 6 列(选中/未选中同宽 => 会话名起点对齐)'
        $g.NameX | Should -Be 7 -Because '会话名紧跟徽标列'
        $g.StatusWidth | Should -Be 6 -Because '状态简写 "● Att" 占 6 列(右对齐)'
        $g.WindowsWidth | Should -Be 4 -Because '窗口数 "3w" 占 4 列(右对齐)'
    }

    It '宽度 64 时三列全留(徽标 / 名称 / 状态 / 窗口数)' {
        $g = & $script:mod { Get-TmuxTuiSessionRowGeometry -Width 64 }
        $g.StatusWidth | Should -BeGreaterThan 0 -Because '宽屏必须保留状态列'
        $g.WindowsWidth | Should -BeGreaterThan 0 -Because '宽屏必须保留窗口数列'
        $g.NameWidth | Should -BeGreaterThan 0 -Because '会话名列永远存在'
    }

    It '宽度 30 时保留状态列但藏掉窗口数列(< 34 档)' {
        $g = & $script:mod { Get-TmuxTuiSessionRowGeometry -Width 30 }
        $g.StatusWidth | Should -BeGreaterThan 0 -Because '中屏仍要显示 ● Att/○ Det'
        $g.WindowsWidth | Should -Be 0 -Because '中屏优先保会话名, 窗口数让位'
    }

    It '宽度 25 时状态列与窗口数列都藏掉(< 26 档)' {
        $g = & $script:mod { Get-TmuxTuiSessionRowGeometry -Width 25 }
        $g.StatusWidth | Should -Be 0 -Because '窄屏必须先舍次要列'
        $g.WindowsWidth | Should -Be 0 -Because '窄屏必须先舍次要列'
        $g.NameWidth | Should -BeGreaterThan 0 -Because '会话名永远保留'
    }

    It '响应式断点边界: 25 -> 双藏 / 26 -> 藏窗口数 / 33 -> 藏窗口数 / 34 -> 三列全留' {
        $result = & $script:mod {
            [PSCustomObject]@{
                W25 = Get-TmuxTuiSessionRowGeometry -Width 25
                W26 = Get-TmuxTuiSessionRowGeometry -Width 26
                W33 = Get-TmuxTuiSessionRowGeometry -Width 33
                W34 = Get-TmuxTuiSessionRowGeometry -Width 34
            }
        }
        $result.W25.StatusWidth | Should -Be 0
        $result.W25.WindowsWidth | Should -Be 0
        $result.W26.StatusWidth | Should -BeGreaterThan 0 -Because '26 列是"只藏窗口数"档的起点'
        $result.W26.WindowsWidth | Should -Be 0
        $result.W33.StatusWidth | Should -BeGreaterThan 0
        $result.W33.WindowsWidth | Should -Be 0
        $result.W34.StatusWidth | Should -BeGreaterThan 0 -Because '34 列是三列全留的起点'
        $result.W34.WindowsWidth | Should -BeGreaterThan 0
    }

    It '各列起点依次递进, 列与列之间不重叠' {
        foreach ($w in @(24, 30, 36, 40, 48, 64, 80)) {
            $g = & $script:mod { param($x) Get-TmuxTuiSessionRowGeometry -Width $x } $w
            $g.NameX | Should -BeGreaterOrEqual ($g.DotX + $g.DotWidth) -Because "宽度 $w 下会话名不能压住徽标列"
            if ($g.StatusWidth -gt 0) {
                $g.StatusX | Should -BeGreaterOrEqual ($g.NameX + $g.NameWidth) -Because "宽度 $w 下状态列不能压住会话名列"
            }
            if ($g.WindowsWidth -gt 0) {
                $g.WindowsX | Should -BeGreaterOrEqual ($g.StatusX + $g.StatusWidth) -Because "宽度 $w 下窗口数列不能压住状态列"
            }
        }
    }

    It '会话名列宽恒 >= 4(名称优先于次要列)' {
        foreach ($w in @(20, 24, 30, 36, 40, 56, 64, 100)) {
            $g = & $script:mod { param($x) Get-TmuxTuiSessionRowGeometry -Width $x } $w
            $g.NameWidth | Should -BeGreaterOrEqual 4 -Because "宽度 $w 下会话名列不能被压没"
        }
    }
}

Describe 'New-TmuxTuiSessionRowList: 列表组装' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'

        $script:makeRows = {
            param([int]$count = 3)
            $list = [System.Collections.Generic.List[PSCustomObject]]::new()
            for ($i = 1; $i -le $count; $i++) {
                $status = if ($i % 2 -eq 1) { 'Attached' } else { 'Detached' }
                $list.Add([PSCustomObject]@{
                        No      = $i
                        Session = "sess-$i"
                        Status  = $status
                        Windows = $i
                        Name    = "sess-$i"
                    }) | Out-Null
            }
            return $list.ToArray()
        }
    }

    It '槽位数量 == 可视高度' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @([PSCustomObject]@{ No = 1; Session = 'a'; Status = 'Attached'; Windows = 1; Name = 'a' })
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 5 -SelectedIndex 0 -Theme $theme -Tgui $tg
            [PSCustomObject]@{ Slots = @($lv.Slots).Count; Height = $lv.Height }
        }
        $result.Slots | Should -Be 5
        $result.Height | Should -Be 5
    }

    It '容器 CanFocus 为真(方向键由编排层在 KeyDown 里实现, 依赖它)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @([PSCustomObject]@{ No = 1; Session = 'a'; Status = 'Attached'; Windows = 1; Name = 'a' })
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 3 -SelectedIndex 0 -Theme $theme -Tgui $tg
            [PSCustomObject]@{ CanFocus = [bool]$lv.View.CanFocus }
        }
        $result.CanFocus | Should -BeTrue
    }

    It '徽标列宽是 6 列(序号徽标占位, 不是旧的 2 列状态点)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @([PSCustomObject]@{ No = 1; Session = 'a'; Status = 'Attached'; Windows = 1; Name = 'a' })
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 3 -SelectedIndex 0 -Theme $theme -Tgui $tg
            [PSCustomObject]@{ DotWidth = $lv.Geometry.DotWidth; LabelWidth = $lv.Slots[0].Dot.Width.ToString() }
        }
        $result.DotWidth | Should -Be 6
        $result.LabelWidth | Should -Match '6' -Because '徽标 Label 本身也占 6 列'
    }

    It '首帧填充后槽位 RowIndex 反映真实行(行数不足的空槽为 -1)' {
        $rows = & $script:makeRows -count 3
        $result = & $script:mod {
            param($r)
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $lv = New-TmuxTuiSessionRowList -Rows $r -Width 56 -Height 5 -SelectedIndex 0 -Theme $theme -Tgui $tg
            [PSCustomObject]@{ RowIndexes = @($lv.Slots | ForEach-Object { $_.RowIndex }) }
        } $rows
        $result.RowIndexes | Should -Be @(0, 1, 2, -1, -1)
    }

    It '只有 SelectedIndex 指向的槽位 Selected 为真, 其余为假' {
        $rows = & $script:makeRows -count 3
        $result = & $script:mod {
            param($r)
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $lv = New-TmuxTuiSessionRowList -Rows $r -Width 56 -Height 5 -SelectedIndex 1 -Theme $theme -Tgui $tg
            [PSCustomObject]@{ Selected = @($lv.Slots | ForEach-Object { [bool]$_.Selected }) }
        } $rows
        $result.Selected | Should -Be @($false, $true, $false, $false, $false)
    }

    It '越界的 SelectedIndex 被容忍(不抛异常, 也不产生非法选中态)' {
        $rows = & $script:makeRows -count 3
        $result = & $script:mod {
            param($r)
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $threw = $false
            $lv = $null
            try {
                $lv = New-TmuxTuiSessionRowList -Rows $r -Width 56 -Height 4 -SelectedIndex 99 -Theme $theme -Tgui $tg
            } catch {
                $threw = $true
            }
            [PSCustomObject]@{
                Threw          = $threw
                SelectedStates = @($lv.Slots | ForEach-Object { [bool]$_.Selected })
            }
        } $rows
        $result.Threw | Should -BeFalse
        # 越界选中不应把任何槽位标成选中(否则会渲染出一个不存在的选中行)
        ($result.SelectedStates | Where-Object { $_ }).Count | Should -Be 0
    }
}

Describe 'Set-TmuxTuiSessionSlot: 槽位渲染与配色 (Forest Matrix)' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It '选中行**不铺任何饱和底色**: 背景与未选中行相同, 且不是蓝底 SelectionBg / 洋红 Selected' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{ No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 2; Name = 'alpha' }
                [PSCustomObject]@{ No = 2; Session = 'beta'; Status = 'Detached'; Windows = 3; Name = 'beta' }
            )
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 3 -SelectedIndex 0 -Theme $theme -Tgui $tg
            $sel = $lv.Slots[0].Bg.GetScheme()
            $plain = $lv.Slots[1].Bg.GetScheme()
            [PSCustomObject]@{
                SameAsPlain  = ($sel -eq $plain)
                IsText       = ($sel -eq $theme.Text)
                IsSelectionBg = ($sel -eq $theme.SelectionBg)
                IsMagenta    = ($sel -eq $theme.Selected)
                SelBg        = "$($sel.Normal.Background.R),$($sel.Normal.Background.G),$($sel.Normal.Background.B)"
                PlainBg      = "$($plain.Normal.Background.R),$($plain.Normal.Background.G),$($plain.Normal.Background.B)"
                MagentaBg    = "$($theme.Selected.Normal.Background.R),$($theme.Selected.Normal.Background.G),$($theme.Selected.Normal.Background.B)"
                BlueBg       = "$($theme.SelectionBg.Normal.Background.R),$($theme.SelectionBg.Normal.Background.G),$($theme.SelectionBg.Normal.Background.B)"
            }
        }
        $result.SameAsPlain | Should -BeTrue -Because '选中态与未选中态的背景必须完全一致(黑底)'
        $result.IsText | Should -BeTrue -Because '背景条走纯黑底的正文 Text 方案'
        $result.IsSelectionBg | Should -BeFalse -Because '高饱和蓝底在 Windows Terminal 上刺眼, 已取消'
        $result.IsMagenta | Should -BeFalse -Because '洋红底造成红绿眩光, 已取消'
        $result.SelBg | Should -Be $result.PlainBg
        $result.SelBg | Should -Not -Be $result.MagentaBg
        $result.SelBg | Should -Not -Be $result.BlueBg
    }

    It '序号徽标: 选中行是 "┃02┃"(U+2503 包裹两位序号) 且用 ForestBadge' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{ No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 2; Name = 'alpha' }
                [PSCustomObject]@{ No = 2; Session = 'beta'; Status = 'Detached'; Windows = 3; Name = 'beta' }
            )
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 3 -SelectedIndex 1 -Theme $theme -Tgui $tg
            $slot = $lv.Slots[1]
            [PSCustomObject]@{
                Text   = [string]$slot.Dot.Text
                IsBadge = ($slot.Dot.GetScheme() -eq $theme.ForestBadge)
            }
        }
        $result.Text | Should -BeExactly ('{0}02{0}' -f [string][char]0x2503) -Because '选中行用 ┃ 包裹两位序号锚定位置'
        $result.IsBadge | Should -BeTrue -Because '选中徽标走 ForestBadge(BrightGreen)'
    }

    It '序号徽标: 未选中行是 "  01  "(两位序号 + 两侧留白) 且用 ForestBadgeOff' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{ No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 2; Name = 'alpha' }
                [PSCustomObject]@{ No = 2; Session = 'beta'; Status = 'Detached'; Windows = 3; Name = 'beta' }
            )
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 3 -SelectedIndex 1 -Theme $theme -Tgui $tg
            $slot = $lv.Slots[0]
            [PSCustomObject]@{
                Text      = [string]$slot.Dot.Text
                IsBadgeOff = ($slot.Dot.GetScheme() -eq $theme.ForestBadgeOff)
            }
        }
        $result.Text | Should -BeExactly '  01  '
        $result.IsBadgeOff | Should -BeTrue -Because '未选中徽标走 ForestBadgeOff(DarkGray)'
    }

    It '徽标列在选中/未选中两态都是 6 列, 会话名起点 X 完全一致' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{ No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 2; Name = 'alpha' }
                [PSCustomObject]@{ No = 2; Session = 'beta'; Status = 'Detached'; Windows = 3; Name = 'beta' }
            )
            $lvSel = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 3 -SelectedIndex 0 -Theme $theme -Tgui $tg
            $lvOff = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 3 -SelectedIndex -1 -Theme $theme -Tgui $tg
            [PSCustomObject]@{
                SelDotWidth = $lvSel.Slots[0].Dot.Width.ToString()
                OffDotWidth = $lvOff.Slots[0].Dot.Width.ToString()
                SelNameX = $lvSel.Slots[0].Name.X.ToString()
                OffNameX = $lvOff.Slots[0].Name.X.ToString()
                SelNameX2 = $lvSel.Slots[1].Name.X.ToString()
                OffNameX2 = $lvOff.Slots[1].Name.X.ToString()
            }
        }
        $result.SelDotWidth | Should -Match '6'
        $result.OffDotWidth | Should -Match '6'
        $result.SelNameX | Should -Be $result.OffNameX -Because '选中态不得把会话名挤右一格'
        $result.SelNameX2 | Should -Be $result.OffNameX2
    }

    It '状态列是简写形态: Attached -> "● Att", Detached -> "○ Det"' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{ No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 2; Name = 'alpha' }
                [PSCustomObject]@{ No = 2; Session = 'beta'; Status = 'Detached'; Windows = 3; Name = 'beta' }
            )
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 3 -SelectedIndex -1 -Theme $theme -Tgui $tg
            [PSCustomObject]@{
                Attached = [string]$lv.Slots[0].Status.Text
                Detached = [string]$lv.Slots[1].Status.Text
            }
        }
        $result.Attached | Should -BeExactly ('{0} Att' -f [string][char]0x25CF)
        $result.Detached | Should -BeExactly ('{0} Det' -f [string][char]0x25CB)
    }

    It 'Attached **恒亮绿**: 未选中与选中两态的状态方案都是 ForestAttached(同一实例)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{ No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 2; Name = 'alpha' }
                [PSCustomObject]@{ No = 2; Session = 'beta'; Status = 'Detached'; Windows = 3; Name = 'beta' }
            )
            $lvOff = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 3 -SelectedIndex -1 -Theme $theme -Tgui $tg
            $lvSel = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 3 -SelectedIndex 0 -Theme $theme -Tgui $tg
            [PSCustomObject]@{
                OffAttached = $lvOff.Slots[0].Status.GetScheme()
                SelAttached = $lvSel.Slots[0].Status.GetScheme()
                ForestAttached = $theme.ForestAttached
            }
        }
        $result.OffAttached | Should -Be $result.ForestAttached -Because '未选中 Attached 状态恒亮绿'
        $result.SelAttached | Should -Be $result.ForestAttached -Because '选中 Attached 状态同样是亮绿(状态语义不随选中态漂移)'
        $result.OffAttached | Should -Be $result.SelAttached -Because '两态必须用同一个 Scheme 实例'
    }

    It 'Detached: 未选中 ForestDetached(DarkGray), 选中 ForestDetachedOn(White)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{ No = 1; Session = 'alpha'; Status = 'Detached'; Windows = 2; Name = 'alpha' }
            )
            $lvOff = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 3 -SelectedIndex -1 -Theme $theme -Tgui $tg
            $lvSel = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 3 -SelectedIndex 0 -Theme $theme -Tgui $tg
            [PSCustomObject]@{
                Off = ($lvOff.Slots[0].Status.GetScheme() -eq $theme.ForestDetached)
                Sel = ($lvSel.Slots[0].Status.GetScheme() -eq $theme.ForestDetachedOn)
            }
        }
        $result.Off | Should -BeTrue
        $result.Sel | Should -BeTrue
    }

    It '选中行可读性: 任何文本片段都不得是 DarkGray 前景(暗字压黑底不可读)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{ No = 1; Session = 'alpha'; Status = 'Detached'; Windows = 2; Name = 'alpha' }
            )
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 3 -SelectedIndex 0 -Theme $theme -Tgui $tg
            $dimRgb = "$($theme.Dim.Normal.Foreground.R),$($theme.Dim.Normal.Foreground.G),$($theme.Dim.Normal.Foreground.B)"
            $slot = $lv.Slots[0]
            $segments = @($slot.Bg, $slot.Dot, $slot.Name, $slot.Status, $slot.Windows)
            $dark = @()
            foreach ($seg in $segments) {
                $rgb = "$($seg.GetScheme().Normal.Foreground.R),$($seg.GetScheme().Normal.Foreground.G),$($seg.GetScheme().Normal.Foreground.B)"
                if ($rgb -eq $dimRgb) { $dark += [string]$seg.Text }
            }
            [PSCustomObject]@{
                DarkSegments = @($dark)
                NameIsOn    = ($slot.Name.GetScheme() -eq $theme.ForestNameOn)
                WinIsOn     = ($slot.Windows.GetScheme() -eq $theme.ForestWinCountOn)
                NameIsOff   = ($slot.Name.GetScheme() -eq $theme.ForestName)
                WinIsOff    = ($slot.Windows.GetScheme() -eq $theme.ForestWinCount)
            }
        }
        @($result.DarkSegments).Count | Should -Be 0 -Because '选中行不允许残留 DarkGray 文本'
        $result.NameIsOn | Should -BeTrue -Because '选中行会话名提亮为 ForestNameOn'
        $result.WinIsOn | Should -BeTrue -Because '选中行窗口数提亮为 ForestWinCountOn'
        $result.NameIsOff | Should -BeFalse
        $result.WinIsOff | Should -BeFalse
    }

    It '未选中行: 会话名 ForestName(Gray), 窗口数 ForestWinCount(DarkGray)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{ No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 2; Name = 'alpha' }
            )
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 3 -SelectedIndex -1 -Theme $theme -Tgui $tg
            $slot = $lv.Slots[0]
            [PSCustomObject]@{
                Name    = ($slot.Name.GetScheme() -eq $theme.ForestName)
                Windows = ($slot.Windows.GetScheme() -eq $theme.ForestWinCount)
            }
        }
        $result.Name | Should -BeTrue
        $result.Windows | Should -BeTrue
    }

    It '窗口数是 "3w" 形态(数字 + w), 两态都是' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{ No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 3; Name = 'alpha' }
            )
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 3 -SelectedIndex -1 -Theme $theme -Tgui $tg
            $lvSel = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 3 -SelectedIndex 0 -Theme $theme -Tgui $tg
            [PSCustomObject]@{
                Off = [string]$lv.Slots[0].Windows.Text
                Sel = [string]$lvSel.Slots[0].Windows.Text
            }
        }
        $result.Off | Should -BeExactly '3w'
        $result.Sel | Should -BeExactly '3w'
    }

    It '名称 / 状态 / 窗口数分别落到对应标签(未选中行)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{ No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 7; Name = 'alpha' }
            )
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 3 -SelectedIndex -1 -Theme $theme -Tgui $tg
            $slot = $lv.Slots[0]
            [PSCustomObject]@{
                Name    = [string]$slot.Name.Text
                Status  = [string]$slot.Status.Text
                Windows = [string]$slot.Windows.Text
                Dot     = [string]$slot.Dot.Text
            }
        }
        $result.Name | Should -BeExactly 'alpha'
        $result.Status | Should -BeExactly ('{0} Att' -f [string][char]0x25CF)
        $result.Windows | Should -BeExactly '7w'
        $result.Dot | Should -BeExactly '  01  '
    }

    It '窄列时状态与窗口数让位(文本为空), 但徽标与会话名仍在' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{ No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 7; Name = 'alpha' }
            )
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 24 -Height 3 -SelectedIndex 0 -Theme $theme -Tgui $tg
            $slot = $lv.Slots[0]
            [PSCustomObject]@{
                Status  = [string]$slot.Status.Text
                Windows = [string]$slot.Windows.Text
                Name    = [string]$slot.Name.Text
                Dot     = [string]$slot.Dot.Text
            }
        }
        $result.Status | Should -BeExactly '' -Because '窄屏先藏状态列'
        $result.Windows | Should -BeExactly '' -Because '窄屏先藏窗口数列'
        $result.Name | Should -BeExactly 'alpha'
        $result.Dot | Should -BeExactly ('{0}01{0}' -f [string][char]0x2503)
    }

    It '空格位(RowIndex=-1)清空所有内容标签' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{ No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 7; Name = 'alpha' }
            )
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 3 -SelectedIndex -1 -Theme $theme -Tgui $tg
            Set-TmuxTuiSessionSlot -ListView $lv -SlotIndex 1 -RowIndex -1 -Selected $false
            $slot = $lv.Slots[1]
            [PSCustomObject]@{
                RowIndex = $slot.RowIndex
                Name     = [string]$slot.Name.Text
                Status   = [string]$slot.Status.Text
                Windows  = [string]$slot.Windows.Text
                Dot      = [string]$slot.Dot.Text
                # 背景条用等宽空白擦除残影(不是空串)
                BgWidth  = ([string]$slot.Bg.Text).Length
            }
        }
        $result.RowIndex | Should -Be -1
        $result.Name | Should -BeExactly ''
        $result.Status | Should -BeExactly ''
        $result.Windows | Should -BeExactly ''
        $result.Dot | Should -BeExactly ''
        $result.BgWidth | Should -Be 56
    }
}

Describe 'Update-TmuxTuiSessionSelection: 选中移动(只重写两行)' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It 'OldIndex == NewIndex 时返回 $false(幂等, 不重刷)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{ No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 2; Name = 'alpha' }
            )
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 3 -SelectedIndex 0 -Theme $theme -Tgui $tg
            Update-TmuxTuiSessionSelection -ListView $lv -OldIndex 0 -NewIndex 0
        }
        $result | Should -BeFalse
    }

    It '换行时返回 $true 并同步 SelectedIndex' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{ No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 2; Name = 'alpha' }
                [PSCustomObject]@{ No = 2; Session = 'beta'; Status = 'Detached'; Windows = 3; Name = 'beta' }
            )
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 3 -SelectedIndex 0 -Theme $theme -Tgui $tg
            $changed = Update-TmuxTuiSessionSelection -ListView $lv -OldIndex 0 -NewIndex 1
            [PSCustomObject]@{ Changed = $changed; Selected = $lv.SelectedIndex }
        }
        $result.Changed | Should -BeTrue
        $result.Selected | Should -Be 1
    }

    It '只重写受影响的两个槽位(其余槽位指纹不变 —— 脏区只有两行)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{ No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 2; Name = 'alpha' }
                [PSCustomObject]@{ No = 2; Session = 'beta'; Status = 'Detached'; Windows = 3; Name = 'beta' }
                [PSCustomObject]@{ No = 3; Session = 'gamma'; Status = 'Attached'; Windows = 4; Name = 'gamma' }
                [PSCustomObject]@{ No = 4; Session = 'delta'; Status = 'Detached'; Windows = 5; Name = 'delta' }
                [PSCustomObject]@{ No = 5; Session = 'epsilon'; Status = 'Attached'; Windows = 6; Name = 'epsilon' }
            )
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 5 -SelectedIndex 0 -Theme $theme -Tgui $tg
            $before = @($lv.Slots | ForEach-Object { '{0}|{1}|{2}' -f $_.RowIndex, [bool]$_.Selected, [string]$_.Name.Text })
            $changed = Update-TmuxTuiSessionSelection -ListView $lv -OldIndex 0 -NewIndex 1
            $after = @($lv.Slots | ForEach-Object { '{0}|{1}|{2}' -f $_.RowIndex, [bool]$_.Selected, [string]$_.Name.Text })
            $diff = 0
            for ($i = 0; $i -lt $before.Count; $i++) {
                if ($before[$i] -ne $after[$i]) { $diff++ }
            }
            [PSCustomObject]@{ Changed = $changed; Diff = $diff }
        }
        $result.Changed | Should -BeTrue
        $result.Diff | Should -Be 2 -Because '移动选中只允许旧行与新行两行被重绘'
    }

    It '移动选中后: 新行变徽标态, 旧行退回未选中徽标态' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{ No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 2; Name = 'alpha' }
                [PSCustomObject]@{ No = 2; Session = 'beta'; Status = 'Detached'; Windows = 3; Name = 'beta' }
            )
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 3 -SelectedIndex 0 -Theme $theme -Tgui $tg
            [void](Update-TmuxTuiSessionSelection -ListView $lv -OldIndex 0 -NewIndex 1)
            [PSCustomObject]@{
                OldDot = [string]$lv.Slots[0].Dot.Text
                NewDot = [string]$lv.Slots[1].Dot.Text
            }
        }
        $result.OldDot | Should -BeExactly '  01  '
        $result.NewDot | Should -BeExactly ('{0}02{0}' -f [string][char]0x2503)
    }
}

Describe 'Set-TmuxTuiSessionScroll: 滚动与空槽' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It 'Top 被夹紧到 [0, max(0, 行数-高度)]' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(1..10 | ForEach-Object {
                    [PSCustomObject]@{ No = $_; Session = "sess-$_"; Status = 'Attached'; Windows = $_; Name = "sess-$_" }
                })
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 4 -SelectedIndex 0 -Theme $theme -Tgui $tg
            Set-TmuxTuiSessionScroll -ListView $lv -Top 99
            $topTooBig = $lv.Top
            # 负数 Top 是"省略"的哨兵值(不改变当前 Top), 因此 Top 始终落在合法区间内
            Set-TmuxTuiSessionScroll -ListView $lv -Top -5
            $topAfterNegative = $lv.Top
            [PSCustomObject]@{
                TopTooBig        = $topTooBig
                TopAfterNegative = $topAfterNegative
                MaxTop           = [Math]::Max(0, @($rows).Count - $lv.Height)
            }
        }
        $result.TopTooBig | Should -Be 6
        $result.TopAfterNegative | Should -BeGreaterOrEqual 0
        $result.TopAfterNegative | Should -BeLessOrEqual $result.MaxTop
    }

    It '行数少于可视高度时, 超出末行的槽位被清空(RowIndex=-1 且标签为空)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{ No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 2; Name = 'alpha' }
                [PSCustomObject]@{ No = 2; Session = 'beta'; Status = 'Detached'; Windows = 3; Name = 'beta' }
            )
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 4 -SelectedIndex 0 -Theme $theme -Tgui $tg
            Set-TmuxTuiSessionScroll -ListView $lv
            $slot = $lv.Slots[3]
            [PSCustomObject]@{
                RowIndex = $slot.RowIndex
                Name     = [string]$slot.Name.Text
                Status   = [string]$slot.Status.Text
                Windows  = [string]$slot.Windows.Text
                Dot      = [string]$slot.Dot.Text
            }
        }
        $result.RowIndex | Should -Be -1
        $result.Name | Should -BeExactly ''
        $result.Status | Should -BeExactly ''
        $result.Windows | Should -BeExactly ''
        $result.Dot | Should -BeExactly ''
    }

    It '以相同 Top 重新滚动不重写任何槽位(未变槽位被跳过)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(1..6 | ForEach-Object {
                    [PSCustomObject]@{ No = $_; Session = "sess-$_"; Status = 'Attached'; Windows = $_; Name = "sess-$_" }
                })
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 4 -SelectedIndex 0 -Theme $theme -Tgui $tg
            $before = @($lv.Slots | ForEach-Object { '{0}|{1}|{2}' -f $_.RowIndex, [bool]$_.Selected, [string]$_.Name.Text })
            Set-TmuxTuiSessionScroll -ListView $lv
            $after = @($lv.Slots | ForEach-Object { '{0}|{1}|{2}' -f $_.RowIndex, [bool]$_.Selected, [string]$_.Name.Text })
            $diff = 0
            for ($i = 0; $i -lt $before.Count; $i++) {
                if ($before[$i] -ne $after[$i]) { $diff++ }
            }
            [PSCustomObject]@{ Diff = $diff }
        }
        $result.Diff | Should -Be 0 -Because '内容与选中态都没变的槽位不得被重写(否则脏区会膨胀到整屏)'
    }

    It '滚动一行: 只有内容真正变化的槽位被重写, 且每个槽位内容与其新行严格对应' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(1..6 | ForEach-Object {
                    [PSCustomObject]@{ No = $_; Session = "sess-$_"; Status = 'Attached'; Windows = $_; Name = "sess-$_" }
                })
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 4 -SelectedIndex 0 -Theme $theme -Tgui $tg
            $before = @($lv.Slots | ForEach-Object { '{0}|{1}|{2}' -f $_.RowIndex, [bool]$_.Selected, [string]$_.Name.Text })
            $beforeRowIndexes = @($lv.Slots | ForEach-Object { $_.RowIndex })
            Set-TmuxTuiSessionScroll -ListView $lv -Top 1
            $after = @($lv.Slots | ForEach-Object { '{0}|{1}|{2}' -f $_.RowIndex, [bool]$_.Selected, [string]$_.Name.Text })
            $afterRowIndexes = @($lv.Slots | ForEach-Object { $_.RowIndex })

            # 被重写的槽位集合 == 行号发生变化的槽位集合(不多刷也不少刷)
            $rewritten = @()
            $contentChanged = @()
            for ($i = 0; $i -lt $before.Count; $i++) {
                if ($before[$i] -ne $after[$i]) { $rewritten += $i }
                if ($beforeRowIndexes[$i] -ne $afterRowIndexes[$i]) { $contentChanged += $i }
            }
            # 每个槽位显示的会话名必须等于它当前行号对应的会话名
            $names = @()
            for ($i = 0; $i -lt $afterRowIndexes.Count; $i++) {
                $idx = $afterRowIndexes[$i]
                $expected = if ($idx -ge 0) { "sess-$($idx + 1)" } else { '' }
                $names += [PSCustomObject]@{ Actual = [string]$lv.Slots[$i].Name.Text; Expected = $expected }
            }
            [PSCustomObject]@{
                Rewritten       = $rewritten.Count
                ContentChanged  = $contentChanged.Count
                SameSet         = (@(Compare-Object -ReferenceObject $rewritten -DifferenceObject $contentChanged).Count -eq 0)
                MismatchedNames = @($names | Where-Object { $_.Actual -ne $_.Expected }).Count
                Top             = $lv.Top
            }
        }
        $result.Top | Should -Be 1
        $result.SameSet | Should -BeTrue -Because '被重写的槽位必须恰好是行号变化的那些槽位'
        $result.MismatchedNames | Should -Be 0 -Because '滚动后每个槽位必须显示它对应行的会话名'
        # 滚动一行, 可见窗口整体平移, 4 个槽位都换了内容
        $result.Rewritten | Should -Be $result.ContentChanged
    }
}

Describe 'Move-TmuxTuiSessionSelection: 边界夹取' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It '末行再往下移不移动(返回 $false, SelectedIndex 不变)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(1..3 | ForEach-Object {
                    [PSCustomObject]@{ No = $_; Session = "sess-$_"; Status = 'Attached'; Windows = $_; Name = "sess-$_" }
                })
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 5 -SelectedIndex 2 -Theme $theme -Tgui $tg
            $moved = Move-TmuxTuiSessionSelection -ListView $lv -Delta 1
            [PSCustomObject]@{ Moved = $moved; Selected = $lv.SelectedIndex }
        }
        $result.Moved | Should -BeFalse
        $result.Selected | Should -Be 2 -Because '末行必须夹取而不是环绕到第一行'
    }

    It '首行再往上移不移动(返回 $false, SelectedIndex 不变)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(1..3 | ForEach-Object {
                    [PSCustomObject]@{ No = $_; Session = "sess-$_"; Status = 'Attached'; Windows = $_; Name = "sess-$_" }
                })
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 5 -SelectedIndex 0 -Theme $theme -Tgui $tg
            $moved = Move-TmuxTuiSessionSelection -ListView $lv -Delta -1
            [PSCustomObject]@{ Moved = $moved; Selected = $lv.SelectedIndex }
        }
        $result.Moved | Should -BeFalse
        $result.Selected | Should -Be 0
    }

    It '中间行向下移动恰好一行' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(1..3 | ForEach-Object {
                    [PSCustomObject]@{ No = $_; Session = "sess-$_"; Status = 'Attached'; Windows = $_; Name = "sess-$_" }
                })
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 5 -SelectedIndex 1 -Theme $theme -Tgui $tg
            $moved = Move-TmuxTuiSessionSelection -ListView $lv -Delta 1
            [PSCustomObject]@{ Moved = $moved; Selected = $lv.SelectedIndex }
        }
        $result.Moved | Should -BeTrue
        $result.Selected | Should -Be 2
    }

    It '中间行向上移动恰好一行' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(1..3 | ForEach-Object {
                    [PSCustomObject]@{ No = $_; Session = "sess-$_"; Status = 'Attached'; Windows = $_; Name = "sess-$_" }
                })
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 5 -SelectedIndex 1 -Theme $theme -Tgui $tg
            $moved = Move-TmuxTuiSessionSelection -ListView $lv -Delta -1
            [PSCustomObject]@{ Moved = $moved; Selected = $lv.SelectedIndex }
        }
        $result.Moved | Should -BeTrue
        $result.Selected | Should -Be 0
    }
}
