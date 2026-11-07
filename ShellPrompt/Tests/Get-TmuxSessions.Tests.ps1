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

    Context '合并探测: 窗口拓扑解析 (ConvertFrom-TmuxWindowFormat)' {

        It '解析会话头 / 窗口行 / 分屏行, 并把活动分屏的命令与路径挂到窗口上' {
            $lines = @(
                'TMUX_WSESSION work'
                'TMUX_WINDOW 0 1 2 main'
                'TMUX_PANE 0 0 1 vim /home/debian/work/hermes'
                'TMUX_PANE 0 1 0 bash /tmp'
                'TMUX_WSESSION other:1'
                'TMUX_WINDOW 0 1 1 logs'
                'TMUX_PANE 0 0 1 tail /var/log'
            )

            $r = & $script:mod { param($l) @(ConvertFrom-TmuxWindowFormat -Lines $l) } $lines

            $r.Count | Should -Be 2
            $r[0].Session | Should -Be 'work'
            $r[0].Index | Should -Be 0
            $r[0].Name | Should -Be 'main'
            $r[0].Active | Should -BeTrue
            $r[0].Panes | Should -Be 2
            $r[0].Command | Should -Be 'vim'
            $r[0].Path | Should -Be '/home/debian/work/hermes'
            # 会话名含冒号时也完整保留(会话名来自独立的 WSESSION 头行)
            $r[1].Session | Should -Be 'other:1'
            $r[1].Command | Should -Be 'tail'
        }

        It '窗口名含空格时完整保留' {
            $r = & $script:mod {
                @(ConvertFrom-TmuxWindowFormat -Lines @(
                        'TMUX_WSESSION my session'
                        'TMUX_WINDOW 2 0 1 my window name'
                    ))
            }

            $r[0].Name | Should -Be 'my window name'
            $r[0].Session | Should -Be 'my session'
        }

        It '路径含空格时完整保留(末尾字段吃掉剩余全部)' {
            $r = & $script:mod {
                @(ConvertFrom-TmuxWindowFormat -Lines @(
                        'TMUX_WSESSION work'
                        'TMUX_WINDOW 0 1 1 main'
                        'TMUX_PANE 0 0 1 vim /home/debian/My Documents'
                    ))
            }

            $r[0].Path | Should -Be '/home/debian/My Documents'
            $r[0].Command | Should -Be 'vim'
        }

        It '畸形行被跳过且不抛异常' {
            $r = & $script:mod {
                @(ConvertFrom-TmuxWindowFormat -Lines @(
                        'garbage'
                        'TMUX_WSESSION work'
                        'TMUX_WINDOW x y z name'
                        'TMUX_PANE bad bad bad'
                    ))
            }

            $r.Count | Should -Be 0
        }

        It '空输入返回空集合' {
            $r = & $script:mod { @(ConvertFrom-TmuxWindowFormat -Lines @()) }

            $r.Count | Should -Be 0
        }
    }

    Context '合并探测: 预览快照解析 (ConvertFrom-TmuxPreviewFormat)' {

        It '按会话分组返回预览行' {
            $lines = @(
                'TMUX_PREVSESSION work'
                'TMUX_PREVIEW $ ls -la'
                'TMUX_PREVIEW total 12'
                'TMUX_PREVSESSION other'
                'TMUX_PREVIEW top'
            )

            $r = & $script:mod { param($l) @(ConvertFrom-TmuxPreviewFormat -Lines $l) } $lines

            $r.Count | Should -Be 2
            $r[0].Session | Should -Be 'work'
            $r[0].Lines.Count | Should -Be 2
            $r[0].Lines[0] | Should -Be '$ ls -la'
            $r[1].Session | Should -Be 'other'
            $r[1].Lines[0] | Should -Be 'top'
        }

        It '会话名含空格时完整保留' {
            $r = & $script:mod {
                @(ConvertFrom-TmuxPreviewFormat -Lines @(
                        'TMUX_PREVSESSION my session'
                        'TMUX_PREVIEW hello'
                    ))
            }

            $r[0].Session | Should -Be 'my session'
            $r[0].Lines[0] | Should -Be 'hello'
        }

        It '畸形/无会话头的行被忽略(不抛异常)' {
            $r = & $script:mod {
                @(ConvertFrom-TmuxPreviewFormat -Lines @('garbage', 'TMUX_PREVIEW orphan'))
            }

            $r.Count | Should -Be 0
        }
    }

    Context '合并探测: 会话行的创建/活动时间戳' {

        It '解析 created/activity 时间戳' {
            $r = & $script:mod {
                @(ConvertFrom-TmuxSessionFormat -Lines @('TMUX_SESSION 1 2 1700000000 1700000900 work'))
            }

            $r[0].Name | Should -Be 'work'
            $r[0].Created | Should -Be 1700000000
            $r[0].Activity | Should -Be 1700000900
        }

        It '旧三字段格式仍可解析, 时间戳按未知(0)处理' {
            $r = & $script:mod {
                @(ConvertFrom-TmuxSessionFormat -Lines @('TMUX_SESSION 1 2 work'))
            }

            $r[0].Name | Should -Be 'work'
            $r[0].Created | Should -Be 0
            $r[0].Activity | Should -Be 0
        }
    }

    Context '合并探测: 切段与旧 tmux 容错 (ConvertFrom-TmuxProbeOutput)' {

        It '切分版本/HOME/会话/窗口/预览/ls 六个段' {
            $raw = @(
                'TMUX_VERSION=tmux 3.3a'
                'TMUX_HOME=/home/debian'
                'TMUX_SESSIONS_BEGIN'
                'TMUX_SESSION 1 2 1700000000 1700000900 work'
                'TMUX_SESSIONS_END'
                'TMUX_WINDOWS_BEGIN'
                'TMUX_WSESSION work'
                'TMUX_WINDOW 0 1 1 main'
                'TMUX_WINDOWS_END'
                'TMUX_PREVIEW_BEGIN'
                'TMUX_PREVSESSION work'
                'TMUX_PREVIEW hello'
                'TMUX_PREVIEW_END'
                'work: 2 windows (created Thu Oct 16 22:35:52 2025) [attached]'
            ) -join "`n"

            $p = & $script:mod { param($r) ConvertFrom-TmuxProbeOutput -Output $r } $raw

            $p.Version | Should -Be '3.3a'
            $p.HomePath | Should -Be '/home/debian'
            $p.SessionLines.Count | Should -Be 1
            $p.WindowLines.Count | Should -Be 2
            $p.PreviewLines.Count | Should -Be 2
            $p.LsLines.Count | Should -Be 1
        }

        It '老 tmux(只有会话段与 ls 段)也能切分, 窗口/预览段为空' {
            $raw = @(
                'TMUX_VERSION=tmux 2.3'
                'TMUX_SESSIONS_BEGIN'
                'TMUX_SESSION 1 2 work'
                'TMUX_SESSIONS_END'
                'work: 2 windows (created Thu Oct 16 22:35:52 2025) [attached]'
            ) -join "`n"

            $p = & $script:mod { param($r) ConvertFrom-TmuxProbeOutput -Output $r } $raw

            $p.Version | Should -Be '2.3'
            $p.SessionLines.Count | Should -Be 1
            $p.WindowLines.Count | Should -Be 0
            $p.PreviewLines.Count | Should -Be 0
            $p.LsLines.Count | Should -Be 1
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

        It '合并查询: 窗口拓扑/预览/HOME 全部来自同一次 SSH 并挂到会话上' {
            $raw = @(
                'TMUX_VERSION=tmux 3.3a'
                'TMUX_HOME=/home/debian'
                'TMUX_SESSIONS_BEGIN'
                'TMUX_SESSION 1 2 1700000000 1700000900 work'
                'TMUX_SESSIONS_END'
                'TMUX_WINDOWS_BEGIN'
                'TMUX_WSESSION work'
                'TMUX_WINDOW 0 1 2 main'
                'TMUX_PANE 0 0 1 vim /home/debian/work/hermes'
                'TMUX_WINDOWS_END'
                'TMUX_PREVIEW_BEGIN'
                'TMUX_PREVSESSION work'
                'TMUX_PREVIEW $ ls'
                'TMUX_PREVIEW total 3'
                'TMUX_PREVIEW_END'
                'work: 2 windows (created Thu Oct 16 22:35:52 2025) [attached]'
            ) -join "`n"

            Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
                [PSCustomObject]@{ Output = $raw; Error = ''; ExitCode = 0 }
            }

            $r = & $script:mod { Get-TmuxSessions -HostName 'mock-merged' -Force }

            # 零额外往返: 整轮只发一次 SSH
            Should -Invoke -CommandName Invoke-SshCommand -ModuleName ShellPrompt -Exactly 1

            $r.Sessions.Count | Should -Be 1
            $session = $r.Sessions[0]
            $session.Name | Should -Be 'work'
            $session.Created | Should -Be 1700000000
            $session.Activity | Should -Be 1700000900
            $session.HomePath | Should -Be '/home/debian'
            $session.WindowList.Count | Should -Be 1
            $session.WindowList[0].Name | Should -Be 'main'
            $session.WindowList[0].Command | Should -Be 'vim'
            $session.WindowList[0].Path | Should -Be '/home/debian/work/hermes'
            $session.PreviewLines.Count | Should -Be 2
            $session.PreviewLines[0] | Should -Be '$ ls'

            # 顶层也暴露窗口/预览集合与 HOME(供上层直接取用)
            $r.HomePath | Should -Be '/home/debian'
            $r.Windows.Count | Should -Be 1
            $r.Previews.Count | Should -Be 1
        }

        It '老 tmux: 窗口/预览段缺失时优雅降级(会话仍解析, 附加字段为空)' {
            $raw = @(
                'TMUX_VERSION=tmux 2.3'
                'TMUX_SESSIONS_BEGIN'
                'TMUX_SESSION 1 2 work'
                'TMUX_SESSIONS_END'
                'work: 2 windows (created Thu Oct 16 22:35:52 2025) [attached]'
            ) -join "`n"

            Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
                [PSCustomObject]@{ Output = $raw; Error = ''; ExitCode = 0 }
            }

            $r = & $script:mod { Get-TmuxSessions -HostName 'mock-old-tmux' -Force }

            $r.Sessions.Count | Should -Be 1
            $r.Sessions[0].WindowList.Count | Should -Be 0
            $r.Sessions[0].PreviewLines.Count | Should -Be 0
            $r.Sessions[0].Created | Should -Be 0
            $r.Windows.Count | Should -Be 0
            $r.Previews.Count | Should -Be 0
        }

        It 'ls 回退路径的会话同样带空窗口/预览字段(不抛异常)' {
            $raw = @(
                'TMUX_VERSION=tmux 1.8'
                'TMUX_SESSIONS_BEGIN'
                'TMUX_SESSIONS_END'
                'btop: 1 windows (created Thu Oct 16 22:35:52 2025) [attached]'
            ) -join "`n"

            Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
                [PSCustomObject]@{ Output = $raw; Error = ''; ExitCode = 0 }
            }

            $r = & $script:mod { Get-TmuxSessions -HostName 'mock-ls-extra' -Force }

            $r.Sessions.Count | Should -Be 1
            $r.Sessions[0].WindowList.Count | Should -Be 0
            $r.Sessions[0].PreviewLines.Count | Should -Be 0
            $r.Sessions[0].Created | Should -Be 0
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
