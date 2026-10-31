<#
.SYNOPSIS
    Terminal.Gui v2 主机选择器的 Pester 测试(视图组装层 + 非交互护栏)

.DESCRIPTION
    2026-10-30 PSTui 移除: 主机选择器改由 ALC 原生 Terminal.Gui v2 承接。
    覆盖:
      - New-TguiHostSelectorWindow 整窗组装(无头可测, 不进事件循环)
      - Invoke-TguiHostSelector 非交互护栏(重定向环境必须直接返回 $null,
        不允许进入阻塞的 TUI 循环)
      - Get-HostSelectorRow 行构造契约(经 Show-HostSelector 使用)
    交互循环(Enter/Esc/过滤重建/缩放)依赖真实 TTY 事件注入, 由真机验收承担;
    本文件不模拟(仓库纪律: 未验证的交互不声称通过)。
#>

Describe 'New-TguiHostSelectorWindow (TGUI 主机选择器整窗组装)' {

    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..\ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module ShellPrompt
    }

    It '应组装出 Window + TableView + TextField + StatusBar(无头)' {
        $win = & $script:mod {
            $rows = Get-HostSelectorRow -Hosts @('debian', 'ubuntu') -LastHost 'ubuntu'
            New-TguiHostSelectorWindow -Title 'SSH 主机选择器 (2)' -Rows $rows -Dispatch { param($a) [void]$a }
        }
        $win | Should -Not -BeNullOrEmpty
        $win.Window.GetType().FullName | Should -Be 'Terminal.Gui.Views.Window'
        $win.Table.GetType().FullName | Should -Be 'Terminal.Gui.Views.TableView'
        $win.FilterField.GetType().FullName | Should -Be 'Terminal.Gui.Views.TextField'
        $null -ne $win.StatusBar | Should -Be $true
    }

    It '行数据应进入表格数据源(HOST / STATE 两列)' {
        $win = & $script:mod {
            $rows = Get-HostSelectorRow -Hosts @('debian', 'ubuntu', 'arch') -LastHost 'ubuntu'
            $w = New-TguiHostSelectorWindow -Title 'T' -Rows $rows -Dispatch { param($a) [void]$a }
            [PSCustomObject]@{
                Columns  = $w.Source.Columns
                RowCount = $rows.Count
            }
        }
        # EnumerableTableSource.Columns 在 2.4.10 是 [int](列数, 探针 p25 实测)
        $win.Columns | Should -Be 2
        $win.RowCount | Should -Be 3
    }

    It '过滤文本应回填 TextField(跨重建保持)' {
        $win = & $script:mod {
            $rows = Get-HostSelectorRow -Hosts @('debian', 'ubuntu')
            New-TguiHostSelectorWindow -Title 'T' -Rows $rows -Filter 'deb' -Dispatch { param($a) [void]$a }
        }
        [string]$win.FilterField.Text | Should -Be 'deb'
    }

    It 'SelectedIndex 应预选指定行' {
        $win = & $script:mod {
            $rows = Get-HostSelectorRow -Hosts @('debian', 'ubuntu', 'arch') -LastHost 'ubuntu'
            $w = New-TguiHostSelectorWindow -Title 'T' -Rows $rows -SelectedIndex 2 -Dispatch { param($a) [void]$a }
            [PSCustomObject]@{
                SelectedY = $w.Table.Value.SelectedCell.Y
                RowCount  = $rows.Count
            }
        }
        $win.SelectedY | Should -Be 2
    }

    It '空过滤结果(空行集合)应仍可组装(空表不崩)' {
        $win = & $script:mod {
            New-TguiHostSelectorWindow -Title 'T' -Rows @() -Dispatch { param($a) [void]$a }
        }
        $win | Should -Not -BeNullOrEmpty
        $win.Table | Should -Not -BeNullOrEmpty
    }

    It 'ShouldProcess 否定时应返回 $null(组装必须显式确认)' {
        $win = & $script:mod {
            $rows = Get-HostSelectorRow -Hosts @('debian')
            New-TguiHostSelectorWindow -Title 'T' -Rows $rows -Dispatch { param($a) [void]$a } -WhatIf
        }
        $win | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-TguiHostSelector (非交互护栏)' {

    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..\ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module ShellPrompt
    }

    It '重定向环境下必须直接返回 $null 且不阻塞' {
        # Pester 运行时 stdin/stdout 均被重定向 —— 探针实测:
        # 该环境下 TG Init 成功但 Run 事件循环永久阻塞, 因此必须提前护栏。
        $rows = & $script:mod { Get-HostSelectorRow -Hosts @('debian', 'ubuntu') }
        $result = & $script:mod { param($r) Invoke-TguiHostSelector -Rows $r } $rows
        $result | Should -BeNullOrEmpty
    }

    It '空行集合应直接返回 $null(不触碰 TGUI)' {
        $result = & $script:mod { Invoke-TguiHostSelector -Rows @() }
        $result | Should -BeNullOrEmpty
    }
}

Describe 'Show-HostSelector (分发器业务装配)' {

    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..\ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module ShellPrompt
    }

    It '空主机列表应告警并返回 $null(不入交互循环)' {
        Mock -CommandName Assert-ConsoleUiReady -ModuleName ShellPrompt -MockWith { }
        Mock -CommandName Write-Warning -ModuleName ShellPrompt -MockWith { }
        $result = & $script:mod { Show-HostSelector -Hosts @() }
        $result | Should -BeNullOrEmpty
        Should -Invoke -CommandName Write-Warning -ModuleName ShellPrompt -Exactly 1
    }

    It '非交互环境下应先被可用性断言拦下(可定位的终止错误)' {
        # 重定向环境下 Get-ConsoleUiState 判定 Available=false,
        # Assert-ConsoleUiReady 在触碰 TGUI 之前抛出。
        $threw = $false
        try {
            & $script:mod { Show-HostSelector -Hosts @('debian') } | Out-Null
        } catch {
            $threw = $true
        }
        $threw | Should -Be $true
    }

    It '仪表盘返回 $null(用户取消)时分发器透传 $null' {
        & $script:mod {
            Mock -CommandName Assert-ConsoleUiReady -ModuleName ShellPrompt -MockWith { }
            Mock -CommandName Get-WttrTitleSuffix -ModuleName ShellPrompt -MockWith { '' }
            Mock -CommandName Show-SshHostDashboard -ModuleName ShellPrompt -MockWith { $null }
            Show-HostSelector -Hosts @('debian', 'ubuntu') -ExitLabel '退出'
        } | Should -BeNullOrEmpty
        Should -Invoke -CommandName Show-SshHostDashboard -ModuleName ShellPrompt -Exactly 1
    }

    It '仪表盘返回选中行时分发器透传该行(.Value = 主机名)' {
        $selected = & $script:mod {
            Mock -CommandName Assert-ConsoleUiReady -ModuleName ShellPrompt -MockWith { }
            Mock -CommandName Get-WttrTitleSuffix -ModuleName ShellPrompt -MockWith { '' }
            Mock -CommandName Show-SshHostDashboard -ModuleName ShellPrompt -MockWith {
                # 形参捕获避免"声明即弃用"; 调用形参形状同时被本断言锁定
                $script:selectorSeenHosts = $Hosts
                $script:selectorSeenLastHost = $LastHost
                [PSCustomObject]@{ Host = 'debian'; State = ''; Disabled = $false; Value = 'debian' }
            }
            Show-HostSelector -Hosts @('debian', 'ubuntu') -LastHost 'debian' -ExitLabel '退出'
        }
        $selected | Should -Not -BeNullOrEmpty
        $selected.Value | Should -Be 'debian'
        & $script:mod { $script:selectorSeenHosts.Count } | Should -Be 2
        & $script:mod { $script:selectorSeenHosts[0] } | Should -Be 'debian'
        & $script:mod { $script:selectorSeenLastHost } | Should -Be 'debian'
    }

    It 'LastHost 为空时应从配置回退 $script:Config.SSH.LastHost' {
        $selected = & $script:mod {
            $original = $script:Config.SSH.LastHost
            try {
                $script:Config.SSH.LastHost = 'ubuntu'
                Mock -CommandName Assert-ConsoleUiReady -ModuleName ShellPrompt -MockWith { }
                Mock -CommandName Get-WttrTitleSuffix -ModuleName ShellPrompt -MockWith { '' }
                Mock -CommandName Show-SshHostDashboard -ModuleName ShellPrompt -MockWith {
                    $script:selectorSeenFallbackLastHost = $LastHost
                    $null
                }
                $null = Show-HostSelector -Hosts @('debian', 'ubuntu')
                [PSCustomObject]@{ LastHost = $script:selectorSeenFallbackLastHost }
            } finally {
                $script:Config.SSH.LastHost = $original
            }
        }
        $selected.LastHost | Should -Be 'ubuntu'
    }

    It '主机名数组应全量透传给仪表盘(不做前置过滤)' {
        & $script:mod {
            Mock -CommandName Assert-ConsoleUiReady -ModuleName ShellPrompt -MockWith { }
            Mock -CommandName Get-WttrTitleSuffix -ModuleName ShellPrompt -MockWith { '' }
            Mock -CommandName Show-SshHostDashboard -ModuleName ShellPrompt -MockWith {
                $script:selectorSeenTitleHosts = $Hosts
                $null
            }
            $null = Show-HostSelector -Hosts @('a', 'b', 'c')
            $script:selectorSeenTitleHosts.Count | Should -Be 3
        }
    }
}
