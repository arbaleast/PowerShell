# New-TmuxTuiDashboardWindow.Tests.ps1 - TGUI 整窗组装契约测试(阶段 A, Goal 六-1/2/4)
# 覆盖:
#   1. 顶部状态区: 标题/统计 Label(含主机名/附/分离计数);
#   2. 空态/错误态 Label(独立于表格, 不放表格行);
#   3. 整窗组装: Window + 表格(Source 列/行) + StatusBar(Shortcuts) 全部到位;
#   4. 中间会话表与底部快捷键栏同时存在(布局契约, 不互相覆盖)。
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

    It '正常态(Session): 表格 2 行 4 列可见, 底栏 7 项快捷键' {
        $vm = Get-TestVm -Mode 'Session'
        $result = & $script:mod {
            param($v)
            New-TmuxTuiDashboardWindow -ViewModel $v -HostName 'deb' `
                -ConnectionState '已连接' -HasSessions $true -Dispatch { param($a) [void]$a }
        } $vm

        $result.Window | Should -Not -BeNullOrEmpty
        $result.Table | Should -Not -BeNullOrEmpty
        $result.Source.Columns | Should -Be 4
        $result.Source.Rows | Should -Be 2
        $result.Shortcuts.Count | Should -Be 7
        $result.StatusBar | Should -Not -BeNullOrEmpty
    }

    It '空状态: 表格 0 行(不伪造), 空态 Label 提示用 N/R/S' {
        $vm = Get-TestVm -Mode 'Empty'
        $result = & $script:mod {
            param($v)
            New-TmuxTuiDashboardWindow -ViewModel $v -HostName 'deb' `
                -ConnectionState '已连接' -HasSessions $false -Dispatch { param($a) [void]$a }
        } $vm

        $result.Source.Rows | Should -Be 0
        $result.CountLabels[2].Text | Should -Match '没有 tmux 会话'
        $result.Shortcuts.Count | Should -Be 6
    }

    It '错误状态: 表格 0 行, 错误 Label 带 E_SSH_TIMEOUT' {
        $vm = Get-TestVm -Mode 'Error'
        $result = & $script:mod {
            param($v)
            New-TmuxTuiDashboardWindow -ViewModel $v -HostName 'deb' `
                -ConnectionState '已连接' -HasSessions $false -Dispatch { param($a) [void]$a }
        } $vm

        $result.Source.Rows | Should -Be 0
        $result.CountLabels[2].Text | Should -Match 'E_SSH_TIMEOUT'
    }

    It '顶部统计数字与视图模型 Counts 一致(3 会话样例附带 1 附 2 分离)' {
        $vm = Get-TestVm -Mode 'Session'
        $result = & $script:mod {
            param($v)
            New-TmuxTuiDashboardWindow -ViewModel $v -HostName 'deb' `
                -ConnectionState '已连接' -HasSessions $true -Dispatch { param($a) [void]$a }
        } $vm

        $result.CountLabels[1].Text | Should -Match '会话: 2'
        $result.CountLabels[1].Text | Should -Match 'Attached: 1'
        $result.CountLabels[1].Text | Should -Match 'Detached: 1'
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

    It '绑定的 Scheme 前景 != 背景(内容不隐形), 且与 UI.Theme 同源' {
        $result = Get-DashboardWindow -Vm (Get-DashboardVm)

        # 标题行 = Menu 边缘带(2026-10-31 层次升级: 取 SchemeOverrides['Menu'].Normal)
        $title = @($result.Window.SubViews | Select-Object -First 1)[0]
        $ts = $title.GetScheme()
        $tf = $ts.Normal.Foreground
        $tb = $ts.Normal.Background
        ($tf.R -ne $tb.R -or $tf.G -ne $tb.G -or $tf.B -ne $tb.B) | Should -BeTrue
        $menuExpected = & $script:mod { $script:Config.UI.Theme.SchemeOverrides['Menu'].Normal }
        "$($tf.R),$($tf.G),$($tf.B)" | Should -Be $menuExpected.Fg
        "$($tb.R),$($tb.G),$($tb.B)" | Should -Be $menuExpected.Bg

        # 统计行(正文) = Base 主题槽位
        $stats = $result.CountLabels[1]
        $cs = $stats.GetScheme()
        $f = $cs.Normal.Foreground
        $b = $cs.Normal.Background
        ($f.R -ne $b.R -or $f.G -ne $b.G -or $f.B -ne $b.B) | Should -BeTrue

        # 与配置的主题槽位同源(不是 TG 内置的白对白)
        $expected = & $script:mod { $script:Config.UI.Theme.Slots.Normal }
        "$($f.R),$($f.G),$($f.B)" | Should -Be $expected.Fg
        "$($b.R),$($b.G),$($b.B)" | Should -Be $expected.Bg
    }

    It '表头 HeaderScheme = Menu 边缘带(与选中行的 Focus 色区分)' {
        $result = Get-DashboardWindow -Vm (Get-DashboardVm)

        $header = $result.Table.Style.HeaderScheme
        $header | Should -Not -BeNullOrEmpty
        $hf = $header.Normal.Foreground
        $hb = $header.Normal.Background
        $menuExpected = & $script:mod { $script:Config.UI.Theme.SchemeOverrides['Menu'].Normal }
        "$($hf.R),$($hf.G),$($hf.B)" | Should -Be $menuExpected.Fg
        "$($hb.R),$($hb.G),$($hb.B)" | Should -Be $menuExpected.Bg
    }

    It '表格 FullRowSelect = $true(选中行整行高亮)' {
        $result = Get-DashboardWindow -Vm (Get-DashboardVm)
        $result.Table.FullRowSelect | Should -BeTrue
    }

    It '错误态辅助行绑定 Error 方案(红字警示), 空态绑定 Menu 边缘带' {
        $vmError = & $script:mod {
            ConvertTo-TmuxTuiViewModel -State (Get-TmuxSessionState -SessionData @{
                    Available = $false; TimedOut = $true
                })
        }
        $winError = Get-DashboardWindow -Vm $vmError
        $hint = $winError.CountLabels[2]
        $es = $hint.GetScheme()
        $ef = $es.Normal.Foreground
        # TG 内置 Error 方案 = 红系(fg != bg, 与正文亮白不一样)
        $ef.R | Should -BeGreaterThan 180
        $ef.R | Should -BeGreaterThan $ef.G
        $ef.R | Should -BeGreaterThan $ef.B

        $vmEmpty = & $script:mod {
            ConvertTo-TmuxTuiViewModel -State (Get-TmuxSessionState -SessionData @{ Available = $true; Sessions = @() })
        }
        $winEmpty = Get-DashboardWindow -Vm $vmEmpty
        $hintEmpty = $winEmpty.CountLabels[2]
        $ms = $hintEmpty.GetScheme()
        $mf = $ms.Normal.Foreground
        $menuExpected = & $script:mod { $script:Config.UI.Theme.SchemeOverrides['Menu'].Normal }
        "$($mf.R),$($mf.G),$($mf.B)" | Should -Be $menuExpected.Fg
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

    It '标题带拆成左右两片且不重叠: 左=产品标识+主机, 右=连接状态徽标' {
        $win = Get-Win -Vm (Get-VmByMode -Mode 'Session')
        $title = $win.CountLabels[0]
        $state = $win.StateLabel

        $title.Text | Should -Match 'ShellPrompt TMUX Manager'
        $title.Text | Should -Match '主机 deb'
        $state.Text | Should -BeExactly '已连接'
        # 两片的 X/Width 由状态文案宽反推, 右侧状态不与左侧标题重叠
        # (Pos/Dim 是 TG 的强类型, 用 ToString 比对 "Absolute(n)" 字面量)
        $title.X.ToString() | Should -BeExactly 'Absolute(0)'
        $title.Width.ToString() | Should -BeExactly 'Absolute(112)'
        $state.X.ToString() | Should -BeExactly 'Absolute(112)'
        $state.Width.ToString() | Should -BeExactly 'Absolute(8)'
        # 状态徽标右对齐(End): 贴在屏幕右缘
        $state.TextAlignment.ToString() | Should -BeExactly 'End'
    }

    It '窄终端下标题降级为短形态, 连接状态徽标仍然完整可见' {
        # 40 列: 状态宽 8, 左侧只剩 32 列 -> 标题走"sss tmux · 主机 deb"形态
        $win = Get-Win -Vm (Get-VmByMode -Mode 'Session') -Width 40
        $win.StateLabel.Text | Should -BeExactly '已连接'
        $win.StateLabel.X.ToString() | Should -BeExactly 'Absolute(32)'
        $win.StateLabel.Width.ToString() | Should -BeExactly 'Absolute(8)'
        $win.CountLabels[0].Text | Should -Match 'sss'
        $win.CountLabels[0].Text | Should -Not -Match 'ShellPrompt TMUX Manager'
    }

    It '连接状态徽标与标题配色不同(状态是独立视觉层, 不靠位置区分)' {
        $win = Get-Win -Vm (Get-VmByMode -Mode 'Session')
        $titleFg = $win.CountLabels[0].GetScheme().Normal.Foreground
        $stateFg = $win.StateLabel.GetScheme().Normal.Foreground
        "$($titleFg.R),$($titleFg.G),$($titleFg.B)" | Should -Not -Be "$($stateFg.R),$($stateFg.G),$($stateFg.B)"
        # 状态徽标 = Dialog 方案(绿字)
        $dialogExpected = & $script:mod { $script:Config.UI.Theme.SchemeOverrides['Dialog'].Normal }
        "$($stateFg.R),$($stateFg.G),$($stateFg.B)" | Should -Be $dialogExpected.Fg
    }

    It '错误态: 状态徽标改文案为"连接失败"并绑 Error(红)方案' {
        $win = Get-Win -Vm (Get-VmByMode -Mode 'Error')
        $win.StateLabel.Text | Should -BeExactly '连接失败'
        $fg = $win.StateLabel.GetScheme().Normal.Foreground
        $fg.R | Should -BeGreaterThan 180
        $fg.R | Should -BeGreaterThan $fg.G
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

    It '表头与选中行配色不同(表头不再与选中行同色)' {
        $win = Get-Win -Vm (Get-VmByMode -Mode 'Session')
        $header = $win.Table.Style.HeaderScheme
        $headerFg = $header.Normal.Foreground
        # 选中行走 Base.Focus(白字); 表头走 Menu.Focus(Sky 冰青字)
        $baseFocus = & $script:mod {
            $tg = Get-TguiContext
            $scheme = $tg.Types.SchemeManager.GetMethod('GetScheme', [type[]]@([string])).Invoke($null, @('Base'))
            "$($scheme.Focus.Foreground.R),$($scheme.Focus.Foreground.G),$($scheme.Focus.Foreground.B)"
        }
        "$($headerFg.R),$($headerFg.G),$($headerFg.B)" | Should -Not -Be $baseFocus
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
