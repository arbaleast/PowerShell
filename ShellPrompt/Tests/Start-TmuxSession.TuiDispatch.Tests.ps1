# Start-TmuxSession.TuiDispatch.Tests.ps1 - Start-TmuxSession 渲染编排契约测试
# 覆盖(2026-10-30 回退轨移除后):
#   1. 单轨: Start-TmuxSession 无条件进入 Show-TmuxTuiDashboard(唯一渲染路径);
#      legacy 主视图/动作条(已删除)不再被引用 —— 取数也不在编排层(在仪表盘内);
#   2. 无 -HostName: 先弹主机选择, 选定后才进 TGUI 仪表盘, LastHost 记忆写回;
#   3. 主机选择取消: 不进仪表盘。
# 说明: 全部交互通过 Mock 隔离, 不连接真实 SSH / 不触碰真实 TG。

Describe 'Start-TmuxSession 渲染编排(单轨)' {

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
        Mock -CommandName Submit-WttrPrefetch -ModuleName ShellPrompt -MockWith { return $null }
        # 防御性 mock: 断言编排入口不再触碰(Should -Invoke 要求 mock 存在)
        Mock -CommandName Invoke-TmuxSessionFetch -ModuleName ShellPrompt -MockWith { return $null }
        Mock -CommandName Enter-TmuxAlternateScreen -ModuleName ShellPrompt -MockWith { }
    }

    It '单轨: 带 -HostName 时直接进 Show-TmuxTuiDashboard 恰好一次' {
        & $script:mod { Start-TmuxSession -HostName 'deb' }

        Should -Invoke -CommandName Show-TmuxTuiDashboard -ModuleName ShellPrompt -Exactly 1 `
            -ParameterFilter { $HostName -eq 'deb' }
        # 取数在仪表盘编排层内, 编排入口不再触碰数据层 / 备用屏原语
        Should -Invoke -CommandName Invoke-TmuxSessionFetch -ModuleName ShellPrompt -Exactly 0
        Should -Invoke -CommandName Enter-TmuxAlternateScreen -ModuleName ShellPrompt -Exactly 0
    }

    It '单轨: 已删除的回退轨入口在模块内不存在(防"幽灵调用"回归)' {
        & $script:mod {
            @('Show-TmuxSessionDashboard', 'Show-TmuxActionBar', 'Read-TmuxActionKey', 'Get-TmuxPlaceholderRow') |
                Where-Object { Get-Command -Name $_ -ErrorAction SilentlyContinue } |
                Should -BeNullOrEmpty
        }
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
}
