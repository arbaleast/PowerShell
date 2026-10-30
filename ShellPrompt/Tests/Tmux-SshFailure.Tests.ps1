# Tmux-SshFailure.Tests.ps1 - tmux 编排层对"ssh 启动失败/远端失败"的降级契约
#
# 覆盖 (2026-10-29 SSH/tmux 可靠性审计):
#   1. Remove-TmuxSession: ssh 启动失败(抛异常)时 -> 警告 + 不抛异常 + 不得打印 [OK];
#      二次确认通过也不等于"删除成功"。
#   2. Remove-TmuxSession: ssh 退出码非 0(远端 kill-session 失败)时 -> 警告 + 不打印 [OK]。
#   3. Remove-TmuxSession: 二次确认取消时 -> 根本不得发起 kill-session。
#   4. Invoke-TmuxAttach / New-TmuxSession: ssh 启动失败时降级为警告, 不冒泡。
#
# 说明: 全部通过 Mock 隔离 ssh/tmux, 不连接真实主机; 断言的是"编排层语义",
#       不是真实 SSH 环境的连通性验证。

Describe 'tmux 编排层对 ssh 失败的降级处理' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    Context 'Remove-TmuxSession (不可逆删除路径)' {

        BeforeEach {
            Mock -CommandName Write-Host -ModuleName ShellPrompt -MockWith { }
            Mock -CommandName Write-Warning -ModuleName ShellPrompt -MockWith { }
            # 列表层返回目标会话 (Value 恒为纯会话名)
            Mock -CommandName Show-TmuxSessionList -ModuleName ShellPrompt -MockWith {
                [PSCustomObject]@{ Value = 'victim-session' }
            }
        }

        It 'ssh 启动失败(抛异常)时降级为警告, 不得抛给调用方, 也不得报删除成功' {
            Mock -CommandName Read-SpectreConfirm -ModuleName ShellPrompt -MockWith { return $true }
            Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
                throw '启动 ssh.exe 失败 (进程未能创建, 与远端命令失败无关): 系统找不到指定的文件。'
            }

            { & $script:mod {
                    Remove-TmuxSession -HostName 'mock-host' -Sessions @([PSCustomObject]@{ Name = 'victim-session' })
                } } | Should -Not -Throw

            Should -Invoke -CommandName Write-Warning -ModuleName ShellPrompt `
                -ParameterFilter { $Message -like '*无法执行 ssh*' }
            Should -Not -Invoke -CommandName Write-Host -ModuleName ShellPrompt `
                -ParameterFilter { $Object -like '*已删除*' }
        }

        It '远端 kill-session 失败(退出码非 0)时必须警告, 不得报删除成功' {
            Mock -CommandName Read-SpectreConfirm -ModuleName ShellPrompt -MockWith { return $true }
            Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
                [PSCustomObject]@{ Output = ''; Error = 'no such session'; ExitCode = 1; TimedOut = $false }
            }

            & $script:mod {
                Remove-TmuxSession -HostName 'mock-host' -Sessions @([PSCustomObject]@{ Name = 'victim-session' })
            }

            Should -Invoke -CommandName Write-Warning -ModuleName ShellPrompt `
                -ParameterFilter { $Message -like '*未成功*' }
            Should -Not -Invoke -CommandName Write-Host -ModuleName ShellPrompt `
                -ParameterFilter { $Object -like '*已删除*' }
        }

        It '二次确认取消时不得发起 kill-session(不可逆操作闸门必须有效)' {
            Mock -CommandName Read-SpectreConfirm -ModuleName ShellPrompt -MockWith { return $false }
            # 桩存在即可(下面断言"一次都没被调用"), 一旦被调用就会误删会话
            Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
                [PSCustomObject]@{ Output = ''; Error = ''; ExitCode = 0; TimedOut = $false }
            }

            & $script:mod {
                Remove-TmuxSession -HostName 'mock-host' -Sessions @([PSCustomObject]@{ Name = 'victim-session' })
            }

            Should -Invoke -CommandName Invoke-SshCommand -ModuleName ShellPrompt -Exactly 0
            Should -Not -Invoke -CommandName Write-Host -ModuleName ShellPrompt `
                -ParameterFilter { $Object -like '*已删除*' }
        }
    }

    Context '附着 / 创建路径' {

        BeforeEach {
            Mock -CommandName Write-Host -ModuleName ShellPrompt -MockWith { }
            Mock -CommandName Write-Warning -ModuleName ShellPrompt -MockWith { }
        }

        It 'Invoke-TmuxAttach 在 ssh 启动失败时降级为警告, 不冒泡' {
            Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
                throw '启动 ssh.exe 失败 (进程未能创建, 与远端命令失败无关)'
            }

            { & $script:mod { Invoke-TmuxAttach -HostName 'mock-host' -SessionName 'btop' } } |
                Should -Not -Throw

            Should -Invoke -CommandName Write-Warning -ModuleName ShellPrompt `
                -ParameterFilter { $Message -like '*无法执行 ssh*' }
            Should -Not -Invoke -CommandName Write-Host -ModuleName ShellPrompt `
                -ParameterFilter { $Object -like '*已分离*' }
        }

        It 'New-TmuxSession 在 ssh 启动失败时降级为警告, 不冒泡' {
            Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
                throw '启动 ssh.exe 失败 (进程未能创建, 与远端命令失败无关)'
            }

            { & $script:mod { New-TmuxSession -HostName 'mock-host' } } | Should -Not -Throw

            Should -Invoke -CommandName Write-Warning -ModuleName ShellPrompt `
                -ParameterFilter { $Message -like '*无法执行 ssh*' }
            Should -Not -Invoke -CommandName Write-Host -ModuleName ShellPrompt `
                -ParameterFilter { $Object -like '*已分离*' }
        }
    }
}
