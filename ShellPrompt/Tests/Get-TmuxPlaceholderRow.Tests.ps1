# Get-TmuxPlaceholderRow.Tests.ps1 - tmux 主视图占位面板行契约回归测试
# 覆盖:
#   1. 探测失败态: Session 列给出错误说明, State 列带错误码与降级指引
#   2. 探测失败态: Value 为空串(该行不是会话), Disabled 为 $false
#   3. 空会话态: State 列给出操作提示, Session 列非空
#   4. 列结构恒定: No / Windows / Status 恒为空串(与会话行同构)
#   5. 边界: ErrorMessage 与 Hint 均缺失时的兜底文案
# 说明: 纯函数, 输入为 Get-TmuxSessionState 的输出, 不触碰真实 ssh / tmux / 控制台。

Describe 'tmux 主视图占位面板行契约' {

    BeforeAll {
        # Pester v6: 路径与模块引用必须放在 BeforeAll 内解析
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    Context '探测失败态占位行' {

        BeforeAll {
            $script:errorState = & $script:mod {
                Get-TmuxSessionState -SessionData @{
                    Available = $false; TimedOut = $true; NetworkError = $false
                    Error = 'ssh timed out'; ExitCode = 255
                }
            }
            $script:errorRow = & $script:mod { param($s) Get-TmuxPlaceholderRow -State $s } $script:errorState
        }

        It 'Session 列给出面向用户的错误说明文字' {
            $script:errorRow.Session | Should -Match 'SSH 连接超时'
        }

        It 'State 列同时含稳定错误码与重试指引' {
            $script:errorRow.State | Should -Match 'E_SSH_TIMEOUT'
            $script:errorRow.State | Should -Match '按 r 重试'
        }

        It 'Value 为空串(该行不是会话)' {
            $script:errorRow.Value | Should -BeExactly ''
        }

        It 'Disabled 为 $false(占位行可被选中以进入动作条)' {
            $script:errorRow.Disabled | Should -BeFalse
        }
    }

    Context '空会话态占位行' {

        BeforeAll {
            $script:emptyState = & $script:mod {
                Get-TmuxSessionState -SessionData @{ Available = $true; Sessions = @(); Version = '3.4' }
            }
            $script:emptyRow = & $script:mod { param($s) Get-TmuxPlaceholderRow -State $s } $script:emptyState
        }

        It 'State 列给出操作提示(含 n 与 r)' {
            $script:emptyRow.State | Should -Match '按 n 新建会话'
            $script:emptyRow.State | Should -Match '按 r 刷新'
        }

        It 'Session 列非空(说明当前确实没有会话)' {
            $script:emptyRow.Session | Should -Not -BeNullOrEmpty
        }

        It 'Value 同样为空串' {
            $script:emptyRow.Value | Should -BeExactly ''
        }
    }

    Context '列结构与会话行同构' {

        It 'No / Windows / Status 三列恒为空串' {
            $state = & $script:mod {
                Get-TmuxSessionState -SessionData @{
                    Available = $false; TimedOut = $true; NetworkError = $false
                    Error = 'ssh timed out'; ExitCode = 255
                }
            }

            $row = & $script:mod { param($s) Get-TmuxPlaceholderRow -State $s } $state

            $row.No | Should -BeExactly ''
            $row.Windows | Should -BeExactly ''
            $row.Status | Should -BeExactly ''
        }
    }

    Context '边界: 文案缺失时的兜底' {

        It 'ErrorMessage 为空时回退到默认说明文案' {
            $state = [PSCustomObject]@{ ErrorCode = ''; ErrorMessage = ''; Hint = '按 n 新建会话 · 按 r 刷新' }

            $row = & $script:mod { param($s) Get-TmuxPlaceholderRow -State $s } $state

            $row.Session | Should -BeExactly '未获取到 tmux 会话数据'
            $row.State | Should -BeExactly '按 n 新建会话 · 按 r 刷新'
        }

        It '错误码与指引都缺失时 State 回退为 EMPTY' {
            $state = [PSCustomObject]@{ ErrorCode = ''; ErrorMessage = '远端当前没有 tmux 会话'; Hint = '' }

            $row = & $script:mod { param($s) Get-TmuxPlaceholderRow -State $s } $state

            $row.State | Should -BeExactly 'EMPTY'
        }
    }
}
