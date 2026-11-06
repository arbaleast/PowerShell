# New-TmuxTuiSessionRowList.Tests.ps1 - tmux 会话仪表盘**左侧会话行列表**的契约测试
#
# 覆盖 (2026-10-31 sss 仪表盘视图层):
#   1. Get-TmuxTuiSessionRowGeometry: 列几何按可视宽度响应式取舍
#      (宽屏三列全留 / 中屏藏窗口数 / 窄屏只剩点+名), 列与列之间永不重叠,
#      会话名列宽恒 >= 4(名称优先于次要列);
#   2. New-TmuxTuiSessionRowList: 槽位数 == 可视高度, 容器 CanFocus 为真
#      (方向键由编排层在 KeyDown 里实现), 首帧槽位 RowIndex 反映真实行,
#      选中槽位 Selected 为真, 越界 SelectedIndex 被容忍;
#   3. Set-TmuxTuiSessionSlot: 选中行用 SelectionBg(蓝底) + ▎ 指示符,
#      行内文本一律提亮(绝无 DarkGray); 未选中行用正文配色,
#      状态点配色跟随 Attached(绿)/Detached(灰), 未选中 Attached 状态文本
#      走 AttachedText(状态联动), 名称/状态/窗口数分别落到对应标签,
#      空格位(RowIndex=-1)清空全部内容标签;
#   4. Update-TmuxTuiSessionSelection: 同下标幂等返回 $false, 换行返回 $true
#      并同步 SelectedIndex, **只重写旧/新两行**(性能契约: 脏区只两行);
#   5. Set-TmuxTuiSessionScroll: Top 夹紧到 [0, max(0, 行数-高度)], 超出末行的
#      槽位被清空, 内容未变的槽位不被重写(跳过未变槽位);
#   6. Move-TmuxTuiSessionSelection: 边界夹取(不环绕), 中间移动恰好一行;
#   7. 阶段一(2026-11-06)可读性契约: 选中行底色**不是洋红**, 选中行任何
#      文本片段都不得是 DarkGray 前景。
#
# 说明: Terminal.Gui 视图可以在无 TTY 的环境下**构造**(不进事件循环),
#       本文件只组装/刷新视图, 不 Init / 不 Run。

Describe 'Get-TmuxTuiSessionRowGeometry: 列几何的响应式取舍' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It '宽度 64 时三列全留(状态点 / 名称 / 状态 / 窗口数)' {
        $g = & $script:mod { Get-TmuxTuiSessionRowGeometry -Width 64 }
        $g.StatusWidth | Should -BeGreaterThan 0 -Because '宽屏必须保留状态列'
        $g.WindowsWidth | Should -BeGreaterThan 0 -Because '宽屏必须保留窗口数列'
        $g.NameWidth | Should -BeGreaterThan 0 -Because '会话名列永远存在'
    }

    It '宽度 36 时保留状态列但藏掉窗口数列' {
        $g = & $script:mod { Get-TmuxTuiSessionRowGeometry -Width 36 }
        $g.StatusWidth | Should -BeGreaterThan 0 -Because '中屏仍要显示 Attached/Detached'
        $g.WindowsWidth | Should -Be 0 -Because '中屏优先保会话名, 窗口数让位'
    }

    It '宽度 24 时状态列与窗口数列都藏掉(只剩状态点 + 会话名)' {
        $g = & $script:mod { Get-TmuxTuiSessionRowGeometry -Width 24 }
        $g.StatusWidth | Should -Be 0 -Because '窄屏必须先舍次要列'
        $g.WindowsWidth | Should -Be 0 -Because '窄屏必须先舍次要列'
        $g.NameWidth | Should -BeGreaterThan 0 -Because '会话名永远保留'
    }

    It '各列起点依次递进, 列与列之间不重叠' {
        foreach ($w in @(24, 30, 36, 40, 48, 64, 80)) {
            $g = & $script:mod { param($x) Get-TmuxTuiSessionRowGeometry -Width $x } $w
            $g.NameX | Should -BeGreaterOrEqual ($g.DotX + $g.DotWidth) -Because "宽度 $w 下会话名不能压住状态点"
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

Describe 'Set-TmuxTuiSessionSlot: 槽位渲染与配色' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It '选中行背景用 SelectionBg(蓝底), 未选中行背景用正文 Text 方案' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{ No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 2; Name = 'alpha' }
                [PSCustomObject]@{ No = 2; Session = 'beta'; Status = 'Detached'; Windows = 3; Name = 'beta' }
            )
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 3 -SelectedIndex 0 -Theme $theme -Tgui $tg
            [PSCustomObject]@{
                SelectedBg   = ($lv.Slots[0].Bg.GetScheme() -eq $theme.SelectionBg)
                UnselectedBg = ($lv.Slots[1].Bg.GetScheme() -eq $theme.Text)
            }
        }
        $result.SelectedBg | Should -BeTrue
        $result.UnselectedBg | Should -BeTrue
    }

    It '选中行底色**不是**洋红(不再使用 theme.Selected 的洋红底)' {
        # 2026-11-06 阶段一: 洋红底 + 行首绿点造成红绿眩光, 且洋红底上残留
        # DarkGray 文字几乎不可读。选中行改为蓝底(SelectionBg)。
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{ No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 2; Name = 'alpha' }
            )
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 3 -SelectedIndex 0 -Theme $theme -Tgui $tg
            $selBg = $lv.Slots[0].Bg.GetScheme()
            $magenta = $theme.Selected
            [PSCustomObject]@{
                IsMagentaScheme = ($selBg -eq $magenta)
                SelBgRgb         = "$($selBg.Normal.Background.R),$($selBg.Normal.Background.G),$($selBg.Normal.Background.B)"
                MagentaBgRgb     = "$($magenta.Normal.Background.R),$($magenta.Normal.Background.G),$($magenta.Normal.Background.B)"
                IsSelectionBg    = ($selBg -eq $theme.SelectionBg)
            }
        }
        $result.IsMagentaScheme | Should -BeFalse -Because '选中行不得再使用洋红底方案'
        $result.SelBgRgb | Should -Not -Be $result.MagentaBgRgb -Because '选中行背景 RGB 不得是洋红'
        $result.IsSelectionBg | Should -BeTrue -Because '选中行底色必须走 SelectionBg 语义方案'
    }

    It '选中行首字符是 ▎(U+258E)并用 SelectionDot 方案' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{ No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 2; Name = 'alpha' }
            )
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 3 -SelectedIndex 0 -Theme $theme -Tgui $tg
            [PSCustomObject]@{
                DotText  = [string]$lv.Slots[0].Dot.Text
                IsDot    = ($lv.Slots[0].Dot.GetScheme() -eq $theme.SelectionDot)
                DotColor = "$($theme.SelectionDot.Normal.Foreground.R),$($theme.SelectionDot.Normal.Foreground.G),$($theme.SelectionDot.Normal.Foreground.B)"
            }
        }
        $result.DotText | Should -BeExactly ([string][char]0x258E) -Because '选中行用 ▎ 锚定"这一行被选中"'
        $result.IsDot | Should -BeTrue
    }

    It '选中行任何文本片段都不得是 DarkGray 前景(暗字压蓝底不可读)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{ No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 2; Name = 'alpha' }
            )
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 3 -SelectedIndex 0 -Theme $theme -Tgui $tg
            $dimRgb = "$($theme.Dim.Normal.Foreground.R),$($theme.Dim.Normal.Foreground.G),$($theme.Dim.Normal.Foreground.B)"
            $slot = $lv.Slots[0]
            $segments = @($slot.Dot, $slot.Name, $slot.Status, $slot.Windows)
            $dark = @()
            foreach ($seg in $segments) {
                $rgb = "$($seg.GetScheme().Normal.Foreground.R),$($seg.GetScheme().Normal.Foreground.G),$($seg.GetScheme().Normal.Foreground.B)"
                if ($rgb -eq $dimRgb) { $dark += $seg.Text }
            }
            [PSCustomObject]@{
                DarkSegments = @($dark)
                NameRgb      = "$($slot.Name.GetScheme().Normal.Foreground.R),$($slot.Name.GetScheme().Normal.Foreground.G),$($slot.Name.GetScheme().Normal.Foreground.B)"
                WinRgb       = "$($slot.Windows.GetScheme().Normal.Foreground.R),$($slot.Windows.GetScheme().Normal.Foreground.G),$($slot.Windows.GetScheme().Normal.Foreground.B)"
            }
        }
        @($result.DarkSegments).Count | Should -Be 0 -Because '选中行不允许残留 DarkGray 文本'
        # 选中行会话名与窗口数必须是"最亮的白"(White)
        $white = '255,255,255'
        $result.NameRgb | Should -Be $white
        $result.WinRgb | Should -Be $white
    }

    It '选中行会话名与窗口数用 SelectionBgText 方案(白 on 蓝)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{ No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 2; Name = 'alpha' }
            )
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 3 -SelectedIndex 0 -Theme $theme -Tgui $tg
            [PSCustomObject]@{
                Name   = ($lv.Slots[0].Name.GetScheme() -eq $theme.SelectionBgText)
                Windows = ($lv.Slots[0].Windows.GetScheme() -eq $theme.SelectionBgText)
            }
        }
        $result.Name | Should -BeTrue
        $result.Windows | Should -BeTrue
    }

    It '状态点配色跟随 Attached(绿) / Detached(灰)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{ No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 2; Name = 'alpha' }
                [PSCustomObject]@{ No = 2; Session = 'beta'; Status = 'Detached'; Windows = 3; Name = 'beta' }
            )
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 3 -SelectedIndex -1 -Theme $theme -Tgui $tg
            [PSCustomObject]@{
                Attached = ($lv.Slots[0].Dot.GetScheme() -eq $theme.Attached)
                Detached = ($lv.Slots[1].Dot.GetScheme() -eq $theme.Detached)
            }
        }
        $result.Attached | Should -BeTrue
        $result.Detached | Should -BeTrue
    }

    It '未选中行首字符: Attached 是 ●(U+25CF), Detached 是 ○(U+25CB)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{ No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 2; Name = 'alpha' }
                [PSCustomObject]@{ No = 2; Session = 'beta'; Status = 'Detached'; Windows = 3; Name = 'beta' }
            )
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 3 -SelectedIndex -1 -Theme $theme -Tgui $tg
            [PSCustomObject]@{
                AttachedDot = [string]$lv.Slots[0].Dot.Text
                DetachedDot = [string]$lv.Slots[1].Dot.Text
            }
        }
        $result.AttachedDot | Should -BeExactly ([string][char]0x25CF)
        $result.DetachedDot | Should -BeExactly ([string][char]0x25CB)
    }

    It '状态联动: 未选中 Attached 行的状态文本用 AttachedText 方案(亮绿)' {
        # 2026-11-06 阶段一核心修复: 右侧详情面板与顶部统计已经是绿的,
        # 左侧 Attached 文本却还是暗灰 —— 三处状态色必须同源。
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{ No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 2; Name = 'alpha' }
                [PSCustomObject]@{ No = 2; Session = 'beta'; Status = 'Detached'; Windows = 3; Name = 'beta' }
            )
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 3 -SelectedIndex -1 -Theme $theme -Tgui $tg
            [PSCustomObject]@{
                Attached = ($lv.Slots[0].Status.GetScheme() -eq $theme.AttachedText)
                Detached = ($lv.Slots[1].Status.GetScheme() -eq $theme.Detached)
                AttachedText = [string]$lv.Slots[0].Status.Text
                DetachedText = [string]$lv.Slots[1].Status.Text
            }
        }
        $result.Attached | Should -BeTrue -Because '未选中 Attached 状态文本必须用 AttachedText(亮绿)'
        $result.Detached | Should -BeTrue -Because '未选中 Detached 状态文本用 Detached(暗灰)'
        $result.AttachedText | Should -BeExactly 'Attached'
        $result.DetachedText | Should -BeExactly 'Detached'
    }

    It '选中行状态文本: Attached 用 SelectionAttached(亮绿 on 蓝), Detached 用 SelectionDetached(白 on 蓝)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{ No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 2; Name = 'alpha' }
                [PSCustomObject]@{ No = 2; Session = 'beta'; Status = 'Detached'; Windows = 3; Name = 'beta' }
            )
            $lvA = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 3 -SelectedIndex 0 -Theme $theme -Tgui $tg
            $lvD = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 3 -SelectedIndex 1 -Theme $theme -Tgui $tg
            [PSCustomObject]@{
                SelAttached = ($lvA.Slots[0].Status.GetScheme() -eq $theme.SelectionAttached)
                SelDetached = ($lvD.Slots[1].Status.GetScheme() -eq $theme.SelectionDetached)
                SelAttachedRgb = "$($theme.SelectionAttached.Normal.Foreground.R),$($theme.SelectionAttached.Normal.Foreground.G),$($theme.SelectionAttached.Normal.Foreground.B)"
                SelDetachedRgb = "$($theme.SelectionDetached.Normal.Foreground.R),$($theme.SelectionDetached.Normal.Foreground.G),$($theme.SelectionDetached.Normal.Foreground.B)"
            }
        }
        $result.SelAttached | Should -BeTrue
        $result.SelDetached | Should -BeTrue
        # 亮绿 / 白 —— 都不是暗灰
        $result.SelAttachedRgb | Should -Be '22,198,12'
        $result.SelDetachedRgb | Should -Be '255,255,255'
    }

    It '未选中行: 会话名用 Text(白), 窗口数用 Subtle(灰)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(
                [PSCustomObject]@{ No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 2; Name = 'alpha' }
            )
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 3 -SelectedIndex -1 -Theme $theme -Tgui $tg
            [PSCustomObject]@{
                Name    = ($lv.Slots[0].Name.GetScheme() -eq $theme.Text)
                Windows = ($lv.Slots[0].Windows.GetScheme() -eq $theme.Subtle)
            }
        }
        $result.Name | Should -BeTrue
        $result.Windows | Should -BeTrue
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
        $result.Status | Should -BeExactly 'Attached'
        $result.Windows | Should -BeExactly '7'
        $result.Dot | Should -BeExactly ([string][char]0x25CF)
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
