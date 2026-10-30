# Remove-TmuxSession.Tests.ps1 - 删除入口(列表选择 + 委托删除屏障)契约测试
# 覆盖 (2026-10-30 TGUI 迁移):
#   1. 会话选定走 Show-TmuxSessionList(旧链路的交互入口不变);
#   2. 选定之后**委托**给 Invoke-TmuxSessionDeletion —— 二次确认与 kill-session
#      只有一份实现, TGUI 仪表盘(直接删表格选中行)走同一条路径;
#   3. 用户取消选择时不触发任何删除动作。
# 说明: 全部通过 Mock 隔离列表与删除屏障, 不触碰真实终端与远端主机。

Describe '删除入口 (Remove-TmuxSession)' {

    BeforeAll {
        # Pester v6: 路径与模块引用必须放在 BeforeAll 内解析
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    BeforeEach {
        Mock -CommandName Write-Host -ModuleName ShellPrompt -MockWith { }
        Mock -CommandName Write-Warning -ModuleName ShellPrompt -MockWith { }
        # 列表层返回目标会话 (Value 恒为纯会话名)
        Mock -CommandName Show-TmuxSessionList -ModuleName ShellPrompt -MockWith {
            [PSCustomObject]@{ Value = 'ci-test-session' }
        }
    }

    It '通过 Show-TmuxSessionList 选择会话' {
        # 删除屏障: 这里只验证"被委托了", 不重复验证屏障内部语义
        Mock -CommandName Invoke-TmuxSessionDeletion -ModuleName ShellPrompt -MockWith { }

        & $script:mod {
            Remove-TmuxSession -HostName 'mock-host' -Sessions @([PSCustomObject]@{ Name = 'ci-test-session' })
        }

        Should -Invoke -CommandName Show-TmuxSessionList -ModuleName ShellPrompt -Exactly 1 `
            -ParameterFilter { $HostName -eq 'mock-host' }
    }

    It '把选中的会话名委托给 Invoke-TmuxSessionDeletion' {
        Mock -CommandName Invoke-TmuxSessionDeletion -ModuleName ShellPrompt -MockWith { }

        & $script:mod {
            Remove-TmuxSession -HostName 'mock-host' -Sessions @([PSCustomObject]@{ Name = 'ci-test-session' })
        }

        Should -Invoke -CommandName Invoke-TmuxSessionDeletion -ModuleName ShellPrompt -Exactly 1 `
            -ParameterFilter {
                $HostName -eq 'mock-host' -and
                $SessionName -eq 'ci-test-session'
            }
    }

    It '用户取消选择时不触发删除屏障' {
        Mock -CommandName Show-TmuxSessionList -ModuleName ShellPrompt -MockWith { return $null }
        Mock -CommandName Invoke-TmuxSessionDeletion -ModuleName ShellPrompt -MockWith { }

        & $script:mod {
            Remove-TmuxSession -HostName 'mock-host' -Sessions @([PSCustomObject]@{ Name = 'ci-test-session' })
        }

        Should -Invoke -CommandName Invoke-TmuxSessionDeletion -ModuleName ShellPrompt -Exactly 0
    }

    It '删除屏障不可被绕过: 二次确认与 kill-session 都发生在屏障内部' {
        # 契约锁: 二次确认与 kill-session 只能在 Invoke-TmuxSessionDeletion 里,
        # Remove-TmuxSession 不得再自带一份实现(否则屏障迟早被改漏一处)。
        # 这里**不** mock 删除屏障, 让它真的跑一遍。
        Mock -CommandName Read-SpectreConfirm -ModuleName ShellPrompt -MockWith { return $true }
        Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
            [PSCustomObject]@{ Output = ''; Error = ''; ExitCode = 0 }
        }

        & $script:mod {
            Remove-TmuxSession -HostName 'mock-host' -Sessions @([PSCustomObject]@{ Name = 'ci-test-session' })
        }

        Should -Invoke -CommandName Read-SpectreConfirm -ModuleName ShellPrompt -Exactly 1 `
            -ParameterFilter { $DefaultAnswer -eq 'n' }
        Should -Invoke -CommandName Invoke-SshCommand -ModuleName ShellPrompt -Exactly 1 `
            -ParameterFilter { $RemoteCommand -like '*tmux kill-session -t*' }
    }
}
