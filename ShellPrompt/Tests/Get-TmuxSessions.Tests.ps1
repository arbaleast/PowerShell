# Get-TmuxSessions.Tests.ps1 - tmux 会话解析与刷新契约回归测试
# 覆盖:
#   1. tmux ls 人类可读输出容错解析(真实模块函数, 不再复制正则字面量)
#   2. tmux list-sessions -F 机器可读解析(会话名含空格/冒号)
#   3. 探测输出切段(版本/机器可读段/ls 段)
#   4. 优雅降级: tmux 不可用 / 输出为空 / 网络故障 / SSH 异常 均不抛异常
#   5. 状态文案与附/分计数(双轨共用的唯一事实源)
#   6. 刷新契约(哨兵值 + Show-TmuxSessionList 刷新循环 + GridView/ANSI 两轨一致)

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

    Context '状态文案与附/分计数 (双轨共用的唯一事实源)' {

        It 'attached 显示为 ● 已附着' {
            $text = & $script:mod { Get-TmuxSessionStateText -Status 'attached' }

            $text | Should -Be '● 已附着'
        }

        It 'detached 显示为 ○ 已分离' {
            $text = & $script:mod { Get-TmuxSessionStateText -Status 'detached' }

            $text | Should -Be '○ 已分离'
        }

        It '空状态按 detached 处理' {
            $text = & $script:mod { Get-TmuxSessionStateText -Status '' }

            $text | Should -Be '○ 已分离'
        }

        It '附/分计数与标题后缀正确' {
            $sessions = @(
                [PSCustomObject]@{ Name = 'btop'; Status = 'attached' }
                [PSCustomObject]@{ Name = 'idle'; Status = 'detached' }
                [PSCustomObject]@{ Name = 'work'; Status = 'detached' }
            )

            $summary = & $script:mod { param($s) Get-TmuxSessionSummary -Sessions $s } $sessions

            $summary.Total | Should -Be 3
            $summary.Attached | Should -Be 1
            $summary.Detached | Should -Be 2
            $summary.TitleSuffix | Should -Be '会话 3 附 1 / 分 2'
        }

        It '空会话集合计数为 0(不出现"附 0"误报)' {
            $summary = & $script:mod { Get-TmuxSessionSummary -Sessions @() }

            $summary.Total | Should -Be 0
            $summary.Attached | Should -Be 0
            $summary.Detached | Should -Be 0
        }
    }

    Context '刷新契约 (哨兵值 + 刷新循环)' {

        It '刷新选择对象带 IsRefresh = $true 与哨兵 Value' {
            $sel = & $script:mod { ConvertTo-TmuxRefreshSelection }

            $sel.IsRefresh | Should -Be $true
            $sel.Value | Should -Be '__tmux_refresh__'
            $sel.Label | Should -Match '刷新'
        }

        It '普通会话选择对象 IsRefresh = $false 且 Value 为纯会话名' {
            $sel = & $script:mod { ConvertTo-TmuxSessionSelection -Name 'btop' -Status 'attached' }

            $sel.IsRefresh | Should -Be $false
            $sel.Value | Should -Be 'btop'
            $sel.RawName | Should -Be 'btop'
            $sel.Status | Should -Be 'attached'
            $sel.Desc | Should -Match 'attached'
        }

        It '选中刷新后重新拉取会话并重新弹出视图, 最终返回用户选中的会话' {
            Mock -CommandName Assert-ConsoleUiReady -ModuleName ShellPrompt -MockWith { }

            # 视图渲染计数: 第一次返回"刷新"哨兵, 第二次返回用户真正选中的会话
            $script:tmuxViewCallCount = 0
            Mock -CommandName Invoke-TmuxSessionListView -ModuleName ShellPrompt -MockWith {
                $script:tmuxViewCallCount++
                if ($script:tmuxViewCallCount -eq 1) {
                    return (& $script:mod { ConvertTo-TmuxRefreshSelection })
                }
                return (& $script:mod { ConvertTo-TmuxSessionSelection -Name 'fresh' -Status 'attached' })
            }

            $sessions = @([PSCustomObject]@{ Name = 'stale'; Status = 'detached' })
            $refresher = {
                return @([PSCustomObject]@{ Name = 'fresh'; Status = 'attached' })
            }

            $sel = & $script:mod {
                param($s, $r)
                Show-TmuxSessionList -HostName 'mock-host' -Sessions $s -SessionRefresher $r
            } $sessions $refresher

            $sel.Value | Should -Be 'fresh'
            $sel.IsRefresh | Should -Be $false
            # 视图被渲染两次(刷新前 + 刷新后), GridView 每帧独立弹窗, 无需清屏重绘
            $script:tmuxViewCallCount | Should -Be 2
        }

        It '刷新后无任何会话时返回 $null 并给出告警(不抛异常)' {
            Mock -CommandName Assert-ConsoleUiReady -ModuleName ShellPrompt -MockWith { }
            Mock -CommandName Invoke-TmuxSessionListView -ModuleName ShellPrompt -MockWith {
                return (& $script:mod { ConvertTo-TmuxRefreshSelection })
            }

            $sessions = @([PSCustomObject]@{ Name = 'stale'; Status = 'detached' })
            $refresher = { return @() }

            $sel = & $script:mod {
                param($s, $r)
                Show-TmuxSessionList -HostName 'mock-host' -Sessions $s -SessionRefresher $r -WarningAction SilentlyContinue
            } $sessions $refresher

            $sel | Should -BeNullOrEmpty
        }

        It '初始会话为空时直接返回 $null 并告警' {
            Mock -CommandName Invoke-TmuxSessionListView -ModuleName ShellPrompt -MockWith { throw '不应被调用' }

            $sel = & $script:mod {
                Show-TmuxSessionList -HostName 'mock-host' -Sessions @() -WarningAction SilentlyContinue
            }

            $sel | Should -BeNullOrEmpty
            Should -Invoke -CommandName Invoke-TmuxSessionListView -ModuleName ShellPrompt -Exactly 0
        }
    }

    Context 'GridView 主轨语义' {

        It 'GridView 轨: -AllowRefresh 时追加刷新行, 且不追加时没有刷新行' {
            Mock -CommandName Invoke-GridViewPrompt -ModuleName ShellPrompt -MockWith { return $null }

            $sessions = @(
                [PSCustomObject]@{ Name = 'btop'; Status = 'attached' }
                [PSCustomObject]@{ Name = 'idle'; Status = 'detached' }
            )

            & $script:mod {
                param($s)
                Invoke-GridViewSessionList -Sessions $s -HostName 'mock-host' -Title 'TMUX 会话列表' `
                    -ShowStateBadge -AllowRefresh | Out-Null
            } $sessions

            Should -Invoke -CommandName Invoke-GridViewPrompt -ModuleName ShellPrompt -Exactly 1 `
                -ParameterFilter { $Rows.Session -contains '⟳ 刷新会话列表' }
        }

        It 'GridView 轨: 不带 -AllowRefresh 时不存在刷新行' {
            Mock -CommandName Invoke-GridViewPrompt -ModuleName ShellPrompt -MockWith { return $null }

            $sessions = @([PSCustomObject]@{ Name = 'btop'; Status = 'attached' })

            & $script:mod {
                param($s)
                Invoke-GridViewSessionList -Sessions $s -HostName 'mock-host' -Title 'TMUX 会话列表' -ShowStateBadge | Out-Null
            } $sessions

            Should -Invoke -CommandName Invoke-GridViewPrompt -ModuleName ShellPrompt -Exactly 1 `
                -ParameterFilter { $Rows.Session -notcontains '⟳ 刷新会话列表' }
        }

        It 'GridView 轨: State 列文案为 ● 已附着 / ○ 已分离' {
            Mock -CommandName Invoke-GridViewPrompt -ModuleName ShellPrompt -MockWith { return $null }

            $sessions = @(
                [PSCustomObject]@{ Name = 'btop'; Status = 'attached' }
                [PSCustomObject]@{ Name = 'idle'; Status = 'detached' }
            )

            & $script:mod {
                param($s)
                Invoke-GridViewSessionList -Sessions $s -HostName 'mock-host' -Title 'TMUX 会话列表' -ShowStateBadge | Out-Null
            } $sessions

            Should -Invoke -CommandName Invoke-GridViewPrompt -ModuleName ShellPrompt -Exactly 1 `
                -ParameterFilter {
                ($Rows | Where-Object { $_.Session -eq 'btop' }).State -eq '● 已附着' -and
                ($Rows | Where-Object { $_.Session -eq 'idle' }).State -eq '○ 已分离'
            }
        }

        It 'GridView 轨: 标题包含附/分计数' {
            Mock -CommandName Invoke-GridViewPrompt -ModuleName ShellPrompt -MockWith { return $null }

            $sessions = @(
                [PSCustomObject]@{ Name = 'btop'; Status = 'attached' }
                [PSCustomObject]@{ Name = 'idle'; Status = 'detached' }
            )

            & $script:mod {
                param($s)
                Invoke-GridViewSessionList -Sessions $s -HostName 'mock-host' -Title 'TMUX 会话列表' -ShowStateBadge | Out-Null
            } $sessions

            Should -Invoke -CommandName Invoke-GridViewPrompt -ModuleName ShellPrompt -Exactly 1 `
                -ParameterFilter { $Title -match '附 1' -and $Title -match '分 1' }
        }

        It '单帧视图: 刷新项存在且状态文案与表格行一致' {
            Mock -CommandName Invoke-GridViewPrompt -ModuleName ShellPrompt -MockWith { return $null }

            $sessions = @(
                [PSCustomObject]@{ Name = 'btop'; Status = 'attached' }
                [PSCustomObject]@{ Name = 'idle'; Status = 'detached' }
            )

            & $script:mod {
                param($s)
                Invoke-TmuxSessionListView -Sessions $s -HostName 'mock-host' -Title 'TMUX 会话列表' `
                    -ShowStateBadge -AllowRefresh | Out-Null
            } $sessions

            Should -Invoke -CommandName Invoke-GridViewPrompt -ModuleName ShellPrompt -Exactly 1 `
                -ParameterFilter {
                $Rows.Session -contains '⟳ 刷新会话列表' -and
                ($Rows | Where-Object { $_.Session -eq 'btop' }).State -eq '● 已附着' -and
                ($Rows | Where-Object { $_.Session -eq 'idle' }).State -eq '○ 已分离'
            }
        }

        It '单帧视图: 标题包含附/分计数' {
            Mock -CommandName Invoke-GridViewPrompt -ModuleName ShellPrompt -MockWith { return $null }

            $sessions = @(
                [PSCustomObject]@{ Name = 'btop'; Status = 'attached' }
                [PSCustomObject]@{ Name = 'idle'; Status = 'detached' }
            )

            & $script:mod {
                param($s)
                Invoke-TmuxSessionListView -Sessions $s -HostName 'mock-host' -Title 'TMUX 会话列表' `
                    -ShowStateBadge -AllowRefresh | Out-Null
            } $sessions

            Should -Invoke -CommandName Invoke-GridViewPrompt -ModuleName ShellPrompt -Exactly 1 `
                -ParameterFilter { $Title -match '附 1' -and $Title -match '分 1' }
        }
    }
}
