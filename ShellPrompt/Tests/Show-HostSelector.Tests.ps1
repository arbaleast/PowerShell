<#
.SYNOPSIS
    Show-HostSelector(SSH 主机选择分发器)的 Pester 测试(业务装配层)

.DESCRIPTION
    2026-11-07 旧主机选择器视图/编排轨随源文件移除后, 本文件只保留生产分发器
    Show-HostSelector 的装配契约 —— 唯一呈现路径为 Show-SshHostDashboard
    -> Invoke-SshHostDashboard。覆盖:
      - 空主机列表告警并返回 $null(不入交互循环)
      - 非交互环境下先被 Assert-ConsoleUiReady 拦下(可定位的终止错误)
      - 仪表盘返回 $null 时透传 $null; 返回选中行时透传该行(.Value = 主机名)
      - LastHost 为空时从 $script:Config.SSH.LastHost 回退
      - 主机名数组全量透传给仪表盘(不做前置过滤)
    交互循环(Enter/Esc/过滤)依赖真实 TTY 事件注入, 由真机验收承担;
    本文件不模拟(仓库纪律: 未验证的交互不声称通过)。
#>

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
