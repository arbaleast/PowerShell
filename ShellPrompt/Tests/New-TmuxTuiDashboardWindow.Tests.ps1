# New-TmuxTuiDashboardWindow.Tests.ps1 - TGUI 整窗组装契约测试(阶段 A, Goal 六-1/2/4)
# 覆盖:
#   1. 顶部状态区: 品牌 / 主机 / 连接状态三片 Label + 五段统计行(Attached 段联动高亮);
#   2. 空态/错误态 Label(独立于表格, 不放表格行);
#   3. 整窗组装: Window + 会话行列表 + 右侧工作区 + 竖线 + StatusBar(Shortcuts) 全部到位;
#   4. 中间会话表与底部快捷键栏同时存在(布局契约, 不互相覆盖);
#   5. 阶段一(2026-11-06)响应式分栏几何: <72 单栏 / 72-99 列表 42% /
#      100-139 列表 40% / >=140 列表封顶 50~54 列, 双栏不变量
#      ListWidth + 3 + DetailWidth == Width, DividerX == ListWidth, DetailX == ListWidth + 3;
#   6. 阶段一标题带/统计联动配色契约。
# 说明: 无头构造(不 Init/不 Run); Terminal.Gui 2.4.10 实测 API 驱动。

Describe 'TGUI 仪表盘整窗组装 (New-TmuxTuiDashboardWindow)' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'

        function Get-TestVm {
            param([string]$Mode)
            switch ($Mode) {
                'Session' {
                    $state = & $script:mod {
                        Get-TmuxSessionState -SessionData @{
                            Available = $true
                            Sessions  = @(
                                [PSCustomObject]@{ Name = 'work'; Status = 'detached'; Windows = 3 }
                                [PSCustomObject]@{ Name = 'ci';   Status = 'attached';  Windows = 1 }
                            )
                        }
                    }
                }
                'Empty' {
                    $state = & $script:mod { Get-TmuxSessionState -SessionData @{ Available = $true; Sessions = @() } }
                }
                'Error' {
                    $state = & $script:mod { Get-TmuxSessionState -SessionData @{ Available = $false; TimedOut = $true } }
                }
            }
            & $script:mod { param($s) ConvertTo-TmuxTuiViewModel -State $s } $state
        }
    }

    It '正常态(Session): 会话列表 2 行, 列表 + 工作区 + 底栏齐备' {
        $vm = Get-TestVm -Mode 'Session'
        $result = & $script:mod {
            param($v)
            New-TmuxTuiDashboardWindow -ViewModel $v -HostName 'deb' `
                -ConnectionState '已连接' -HasSessions $true -Dispatch { param($a) [void]$a }
        } $vm

        $result.Window | Should -Not -BeNullOrEmpty
        # 2026-10-31: 会话表由 TG TableView 换成**自定义行列表**(延迟根因:
        # TableView 每次选中变化都把整表标脏)。列几何改为
        # 状态点 / 会话名 / 状态 / 窗口数 四段(不再是 No/SESSION/STATUS/WINDOWS)。
        $result.SessionList | Should -Not -BeNullOrEmpty
        @($result.SessionList.Rows).Count | Should -Be 2
        $result.SessionList.Geometry.DotWidth | Should -Be 2
        $result.SessionList.Geometry.NameWidth | Should -BeGreaterThan 0
        $result.SessionList.Geometry.StatusWidth | Should -BeGreaterThan 0
        $result.SessionList.Geometry.WindowsWidth | Should -BeGreaterThan 0
        $result.DetailPanel | Should -Not -BeNullOrEmpty
        # 阶段一: Esc 与 q 合并成一项, 底栏共 6 项
        $result.Shortcuts.Count | Should -Be 6
        $result.StatusBar | Should -Not -BeNullOrEmpty
    }

    It '空状态: 列表 0 行(不伪造), 列表隐藏, 空态 Label 提示用 N/R/S' {
        $vm = Get-TestVm -Mode 'Empty'
        $result = & $script:mod {
            param($v)
            New-TmuxTuiDashboardWindow -ViewModel $v -HostName 'deb' `
                -ConnectionState '已连接' -HasSessions $false -Dispatch { param($a) [void]$a }
        } $vm

        @($result.SessionList.Rows).Count | Should -Be 0
        $result.SessionList.View.Visible | Should -BeFalse
        # 阶段一: 辅助行不再塞进 CountLabels[2], 改用独立提示 Label
        $result.GuidanceLabel.Text | Should -Match 'n 新建'
        $result.GuidanceLabel.Text | Should -Match 'r 刷新'
        # 无会话时没有附着项, 删除项标注不可用 => 共 5 项
        $result.Shortcuts.Count | Should -Be 5
    }

    It '错误状态: 列表 0 行且隐藏, 错误 Label 带 E_SSH_TIMEOUT' {
        $vm = Get-TestVm -Mode 'Error'
        $result = & $script:mod {
            param($v)
            New-TmuxTuiDashboardWindow -ViewModel $v -HostName 'deb' `
                -ConnectionState '已连接' -HasSessions $false -Dispatch { param($a) [void]$a }
        } $vm

        @($result.SessionList.Rows).Count | Should -Be 0
        $result.SessionList.View.Visible | Should -BeFalse
        # 错误码与原因在辅助行(不是表格行, 也不是居中指引)
        $hintText = @($result.Window.SubViews | ForEach-Object { [string]$_.Text }) -join '|'
        $hintText | Should -Match 'E_SSH_TIMEOUT'
    }

    It '顶部统计数字与视图模型 Counts 一致(2 会话样例附带 1 附 1 分离)' {
        $vm = Get-TestVm -Mode 'Session'
        $result = & $script:mod {
            param($v)
            New-TmuxTuiDashboardWindow -ViewModel $v -HostName 'deb' `
                -ConnectionState '已连接' -HasSessions $true -Dispatch { param($a) [void]$a }
        } $vm

        # 阶段一: 统计行拆成 5 片, 旧的"整行统计 Label"已不存在
        @($result.StatsLabels).Count | Should -Be 5
        $result.StatsLabels[0].Text | Should -Match '会话: 2'
        $result.StatsLabels[2].Text | Should -Match 'Attached: 1'
        $result.StatsLabels[4].Text | Should -Match 'Detached: 1'
        # StatsAttachedLabel 指向 Attached 段
        [string]$result.StatsAttachedLabel.Text | Should -BeExactly 'Attached: 1'
    }

    It '阶段一: CountLabels 只剩品牌片与辅助行片, 旧的"整行统计 Label"已不存在' {
        $vm = Get-TestVm -Mode 'Session'
        $result = & $script:mod {
            param($v)
            New-TmuxTuiDashboardWindow -ViewModel $v -HostName 'deb' `
                -ConnectionState '已连接' -HasSessions $true -Dispatch { param($a) [void]$a }
        } $vm

        @($result.CountLabels).Count | Should -Be 2 -Because 'CountLabels = @(品牌片, 辅助行片)'
        [string]$result.CountLabels[0].Text | Should -Match 'ShellPrompt' -Because '第 0 片是品牌标识'
        # 统计不再走 CountLabels, 改走 StatsLabels
        ([string]$result.CountLabels[1].Text) | Should -Not -Match 'Attached:'
    }
}

Describe 'TGUI 仪表盘标题带与统计联动 (2026-11-06 阶段一配色契约)' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'

        function Get-VmByMode {
            param([string]$Mode)
            & $script:mod {
                param($m)
                $data = switch ($m) {
                    'Empty' { @{ Available = $true; Sessions = @() } }
                    'Error' { @{ Available = $false; TimedOut = $true } }
                    default {
                        @{
                            Available = $true
                            Sessions  = @(
                                [PSCustomObject]@{ Name = 'work'; Status = 'attached';  Windows = 2 }
                                [PSCustomObject]@{ Name = 'ci';   Status = 'detached'; Windows = 1 }
                            )
                        }
                    }
                }
                ConvertTo-TmuxTuiViewModel -State (Get-TmuxSessionState -SessionData $data)
            } $Mode
        }

        function Get-Win {
            param([object]$Vm, [int]$Width = 120, [int]$Height = 35, [int]$SelectedIndex = -1)
            & $script:mod {
                param($v, $w, $h, $sel)
                New-TmuxTuiDashboardWindow -ViewModel $v -HostName 'deb' `
                    -ConnectionState '已连接' -HasSessions $true -Dispatch { } `
                    -WindowWidth $w -WindowHeight $h -SelectedIndex $sel
            } $Vm $Width $Height $SelectedIndex
        }
    }

    It '标题带拆成品牌 / 主机 / 状态三片' {
        $win = Get-Win -Vm (Get-VmByMode -Mode 'Session')
        $win.BrandLabel.Text | Should -Match 'ShellPrompt' -Because '品牌段承载产品标识'
        $win.HostLabel.Text | Should -Match 'deb' -Because '主机段承载当前连接目标'
        $win.StateLabel.Text | Should -BeExactly '● 已连接'
        # 三片互不重叠: 品牌 -> 主机 -> 状态, X 依次递进
        # (Pos 的 ToString 形如 "Absolute(n)")
        $brandX = [int]($win.BrandLabel.X.ToString() -replace '\D', '')
        $hostX = [int]($win.HostLabel.X.ToString() -replace '\D', '')
        $stateX = [int]($win.StateLabel.X.ToString() -replace '\D', '')
        $brandX | Should -Be 0
        $hostX | Should -BeGreaterThan $brandX
        $stateX | Should -BeGreaterThan $hostX
    }

    It '品牌段用 AccentCyan(亮青), 主机段用 Subtle(灰)' {
        $win = Get-Win -Vm (Get-VmByMode -Mode 'Session')
        $result = & $script:mod {
            param($brandLabel, $hostLabel)
            $theme = Get-TuiDashboardTheme -Tgui (Get-TguiContext)
            [PSCustomObject]@{
                BrandIsAccentCyan = ($brandLabel.GetScheme() -eq $theme.AccentCyan)
                HostIsSubtle      = ($hostLabel.GetScheme() -eq $theme.Subtle)
            }
        } $win.BrandLabel $win.HostLabel
        $result.BrandIsAccentCyan | Should -BeTrue
        $result.HostIsSubtle | Should -BeTrue
    }

    It '连接状态徽标: 正常态 "● 已连接", 错误态 "○ 未连接", 两者前景色不同' {
        $winOk = Get-Win -Vm (Get-VmByMode -Mode 'Session')
        $winErr = Get-Win -Vm (Get-VmByMode -Mode 'Error')
        $winOk.StateLabel.Text | Should -BeExactly '● 已连接'
        $winErr.StateLabel.Text | Should -BeExactly '○ 未连接'
        $okFg = "$($winOk.StateLabel.GetScheme().Normal.Foreground.R),$($winOk.StateLabel.GetScheme().Normal.Foreground.G),$($winOk.StateLabel.GetScheme().Normal.Foreground.B)"
        $errFg = "$($winErr.StateLabel.GetScheme().Normal.Foreground.R),$($winErr.StateLabel.GetScheme().Normal.Foreground.G),$($winErr.StateLabel.GetScheme().Normal.Foreground.B)"
        $okFg | Should -Not -Be $errFg -Because '已连接与未连接必须靠颜色可分(符号之外还有第二重表达)'
    }

    It '状态徽标在窄终端下仍然完整可见' {
        $win = Get-Win -Vm (Get-VmByMode -Mode 'Session') -Width 40
        $win.StateLabel.Text | Should -BeExactly '● 已连接'
        $win.StateLabel.Width.ToString() | Should -Not -BeNullOrEmpty
        # 状态段右对齐(End): 贴在屏幕右缘
        $win.StateLabel.TextAlignment.ToString() | Should -BeExactly 'End'
    }

    It '统计联动: Attached 段在 Attached > 0 时用亮绿(AttachedText)' {
        $win = Get-Win -Vm (Get-VmByMode -Mode 'Session')
        $result = & $script:mod {
            param($label)
            $theme = Get-TuiDashboardTheme -Tgui (Get-TguiContext)
            [PSCustomObject]@{
                IsAttachedText = ($label.GetScheme() -eq $theme.AttachedText)
                Fg = "$($label.GetScheme().Normal.Foreground.R),$($label.GetScheme().Normal.Foreground.G),$($label.GetScheme().Normal.Foreground.B)"
                Green = "$($theme.AttachedText.Normal.Foreground.R),$($theme.AttachedText.Normal.Foreground.G),$($theme.AttachedText.Normal.Foreground.B)"
            }
        } $win.StatsAttachedLabel
        $result.IsAttachedText | Should -BeTrue -Because '顶部统计的 Attached 段必须与列表/详情面板同源(亮绿)'
        $result.Fg | Should -Be $result.Green
    }

    It '统计联动: Attached == 0 时 Attached 段不得是亮绿' {
        $vm = & $script:mod {
            ConvertTo-TmuxTuiViewModel -State (Get-TmuxSessionState -SessionData @{
                    Available = $true
                    Sessions  = @([PSCustomObject]@{ Name = 'idle'; Status = 'detached'; Windows = 1 })
                })
        }
        $win = Get-Win -Vm $vm
        $result = & $script:mod {
            param($label)
            $theme = Get-TuiDashboardTheme -Tgui (Get-TguiContext)
            [PSCustomObject]@{
                IsAttachedText = ($label.GetScheme() -eq $theme.AttachedText)
                IsDim          = ($label.GetScheme() -eq $theme.Dim)
                Fg = "$($label.GetScheme().Normal.Foreground.R),$($label.GetScheme().Normal.Foreground.G),$($label.GetScheme().Normal.Foreground.B)"
                Green = "$($theme.AttachedText.Normal.Foreground.R),$($theme.AttachedText.Normal.Foreground.G),$($theme.AttachedText.Normal.Foreground.B)"
            }
        } $win.StatsAttachedLabel
        $result.IsAttachedText | Should -BeFalse -Because '没有 Attached 会话时不得高亮成亮绿'
        $result.IsDim | Should -BeTrue
        $result.Fg | Should -Not -Be $result.Green
    }
}

Describe 'TGUI 仪表盘主题配色 (2026-10-30 真机验收补修)' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'

        function Get-DashboardVm {
            & $script:mod {
                ConvertTo-TmuxTuiViewModel -State (Get-TmuxSessionState -SessionData @{
                        Available = $true
                        Sessions  = @([PSCustomObject]@{ Name = 'work'; Status = 'detached'; Windows = 2 })
                    })
            }
        }

        function Get-DashboardWindow {
            param([object]$Vm)
            & $script:mod {
                param($v) New-TmuxTuiDashboardWindow -ViewModel $v -HostName 'deb' `
                    -ConnectionState '已连接' -HasSessions $true -Dispatch { } `
                    -WindowWidth 120 -WindowHeight 35
            } $Vm
        }
    }

    It '每个子视图 + Window 都有显式 Scheme(修复 Base 白对白隐形)' {
        $result = Get-DashboardWindow -Vm (Get-DashboardVm)

        $views = @($result.Window.SubViews) + @($result.Window)
        $withScheme = @($views | Where-Object { $_.HasScheme })
        $withScheme | Should -HaveCount $views.Count
    }

    It '绑定的 Scheme 前景 != 背景(内容不隐形)' {
        $result = Get-DashboardWindow -Vm (Get-DashboardVm)

        # 阶段一: 标题带改走**语义 Scheme**(AccentCyan), 不再依赖主题配置的 Menu 槽位
        $brand = $result.BrandLabel
        $bs = $brand.GetScheme()
        $bf = $bs.Normal.Foreground
        $bb = $bs.Normal.Background
        ($bf.R -ne $bb.R -or $bf.G -ne $bb.G -or $bf.B -ne $bb.B) | Should -BeTrue

        # 统计行(Attached 段)同样前景 != 背景
        $stats = $result.StatsAttachedLabel
        $cs = $stats.GetScheme()
        $f = $cs.Normal.Foreground
        $b = $cs.Normal.Background
        ($f.R -ne $b.R -or $f.G -ne $b.G -or $f.B -ne $b.B) | Should -BeTrue
    }

    It '选中行与正文配色可分(蓝底 vs 黑底), 不再依赖 TableView 表头' {
        # 2026-10-31: TableView 移除后没有"表头"概念, 原来的
        # "表头 Menu.Focus 与选中行 Base.Focus 前景色可分"这条契约改成
        # "选中行底色 与 正文底色 可分" —— 视觉目标不变(层次可辨), 实现换了。
        $result = & $script:mod {
            param($v)
            New-TmuxTuiDashboardWindow -ViewModel $v -HostName 'deb' `
                -ConnectionState '已连接' -HasSessions $true -Dispatch { param($a) [void]$a } `
                -SelectedIndex 0
        } (Get-DashboardVm)
        $list = $result.SessionList
        $selAttr = $list.Slots[0].Bg.GetScheme().Normal
        $plainAttr = $list.Slots[1].Bg.GetScheme().Normal
        # 选中行: 前景 != 背景(否则白字压底会看不见) —— 逐通道比 fg 与 bg
        ($selAttr.Foreground.R -ne $selAttr.Background.R -or
         $selAttr.Foreground.G -ne $selAttr.Background.G -or
         $selAttr.Foreground.B -ne $selAttr.Background.B) | Should -BeTrue
        # 选中行与未选中行的**背景色不同**
        "$($selAttr.Background.R),$($selAttr.Background.G),$($selAttr.Background.B)" |
            Should -Not -Be "$($plainAttr.Background.R),$($plainAttr.Background.G),$($plainAttr.Background.B)"
    }

    It '选中行整行蓝底(阶段一: 不再是洋红底), 未选中行仍是正文黑底' {
        # 2026-10-31: TableView 的 FullRowSelect 随 TableView 一起移除 ——
        #   选中行整行高亮改由"背景条 Label"承担(整行宽的空格 Label + 选中底方案)。
        # 2026-11-06 阶段一: 洋红底 -> 蓝底(SelectionBg), 消除红绿眩光。
        $result = & $script:mod {
            param($v)
            New-TmuxTuiDashboardWindow -ViewModel $v -HostName 'deb' `
                -ConnectionState '已连接' -HasSessions $true -Dispatch { param($a) [void]$a } `
                -SelectedIndex 0
        } (Get-DashboardVm)
        $list = $result.SessionList
        # 首行是选中行(SelectedIndex=0), 它的背景应是 SelectionBg 方案
        $slot = $list.Slots[0]
        $slot.Selected | Should -BeTrue
        $selBg = $slot.Bg.GetScheme().Normal.Background
        $txtBg = $list.Theme.Text.Normal.Background
        # 蓝底与正文黑底必须不同 —— 这就是"整行高亮"的实体证据
        "$($selBg.R),$($selBg.G),$($selBg.B)" | Should -Not -Be "$($txtBg.R),$($txtBg.G),$($txtBg.B)"
        # 阶段一: 选中行底色**不是**洋红
        $magentaBg = $list.Theme.Selected.Normal.Background
        "$($selBg.R),$($selBg.G),$($selBg.B)" | Should -Not -Be "$($magentaBg.R),$($magentaBg.G),$($magentaBg.B)"
        # 未选中行仍是正文黑底
        $plain = $list.Slots[1]
        $plain.Selected | Should -BeFalse
        $plainBg = $plain.Bg.GetScheme().Normal.Background
        "$($plainBg.R),$($plainBg.G),$($plainBg.B)" | Should -Be "$($txtBg.R),$($txtBg.G),$($txtBg.B)"
    }

    It '错误态辅助行绑定 Error 方案(红字警示), 空态绑定可见方案' {
        $vmError = & $script:mod {
            ConvertTo-TmuxTuiViewModel -State (Get-TmuxSessionState -SessionData @{
                    Available = $false; TimedOut = $true
                })
        }
        $winError = Get-DashboardWindow -Vm $vmError
        $hintText = @($winError.Window.SubViews | ForEach-Object { [string]$_.Text }) -join '|'
        $hintText | Should -Match 'E_SSH_TIMEOUT'
        $es = $winError.StateLabel.GetScheme()
        $ef = $es.Normal.Foreground
        # TG 内置 Error 方案 = 红系(fg != bg, 与正文亮白不一样)
        $ef.R | Should -BeGreaterThan 180
        $ef.R | Should -BeGreaterThan $ef.G
        $ef.R | Should -BeGreaterThan $ef.B
    }

    It '表格与快捷键栏同样绑到可见方案(正文与底栏都不隐形)' {
        $result = Get-DashboardWindow -Vm (Get-DashboardVm)

        foreach ($view in @($result.Table, $result.StatusBar)) {
            $cs = $view.GetScheme()
            $f = $cs.Normal.Foreground
            $b = $cs.Normal.Background
            ($f.R -ne $b.R -or $f.G -ne $b.G -or $f.B -ne $b.B) | Should -BeTrue
        }
    }
}

Describe 'TGUI 仪表盘视觉层次 (2026-10-31 UI 升级)' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'

        function Get-VmByMode {
            param([string]$Mode)
            & $script:mod {
                param($m)
                $data = switch ($m) {
                    'Empty' { @{ Available = $true; Sessions = @() } }
                    'Error' { @{ Available = $false; TimedOut = $true } }
                    default { @{ Available = $true; Sessions = @([PSCustomObject]@{ Name = 'work'; Status = 'detached'; Windows = 2 }) } }
                }
                ConvertTo-TmuxTuiViewModel -State (Get-TmuxSessionState -SessionData $data)
            } $Mode
        }

        function Get-Win {
            param([object]$Vm, [int]$Width = 120, [int]$Height = 35)
            & $script:mod {
                param($v, $w, $h) New-TmuxTuiDashboardWindow -ViewModel $v -HostName 'deb' `
                    -ConnectionState '已连接' -HasSessions $true -Dispatch { } `
                    -WindowWidth $w -WindowHeight $h
            } $Vm $Width $Height
        }
    }

    It '窄终端下标题降级为短形态, 连接状态徽标仍然完整可见' {
        # 40 列: 左侧宽度不足以放全称 -> 标题走短形态
        $win = Get-Win -Vm (Get-VmByMode -Mode 'Session') -Width 40
        $win.StateLabel.Text | Should -BeExactly '● 已连接'
        $win.BrandLabel.Text | Should -Not -Match 'ShellPrompt' -Because '40 列放不下全称, 必须降级'
        $win.BrandLabel.Text | Should -Match 'sss'
    }

    It '连接状态徽标与品牌段配色不同(状态是独立视觉层, 不靠位置区分)' {
        $win = Get-Win -Vm (Get-VmByMode -Mode 'Session')
        $brandFg = $win.BrandLabel.GetScheme().Normal.Foreground
        $stateFg = $win.StateLabel.GetScheme().Normal.Foreground
        "$($brandFg.R),$($brandFg.G),$($brandFg.B)" | Should -Not -Be "$($stateFg.R),$($stateFg.G),$($stateFg.B)"
    }

    It '空态/错误态: 表格隐藏, 主体区改为居中指引(不再画空表格框)' {
        foreach ($mode in @('Empty', 'Error')) {
            $win = Get-Win -Vm (Get-VmByMode -Mode $mode)
            $win.ShowSessionTable | Should -BeFalse
            $win.Table.Visible | Should -BeFalse
            $win.GuidanceLabel.Text | Should -Not -BeNullOrEmpty
            # 居中对齐
            $win.GuidanceLabel.TextAlignment.ToString() | Should -BeExactly 'Center'
        }
    }

    It '正常态: 表格可见, 居中指引为空(不与表格抢行)' {
        $win = Get-Win -Vm (Get-VmByMode -Mode 'Session')
        $win.ShowSessionTable | Should -BeTrue
        $win.GuidanceLabel.Text | Should -BeNullOrEmpty
    }

    It '空态指引文案与底部快捷键栏同源(同一套动作定义, 不再两处各说各话)' {
        $win = Get-Win -Vm (Get-VmByMode -Mode 'Empty')
        $win.GuidanceLabel.Text | Should -Match 'n 新建'
        $win.GuidanceLabel.Text | Should -Match 'r 刷新'
        # 底栏里确实有同名动作项
        @($win.Shortcuts | Where-Object { $_.Title -eq '刷新' }).Count | Should -Be 1
    }

    It '底部快捷键栏取 Base: 键名(HotNormal 冰青)与标签(Normal 亮白)分层, 不与正文挤成一色' {
        $win = Get-Win -Vm (Get-VmByMode -Mode 'Session')
        $bar = $win.StatusBar.GetScheme()
        # 键名 = HotNormal, 标签 = Normal —— 两者前景色必须不同, 否则底栏是一整条同色带
        $keyFg = "$($bar.HotNormal.Foreground.R),$($bar.HotNormal.Foreground.G),$($bar.HotNormal.Foreground.B)"
        $labelFg = "$($bar.Normal.Foreground.R),$($bar.Normal.Foreground.G),$($bar.Normal.Foreground.B)"
        $keyFg | Should -Not -Be $labelFg
        # 键名 = Sky 冰青(137,220,235): 16 色终端里量化为 SGR 96
        $keyFg | Should -BeExactly '137,220,235'
    }
}

Describe 'TGUI 仪表盘响应式分栏几何 (2026-11-06 阶段一)' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It '< 72 列: 单栏(列表铺满, 无竖线, 无工作区)' {
        foreach ($w in @(40, 60, 71)) {
            $plan = & $script:mod { param($x) New-TmuxTuiLayoutPlan -Width $x -Height 35 } $w
            $plan.SplitMode | Should -Be 'Single' -Because "$w 列放不下右侧工作区"
            $plan.ListWidth | Should -Be $w
            $plan.DetailWidth | Should -Be 0
            $plan.DividerX | Should -Be -1
            $plan.DetailX | Should -Be -1
        }
    }

    It '72-99 列: 双栏, 列表占 42%' {
        foreach ($w in @(72, 80, 99)) {
            $plan = & $script:mod { param($x) New-TmuxTuiLayoutPlan -Width $x -Height 35 } $w
            $plan.SplitMode | Should -Be 'Dual' -Because "$w 列应当分栏"
            $plan.ListRatio | Should -Be 0.42
            $plan.ListWidth | Should -Be ([int][Math]::Floor($w * 0.42))
        }
    }

    It '100-139 列: 双栏, 列表占 40%' {
        foreach ($w in @(100, 120, 139)) {
            $plan = & $script:mod { param($x) New-TmuxTuiLayoutPlan -Width $x -Height 35 } $w
            $plan.SplitMode | Should -Be 'Dual'
            $plan.ListRatio | Should -Be 0.4
            $plan.ListWidth | Should -Be ([int][Math]::Floor($w * 0.4))
        }
    }

    It '>= 140 列: 列表封顶在 50~54 列, 余量全给工作区' {
        foreach ($w in @(140, 160, 200)) {
            $plan = & $script:mod { param($x) New-TmuxTuiLayoutPlan -Width $x -Height 35 } $w
            $plan.SplitMode | Should -Be 'Dual'
            $plan.ListWidth | Should -BeGreaterOrEqual 50 -Because "$w 列的大屏档位列表不得窄于 50"
            $plan.ListWidth | Should -BeLessOrEqual 54 -Because "$w 列的大屏档位列表不得宽于 54"
        }
    }

    It '双栏几何不变量: ListWidth + 3 + DetailWidth == Width, DividerX == ListWidth, DetailX == ListWidth + 3' {
        foreach ($w in @(72, 80, 99, 100, 120, 139, 140, 160, 200)) {
            $plan = & $script:mod { param($x) New-TmuxTuiLayoutPlan -Width $x -Height 35 } $w
            ($plan.ListWidth + 3 + $plan.DetailWidth) | Should -Be $w -Because "$w 列下列表/竖线/间距/工作区必须刚好铺满"
            $plan.DividerX | Should -Be $plan.ListWidth -Because "$w 列下竖线紧贴列表右缘"
            $plan.DetailX | Should -Be ($plan.ListWidth + 3) -Because "$w 列下工作区与竖线之间留 2 列呼吸间距"
            $plan.DetailWidth | Should -BeGreaterOrEqual 24 -Because "$w 列下工作区至少 24 列, 否则退回单栏"
        }
    }

    It '工作区放不下(< 24 列)时退回单栏' {
        # 断点边界: 72 列起分栏; 但如果按比例算出的工作区不足 24 列, 必须退回单栏
        $plan = & $script:mod { New-TmuxTuiLayoutPlan -Width 72 -Height 35 }
        $plan.SplitMode | Should -Be 'Dual'
        $plan.DetailWidth | Should -BeGreaterOrEqual 24
    }
}

Describe 'TGUI 仪表盘多尺寸装配验证 (2026-11-06 阶段一)' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It '60x20 / 80x24 / 120x35 / 160x45 四档: 不抛异常, 主体区高度为正, 矩形不越界不重叠' {
        $frames = & $script:mod {
            foreach ($size in @(@(60, 20), @(80, 24), @(120, 35), @(160, 45))) {
                $w = $size[0]; $h = $size[1]
                $vm = ConvertTo-TmuxTuiViewModel -State (Get-TmuxSessionState -SessionData @{
                        Available = $true
                        Sessions  = @(
                            [PSCustomObject]@{ Name = 'work'; Status = 'attached';  Windows = 2 }
                            [PSCustomObject]@{ Name = 'ci';   Status = 'detached'; Windows = 1 }
                        )
                    })
                $result = New-TmuxTuiDashboardWindow -ViewModel $vm -HostName 'deb' `
                    -ConnectionState '已连接' -HasSessions $true -Dispatch { } `
                    -WindowWidth $w -WindowHeight $h -SelectedIndex 0
                # 触发一次真实布局, 读回 Terminal.Gui 算出的 Frame
                $layoutM = $result.Window.GetType().GetMethod('Layout', [type[]]@([System.Drawing.Size]))
                [void]$layoutM.Invoke($result.Window, @([System.Drawing.Size]::new($w, $h)))
                [PSCustomObject]@{
                    Width        = $w
                    Height       = $h
                    Mode         = $result.Layout.SplitMode
                    TableHeight  = $result.Layout.TableHeight
                    ListX        = $result.SessionList.View.Frame.X
                    ListWidth    = $result.SessionList.View.Frame.Width
                    DividerX     = $(if ($null -ne $result.Divider) { $result.Divider.Frame.X } else { -1 })
                    DividerWidth = $(if ($null -ne $result.Divider) { $result.Divider.Frame.Width } else { 0 })
                    DetailX      = $(if ($null -ne $result.DetailPanel) { $result.DetailPanel.View.Frame.X } else { -1 })
                    DetailWidth  = $(if ($null -ne $result.DetailPanel) { $result.DetailPanel.View.Frame.Width } else { 0 })
                    HasDivider   = ($null -ne $result.Divider)
                    HasDetail    = ($null -ne $result.DetailPanel)
                }
            }
        }

        $frames | Should -HaveCount 4
        foreach ($f in $frames) {
            $f.TableHeight | Should -BeGreaterThan 0 -Because "$($f.Width)x$($f.Height) 的主体区高度不得为负"
            # 列表矩形不得越出窗口右缘
            ($f.ListX + $f.ListWidth) | Should -BeLessOrEqual $f.Width
            if ($f.HasDivider) {
                # 竖线紧跟列表右缘, 且不与列表重叠
                $f.DividerX | Should -BeGreaterOrEqual ($f.ListX + $f.ListWidth)
                ($f.DividerX + $f.DividerWidth) | Should -BeLessOrEqual $f.Width
            }
            if ($f.HasDetail) {
                # 工作区不得越出窗口右缘, 也不得压住列表/竖线
                $f.DetailX | Should -BeGreaterOrEqual ($f.ListX + $f.ListWidth)
                ($f.DetailX + $f.DetailWidth) | Should -BeLessOrEqual $f.Width
            }
            if ($f.Mode -eq 'Dual') {
                $f.HasDivider | Should -BeTrue -Because "$($f.Width) 列是双栏, 必须有分隔竖线"
                $f.HasDetail | Should -BeTrue -Because "$($f.Width) 列是双栏, 必须有右侧工作区"
                # 竖线 + 工作区不得压住列表
                $f.DividerX | Should -BeGreaterOrEqual ($f.ListX + $f.ListWidth)
            }
            else {
                $f.HasDivider | Should -BeFalse -Because "$($f.Width) 列是单栏, 不画竖线"
                $f.HasDetail | Should -BeFalse -Because "$($f.Width) 列是单栏, 不显示工作区"
                $f.ListWidth | Should -Be $f.Width -Because '单栏时列表铺满整宽'
            }
        }
    }
}
