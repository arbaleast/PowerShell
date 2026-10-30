# Start-TmuxSession.Tests.ps1 - tmux 管理器编排流程(方案 A)的集成测试
#
# 覆盖 (2026-10-29 方案 A: 会话列表即主界面):
#   1. 有会话时, 真实会话列表(Show-TmuxSessionList)是第一个交互入口;
#      Enter 选中会话 -> 立即附着(Invoke-TmuxAttach), 而不是先进动作菜单
#   2. 用户取消(列表 ESC + 全局菜单 ESC) -> 不误执行任何 tmux/SSH 操作
#   3. 空会话/探测失败 -> 不弹空表格, 直接进全局操作菜单(-HasSessions $false)并给出明确提示
#   4. 全局菜单 New/Remove/Ssh/Refresh -> 各自正确分发, 且结束后回到循环重新拉会话
#
# 说明: 交互全部通过 Mock 隔离, 不连接真实 SSH / tmux; PowerShell 会话循环依赖
# Mock 返回 $null 收敛到退出分支。

Describe 'Start-TmuxSession (方案 A: 会话列表即主界面)' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    BeforeEach {
        # 通用静音: 交互输出/横幅/探测提示不参与断言
        Mock -CommandName Write-Host -ModuleName ShellPrompt -MockWith { }
        Mock -CommandName Write-Warning -ModuleName ShellPrompt -MockWith { }
        Mock -CommandName Write-TmuxWelcomeBanner -ModuleName ShellPrompt -MockWith { }
        Mock -CommandName Write-TmuxAvailabilityNotice -ModuleName ShellPrompt -MockWith { }

        # spinner 封装透传: 直接执行调用方的 ScriptBlock
        # (非高级 scriptblock 会忽略未声明的命名参数, 只保留用到的 $ScriptBlock
        #  即可避免 PSReviewUnusedParameter)
        Mock -CommandName Invoke-WithProgress -ModuleName ShellPrompt -MockWith {
            param($ScriptBlock)
            & $ScriptBlock
        }

        # 探测: 默认远端 tmux 可用
        Mock -CommandName Get-TmuxAvailability -ModuleName ShellPrompt -MockWith {
            [PSCustomObject]@{
                Available = $true
                Version   = '3.3a'
                Error     = ''
            }
        }

        # 所有会话级 UI / 操作默认拒绝执行, 由各用例按需打桩
        Mock -CommandName Show-TmuxSessionList -ModuleName ShellPrompt -MockWith { return $null }
        Mock -CommandName Show-SessionManager -ModuleName ShellPrompt -MockWith { return $null }
        Mock -CommandName Invoke-TmuxAttach -ModuleName ShellPrompt -MockWith { }
        Mock -CommandName New-TmuxSession -ModuleName ShellPrompt -MockWith { }
        Mock -CommandName Remove-TmuxSession -ModuleName ShellPrompt -MockWith { }
        Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith {
            [PSCustomObject]@{ Output = ''; Error = ''; ExitCode = 0 }
        }
    }

    Context '主界面: 真实会话列表' {

        It '有会话时应先弹会话列表(而非动作菜单), Enter 选中会话后立即附着' {
            $script:callOrder = [System.Collections.Generic.List[string]]::new()
            $script:listCallCount = 0
            Mock -CommandName Show-TmuxSessionList -ModuleName ShellPrompt -MockWith {
                $script:callOrder.Add('list') | Out-Null
                $script:listCallCount++
                # 第一次: 用户选中 'work'; 第二次(附着返回后重拉): 用户 ESC 退出
                if ($script:listCallCount -eq 1) {
                    return [PSCustomObject]@{ Value = 'work' }
                }
                return $null
            }
            Mock -CommandName Show-SessionManager -ModuleName ShellPrompt -MockWith {
                $script:callOrder.Add('menu') | Out-Null
                return $null
            }
            Mock -CommandName Get-TmuxSessions -ModuleName ShellPrompt -MockWith {
                $script:callOrder.Add('fetch') | Out-Null
                return @{
                    Sessions = @(
                        [PSCustomObject]@{ Name = 'work'; Status = 'detached'; Windows = 1 }
                        [PSCustomObject]@{ Name = 'ci'; Status = 'attached'; Windows = 2 }
                    )
                }
            }

            & $script:mod { Start-TmuxSession -HostName 'mock-host' }

            # 交互顺序: fetch(list 数据) -> 会话列表 -> 附着 -> fetch(状态重新获取) -> 会话列表 -> 全局菜单
            $script:callOrder[0] | Should -Be 'fetch'
            $script:callOrder[1] | Should -Be 'list'
            $script:callOrder | Should -Contain 'menu'
            ($script:callOrder[0..1] -join '>') | Should -Be 'fetch>list'
            # 附着发生在动作菜单之前: 第一次 'list' 出现必须早于唯一一次 'menu'
            ($script:callOrder.IndexOf('list') -lt $script:callOrder.IndexOf('menu')) | Should -BeTrue
            # Enter 直接触发目标会话的附着
            Should -Invoke -CommandName Invoke-TmuxAttach -ModuleName ShellPrompt -Exactly 1 `
                -ParameterFilter { $HostName -eq 'mock-host' -and $SessionName -eq 'work' }
            # 附着后回到循环重新拉会话, 再经 ESC 进入全局菜单
            Should -Invoke -CommandName Get-TmuxSessions -ModuleName ShellPrompt -Exactly 2
            Should -Invoke -CommandName Show-TmuxSessionList -ModuleName ShellPrompt -Exactly 2
            Should -Invoke -CommandName Show-SessionManager -ModuleName ShellPrompt -Exactly 1
            # 附着期间不得误创建/误删除/误直连
            Should -Invoke -CommandName New-TmuxSession -ModuleName ShellPrompt -Exactly 0
            Should -Invoke -CommandName Remove-TmuxSession -ModuleName ShellPrompt -Exactly 0
            Should -Invoke -CommandName Invoke-SshCommand -ModuleName ShellPrompt -Exactly 0
        }

        It '刷新后行序保持稳定: 远端返回顺序变化时, 列表仍按上一轮顺序展示' {
            # 2026-10-29 审计: GridView 无预选行参数, 刷新后光标回第一行;
            # 若会话顺序在两轮之间漂移, 同一行位置会指向别的会话 -> 误附着/误删。
            # 这里验证编排层用 Merge-TmuxSessionOrder 把顺序钉在上一轮基线上。
            $script:fetchCount = 0
            Mock -CommandName Get-TmuxSessions -ModuleName ShellPrompt -MockWith {
                $script:fetchCount++
                if ($script:fetchCount -eq 1) {
                    return @{
                        Sessions = @(
                            [PSCustomObject]@{ Name = 'work'; Status = 'detached'; Windows = 1 }
                            [PSCustomObject]@{ Name = 'ci'; Status = 'attached'; Windows = 2 }
                        )
                    }
                }
                # 第二轮: 远端顺序颠倒, 并多出一个新会话
                return @{
                    Sessions = @(
                        [PSCustomObject]@{ Name = 'ci'; Status = 'attached'; Windows = 2 }
                        [PSCustomObject]@{ Name = 'work'; Status = 'detached'; Windows = 1 }
                        [PSCustomObject]@{ Name = 'new'; Status = 'detached'; Windows = 1 }
                    )
                }
            }
            $script:listOrders = [System.Collections.Generic.List[string]]::new()
            $script:listCallCount = 0
            Mock -CommandName Show-TmuxSessionList -ModuleName ShellPrompt -MockWith {
                $script:listCallCount++
                $script:listOrders.Add((@($Sessions | ForEach-Object { $_.Name }) -join ',')) | Out-Null
                # 第一轮: 用户 Enter 选中一个会话 -> 附着后回到循环顶部重拉;
                # 第二轮: 用户 ESC -> 进入全局菜单 -> 退出管理器。
                if ($script:listCallCount -eq 1) {
                    return [PSCustomObject]@{ Value = 'work' }
                }
                return $null
            }
            Mock -CommandName Show-SessionManager -ModuleName ShellPrompt -MockWith { return $null }

            & $script:mod { Start-TmuxSession -HostName 'mock-host' }

            # 第一轮: 原样展示远端顺序
            $script:listOrders[0] | Should -Be 'work,ci'
            # 第二轮: 幸存会话保持上一轮相对顺序(work,ci), 新会话追加到末尾
            $script:listOrders[1] | Should -Be 'work,ci,new'
        }

        It '列表取消后进入全局操作菜单, 不应直接附着' {
            Mock -CommandName Get-TmuxSessions -ModuleName ShellPrompt -MockWith {
                return @{
                    Sessions = @([PSCustomObject]@{ Name = 'work'; Status = 'detached'; Windows = 1 })
                }
            }

            & $script:mod { Start-TmuxSession -HostName 'mock-host' }

            Should -Invoke -CommandName Show-TmuxSessionList -ModuleName ShellPrompt -Exactly 1
            Should -Invoke -CommandName Show-SessionManager -ModuleName ShellPrompt -Exactly 1
            Should -Invoke -CommandName Invoke-TmuxAttach -ModuleName ShellPrompt -Exactly 0
            Should -Invoke -CommandName New-TmuxSession -ModuleName ShellPrompt -Exactly 0
            Should -Invoke -CommandName Remove-TmuxSession -ModuleName ShellPrompt -Exactly 0
            Should -Invoke -CommandName Invoke-SshCommand -ModuleName ShellPrompt -Exactly 0
        }
    }

    Context '空状态与探测失败' {

        It '无任何会话时不弹会话列表, 直接进全局菜单(-HasSessions $false)并给出空状态提示' {
            # 契约(2026-10-29 审计): Get-TmuxSessions 同时返回探测结果,
            # Available=$true 且 Sessions 为空 => "确实没有会话"(不是查询失败)。
            Mock -CommandName Get-TmuxSessions -ModuleName ShellPrompt -MockWith {
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

            Should -Invoke -CommandName Show-TmuxSessionList -ModuleName ShellPrompt -Exactly 0
            Should -Invoke -CommandName Show-SessionManager -ModuleName ShellPrompt -Exactly 1 `
                -ParameterFilter { $HasSessions -eq $false -and $HostName -eq 'mock-host' }
            Should -Invoke -CommandName Write-Warning -ModuleName ShellPrompt `
                -ParameterFilter { $Message -like '*没有 tmux 会话*' }
        }

        It '探测失败(tmux 检测失败)时不弹会话列表, 且提示为数据获取失败而非空列表' {
            Mock -CommandName Get-TmuxAvailability -ModuleName ShellPrompt -MockWith {
                [PSCustomObject]@{ Available = $false; Version = ''; Error = 'Connection refused' }
            }
            # 契约(2026-10-29 审计): 探测失败时 Available=$false —— 空状态提示必须走
            # "未能获取"分支, 不能伪装成"当前没有 tmux 会话"。
            Mock -CommandName Get-TmuxSessions -ModuleName ShellPrompt -MockWith {
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

            Should -Invoke -CommandName Show-TmuxSessionList -ModuleName ShellPrompt -Exactly 0
            Should -Invoke -CommandName Show-SessionManager -ModuleName ShellPrompt -Exactly 1 `
                -ParameterFilter { $HasSessions -eq $false }
            Should -Invoke -CommandName Write-Warning -ModuleName ShellPrompt `
                -ParameterFilter { $Message -like '*未能获取*' }
            Should -Invoke -CommandName Write-Warning -ModuleName ShellPrompt `
                -ParameterFilter { $Message -like '*没有 tmux 会话*' } -Exactly 0
        }

        It 'SSH 等待超时时提示"超时", 不得伪装成"没有会话"或"检测失败"' {
            # 契约(2026-10-29 审计): TimedOut 由 SSH 层透传到探测结果,
            # 上层据此把"超时"与"远端检测失败"分开提示, 便于用户判断是网络问题还是配置问题。
            Mock -CommandName Get-TmuxSessions -ModuleName ShellPrompt -MockWith {
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

            Should -Invoke -CommandName Write-Warning -ModuleName ShellPrompt `
                -ParameterFilter { $Message -like '*超时*' }
            Should -Invoke -CommandName Write-Warning -ModuleName ShellPrompt `
                -ParameterFilter { $Message -like '*没有 tmux 会话*' } -Exactly 0
            Should -Invoke -CommandName Write-Warning -ModuleName ShellPrompt `
                -ParameterFilter { $Message -like '*tmux 检测失败*' } -Exactly 0
        }
    }

    Context '全局操作菜单(ESC 后的轻量菜单)' {

        # 公共打桩: 列表 ESC 进全局菜单; 菜单第一次返回本 It 指定的动作,
        # 第二次(循环回来后)返回 $null 收敛退出。
        BeforeEach {
            $script:menuCallCount = 0
            $script:requestedAction = $null
            Mock -CommandName Get-TmuxSessions -ModuleName ShellPrompt -MockWith {
                return @{
                    Sessions = @([PSCustomObject]@{ Name = 'work'; Status = 'detached'; Windows = 1 })
                }
            }
            Mock -CommandName Show-TmuxSessionList -ModuleName ShellPrompt -MockWith { return $null }
            Mock -CommandName Show-SessionManager -ModuleName ShellPrompt -MockWith {
                $script:menuCallCount++
                if ($script:menuCallCount -eq 1) {
                    return [PSCustomObject]@{ Value = $script:requestedAction }
                }
                return $null
            }
        }

        It 'New 应分发到 New-TmuxSession' {
            $script:requestedAction = 'New'

            & $script:mod { Start-TmuxSession -HostName 'mock-host' -WarningAction SilentlyContinue }

            # 动作执行后回到循环顶部重新拉会话 + 重新弹列表, 再经 ESC 收敛退出
            Should -Invoke -CommandName Get-TmuxSessions -ModuleName ShellPrompt -Exactly 2
            Should -Invoke -CommandName Show-SessionManager -ModuleName ShellPrompt -Exactly 2
            Should -Invoke -CommandName New-TmuxSession -ModuleName ShellPrompt -Exactly 1 `
                -ParameterFilter { $HostName -eq 'mock-host' }
        }

        It 'Remove 应分发到 Remove-TmuxSession (目标会话明确, 且删除函数内部有二次确认)' {
            $script:requestedAction = 'Remove'

            & $script:mod { Start-TmuxSession -HostName 'mock-host' -WarningAction SilentlyContinue }

            Should -Invoke -CommandName Get-TmuxSessions -ModuleName ShellPrompt -Exactly 2
            Should -Invoke -CommandName Show-SessionManager -ModuleName ShellPrompt -Exactly 2
            Should -Invoke -CommandName Remove-TmuxSession -ModuleName ShellPrompt -Exactly 1 `
                -ParameterFilter { $HostName -eq 'mock-host' }
        }

        It 'Ssh 应分发到交互式 SSH 直连(不带 tmux 命令)' {
            $script:requestedAction = 'Ssh'

            & $script:mod { Start-TmuxSession -HostName 'mock-host' -WarningAction SilentlyContinue }

            Should -Invoke -CommandName Get-TmuxSessions -ModuleName ShellPrompt -Exactly 2
            Should -Invoke -CommandName Show-SessionManager -ModuleName ShellPrompt -Exactly 2
            Should -Invoke -CommandName Invoke-SshCommand -ModuleName ShellPrompt -Exactly 1 `
                -ParameterFilter { $HostName -eq 'mock-host' -and -not $RemoteCommand }
        }

        It 'Refresh 应只触发循环重拉, 不误分发 创建/删除/直连' {
            $script:requestedAction = 'Refresh'

            & $script:mod { Start-TmuxSession -HostName 'mock-host' -WarningAction SilentlyContinue }

            Should -Invoke -CommandName Get-TmuxSessions -ModuleName ShellPrompt -Exactly 2
            Should -Invoke -CommandName Show-SessionManager -ModuleName ShellPrompt -Exactly 2
            Should -Invoke -CommandName New-TmuxSession -ModuleName ShellPrompt -Exactly 0
            Should -Invoke -CommandName Remove-TmuxSession -ModuleName ShellPrompt -Exactly 0
            Should -Invoke -CommandName Invoke-SshCommand -ModuleName ShellPrompt -Exactly 0
        }
    }
}
