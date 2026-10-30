# Get-TmuxActionDefinition.Tests.ps1 - tmux 管理器动作定义(键位/文案/动作值)契约回归测试
# 覆盖:
#   1. 有会话时 6 个键位的固定顺序(a/n/r/s/x/q)与动作值映射
#   2. 无会话时剔除依赖会话的动作(a=附着 / x=删除), 只剩 n/r/s/q
#   3. Context=Error 只切换文案(r=重试 / s=直连), 键位与动作值保持不变
#   4. RequiresSessions 标记的正确性(仅 a/x 为 $true)
#   5. 默认参数(HasSessions=$false / Context='Normal')

Describe 'tmux 管理器动作定义契约' {

    BeforeAll {
        # Pester v6: 路径与模块引用必须放在 BeforeAll 内解析
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    Context '有会话时的动作集合 (HasSessions = $true, Normal)' {

        It '键位顺序固定为 a,n,r,s,x,q' {
            $defs = @(& $script:mod { Get-TmuxActionDefinition -HasSessions $true })

            @($defs | ForEach-Object { $_.Key }) | Should -Be @('a', 'n', 'r', 's', 'x', 'q')
        }

        It '动作值依次为 Attach,New,Refresh,Ssh,Remove,Quit' {
            $defs = @(& $script:mod { Get-TmuxActionDefinition -HasSessions $true })

            @($defs | ForEach-Object { $_.Value }) | Should -Be @('Attach', 'New', 'Refresh', 'Ssh', 'Remove', 'Quit')
        }

        It '文案依次为 附着,新建,刷新,SSH,删除,退出' {
            $defs = @(& $script:mod { Get-TmuxActionDefinition -HasSessions $true })

            @($defs | ForEach-Object { $_.Label }) | Should -Be @('附着', '新建', '刷新', 'SSH', '删除', '退出')
        }

        It 'RequiresSessions 仅附着(a)与删除(x)为 $true' {
            $defs = @(& $script:mod { Get-TmuxActionDefinition -HasSessions $true })

            ($defs | Where-Object { $_.Key -eq 'a' }).RequiresSessions | Should -BeTrue
            ($defs | Where-Object { $_.Key -eq 'x' }).RequiresSessions | Should -BeTrue
            @($defs | Where-Object { $_.RequiresSessions } | ForEach-Object { $_.Key }) | Should -Be @('a', 'x')
        }
    }

    Context '无会话时剔除依赖会话的动作 (HasSessions = $false)' {

        It '只剩 n,r,s,q 四个键位(附着与删除被剔除)' {
            $defs = @(& $script:mod { Get-TmuxActionDefinition -HasSessions $false })

            @($defs | ForEach-Object { $_.Key }) | Should -Be @('n', 'r', 's', 'q')
        }

        It '被剔除的键位确实不在集合内' {
            $defs = @(& $script:mod { Get-TmuxActionDefinition -HasSessions $false })

            @($defs | Where-Object { $_.Key -eq 'a' }) | Should -BeNullOrEmpty
            @($defs | Where-Object { $_.Key -eq 'x' }) | Should -BeNullOrEmpty
        }

        It '剩余动作值与文案不变' {
            $defs = @(& $script:mod { Get-TmuxActionDefinition -HasSessions $false })

            @($defs | ForEach-Object { $_.Value }) | Should -Be @('New', 'Refresh', 'Ssh', 'Quit')
            @($defs | ForEach-Object { $_.Label }) | Should -Be @('新建', '刷新', 'SSH', '退出')
        }
    }

    Context '错误上下文只切换文案 (Context = Error)' {

        It '文案变为 附着,新建,重试,直连,删除,退出' {
            $defs = @(& $script:mod { Get-TmuxActionDefinition -HasSessions $true -Context 'Error' })

            @($defs | ForEach-Object { $_.Label }) | Should -Be @('附着', '新建', '重试', '直连', '删除', '退出')
        }

        It '键位与动作值不受上下文影响' {
            $defs = @(& $script:mod { Get-TmuxActionDefinition -HasSessions $true -Context 'Error' })

            @($defs | ForEach-Object { $_.Key }) | Should -Be @('a', 'n', 'r', 's', 'x', 'q')
            @($defs | ForEach-Object { $_.Value }) | Should -Be @('Attach', 'New', 'Refresh', 'Ssh', 'Remove', 'Quit')
        }
    }

    Context '默认参数' {

        It '默认 HasSessions=$false 且 Context=Normal(与显式传参等价)' {
            $defaults = @(& $script:mod { Get-TmuxActionDefinition })
            $explicit = @(& $script:mod { Get-TmuxActionDefinition -HasSessions $false -Context 'Normal' })

            @($defaults | ForEach-Object { $_.Key }) | Should -Be @('n', 'r', 's', 'q')
            @($defaults | ForEach-Object { $_.Label }) | Should -Be @($explicit | ForEach-Object { $_.Label })
        }
    }
}
