# Start-TmuxSession.TuiDispatch.Tests.ps1 - TGUI 分发层契约测试(阶段 B)
# 覆盖:
#   1. Start-TmuxSession 依 DashboardTuiEnabled 开关分发: 默认($true)直接进
#       Show-TmuxTuiDashboard(阶段 B 编排层), 不进 legacy 主视图/动作条;
#   2. DashboardTuiEnabled=$false: 仅在此配置下走 legacy 主循环
#       (legacy 主路径的完整契约由 Start-TmuxSession.Tests.ps1 覆盖。
# 说明: 全部交互通过 Mock 隔离, 不连接真实 SSH / 不触碰真实 TG。

Describe 'Start-TmuxSession 渲染分发 (TGUI 阶段 B)' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    BeforeEach {
        Mock -CommandName Write-Host -ModuleName ShellPrompt -MockWith { }
        Mock -CommandName Write-Warning -ModuleName ShellPrompt -MockWith { }
        Mock -CommandName Write-TmuxWelcomeBanner -ModuleName ShellPrompt -MockWith { }
        Mock -CommandName Test-SshHostName -ModuleName ShellPrompt -MockWith { return $true }
        Mock -CommandName Show-TmuxTuiDashboard -ModuleName ShellPrompt -MockWith { return 'Exit' }
        # legacy 路径组件防御性 mock(断言应命中 0 次)
        Mock -CommandName Show-TmuxSessionDashboard -ModuleName ShellPrompt -MockWith { return $null }
        Mock -CommandName Show-TmuxActionBar -ModuleName ShellPrompt -MockWith { return $null }
        Mock -CommandName Invoke-TmuxSessionFetch -ModuleName ShellPrompt -MockWith { return $null }
        Mock -CommandName Submit-WttrPrefetch -ModuleName ShellPrompt -MockWith { return $null }
        Mock -CommandName Enter-TmuxAlternateScreen -ModuleName ShellPrompt -MockWith { }
        Mock -CommandName Exit-TmuxAlternateScreen -ModuleName ShellPrompt -MockWith { }
        Mock -CommandName Clear-TmuxScreen -ModuleName ShellPrompt -MockWith { }
    }

    It 'TUI 默认开启($true): 跳过 legacy 主循环, 直接进 Show-TmuxTuiDashboard' {
        & $script:mod { Start-TmuxSession -HostName 'deb' }

        Should -Invoke -CommandName Show-TmuxTuiDashboard -ModuleName ShellPrompt -Exactly 1 `
            -ParameterFilter { $HostName -eq 'deb' }
        Should -Invoke -CommandName Show-TmuxSessionDashboard -ModuleName ShellPrompt -Exactly 0
        Should -Invoke -CommandName Show-TmuxActionBar -ModuleName ShellPrompt -Exactly 0
        Should -Invoke -CommandName Invoke-TmuxSessionFetch -ModuleName ShellPrompt -Exactly 0
        Should -Invoke -CommandName Enter-TmuxAlternateScreen -ModuleName ShellPrompt -Exactly 0
    }

    It 'DashboardTuiEnabled=$false: 仅在此配置下走 legacy 主循环' {
        & $script:mod { $script:Config.UI.DashboardTuiEnabled = $false }

        & $script:mod { Start-TmuxSession -HostName 'deb' }

        Should -Invoke -CommandName Show-TmuxTuiDashboard -ModuleName ShellPrompt -Exactly 0
        Should -Invoke -CommandName Show-TmuxSessionDashboard -ModuleName ShellPrompt -Exactly 1
        Should -Invoke -CommandName Show-TmuxActionBar -ModuleName ShellPrompt -Exactly 1
    }
}

Describe 'Start-TmuxSession 无主机路径 (2026-10-30 审计#5)' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    BeforeEach {
        Mock -CommandName Write-Host -ModuleName ShellPrompt -MockWith { }
        Mock -CommandName Write-Warning -ModuleName ShellPrompt -MockWith { }
        Mock -CommandName Write-TmuxWelcomeBanner -ModuleName ShellPrompt -MockWith { }
        Mock -CommandName Test-SshHostName -ModuleName ShellPrompt -MockWith { return $true }
        Mock -CommandName Invoke-WithProgress -ModuleName ShellPrompt -MockWith { return @(@{ Value = 'deb' }) }
        # 选择桩: 返回选择结果形状(与 Show-HostSelector 契约一致 = .Value 会话名)
        Mock -CommandName Show-HostSelector -ModuleName ShellPrompt -MockWith {
            param($Hosts, $LastHost)
            [void]$Hosts; [void]$LastHost
            return [PSCustomObject]@{ Value = 'deb' }
        }
        Mock -CommandName Show-TmuxTuiDashboard -ModuleName ShellPrompt -MockWith { return 'Exit' }
    }

    It '无 -HostName: 先弹主机选择, 选定主机后才进 TGUI 仪表盘(S1 回归保护)' {
        & $script:mod { Start-TmuxSession }

        Should -Invoke -CommandName Show-HostSelector -ModuleName ShellPrompt -Exactly 1
        Should -Invoke -CommandName Show-TmuxTuiDashboard -ModuleName ShellPrompt -Exactly 1 `
            -ParameterFilter { $HostName -eq 'deb' }
        # LastHost 记忆在任何分支都写回
        & $script:mod { $script:Config.SSH.LastHost } | Should -BeExactly 'deb'
    }

    It '主机选择被用户取消: 不进任何仪表盘' {
        Mock -CommandName Show-HostSelector -ModuleName ShellPrompt -MockWith { return $null }

        & $script:mod { Start-TmuxSession }

        Should -Invoke -CommandName Show-TmuxTuiDashboard -ModuleName ShellPrompt -Exactly 0
    }

    It '取消选择同样受 legacy 分支保护: DashboardTuiEnabled=$false 时 legacy 主视图也不启动' {
        Mock -CommandName Show-HostSelector -ModuleName ShellPrompt -MockWith { return $null }
        Mock -CommandName Show-TmuxSessionDashboard -ModuleName ShellPrompt -MockWith { return $null }
        Mock -CommandName Show-TmuxActionBar -ModuleName ShellPrompt -MockWith { return $null }
        & $script:mod { $script:Config.UI.DashboardTuiEnabled = $false }

        & $script:mod { Start-TmuxSession }

        Should -Invoke -CommandName Show-HostSelector -ModuleName ShellPrompt -Exactly 1
        Should -Invoke -CommandName Show-TmuxSessionDashboard -ModuleName ShellPrompt -Exactly 0
        Should -Invoke -CommandName Show-TmuxActionBar -ModuleName ShellPrompt -Exactly 0
    }
}
