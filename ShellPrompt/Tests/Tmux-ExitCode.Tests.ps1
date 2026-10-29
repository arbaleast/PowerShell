# Tmux-ExitCode.Tests.ps1 - tmux / SSH 退出码契约回归测试
# 覆盖 (2026-10-29 新增, 对应审计 P0-1 / P0-2 / P0-7):
#   1. 不可逆删除: 未经二次确认绝不发出 kill-session
#   2. 不可逆删除: ssh 退出码非 0 时不得打印 [OK], 必须给出警告
#   3. 不可逆删除: ssh 退出码为 0 时才打印 [OK]
#   4. 附加会话: 远端命令先用 has-session 判定, 不用 attach 2>/dev/null 吞错
#   5. 附加会话: 退出码非 0 时不得打印 [OK]

Describe 'tmux / SSH 退出码契约' {

    BeforeAll {
        # Pester v6: 路径与模块引用必须放在 BeforeAll 内解析
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    Context 'Remove-TmuxSession（不可逆删除）' {

        BeforeEach {
            Mock -CommandName Show-TmuxSessionList -ModuleName ShellPrompt -MockWith {
                [PSCustomObject]@{ Value = 'ci-test-session' }
            }
            Mock -CommandName Write-Host -ModuleName ShellPrompt -MockWith { }
            Mock -CommandName Write-Warning -ModuleName ShellPrompt -MockWith { }
        }

        It '未经二次确认时绝不发出 kill-session' {
            Mock -CommandName Read-SpectreConfirm -ModuleName ShellPrompt -MockWith { return $false }
            Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
                [PSCustomObject]@{ Output = ''; Error = ''; ExitCode = 0 }
            }

            & $script:mod {
                Remove-TmuxSession -HostName 'mock-host' -Sessions @([PSCustomObject]@{ Name = 'ci-test-session' })
            }

            Should -Invoke -CommandName Invoke-SshCommand -ModuleName ShellPrompt -Exactly 0
        }

        It 'ssh 退出码非 0 时不得打印 [OK], 必须给出警告' {
            Mock -CommandName Read-SpectreConfirm -ModuleName ShellPrompt -MockWith { return $true }
            Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
                [PSCustomObject]@{ Output = ''; Error = 'no such session'; ExitCode = 1 }
            }

            & $script:mod {
                Remove-TmuxSession -HostName 'mock-host' -Sessions @([PSCustomObject]@{ Name = 'ci-test-session' })
            }

            Should -Invoke -CommandName Invoke-SshCommand -ModuleName ShellPrompt -Exactly 1
            Should -Not -Invoke -CommandName Write-Host -ModuleName ShellPrompt `
                -ParameterFilter { $Object -like '*已删除*' }
            Should -Invoke -CommandName Write-Warning -ModuleName ShellPrompt `
                -ParameterFilter { $Message -like '*未成功*' }
        }

        It 'ssh 退出码为 0 时才打印 [OK]' {
            Mock -CommandName Read-SpectreConfirm -ModuleName ShellPrompt -MockWith { return $true }
            Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
                [PSCustomObject]@{ Output = ''; Error = ''; ExitCode = 0 }
            }

            & $script:mod {
                Remove-TmuxSession -HostName 'mock-host' -Sessions @([PSCustomObject]@{ Name = 'ci-test-session' })
            }

            Should -Invoke -CommandName Write-Host -ModuleName ShellPrompt `
                -ParameterFilter { $Object -like '*已删除*' }
            Should -Not -Invoke -CommandName Write-Warning -ModuleName ShellPrompt `
                -ParameterFilter { $Message -like '*未成功*' }
        }

        It 'kill-session 的会话名经过单引号转义' {
            Mock -CommandName Read-SpectreConfirm -ModuleName ShellPrompt -MockWith { return $true }
            Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
                [PSCustomObject]@{ Output = ''; Error = ''; ExitCode = 0 }
            }

            & $script:mod {
                Remove-TmuxSession -HostName 'mock-host' -Sessions @([PSCustomObject]@{ Name = 'ci-test-session' })
            }

            Should -Invoke -CommandName Invoke-SshCommand -ModuleName ShellPrompt -Exactly 1 `
                -ParameterFilter { $RemoteCommand -like '*tmux kill-session -t*' }
        }
    }

    Context 'Connect-TmuxSession（附加会话）' {

        BeforeEach {
            Mock -CommandName Show-TmuxSessionList -ModuleName ShellPrompt -MockWith {
                [PSCustomObject]@{ Value = 'ci-test-session' }
            }
            Mock -CommandName Write-Host -ModuleName ShellPrompt -MockWith { }
            Mock -CommandName Write-Warning -ModuleName ShellPrompt -MockWith { }
        }

        It '先用 has-session 判定再 attach, 不再吞掉 attach 的 stderr' {
            Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
                [PSCustomObject]@{ Output = ''; Error = ''; ExitCode = 0 }
            }

            & $script:mod {
                Connect-TmuxSession -HostName 'mock-host' -Sessions @([PSCustomObject]@{ Name = 'ci-test-session' })
            }

            Should -Invoke -CommandName Invoke-SshCommand -ModuleName ShellPrompt -Exactly 1 `
                -ParameterFilter { $RemoteCommand -like '*tmux has-session -t*' }
            Should -Invoke -CommandName Invoke-SshCommand -ModuleName ShellPrompt -Exactly 1 `
                -ParameterFilter { $RemoteCommand -like '*tmux attach -d -t*' }
            Should -Invoke -CommandName Invoke-SshCommand -ModuleName ShellPrompt -Exactly 1 `
                -ParameterFilter { $RemoteCommand -like '*tmux new-session -A -s*' }
        }

        It 'ssh 退出码非 0 时不得打印 [OK]' {
            Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
                [PSCustomObject]@{ Output = ''; Error = 'attach failed'; ExitCode = 255 }
            }

            & $script:mod {
                Connect-TmuxSession -HostName 'mock-host' -Sessions @([PSCustomObject]@{ Name = 'ci-test-session' })
            }

            Should -Not -Invoke -CommandName Write-Host -ModuleName ShellPrompt `
                -ParameterFilter { $Object -like '*已分离*' }
            Should -Invoke -CommandName Write-Warning -ModuleName ShellPrompt `
                -ParameterFilter { $Message -like '*未成功结束*' }
        }
    }
}
