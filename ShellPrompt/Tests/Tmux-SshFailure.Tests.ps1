# Tmux-SshFailure.Tests.ps1 - tmux 编排层对"ssh 启动失败/远端失败"的降级契约
#
# 覆盖 (2026-10-29 SSH/tmux 可靠性审计):
#   1. Invoke-TmuxAttach / New-TmuxSession: ssh 启动失败时降级为警告, 不冒泡。
# 说明: 2026-10-31 死代码清理后, Remove-TmuxSession 已删除(旧会话列表链的删除入口);
#       删除路径的降级语义现由 Invoke-TmuxSessionDeletion 承担。
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
            # 输入态读取器注入空串(= 随机名称路径), 不触碰真实控制台
            Mock -CommandName Read-TmuxConsoleLine -ModuleName ShellPrompt -MockWith { return '' }
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
