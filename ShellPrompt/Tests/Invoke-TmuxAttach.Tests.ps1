# Invoke-TmuxAttach.Tests.ps1 - tmux 会话附着执行层(方案 A 抽出)的契约测试
# 覆盖 (2026-10-29 方案 A):
#   1. 远端命令保持 has-session 判定 + attach -d / new-session -A 兜底语义
#   2. 会话名安全转义(单引号包裹), 不做字符串裸拼接
#   3. ssh 退出码 0 -> [OK]; 非 0 -> 警告且不打印 [OK]

Describe 'Invoke-TmuxAttach (附着执行层)' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    BeforeEach {
        Mock -CommandName Write-Host -ModuleName ShellPrompt -MockWith { }
        Mock -CommandName Write-Warning -ModuleName ShellPrompt -MockWith { }
    }

    It '远端命令应为 has-session 判定 + attach -d / new-session -A 兜底, 且会话名安全转义' {
        Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
            [PSCustomObject]@{ Output = ''; Error = ''; ExitCode = 0 }
        }

        & $script:mod {
            Invoke-TmuxAttach -HostName 'mock-host' -SessionName "it's a test"
        }

        Should -Invoke -CommandName Invoke-SshCommand -ModuleName ShellPrompt -Exactly 1 `
            -ParameterFilter {
                $HostName -eq 'mock-host' -and
                $RemoteCommand -match '^tmux has-session -t ' -and
                $RemoteCommand -like "*'\''*"
            }
        Should -Invoke -CommandName Invoke-SshCommand -ModuleName ShellPrompt -Exactly 1 `
            -ParameterFilter { $RemoteCommand -like '*tmux attach -d -t*' }
        Should -Invoke -CommandName Invoke-SshCommand -ModuleName ShellPrompt -Exactly 1 `
            -ParameterFilter { $RemoteCommand -like '*tmux new-session -A -s*' }
    }

    It 'ssh 退出码为 0 时应打印 [OK](回到管理菜单)' {
        Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
            [PSCustomObject]@{ Output = ''; Error = ''; ExitCode = 0 }
        }

        & $script:mod {
            Invoke-TmuxAttach -HostName 'mock-host' -SessionName 'btop'
        }

        Should -Invoke -CommandName Write-Host -ModuleName ShellPrompt `
            -ParameterFilter { $Object -like '*已分离*' }
        Should -Not -Invoke -CommandName Write-Warning -ModuleName ShellPrompt
    }

    It 'ssh 退出码非 0 时不得打印 [OK], 必须给出警告' {
        Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
            [PSCustomObject]@{ Output = ''; Error = 'attach failed'; ExitCode = 255 }
        }

        & $script:mod {
            Invoke-TmuxAttach -HostName 'mock-host' -SessionName 'btop'
        }

        Should -Not -Invoke -CommandName Write-Host -ModuleName ShellPrompt `
            -ParameterFilter { $Object -like '*已分离*' }
        Should -Invoke -CommandName Write-Warning -ModuleName ShellPrompt `
            -ParameterFilter { $Message -like '*未成功结束*' }
    }

    It 'ssh 启动失败(抛异常)时降级为警告, 不得让异常冒泡打断管理器' {
        # 未安装 OpenSSH 客户端 / ssh.exe 不在 PATH 时 Invoke-SshCommand 会抛异常。
        # 这里验证: 异常被就地捕获 -> 警告 -> 不打印 [OK] -> 不向调用方抛出。
        Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
            throw 'The system cannot find the file specified.'
        }

        { & $script:mod { Invoke-TmuxAttach -HostName 'mock-host' -SessionName 'btop' } } |
            Should -Not -Throw

        Should -Invoke -CommandName Write-Warning -ModuleName ShellPrompt `
            -ParameterFilter { $Message -like '*无法执行 ssh*' }
        Should -Not -Invoke -CommandName Write-Host -ModuleName ShellPrompt `
            -ParameterFilter { $Object -like '*已分离*' }
    }
}
