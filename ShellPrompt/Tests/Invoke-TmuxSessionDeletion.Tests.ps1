# Invoke-TmuxSessionDeletion.Tests.ps1 - 删除屏障(二次确认 + kill-session)契约测试
# 覆盖 (2026-10-30 TGUI 迁移):
#   1. 二次确认被拒 -> 绝不发出 kill-session(不可逆操作的闸门必须有效);
#   2. 二次确认通过 -> 发出 kill-session, 会话名经单引号转义;
#   3. 确认提示文本包含会话名(且 '[' 已转义成 '[['), 默认答案为 'n';
#   4. 确认过程抛异常 -> 按"不删除"处理, 绝不发出 kill-session;
#   5. ssh 退出码非 0 / ssh 启动失败 -> 警告 + 不打印 [OK]。
# 说明: 全部通过 Mock 隔离 Spectre 提示与 ssh, 不触碰真实终端与远端主机。

Describe '删除屏障 (Invoke-TmuxSessionDeletion)' {

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
    }

    It '二次确认被拒时绝不发出 kill-session' {
        Mock -CommandName Read-SpectreConfirm -ModuleName ShellPrompt -MockWith { return $false }
        Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
            [PSCustomObject]@{ Output = ''; Error = ''; ExitCode = 0 }
        }

        & $script:mod {
            Invoke-TmuxSessionDeletion -HostName 'mock-host' -SessionName 'ci-test-session'
        }

        Should -Invoke -CommandName Invoke-SshCommand -ModuleName ShellPrompt -Exactly 0
        Should -Invoke -CommandName Write-Warning -ModuleName ShellPrompt `
            -ParameterFilter { $Message -like '*已放弃删除*' }
    }

    It '二次确认通过时发出 kill-session, 且会话名经单引号转义' {
        Mock -CommandName Read-SpectreConfirm -ModuleName ShellPrompt -MockWith { return $true }
        Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
            [PSCustomObject]@{ Output = ''; Error = ''; ExitCode = 0 }
        }

        & $script:mod {
            Invoke-TmuxSessionDeletion -HostName 'mock-host' -SessionName 'ci-test-session'
        }

        Should -Invoke -CommandName Invoke-SshCommand -ModuleName ShellPrompt -Exactly 1 `
            -ParameterFilter {
                $HostName -eq 'mock-host' -and
                $RemoteCommand -eq "tmux kill-session -t 'ci-test-session'"
            }
        Should -Invoke -CommandName Write-Host -ModuleName ShellPrompt `
            -ParameterFilter { $Object -like '*已删除*' }
    }

    It '会话名含单引号时按 SSH 规则转义后再交给远端' {
        Mock -CommandName Read-SpectreConfirm -ModuleName ShellPrompt -MockWith { return $true }
        Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
            [PSCustomObject]@{ Output = ''; Error = ''; ExitCode = 0 }
        }

        & $script:mod {
            Invoke-TmuxSessionDeletion -HostName 'mock-host' -SessionName "it's a test"
        }

        Should -Invoke -CommandName Invoke-SshCommand -ModuleName ShellPrompt -Exactly 1 `
            -ParameterFilter { $RemoteCommand -eq "tmux kill-session -t 'it'\''s a test'" }
    }

    It '确认提示文本包含会话名, 且默认答案为 n' {
        Mock -CommandName Read-SpectreConfirm -ModuleName ShellPrompt -MockWith { return $true }
        Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
            [PSCustomObject]@{ Output = ''; Error = ''; ExitCode = 0 }
        }

        & $script:mod {
            Invoke-TmuxSessionDeletion -HostName 'mock-host' -SessionName 'ci-test-session'
        }

        Should -Invoke -CommandName Read-SpectreConfirm -ModuleName ShellPrompt -Exactly 1 `
            -ParameterFilter {
                $Message -like '*ci-test-session*' -and
                $DefaultAnswer -eq 'n'
            }
    }

    It '会话名含 [ 时提示文本按 Spectre markup 规则转义为 [[' {
        Mock -CommandName Read-SpectreConfirm -ModuleName ShellPrompt -MockWith { return $true }
        Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
            [PSCustomObject]@{ Output = ''; Error = ''; ExitCode = 0 }
        }

        & $script:mod {
            Invoke-TmuxSessionDeletion -HostName 'mock-host' -SessionName 'ci[1]'
        }

        # 文本含正则元字符([), 用 -Match + [regex]::Escape 断言(不做子串 -Contain)
        Should -Invoke -CommandName Read-SpectreConfirm -ModuleName ShellPrompt -Exactly 1 `
            -ParameterFilter { $Message -match ([regex]::Escape('ci[[1]')) }
    }

    It '确认过程抛异常时按"不删除"处理, 绝不发出 kill-session' {
        Mock -CommandName Read-SpectreConfirm -ModuleName ShellPrompt -MockWith { throw '非交互终端' }
        Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
            [PSCustomObject]@{ Output = ''; Error = ''; ExitCode = 0 }
        }

        { & $script:mod {
                Invoke-TmuxSessionDeletion -HostName 'mock-host' -SessionName 'ci-test-session'
            } } | Should -Not -Throw

        Should -Invoke -CommandName Invoke-SshCommand -ModuleName ShellPrompt -Exactly 0
        Should -Invoke -CommandName Write-Warning -ModuleName ShellPrompt `
            -ParameterFilter { $Message -like '*无法完成二次确认*' }
        Should -Not -Invoke -CommandName Write-Host -ModuleName ShellPrompt `
            -ParameterFilter { $Object -like '*已删除*' }
    }

    It 'ssh 退出码非 0 时不得打印 [OK], 必须给出警告' {
        Mock -CommandName Read-SpectreConfirm -ModuleName ShellPrompt -MockWith { return $true }
        Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
            [PSCustomObject]@{ Output = ''; Error = 'no such session'; ExitCode = 1 }
        }

        & $script:mod {
            Invoke-TmuxSessionDeletion -HostName 'mock-host' -SessionName 'ci-test-session'
        }

        Should -Invoke -CommandName Write-Warning -ModuleName ShellPrompt `
            -ParameterFilter { $Message -like '*未成功*' }
        Should -Not -Invoke -CommandName Write-Host -ModuleName ShellPrompt `
            -ParameterFilter { $Object -like '*已删除*' }
    }

    It 'ssh 启动失败(抛异常)时降级为警告, 不得报删除成功' {
        Mock -CommandName Read-SpectreConfirm -ModuleName ShellPrompt -MockWith { return $true }
        Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
            throw '启动 ssh.exe 失败 (进程未能创建)'
        }

        { & $script:mod {
                Invoke-TmuxSessionDeletion -HostName 'mock-host' -SessionName 'ci-test-session'
            } } | Should -Not -Throw

        Should -Invoke -CommandName Write-Warning -ModuleName ShellPrompt `
            -ParameterFilter { $Message -like '*无法执行 ssh*' }
        Should -Not -Invoke -CommandName Write-Host -ModuleName ShellPrompt `
            -ParameterFilter { $Object -like '*已删除*' }
    }
}
