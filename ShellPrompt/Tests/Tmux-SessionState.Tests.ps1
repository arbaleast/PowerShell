# Tmux-SessionState.Tests.ps1 - tmux 会话状态一致性审计回归测试 (2026-10-29)
# 覆盖:
#   1. Get-TmuxSessions 契约扩展: "查询失败" vs "查询成功但没有会话" 可区分
#      (Available / Error / ExitCode / NetworkError 四个新键, 只追加不改旧键)
#   2. Show-TmuxSessionList 刷新循环:
#      - 刷新后列表顺序变化时, 行序保持稳定(Merge-TmuxSessionOrder);
#      - 刷新后原会话消失时给出明确警告;
#      - 刷新脚本块 throw 时保留原列表并警告(不折叠成"没有会话", 可重试)。
#   3. Merge-TmuxSessionOrder 合并规则(纯函数契约)。
#   4. Remove-TmuxSession: 二次确认的取消/抛异常/确认路径(kill-session 只在确认后发出);
#      刷新脚本块的失败判定口径(退出码非 0 或网络错误 -> 抛出, 由列表层恢复)。
#   5. Restore-GridViewSelection: 会话名作为键列时的隐藏字段恢复(含重名现状锁定)。
# 说明: 全部用 Mock 隔离真实 ssh / tmux, 不代表真实终端环境验证通过。

Describe 'tmux 会话状态一致性审计 (2026-10-29)' {

    BeforeAll {
        # Pester v6: 路径与模块引用必须放在 BeforeAll 内解析
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    Context 'Get-TmuxSessions: 查询失败 vs 查询成功但没有会话' {

        BeforeEach {
            Mock -CommandName Write-Warning -ModuleName ShellPrompt -MockWith { }
            Mock -CommandName Write-Host -ModuleName ShellPrompt -MockWith { }
        }

        It 'SSH 连接失败时 Available=$false 且 NetworkError=$true, Sessions 为空' {
            Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
                [PSCustomObject]@{
                    Output   = ''
                    Error    = 'ssh: connect to host mock-audit-net port 22: Connection refused'
                    ExitCode = 255
                }
            }

            $r = & $script:mod { Get-TmuxSessions -HostName 'mock-audit-net' -Force }

            # 关键契约: 失败信息随返回值携带, 调用方无需再靠"Sessions 为空"推断
            $r.Available | Should -BeFalse
            $r.NetworkError | Should -BeTrue
            $r.ExitCode | Should -Be 255
            $r.Sessions.Count | Should -Be 0
        }

        It '探测成功但远端没有任何会话时 Available=$true 且 Sessions 为空' {
            Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
                [PSCustomObject]@{
                    Output   = "TMUX_VERSION=3.4`nTMUX_SESSIONS_BEGIN`nTMUX_SESSIONS_END`n"
                    Error    = ''
                    ExitCode = 0
                }
            }

            $r = & $script:mod { Get-TmuxSessions -HostName 'mock-audit-empty' -Force }

            $r.Available | Should -BeTrue
            $r.NetworkError | Should -BeFalse
            $r.Version | Should -Be '3.4'
            $r.Sessions.Count | Should -Be 0
        }

        It '远端无 tmux 时 Available=$false 且保留 stderr 原文(区分于"没有会话")' {
            Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
                [PSCustomObject]@{
                    Output   = "TMUX_VERSION=`nTMUX_SESSIONS_BEGIN`nTMUX_SESSIONS_END`n"
                    Error    = 'bash: tmux: command not found'
                    ExitCode = 127
                }
            }

            $r = & $script:mod { Get-TmuxSessions -HostName 'mock-audit-notmux' -Force }

            $r.Available | Should -BeFalse
            $r.Version | Should -Be ''
            $r.Error | Should -Match 'command not found'
            $r.Sessions.Count | Should -Be 0
        }

        It '探测成功且有会话时新旧键共存(旧键行为不变)' {
            Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
                [PSCustomObject]@{
                    Output   = ("TMUX_VERSION=3.4`nTMUX_SESSIONS_BEGIN`n" +
                        "TMUX_SESSION 0 1 alpha`nTMUX_SESSION 1 2 beta`nTMUX_SESSIONS_END`n")
                    Error    = ''
                    ExitCode = 0
                }
            }

            $r = & $script:mod { Get-TmuxSessions -HostName 'mock-audit-has' -Force }

            # 旧键: Sessions / RawOutput / Version 语义不变
            $r.Sessions.Count | Should -Be 2
            $r.Sessions[0].Name | Should -Be 'alpha'
            $r.Version | Should -Be '3.4'
            # 新键: 同一次探测的结果
            $r.Available | Should -BeTrue
            $r.ExitCode | Should -Be 0
            $r.NetworkError | Should -BeFalse
        }
    }

    Context 'Merge-TmuxSessionOrder: 刷新前后行序稳定的合并规则' {

        It '幸存会话保持原相对顺序, 新会话按刷新顺序追加末尾' {
            $prev = @(
                [PSCustomObject]@{ Name = 'a'; Status = 'detached' },
                [PSCustomObject]@{ Name = 'b'; Status = 'detached' },
                [PSCustomObject]@{ Name = 'c'; Status = 'attached' }
            )
            # 刷新结果顺序完全打乱, 且多了一个新会话 x
            $refreshed = @(
                [PSCustomObject]@{ Name = 'c'; Status = 'detached' },
                [PSCustomObject]@{ Name = 'x'; Status = 'detached' },
                [PSCustomObject]@{ Name = 'b'; Status = 'attached' }
            )

            $merged = & $script:mod {
                param($p, $r)
                Merge-TmuxSessionOrder -Previous $p -Refreshed $r
            } $prev $refreshed

            @($merged | ForEach-Object { $_.Name }) | Should -Be @('b', 'c', 'x')
        }

        It '原列表全部消失时只剩新会话' {
            $prev = @([PSCustomObject]@{ Name = 'gone'; Status = 'detached' })
            $refreshed = @(
                [PSCustomObject]@{ Name = 'n1'; Status = 'detached' },
                [PSCustomObject]@{ Name = 'n2'; Status = 'detached' }
            )

            $merged = & $script:mod {
                param($p, $r)
                Merge-TmuxSessionOrder -Previous $p -Refreshed $r
            } $prev $refreshed

            @($merged | ForEach-Object { $_.Name }) | Should -Be @('n1', 'n2')
        }

        It 'Previous 为空时原样返回刷新结果(不抛异常)' {
            $refreshed = @([PSCustomObject]@{ Name = 'solo'; Status = 'detached' })

            $merged = & $script:mod {
                param($r)
                Merge-TmuxSessionOrder -Refreshed $r
            } $refreshed

            @($merged | ForEach-Object { $_.Name }) | Should -Be @('solo')
        }

        It '会话名匹配区分大小写(-ceq): 大小写变体视为不同会话' {
            $prev = @([PSCustomObject]@{ Name = 'Foo'; Status = 'attached' })
            $refreshed = @([PSCustomObject]@{ Name = 'foo'; Status = 'detached' })

            $merged = & $script:mod {
                param($p, $r)
                Merge-TmuxSessionOrder -Previous $p -Refreshed $r
            } $prev $refreshed

            @($merged | ForEach-Object { $_.Name }) | Should -Be @('foo')
        }
    }

    Context 'Show-TmuxSessionList: 刷新循环的行序稳定与失败反馈' {

        BeforeEach {
            Mock -CommandName Assert-ConsoleUiReady -ModuleName ShellPrompt -MockWith { }
            Mock -CommandName Write-Host -ModuleName ShellPrompt -MockWith { }
            Mock -CommandName Write-Warning -ModuleName ShellPrompt -MockWith { }
        }

        It '刷新后顺序变化时第一行仍是原第一行会话(行位置稳定)' {
            # 视图渲染计数: 第一次返回"刷新"哨兵, 第二次捕获传入的行序并返回选中
            $script:auditViewCalls = 0
            $script:auditCapturedNames = $null
            Mock -CommandName Invoke-TmuxSessionListView -ModuleName ShellPrompt -MockWith {
                $script:auditViewCalls++
                if ($script:auditViewCalls -eq 1) {
                    return (& $script:mod { ConvertTo-TmuxRefreshSelection })
                }
                $script:auditCapturedNames = @($Sessions | ForEach-Object { [string]$_.Name })
                return (& $script:mod { ConvertTo-TmuxSessionSelection -Name 'alpha' -Status 'detached' })
            }

            $sessions = @(
                [PSCustomObject]@{ Name = 'alpha'; Status = 'detached' },
                [PSCustomObject]@{ Name = 'beta'; Status = 'attached' }
            )
            # 刷新结果顺序与展示顺序相反(模拟远端列表顺序变化)
            $refresher = {
                @(
                    [PSCustomObject]@{ Name = 'beta'; Status = 'attached' },
                    [PSCustomObject]@{ Name = 'alpha'; Status = 'detached' }
                )
            }

            $sel = & $script:mod {
                param($s, $r)
                Show-TmuxSessionList -HostName 'mock-audit-host' -Sessions $s -SessionRefresher $r
            } $sessions $refresher

            # 刷新后重新弹出的表格: 行序保持上一次展示的顺序, 第一行仍是 alpha
            $script:auditCapturedNames | Should -Be @('alpha', 'beta')
            $sel.Value | Should -Be 'alpha'
            $script:auditViewCalls | Should -Be 2
        }

        It '刷新后原会话被删除时明确警告并列出消失的会话名' {
            $script:auditViewCalls = 0
            $script:auditCapturedNames = $null
            Mock -CommandName Invoke-TmuxSessionListView -ModuleName ShellPrompt -MockWith {
                $script:auditViewCalls++
                if ($script:auditViewCalls -eq 1) {
                    return (& $script:mod { ConvertTo-TmuxRefreshSelection })
                }
                $script:auditCapturedNames = @($Sessions | ForEach-Object { [string]$_.Name })
                return (& $script:mod { ConvertTo-TmuxSessionSelection -Name 'beta' -Status 'detached' })
            }

            $sessions = @(
                [PSCustomObject]@{ Name = 'alpha'; Status = 'detached' },
                [PSCustomObject]@{ Name = 'beta'; Status = 'attached' }
            )
            # alpha 已被其他进程删除
            $refresher = { @([PSCustomObject]@{ Name = 'beta'; Status = 'attached' }) }

            $sel = & $script:mod {
                param($s, $r)
                Show-TmuxSessionList -HostName 'mock-audit-host' -Sessions $s -SessionRefresher $r
            } $sessions $refresher

            Should -Invoke -CommandName Write-Warning -ModuleName ShellPrompt `
                -ParameterFilter { $Message -like '*已不存在*' -and $Message -like '*alpha*' }
            $script:auditCapturedNames | Should -Be @('beta')
            $sel.Value | Should -Be 'beta'
        }

        It '刷新脚本块 throw 时保留原列表并警告, 不折叠成"没有会话"' {
            $script:auditViewCalls = 0
            $script:auditCapturedNames = $null
            Mock -CommandName Invoke-TmuxSessionListView -ModuleName ShellPrompt -MockWith {
                $script:auditViewCalls++
                if ($script:auditViewCalls -eq 1) {
                    return (& $script:mod { ConvertTo-TmuxRefreshSelection })
                }
                # 第二帧: 用户看到保留的原列表后按 ESC 退出
                $script:auditCapturedNames = @($Sessions | ForEach-Object { [string]$_.Name })
                return $null
            }

            $sessions = @(
                [PSCustomObject]@{ Name = 'alpha'; Status = 'detached' },
                [PSCustomObject]@{ Name = 'beta'; Status = 'attached' }
            )
            $refresher = { throw 'SSH connection broken' }

            $sel = & $script:mod {
                param($s, $r)
                Show-TmuxSessionList -HostName 'mock-audit-host' -Sessions $s -SessionRefresher $r
            } $sessions $refresher

            # 失败后没有退出列表, 而是带着原列表重新弹窗(用户可重试刷新或 ESC)
            $script:auditViewCalls | Should -Be 2
            $script:auditCapturedNames | Should -Be @('alpha', 'beta')
            Should -Invoke -CommandName Write-Warning -ModuleName ShellPrompt `
                -ParameterFilter { $Message -like '*刷新会话列表失败*' -and $Message -like '*SSH connection broken*' }
            $sel | Should -BeNullOrEmpty
        }

        It '刷新后确实没有任何会话时返回 $null 并警告(与失败路径区分)' {
            $script:auditViewCalls = 0
            Mock -CommandName Invoke-TmuxSessionListView -ModuleName ShellPrompt -MockWith {
                $script:auditViewCalls++
                return (& $script:mod { ConvertTo-TmuxRefreshSelection })
            }

            $sessions = @([PSCustomObject]@{ Name = 'alpha'; Status = 'detached' })
            $refresher = { @() }

            $sel = & $script:mod {
                param($s, $r)
                Show-TmuxSessionList -HostName 'mock-audit-host' -Sessions $s -SessionRefresher $r
            } $sessions $refresher

            # 空结果(查询成功)是明确退出, 不是保留原列表
            $sel | Should -BeNullOrEmpty
            Should -Invoke -CommandName Write-Warning -ModuleName ShellPrompt `
                -ParameterFilter { $Message -like '*没有可用的 tmux 会话*' }
        }

        It 'Get-TmuxRefreshedSession 对 throw 原样向上抛出(恢复策略由列表层决定)' {
            { & $script:mod { Get-TmuxRefreshedSession -SessionRefresher { throw 'boom' } } } |
                Should -Throw '*boom*'
        }
    }

    Context 'Remove-TmuxSession: 二次确认与刷新失败口径' {

        BeforeEach {
            Mock -CommandName Write-Host -ModuleName ShellPrompt -MockWith { }
            Mock -CommandName Write-Warning -ModuleName ShellPrompt -MockWith { }
            Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
                [PSCustomObject]@{ Output = ''; Error = ''; ExitCode = 0 }
            }
        }

        It '用户取消二次确认时不发出 kill-session 并给出提示' {
            Mock -CommandName Show-TmuxSessionList -ModuleName ShellPrompt -MockWith {
                [PSCustomObject]@{ Value = 'ci-test-session' }
            }
            Mock -CommandName Read-SpectreConfirm -ModuleName ShellPrompt -MockWith { return $false }

            & $script:mod {
                Remove-TmuxSession -HostName 'mock-audit-host' -Sessions @([PSCustomObject]@{ Name = 'ci-test-session' })
            }

            Should -Invoke -CommandName Invoke-SshCommand -ModuleName ShellPrompt -Exactly 0
            Should -Invoke -CommandName Write-Warning -ModuleName ShellPrompt `
                -ParameterFilter { $Message -like '*已放弃删除*' }
        }

        It '二次确认过程抛异常时按"不删除"处理, 不发出 kill-session' {
            Mock -CommandName Show-TmuxSessionList -ModuleName ShellPrompt -MockWith {
                [PSCustomObject]@{ Value = 'ci-test-session' }
            }
            Mock -CommandName Read-SpectreConfirm -ModuleName ShellPrompt -MockWith { throw '非交互终端' }

            & $script:mod {
                Remove-TmuxSession -HostName 'mock-audit-host' -Sessions @([PSCustomObject]@{ Name = 'ci-test-session' })
            }

            Should -Invoke -CommandName Invoke-SshCommand -ModuleName ShellPrompt -Exactly 0
            Should -Invoke -CommandName Write-Warning -ModuleName ShellPrompt `
                -ParameterFilter { $Message -like '*无法完成二次确认*' }
        }

        It '用户确认后才发出 kill-session' {
            Mock -CommandName Show-TmuxSessionList -ModuleName ShellPrompt -MockWith {
                [PSCustomObject]@{ Value = 'ci-test-session' }
            }
            Mock -CommandName Read-SpectreConfirm -ModuleName ShellPrompt -MockWith { return $true }

            & $script:mod {
                Remove-TmuxSession -HostName 'mock-audit-host' -Sessions @([PSCustomObject]@{ Name = 'ci-test-session' })
            }

            Should -Invoke -CommandName Invoke-SshCommand -ModuleName ShellPrompt -Exactly 1 `
                -ParameterFilter { $RemoteCommand -like '*tmux kill-session -t*' }
            Should -Invoke -CommandName Write-Host -ModuleName ShellPrompt `
                -ParameterFilter { $Object -like '*已删除*' }
        }

        It '刷新脚本块: SSH 传输层失败(退出码非 0 / 网络错误)时抛出异常' {
            $script:auditRefresherThrew = $false
            $script:auditRefresherError = ''
            # 捕获 Remove-TmuxSession 传入的刷新脚本块并执行, 观察其失败语义
            Mock -CommandName Show-TmuxSessionList -ModuleName ShellPrompt -MockWith {
                try {
                    & $SessionRefresher
                } catch {
                    $script:auditRefresherThrew = $true
                    $script:auditRefresherError = $_.Exception.Message
                }
                return $null
            }
            Mock -CommandName Get-TmuxSessions -ModuleName ShellPrompt -MockWith {
                @{
                    Sessions     = [System.Collections.Generic.List[object]]::new()
                    RawOutput    = ''
                    Version      = ''
                    Available    = $false
                    Error        = 'ssh: connect to host mock-audit-host port 22: Connection refused'
                    ExitCode     = 255
                    NetworkError = $true
                }
            }
            Mock -CommandName Read-SpectreConfirm -ModuleName ShellPrompt -MockWith { return $true }

            & $script:mod {
                Remove-TmuxSession -HostName 'mock-audit-host' -Sessions @([PSCustomObject]@{ Name = 'ci-test-session' })
            }

            $script:auditRefresherThrew | Should -BeTrue
            $script:auditRefresherError | Should -Match 'mock-audit-host'
            # 抛出后列表层保留原列表, 本次选择被取消 -> 不发 kill-session
            Should -Invoke -CommandName Invoke-SshCommand -ModuleName ShellPrompt -Exactly 0
        }

        It '刷新脚本块: 探测成功但没有会话时正常返回空集合(不算失败)' {
            $script:auditRefresherThrew = $false
            $script:auditRefresherCount = -1
            Mock -CommandName Show-TmuxSessionList -ModuleName ShellPrompt -MockWith {
                try {
                    $script:auditRefresherCount = @(& $SessionRefresher).Count
                } catch {
                    $script:auditRefresherThrew = $true
                }
                return $null
            }
            Mock -CommandName Get-TmuxSessions -ModuleName ShellPrompt -MockWith {
                @{
                    Sessions     = [System.Collections.Generic.List[object]]::new()
                    RawOutput    = ''
                    Version      = '3.4'
                    Available    = $true
                    Error        = ''
                    ExitCode     = 0
                    NetworkError = $false
                }
            }

            & $script:mod {
                Remove-TmuxSession -HostName 'mock-audit-host' -Sessions @([PSCustomObject]@{ Name = 'ci-test-session' })
            }

            $script:auditRefresherThrew | Should -BeFalse
            $script:auditRefresherCount | Should -Be 0
            Should -Invoke -CommandName Get-TmuxSessions -ModuleName ShellPrompt -Exactly 1 `
                -ParameterFilter { $Force -eq $true }
        }
    }

    Context 'Restore-GridViewSelection: 会话名键列的隐藏字段恢复' {

        It '正常会话行按 Session 名找回原行并恢复 Value/Status/Disabled' {
            $rows = & $script:mod {
                $s = @(
                    [PSCustomObject]@{ Name = 'alpha'; Status = 'attached'; Windows = 2 },
                    [PSCustomObject]@{ Name = 'beta'; Status = 'detached'; Windows = 1 }
                )
                Get-TmuxSessionGridRow -Sessions $s -ShowStateBadge
            }
            # 模拟 Out-ConsoleGridView 返回的"裁剪后"行: 隐藏列已被列裁剪移除
            $selected = [PSCustomObject]@{ No = '02'; Session = 'beta'; State = '' }

            $restored = & $script:mod {
                param($sel, $r)
                Restore-GridViewSelection -Selected $sel -Rows $r -KeyColumn 'Session' `
                    -HiddenKeys @('Value', 'Status', 'Disabled') `
                    -HiddenColumns @{ Value = ''; Status = ''; Disabled = $false }
            } $selected $rows

            $restored.Value | Should -Be 'beta'
            $restored.Status | Should -Be 'detached'
            $restored.Disabled | Should -BeFalse
        }

        It '同名会话行(现实中 tmux 拒绝创建重名会话)时隐藏字段取第一个匹配行 —— 锁定现状' {
            # 说明: tmux 在创建时拒绝与现有会话同名的新会话("duplicate session"),
            # 因此该场景在真实远端不可达; 此用例仅锁定 Restore-GridViewSelection
            # "按键列取第一个匹配行"的现状, 防止后续无意间改变该语义。
            $rows = @(
                [PSCustomObject]@{ No = '01'; Session = 'dup'; State = ''; Windows = ''; Status = 'attached'; Disabled = $false; Value = 'dup' },
                [PSCustomObject]@{ No = '02'; Session = 'dup'; State = ''; Windows = ''; Status = 'detached'; Disabled = $false; Value = 'dup' }
            )
            $selected = [PSCustomObject]@{ No = '02'; Session = 'dup' }

            $restored = & $script:mod {
                param($sel, $r)
                Restore-GridViewSelection -Selected $sel -Rows $r -KeyColumn 'Session' `
                    -HiddenKeys @('Value', 'Status') `
                    -HiddenColumns @{ Value = ''; Status = '' }
            } $selected $rows

            $restored.Status | Should -Be 'attached'
            $restored.Value | Should -Be 'dup'
        }
    }
}
