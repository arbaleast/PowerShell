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

        $label = @($result.Window.SubViews | Select-Object -First 1)
        $cs = $label[0].GetScheme()
        $f = $cs.Normal.Foreground
        $b = $cs.Normal.Background
        ($f.R -ne $b.R -or $f.G -ne $b.G -or $f.B -ne $b.B) | Should -BeTrue

        # 与配置的主题槽位同源(不是 TG 内置的白对白)
        $expected = & $script:mod { $script:Config.UI.Theme.Slots.Normal }
        "$($f.R),$($f.G),$($f.B)" | Should -Be $expected.Fg
        "$($b.R),$($b.G),$($b.B)" | Should -Be $expected.Bg
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
