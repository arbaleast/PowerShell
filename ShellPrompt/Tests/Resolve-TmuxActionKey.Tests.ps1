# Resolve-TmuxActionKey.Tests.ps1 - 单键 -> 动作值 映射契约回归测试
# 覆盖:
#   1. 常驻键位映射(n=新建 / r=刷新 / s=SSH / q=退出)
#   2. 大小写不敏感('N' 与 'n' 同义)
#   3. 依赖会话的键位(a=附着 / x=删除)在无会话时不解析
#   4. 未登记键与空白键返回空串
#   5. Context 不影响键位映射结果(错误上下文下 r 仍是 Refresh)

Describe 'tmux 管理器单键动作解析契约' {

    BeforeAll {
        # Pester v6: 路径与模块引用必须放在 BeforeAll 内解析
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    Context '常驻键位映射' {

        It 'n 解析为 New' {
            $action = & $script:mod { Resolve-TmuxActionKey -Key 'n' -HasSessions $true }

            $action | Should -BeExactly 'New'
        }

        It 'r 解析为 Refresh' {
            $action = & $script:mod { Resolve-TmuxActionKey -Key 'r' -HasSessions $true }

            $action | Should -BeExactly 'Refresh'
        }

        It 's 解析为 Ssh' {
            $action = & $script:mod { Resolve-TmuxActionKey -Key 's' -HasSessions $true }

            $action | Should -BeExactly 'Ssh'
        }

        It 'q 解析为 Quit' {
            $action = & $script:mod { Resolve-TmuxActionKey -Key 'q' -HasSessions $true }

            $action | Should -BeExactly 'Quit'
        }

        It '键位大小写不敏感(大写 N 同样解析为 New)' {
            $action = & $script:mod { Resolve-TmuxActionKey -Key 'N' -HasSessions $true }

            $action | Should -BeExactly 'New'
        }
    }

    Context '依赖会话的键位' {

        It '有会话时 a 解析为 Attach' {
            $action = & $script:mod { Resolve-TmuxActionKey -Key 'a' -HasSessions $true }

            $action | Should -BeExactly 'Attach'
        }

        It '有会话时 x 解析为 Remove' {
            $action = & $script:mod { Resolve-TmuxActionKey -Key 'x' -HasSessions $true }

            $action | Should -BeExactly 'Remove'
        }

        It '无会话时 a 不解析(返回空串)' {
            $action = & $script:mod { Resolve-TmuxActionKey -Key 'a' -HasSessions $false }

            $action | Should -BeExactly ''
        }

        It '无会话时 x 不解析(返回空串)' {
            $action = & $script:mod { Resolve-TmuxActionKey -Key 'x' -HasSessions $false }

            $action | Should -BeExactly ''
        }
    }

    Context '未命中与边界输入' {

        It '未登记的键 z 返回空串' {
            $action = & $script:mod { Resolve-TmuxActionKey -Key 'z' -HasSessions $true }

            $action | Should -BeExactly ''
        }

        It '空串键返回空串' {
            $action = & $script:mod { Resolve-TmuxActionKey -Key '' -HasSessions $true }

            $action | Should -BeExactly ''
        }

        It '空白键返回空串' {
            $action = & $script:mod { Resolve-TmuxActionKey -Key ' ' -HasSessions $true }

            $action | Should -BeExactly ''
        }
    }

    Context '上下文不影响键位映射' {

        It 'Error 上下文下 r 仍解析为 Refresh' {
            $action = & $script:mod { Resolve-TmuxActionKey -Key 'r' -HasSessions $true -Context 'Error' }

            $action | Should -BeExactly 'Refresh'
        }

        It 'Error 上下文下其余键位映射同样不变' {
            $normal = @(& $script:mod {
                @('a', 'n', 'r', 's', 'x', 'q') | ForEach-Object { Resolve-TmuxActionKey -Key $_ -HasSessions $true }
            })
            $errored = @(& $script:mod {
                @('a', 'n', 'r', 's', 'x', 'q') | ForEach-Object {
                    Resolve-TmuxActionKey -Key $_ -HasSessions $true -Context 'Error'
                }
            })

            $errored | Should -Be $normal
        }
    }
}
