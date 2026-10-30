# Tmux-SessionState.Tests.ps1 - tmux 会话状态一致性审计回归测试 (2026-10-29)
# 覆盖:
#   1. Get-TmuxSessions 契约扩展: "查询失败" vs "查询成功但没有会话" 可区分
#      (Available / Error / ExitCode / NetworkError 四个新键, 只追加不改旧键)
#   2. Restore-GridViewSelection: 键列命中行的隐藏字段恢复(含重名现状锁定)。
# 说明: 2026-10-31 死代码清理后, 旧会话列表链(Show-TmuxSessionList 刷新循环 /
#       Merge-TmuxSessionOrder / Remove-TmuxSession)已删除, 对应用例一并移除;
#       防误删屏障现由 Invoke-TmuxSessionDeletion 承担(见 Invoke-TmuxSessionDeletion 测试)。
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

    Context 'Restore-GridViewSelection: 会话名键列的隐藏字段恢复' {

        It '正常会话行按 Session 名找回原行并恢复 Value/Status/Disabled' {
            # 行形状与 GridView 表格行一致(No/Session/State/Windows/Status/Disabled/Value)
            $rows = @(
                [PSCustomObject]@{ No = '01'; Session = 'alpha'; State = '● 已附着'; Windows = 2; Status = 'attached'; Disabled = $false; Value = 'alpha' },
                [PSCustomObject]@{ No = '02'; Session = 'beta'; State = '○ 已分离'; Windows = 1; Status = 'detached'; Disabled = $false; Value = 'beta' }
            )
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
