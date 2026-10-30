# Start-TmuxSession.Tests.ps1 - tmux 管理器编排流程(2026-10-30 TUI 重构)的集成测试
#
# 覆盖:
#   1. 唯一主视图: 会话表格(Show-TmuxSessionDashboard)是唯一交互入口,
#      选中会话 -> 立即附着(Invoke-TmuxAttach), 不再经过"全局操作菜单";
#   2. 底部单行动作条(Show-TmuxActionBar)承担全局动作分发, 键位契约由
#      Get-TmuxActionDefinition 驱动; ESC / $null = 退出管理器;
#   3. 状态降级: 探测失败 -> 主视图拿到的 State.Status='Error' 且带错误码,
#      动作条按 Error 上下文渲染(重试/直连); 空会话 != 探测失败;
#   4. 静默刷新: 成功路径不再输出 "[OK] 正在重新获取会话列表 ..." 之类的 toast;
#   5. 行序稳定: 远端返回顺序变化时, 主视图仍按上一轮顺序展示(防误附着/误删)。
#
# 说明: 交互全部通过 Mock 隔离, 不连接真实 SSH / tmux; 会话循环依赖
# Mock 返回 $null 收敛到退出分支。数据层(Get-TmuxSessionState / Merge-TmuxSessionOrder)
# 不打桩, 走真实实现, 以便同时覆盖归一化逻辑。

Describe 'Start-TmuxSession (单主视图 + 单行动作条)' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    BeforeEach {
        # 通用静音: 交互输出/横幅/天气预取不参与断言
        Mock -CommandName Write-Host -ModuleName ShellPrompt -MockWith { }
        Mock -CommandName Write-Warning -ModuleName ShellPrompt -MockWith { }
        Mock -CommandName Write-TmuxWelcomeBanner -ModuleName ShellPrompt -MockWith { }
        Mock -CommandName Submit-WttrPrefetch -ModuleName ShellPrompt -MockWith { return $null }

        # 所有会话级 UI / 操作默认拒绝执行, 由各用例按需打桩
        Mock -CommandName Show-TmuxSessionDashboard -ModuleName ShellPrompt -MockWith { return $null }
        Mock -CommandName Show-TmuxActionBar -ModuleName ShellPrompt -MockWith { return $null }
        Mock -CommandName Invoke-TmuxAttach -ModuleName ShellPrompt -MockWith { }
        Mock -CommandName New-TmuxSession -ModuleName ShellPrompt -MockWith { }
        Mock -CommandName Remove-TmuxSession -ModuleName ShellPrompt -MockWith { }
        Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
            [PSCustomObject]@{ Output = ''; Error = ''; ExitCode = 0 }
        }
    }

    Context '唯一主视图' {

        It '选中会话后立即附着, 不经过动作条' {
            $script:callOrder = [System.Collections.Generic.List[string]]::new()
            $script:dashboardCallCount = 0
            Mock -CommandName Invoke-TmuxSessionFetch -ModuleName ShellPrompt -MockWith {
                $script:callOrder.Add('fetch') | Out-Null
                return @{
                    Sessions     = @(
                        [PSCustomObject]@{ Name = 'work'; Status = 'detached'; Windows = 1 }
                        [PSCustomObject]@{ Name = 'ci'; Status = 'attached'; Windows = 2 }
                    )
                    Available    = $true
                    Version      = '3.3a'
                    Error        = ''
                    ExitCode     = 0
                    NetworkError = $false
                }
            }
            Mock -CommandName Show-TmuxSessionDashboard -ModuleName ShellPrompt -MockWith {
                $script:callOrder.Add('dashboard') | Out-Null
                $script:dashboardCallCount++
                # 第一次: 用户 Enter 选中 'work'; 第二次(附着返回后重拉): 用户 ESC
                if ($script:dashboardCallCount -eq 1) {
                    return [PSCustomObject]@{ Value = 'work' }
                }
                return $null
            }

            & $script:mod { Start-TmuxSession -HostName 'mock-host' }

            # 交互顺序: fetch -> 主视图 -> 附着 -> fetch -> 主视图 -> 动作条
            ($script:callOrder[0..1] -join '>') | Should -Be 'fetch>dashboard'
            Should -Invoke -CommandName Invoke-TmuxAttach -ModuleName ShellPrompt -Exactly 1 `
                -ParameterFilter { $HostName -eq 'mock-host' -and $SessionName -eq 'work' }
            # 附着会改变远端状态 -> 下一轮重新取数
            Should -Invoke -CommandName Invoke-TmuxSessionFetch -ModuleName ShellPrompt -Exactly 2
            Should -Invoke -CommandName Show-TmuxSessionDashboard -ModuleName ShellPrompt -Exactly 2
            # 附着期间不得误创建/误删除/误直连
            Should -Invoke -CommandName New-TmuxSession -ModuleName ShellPrompt -Exactly 0
            Should -Invoke -CommandName Remove-TmuxSession -ModuleName ShellPrompt -Exactly 0
            Should -Invoke -CommandName Invoke-SshCommand -ModuleName ShellPrompt -Exactly 0
        }

        It '主视图取消(ESC)后进入动作条, 不应直接附着' {
            Mock -CommandName Invoke-TmuxSessionFetch -ModuleName ShellPrompt -MockWith {
                return @{
                    Sessions  = @([PSCustomObject]@{ Name = 'work'; Status = 'detached'; Windows = 1 })
                    Available = $true
                    Version   = '3.3a'
                }
            }

            & $script:mod { Start-TmuxSession -HostName 'mock-host' }

            Should -Invoke -CommandName Show-TmuxSessionDashboard -ModuleName ShellPrompt -Exactly 1
            Should -Invoke -CommandName Show-TmuxActionBar -ModuleName ShellPrompt -Exactly 1
            Should -Invoke -CommandName Invoke-TmuxAttach -ModuleName ShellPrompt -Exactly 0
            Should -Invoke -CommandName New-TmuxSession -ModuleName ShellPrompt -Exactly 0
            Should -Invoke -CommandName Remove-TmuxSession -ModuleName ShellPrompt -Exactly 0
            Should -Invoke -CommandName Invoke-SshCommand -ModuleName ShellPrompt -Exactly 0
        }

        It '刷新后行序保持稳定: 远端返回顺序变化时, 主视图仍按上一轮顺序展示' {
            # 2026-10-29 审计: GridView 无预选行参数, 重新弹表后光标回到第一行;
            # 若会话顺序在两轮之间漂移, 同一行位置会指向别的会话 -> 误附着/误删风险。
            $script:fetchCount = 0
            Mock -CommandName Invoke-TmuxSessionFetch -ModuleName ShellPrompt -MockWith {
                $script:fetchCount++
                if ($script:fetchCount -eq 1) {
                    return @{
                        Sessions  = @(
                            [PSCustomObject]@{ Name = 'work'; Status = 'detached'; Windows = 1 }
                            [PSCustomObject]@{ Name = 'ci'; Status = 'attached'; Windows = 2 }
                        )
                        Available = $true
                    }
                }
                # 第二轮: 远端顺序颠倒, 并多出一个新会话
                return @{
                    Sessions  = @(
                        [PSCustomObject]@{ Name = 'ci'; Status = 'attached'; Windows = 2 }
                        [PSCustomObject]@{ Name = 'work'; Status = 'detached'; Windows = 1 }
                        [PSCustomObject]@{ Name = 'new'; Status = 'detached'; Windows = 1 }
                    )
                    Available = $true
                }
            }
            $script:viewOrders = [System.Collections.Generic.List[string]]::new()
            Mock -CommandName Show-TmuxSessionDashboard -ModuleName ShellPrompt -MockWith {
                $script:viewOrders.Add((@($State.Sessions | ForEach-Object { $_.Name }) -join ',')) | Out-Null
                return $null
            }
            # 动作条: 第一轮按 [r] 刷新触发重取, 第二轮 ESC 退出; 否则默认桩($null)
            # 会让循环在第 1 轮后就退出, "重取后的行序"根本测不到。
            $script:actionCount = 0
            Mock -CommandName Show-TmuxActionBar -ModuleName ShellPrompt -MockWith {
                $script:actionCount++
                if ($script:actionCount -eq 1) {
                    return [PSCustomObject]@{ Value = 'Refresh'; Key = 'r' }
                }
                return $null
            }

            & $script:mod { Start-TmuxSession -HostName 'mock-host' }

            # 第一轮: 原样展示远端顺序
            $script:viewOrders[0] | Should -Be 'work,ci'
            # 第二轮: 幸存会话保持上一轮相对顺序(work,ci), 新会话追加到末尾
            $script:viewOrders[1] | Should -Be 'work,ci,new'
        }
    }

    Context '空状态与探测失败' {

        It '确实没有会话时: 状态为 Empty, 动作条按无会话渲染(不暴露附着/删除)' {
            Mock -CommandName Invoke-TmuxSessionFetch -ModuleName ShellPrompt -MockWith {
                return @{
                    Sessions     = @()
                    Available    = $true
                    Version      = '3.3a'
                    Error        = ''
                    ExitCode     = 0
                    NetworkError = $false
                }
            }

            & $script:mod { Start-TmuxSession -HostName 'mock-host' -WarningAction SilentlyContinue }

            Should -Invoke -CommandName Show-TmuxSessionDashboard -ModuleName ShellPrompt -Exactly 1 `
                -ParameterFilter { $State.Status -eq 'Empty' -and $State.ErrorCode -eq '' }
            Should -Invoke -CommandName Show-TmuxActionBar -ModuleName ShellPrompt -Exactly 1 `
                -ParameterFilter { $HasSessions -eq $false -and $Context -eq 'Normal' }
        }

        It '探测失败时: 状态为 Error 且带错误码, 动作条按 Error 上下文渲染' {
            Mock -CommandName Invoke-TmuxSessionFetch -ModuleName ShellPrompt -MockWith {
                return @{
                    Sessions     = @()
                    Available    = $false
                    Version      = ''
                    Error        = 'Connection refused'
                    ExitCode     = 255
                    NetworkError = $true
                }
            }

            & $script:mod { Start-TmuxSession -HostName 'mock-host' -WarningAction SilentlyContinue }

            Should -Invoke -CommandName Show-TmuxSessionDashboard -ModuleName ShellPrompt -Exactly 1 `
                -ParameterFilter {
                    $State.Status -eq 'Error' -and
                    $State.ErrorCode -eq 'E_SSH_UNREACHABLE' -and
                    $State.ErrorMessage -ne '' -and
                    $State.Hint -ne ''
                }
            # 失败态的动作条用 Error 上下文(重试/直连), 且仍然没有会话
            Should -Invoke -CommandName Show-TmuxActionBar -ModuleName ShellPrompt -Exactly 1 `
                -ParameterFilter { $HasSessions -eq $false -and $Context -eq 'Error' }
        }

        It 'SSH 等待超时时错误码为 E_SSH_TIMEOUT, 不得伪装成"没有会话"' {
            Mock -CommandName Invoke-TmuxSessionFetch -ModuleName ShellPrompt -MockWith {
                return @{
                    Sessions     = @()
                    Available    = $false
                    Version      = ''
                    Error        = ''
                    ExitCode     = -1
                    NetworkError = $false
                    TimedOut     = $true
                }
            }

            & $script:mod { Start-TmuxSession -HostName 'mock-host' -WarningAction SilentlyContinue }

            Should -Invoke -CommandName Show-TmuxSessionDashboard -ModuleName ShellPrompt -Exactly 1 `
                -ParameterFilter { $State.ErrorCode -eq 'E_SSH_TIMEOUT' }
        }
    }

    Context '底部单行动作条(全局动作分发)' {

        # 公共打桩: 主视图一律返回 $null(用户 ESC), 动作条第一次返回本 It 指定的动作,
        # 第二次(循环回来后)返回 $null 收敛退出。
        BeforeEach {
            $script:actionBarCallCount = 0
            $script:requestedAction = $null
            Mock -CommandName Invoke-TmuxSessionFetch -ModuleName ShellPrompt -MockWith {
                return @{
                    Sessions  = @([PSCustomObject]@{ Name = 'work'; Status = 'detached'; Windows = 1 })
                    Available = $true
                    Version   = '3.3a'
                }
            }
            Mock -CommandName Show-TmuxActionBar -ModuleName ShellPrompt -MockWith {
                $script:actionBarCallCount++
                if ($script:actionBarCallCount -eq 1) {
                    return [PSCustomObject]@{ Value = $script:requestedAction; Key = 'x' }
                }
                return $null
            }
        }

        It 'New 应分发到 New-TmuxSession' {
            $script:requestedAction = 'New'

            & $script:mod { Start-TmuxSession -HostName 'mock-host' -WarningAction SilentlyContinue }

            Should -Invoke -CommandName Invoke-TmuxSessionFetch -ModuleName ShellPrompt -Exactly 2
            Should -Invoke -CommandName Show-TmuxActionBar -ModuleName ShellPrompt -Exactly 2
            Should -Invoke -CommandName New-TmuxSession -ModuleName ShellPrompt -Exactly 1 `
                -ParameterFilter { $HostName -eq 'mock-host' }
        }

        It 'Remove 应分发到 Remove-TmuxSession (目标会话明确, 且删除函数内部有二次确认)' {
            $script:requestedAction = 'Remove'

            & $script:mod { Start-TmuxSession -HostName 'mock-host' -WarningAction SilentlyContinue }

            Should -Invoke -CommandName Remove-TmuxSession -ModuleName ShellPrompt -Exactly 1 `
                -ParameterFilter { $HostName -eq 'mock-host' }
        }

        It 'Ssh 应分发到交互式 SSH 直连(不带 tmux 命令)' {
            $script:requestedAction = 'Ssh'

            & $script:mod { Start-TmuxSession -HostName 'mock-host' -WarningAction SilentlyContinue }

            Should -Invoke -CommandName Invoke-SshCommand -ModuleName ShellPrompt -Exactly 1 `
                -ParameterFilter { $HostName -eq 'mock-host' -and -not $RemoteCommand }
        }

        It 'Refresh 应只触发重新取数, 不误分发 创建/删除/直连' {
            $script:requestedAction = 'Refresh'

            & $script:mod { Start-TmuxSession -HostName 'mock-host' -WarningAction SilentlyContinue }

            Should -Invoke -CommandName Invoke-TmuxSessionFetch -ModuleName ShellPrompt -Exactly 2
            Should -Invoke -CommandName New-TmuxSession -ModuleName ShellPrompt -Exactly 0
            Should -Invoke -CommandName Remove-TmuxSession -ModuleName ShellPrompt -Exactly 0
            Should -Invoke -CommandName Invoke-SshCommand -ModuleName ShellPrompt -Exactly 0
        }

        It 'Attach 应回到主视图选会话, 且不额外重新取数' {
            $script:requestedAction = 'Attach'

            & $script:mod { Start-TmuxSession -HostName 'mock-host' -WarningAction SilentlyContinue }

            # Attach 复用当前状态(不重新探测): 取数次数保持 1
            Should -Invoke -CommandName Invoke-TmuxSessionFetch -ModuleName ShellPrompt -Exactly 1
            # 主视图被重新渲染一次(第一次 ESC + Attach 后再回列表)
            Should -Invoke -CommandName Show-TmuxSessionDashboard -ModuleName ShellPrompt -Exactly 2
            Should -Invoke -CommandName Invoke-TmuxAttach -ModuleName ShellPrompt -Exactly 0
        }

        It 'Quit 应立即退出管理器, 不再取数也不再渲染' {
            $script:requestedAction = 'Quit'

            & $script:mod { Start-TmuxSession -HostName 'mock-host' -WarningAction SilentlyContinue }

            Should -Invoke -CommandName Invoke-TmuxSessionFetch -ModuleName ShellPrompt -Exactly 1
            Should -Invoke -CommandName Show-TmuxActionBar -ModuleName ShellPrompt -Exactly 1
            Should -Invoke -CommandName Show-TmuxSessionDashboard -ModuleName ShellPrompt -Exactly 1
        }
    }

    Context '静默状态' {

        It '刷新等成功路径不得输出"正在重新获取会话列表"之类的 toast' {
            $script:actionBarCallCount = 0
            Mock -CommandName Invoke-TmuxSessionFetch -ModuleName ShellPrompt -MockWith {
                return @{
                    Sessions  = @([PSCustomObject]@{ Name = 'work'; Status = 'detached'; Windows = 1 })
                    Available = $true
                    Version   = '3.3a'
                }
            }
            Mock -CommandName Show-TmuxActionBar -ModuleName ShellPrompt -MockWith {
                $script:actionBarCallCount++
                if ($script:actionBarCallCount -eq 1) {
                    return [PSCustomObject]@{ Value = 'Refresh'; Key = 'r' }
                }
                return $null
            }

            & $script:mod { Start-TmuxSession -HostName 'mock-host' -WarningAction SilentlyContinue }

            Should -Invoke -CommandName Write-Host -ModuleName ShellPrompt -Exactly 0 `
                -ParameterFilter { $Object -like '*重新获取*' }
            Should -Invoke -CommandName Write-Host -ModuleName ShellPrompt -Exactly 0 `
                -ParameterFilter { $Object -like '*正在获取*' }
        }
    }
}
