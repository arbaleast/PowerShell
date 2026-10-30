# Get-TmuxSessions.Tests.ps1 - tmux 会话解析与刷新契约回归测试
# 覆盖:
#   1. tmux ls 人类可读输出容错解析(真实模块函数, 不再复制正则字面量)
#   2. tmux list-sessions -F 机器可读解析(会话名含空格/冒号)
#   3. 探测输出切段(版本/机器可读段/ls 段)
#   4. 优雅降级: tmux 不可用 / 输出为空 / 网络故障 / SSH 异常 均不抛异常
# 说明: 2026-10-31 死代码清理后, 状态文案/计数汇总/刷新循环/会话列表渲染层
#       (Get-TmuxSessionStateText / Get-TmuxSessionSummary / Show-TmuxSessionList /
#        Invoke-GridViewSessionList 等)已随旧双轨实现删除, 对应用例一并移除;
#       会话状态语义改由 Get-TmuxSessionState 的契约测试覆盖。

Describe 'tmux 会话解析与刷新契约' {

    BeforeAll {
        # Pester v6: 路径与模块引用必须放在 BeforeAll 内解析
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    Context 'tmux ls 容错解析 (ConvertFrom-TmuxLsOutput)' {

        It '方括号 [attached] 形态判定为 attached' {
            $line = 'btop: 1 windows (created Thu Oct 16 22:35:52 2025) [attached]'
            $r = & $script:mod { param($l) @(ConvertFrom-TmuxLsOutput -Lines @($l)) } $line

            $r.Count | Should -Be 1
            $r[0].Name | Should -Be 'btop'
            $r[0].Status | Should -Be 'attached'
            $r[0].Windows | Should -Be 1
        }

        It '无 attached 标记判定为 detached' {
            $line = 'tmux-126014: 1 windows (created Thu Oct 17 10:00:00 2025)'
            $r = & $script:mod { param($l) @(ConvertFrom-TmuxLsOutput -Lines @($l)) } $line

            $r[0].Name | Should -Be 'tmux-126014'
            $r[0].Status | Should -Be 'detached'
        }

        It '单数 window 形态可解析' {
            $line = 'single: 1 window (created Thu Oct 17 10:00:00 2025) [attached]'
            $r = & $script:mod { param($l) @(ConvertFrom-TmuxLsOutput -Lines @($l)) } $line

            $r[0].Name | Should -Be 'single'
            $r[0].Status | Should -Be 'attached'
        }

        It '会话名含空格时名称完整保留' {
            $line = 'my session: 1 windows (created Thu Oct 17 10:00:00 2025) [attached]'
            $r = & $script:mod { param($l) @(ConvertFrom-TmuxLsOutput -Lines @($l)) } $line

            $r[0].Name | Should -Be 'my session'
            $r[0].Status | Should -Be 'attached'
        }

        It '会话名含冒号时名称完整保留' {
            $line = 'a:b: 1 windows (created Thu Oct 17 10:00:00 2025)'
            $r = & $script:mod { param($l) @(ConvertFrom-TmuxLsOutput -Lines @($l)) } $line

            $r[0].Name | Should -Be 'a:b'
            $r[0].Status | Should -Be 'detached'
        }

        It '冒号后无空格的紧凑写法同样可解析' {
            $line = 'my session:1 windows (created Thu Oct 17 10:00:00 2025)'
            $r = & $script:mod { param($l) @(ConvertFrom-TmuxLsOutput -Lines @($l)) } $line

            $r[0].Name | Should -Be 'my session'
            $r[0].Status | Should -Be 'detached'
        }

        It '(attached) 括号形态判定为 attached' {
            $line = 'parenattach: 1 windows (attached)'
            $r = & $script:mod { param($l) @(ConvertFrom-TmuxLsOutput -Lines @($l)) } $line

            $r[0].Status | Should -Be 'attached'
        }

        It '缺少 (created ...) 时仍可解析并视为 detached' {
            $line = 'nocreated: 2 windows'
            $r = & $script:mod { param($l) @(ConvertFrom-TmuxLsOutput -Lines @($l)) } $line

            $r[0].Name | Should -Be 'nocreated'
            $r[0].Status | Should -Be 'detached'
            $r[0].Windows | Should -Be 2
        }

        It '大写 WINDOWS / ATTACHED 也能正确判定(大小写不敏感)' {
            $line = 'UPPER: 1 WINDOWS (created Thu Oct 17 10:00:00 2025) [ATTACHED]'
            $r = & $script:mod { param($l) @(ConvertFrom-TmuxLsOutput -Lines @($l)) } $line

            $r[0].Name | Should -Be 'UPPER'
            $r[0].Status | Should -Be 'attached'
        }

        It '附加尾部字段不影响 attached 判定' {
            $line = 'extra: 2 windows (created Thu Oct 17 10:00:00 2025) [attached] (grouped)'
            $r = & $script:mod { param($l) @(ConvertFrom-TmuxLsOutput -Lines @($l)) } $line

            $r[0].Name | Should -Be 'extra'
            $r[0].Status | Should -Be 'attached'
        }

        It '无法识别的行被跳过(不抛异常, 不产生脏会话)' {
            $r = & $script:mod { @(ConvertFrom-TmuxLsOutput -Lines @('no windows here', '', '   ')) }

            $r.Count | Should -Be 0
        }

        It '空输入返回空集合' {
            $r = & $script:mod { @(ConvertFrom-TmuxLsOutput -Lines @()) }

            $r.Count | Should -Be 0
        }
    }

    Context 'list-sessions -F 机器可读解析 (ConvertFrom-TmuxSessionFormat)' {

        It 'attached 客户端数大于 0 判定为 attached' {
            $r = & $script:mod { @(ConvertFrom-TmuxSessionFormat -Lines @('TMUX_SESSION 1 2 btop')) }

            $r[0].Name | Should -Be 'btop'
            $r[0].Status | Should -Be 'attached'
            $r[0].Windows | Should -Be 2
        }

        It 'attached 客户端数为 0 判定为 detached' {
            $r = & $script:mod { @(ConvertFrom-TmuxSessionFormat -Lines @('TMUX_SESSION 0 1 other')) }

            $r[0].Status | Should -Be 'detached'
        }

        It '会话名含空格与冒号时完整保留(名称位于字段末尾)' {
            $r = & $script:mod { @(ConvertFrom-TmuxSessionFormat -Lines @('TMUX_SESSION 1 1 my session:1')) }

            $r[0].Name | Should -Be 'my session:1'
            $r[0].Status | Should -Be 'attached'
        }

        It '非法行被跳过' {
            $r = & $script:mod { @(ConvertFrom-TmuxSessionFormat -Lines @('garbage line', 'TMUX_SESSION x y z')) }

            $r.Count | Should -Be 0
        }
    }

    Context '探测输出切段 (ConvertFrom-TmuxProbeOutput)' {

        It '正确切分版本段/机器可读段/ls 段' {
            $raw = @(
                'TMUX_VERSION=tmux 3.3a'
                'TMUX_SESSIONS_BEGIN'
                'TMUX_SESSION 1 2 btop'
                'TMUX_SESSIONS_END'
                'btop: 1 windows (created Thu Oct 16 22:35:52 2025) [attached]'
            ) -join "`n"

            $p = & $script:mod { param($r) ConvertFrom-TmuxProbeOutput -Output $r } $raw

            $p.Version | Should -Be '3.3a'
            $p.SessionLines.Count | Should -Be 1
            $p.LsLines.Count | Should -Be 1
        }

        It '空输出返回空集合且版本为空' {
            $p = & $script:mod { ConvertFrom-TmuxProbeOutput -Output '' }

            $p.Version | Should -Be ''
            $p.SessionLines.Count | Should -Be 0
            $p.LsLines.Count | Should -Be 0
        }

        It '缺少标记行时按顺序容错切段' {
            $raw = 'btop: 1 windows (created Thu Oct 16 22:35:52 2025) [attached]'
            $p = & $script:mod { param($r) ConvertFrom-TmuxProbeOutput -Output $r } $raw

            $p.LsLines.Count | Should -Be 0
            $p.SessionLines.Count | Should -Be 0
        }
    }

    Context '优雅降级 (Get-TmuxSessions)' {

        It '远端无 tmux 时返回空集合且不抛异常' {
            Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
                [PSCustomObject]@{ Output = ''; Error = 'bash: tmux: command not found'; ExitCode = 127 }
            }

            $r = & $script:mod { Get-TmuxSessions -HostName 'mock-no-tmux' -Force }

            $r.Sessions.Count | Should -Be 0
            $r.Version | Should -Be ''
        }

        It 'SSH 输出为空时返回空集合' {
            Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
                [PSCustomObject]@{ Output = ''; Error = ''; ExitCode = 0 }
            }

            $r = & $script:mod { Get-TmuxSessions -HostName 'mock-empty-out' -Force }

            $r.Sessions.Count | Should -Be 0
        }

        It '网络故障时返回空集合且不冒泡' {
            Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
                [PSCustomObject]@{
                    Output   = ''
                    Error    = 'ssh: connect to host mock-host port 22: Connection refused'
                    ExitCode = 255
                }
            }

            $r = & $script:mod { Get-TmuxSessions -HostName 'mock-net-err' -Force }

            $r.Sessions.Count | Should -Be 0
        }

        It 'SSH 调用抛异常时降级为空集合(不冒泡)' {
            Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith { throw 'ssh.exe not found' }

            $r = & $script:mod { Get-TmuxSessions -HostName 'mock-throw' -Force }

            $r.Sessions.Count | Should -Be 0
        }

        It '机器可读段有数据时走主路径并正确判定状态' {
            $raw = @(
                'TMUX_VERSION=tmux 3.3a'
                'TMUX_SESSIONS_BEGIN'
                'TMUX_SESSION 1 2 btop'
                'TMUX_SESSION 0 1 idle'
                'TMUX_SESSIONS_END'
                'btop: 1 windows (created Thu Oct 16 22:35:52 2025) [attached]'
            ) -join "`n"

            Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
                [PSCustomObject]@{ Output = $raw; Error = ''; ExitCode = 0 }
            }

            $r = & $script:mod { Get-TmuxSessions -HostName 'mock-machine' -Force }

            $r.Sessions.Count | Should -Be 2
            ($r.Sessions | Where-Object { $_.Name -eq 'btop' }).Status | Should -Be 'attached'
            ($r.Sessions | Where-Object { $_.Name -eq 'idle' }).Status | Should -Be 'detached'
            $r.Version | Should -Be '3.3a'
        }

        It '机器可读段为空时回退 tmux ls 容错解析' {
            $raw = @(
                'TMUX_VERSION=tmux 3.3a'
                'TMUX_SESSIONS_BEGIN'
                'TMUX_SESSIONS_END'
                'btop: 1 windows (created Thu Oct 16 22:35:52 2025) [attached]'
                'idle: 1 windows (created Thu Oct 17 10:00:00 2025)'
            ) -join "`n"

            Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
                [PSCustomObject]@{ Output = $raw; Error = ''; ExitCode = 0 }
            }

            $r = & $script:mod { Get-TmuxSessions -HostName 'mock-ls-fallback' -Force }

            $r.Sessions.Count | Should -Be 2
            ($r.Sessions | Where-Object { $_.Name -eq 'btop' }).Status | Should -Be 'attached'
            ($r.Sessions | Where-Object { $_.Name -eq 'idle' }).Status | Should -Be 'detached'
        }

        It 'TTL 缓存生效: 第二次调用不重复发起 SSH' {
            Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
                [PSCustomObject]@{ Output = 'TMUX_VERSION=tmux 3.3a'; Error = ''; ExitCode = 0 }
            }

            & $script:mod { Get-TmuxSessions -HostName 'mock-cache' } | Out-Null
            & $script:mod { Get-TmuxSessions -HostName 'mock-cache' } | Out-Null

            Should -Invoke -CommandName Invoke-SshCommand -ModuleName ShellPrompt -Exactly 1
        }

        It '-Force 强制跳过 TTL 缓存重新探测' {
            Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
                [PSCustomObject]@{ Output = 'TMUX_VERSION=tmux 3.3a'; Error = ''; ExitCode = 0 }
            }

            & $script:mod { Get-TmuxSessions -HostName 'mock-force' } | Out-Null
            & $script:mod { Get-TmuxSessions -HostName 'mock-force' -Force } | Out-Null

            Should -Invoke -CommandName Invoke-SshCommand -ModuleName ShellPrompt -Exactly 2
        }
    }

}
