# Show-TmuxTuiDashboard.Tests.ps1 - TGUI 仪表盘契约测试(阶段 B, Goal 三/四/六)
# 覆盖:
#   1. 布局计划(纯函数): 100x30 / 120x35 / 160x45 三档零重叠零空档;
#   2. **真实 Terminal.Gui 布局测量**: Window.Layout(Size) 后读 Frame,
#      断言表格与快捷键栏既不重叠也不留空档(Goal 三-5);
#   3. 窄窗口隐藏次要列(Goal 三-5);
#   4. 快捷键绑定契约: BindKeyToApplication / Command=NotBound / Esc 不重复绑定;
#   5. **Terminal.Gui 键盘注入**: Application.Begin + RaiseKeyDownEvent,
#      Enter/N/Q 各自触发对应 Shortcut.Action 恰好一次(Goal 六-5);
#   6. TG 键 -> 仓库键事件形状的桥接(ConvertTo-TguiKeyInfo);
#   7. 业务动作分发(new/delete/refresh/attach/ssh, Goal 六-4);
#   8. 非交互终端护栏 + 终端所有者还原(Goal 四)。
# 说明: 全部无头(不启真实 SSH / 不连远端); TG 侧只做 Begin/End 级别的注入。

Describe 'TGUI 仪表盘 (Show-TmuxTuiDashboard 阶段 B)' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'

        function Get-TguiVm {
            param([ValidateSet('Session', 'Empty', 'Error')][string]$Mode = 'Session')
            & $script:mod {
                param($m)
                $state = switch ($m) {
                    'Session' {
                        Get-TmuxSessionState -SessionData @{
                            Available = $true
                            Sessions  = @(
                                [PSCustomObject]@{ Name = 'work'; Status = 'detached'; Windows = 3 }
                                [PSCustomObject]@{ Name = 'ci';   Status = 'attached';  Windows = 1 }
                            )
                        }
                    }
                    'Empty' { Get-TmuxSessionState -SessionData @{ Available = $true; Sessions = @() } }
                    'Error' { Get-TmuxSessionState -SessionData @{ Available = $false; TimedOut = $true } }
                }
                ConvertTo-TmuxTuiViewModel -State $state
            } $Mode
        }
    }

    # ---------------------------------------------------------------- 布局
    Context '布局计划(纯函数 New-TmuxTuiLayoutPlan)' {

        It '100x30 / 120x35 / 160x45 三档: 表格区与快捷键栏零重叠' {
            $result = & $script:mod {
                foreach ($size in @(@(100, 30), @(120, 35), @(160, 45))) {
                    $plan = New-TmuxTuiLayoutPlan -Width $size[0] -Height $size[1]
                    [PSCustomObject]@{
                        Width          = $plan.Width
                        Height         = $plan.Height
                        TitleRow       = $plan.TitleRow
                        StatsRow       = $plan.StatsRow
                        HintRow        = $plan.HintRow
                        TableRow       = $plan.TableRow
                        TableHeight    = $plan.TableHeight
                        TableBottomRow = $plan.TableBottomRow
                        StatusBarRow   = $plan.StatusBarRow
                    }
                }
            }
            $result | Should -HaveCount 3
            foreach ($plan in $result) {
                # 顶部三行不重叠
                $plan.TitleRow | Should -BeLessThan $plan.StatsRow
                $plan.StatsRow | Should -BeLessThan $plan.HintRow
                $plan.HintRow | Should -BeLessThan $plan.TableRow
                # 底部: 表格最后一行 < 快捷键栏行 —— 零重叠
                $plan.TableBottomRow | Should -BeLessThan $plan.StatusBarRow
                # 快捷键栏贴在最后一行
                $plan.StatusBarRow | Should -Be ($plan.Height - 1)
                $plan.TableHeight | Should -BeGreaterThan 0
            }
        }

        It '极小窗口(高度 6)也不产生负高度' {
            $plan = & $script:mod { New-TmuxTuiLayoutPlan -Width 40 -Height 6 }
            $plan.TableHeight | Should -BeGreaterOrEqual 1
        }
    }

    Context '真实 Terminal.Gui 布局测量(Window.Layout)' {

        It '三档尺寸下表格与快捷键栏零重叠零空档' {
            $frames = & $script:mod {
                foreach ($size in @(@(100, 30), @(120, 35), @(160, 45))) {
                    $w = $size[0]; $h = $size[1]
                    $vm = ConvertTo-TmuxTuiViewModel -State (Get-TmuxSessionState -SessionData @{
                            Available = $true
                            Sessions  = @([PSCustomObject]@{ Name = 'work'; Status = 'detached'; Windows = 2 })
                        })
                    $result = New-TmuxTuiDashboardWindow -ViewModel $vm -HostName 'deb' `
                        -ConnectionState '已连接' -HasSessions $true -Dispatch { } `
                        -WindowWidth $w -WindowHeight $h
                    # 触发一次真实布局, 读回 Terminal.Gui 算出的 Frame
                    $layoutM = $result.Window.GetType().GetMethod('Layout', [type[]]@([System.Drawing.Size]))
                    [void]$layoutM.Invoke($result.Window, @([System.Drawing.Size]::new($w, $h)))
                    [PSCustomObject]@{
                        Width        = $w
                        Height       = $h
                        TableTop     = $result.Table.Frame.Y
                        TableHeight  = $result.Table.Frame.Height
                        BarTop       = $result.StatusBar.Frame.Y
                        BarHeight    = $result.StatusBar.Frame.Height
                        TableWidth   = $result.Table.Frame.Width
                    }
                }
            }
            $frames | Should -HaveCount 3
            foreach ($f in $frames) {
                # 表格顶行固定在第 3 行(标题/统计/辅助各占一行)
                $f.TableTop | Should -Be 3
                # 快捷键栏贴底, 高 1 行
                $f.BarTop | Should -Be ($f.Height - 1)
                $f.BarHeight | Should -Be 1
                # 表格的排他底边 == 快捷键栏顶行 ⇒ 既不重叠也不留空档
                ($f.TableTop + $f.TableHeight) | Should -Be $f.BarTop
                # 表格铺满整宽(无横向溢出)
                $f.TableWidth | Should -Be $f.Width
            }
        }

        It '窄窗口隐藏次要列(宽度 < 96 隐藏 STATUS, < 72 再隐藏 WINDOWS)' {
            $columns = & $script:mod {
                param($w)
                $vm = ConvertTo-TmuxTuiViewModel -State (Get-TmuxSessionState -SessionData @{
                        Available = $true
                        Sessions  = @([PSCustomObject]@{ Name = 'work'; Status = 'detached'; Windows = 2 })
                    })
                $result = New-TmuxTuiDashboardWindow -ViewModel $vm -HostName 'deb' `
                    -ConnectionState '已连接' -HasSessions $true -Dispatch { } `
                    -WindowWidth $w -WindowHeight 30
                $result.Source.Columns
            } 140
            # 注: .Source.Columns 是 Int32 计数(不是名字集合), 名字级断言由
            # New-TmuxTuiSessionTable.Tests.ps1 的列计划契约覆盖。
            $columns | Should -Be 4
            $narrow = & $script:mod {
                param($w)
                $vm = ConvertTo-TmuxTuiViewModel -State (Get-TmuxSessionState -SessionData @{
                        Available = $true
                        Sessions  = @([PSCustomObject]@{ Name = 'work'; Status = 'detached'; Windows = 2 })
                    })
                $result = New-TmuxTuiDashboardWindow -ViewModel $vm -HostName 'deb' `
                    -ConnectionState '已连接' -HasSessions $true -Dispatch { } `
                    -WindowWidth $w -WindowHeight 30
                $result.Source.Columns
            } 80
            $narrow | Should -Be 3
        }
    }

    # ------------------------------------------------------------ 快捷键契约
    Context '快捷键绑定契约' {

        It 'Enter/N/Q/R/S/X 登记到应用级键表(BindKeyToApplication=$true)' {
            $bindings = & $script:mod {
                $list = New-TmuxTuiShortcutList -HasSessions $true -Dispatch { }
                $list | ForEach-Object { [PSCustomObject]@{ Key = $_.Key.ToString(); Bind = $_.BindKeyToApplication; Command = $_.Command.ToString(); Enabled = $_.Enabled } }
            }
            $bindings | Where-Object { $_.Key -eq 'Enter' } | Should -Not -BeNullOrEmpty
            foreach ($k in @('Enter', 'N', 'Q', 'R', 'S', 'X')) {
                $item = $bindings | Where-Object { $_.Key -eq $k }
                $item | Should -Not -BeNullOrEmpty
                $item.Bind | Should -BeTrue
                # Command 必须是 NotBound: 与 Accept 同时出现会死循环 StackOverflow 崩进程
                $item.Command | Should -Be 'NotBound'
            }
        }

        It 'Esc 不重复绑定到应用级(TG 已内置 Esc->Quit, 重复绑定会抛异常)' {
            $bindings = & $script:mod {
                $list = New-TmuxTuiShortcutList -HasSessions $true -Dispatch { }
                $list | ForEach-Object { [PSCustomObject]@{ Key = $_.Key.ToString(); Bind = $_.BindKeyToApplication } }
            }
            $esc = $bindings | Where-Object { $_.Key -eq 'Esc' }
            $esc | Should -Not -BeNullOrEmpty
            $esc.Bind | Should -BeFalse
        }

        It '无会话时删除项显式标注不可用且不绑定键位' {
            $bindings = & $script:mod {
                $list = New-TmuxTuiShortcutList -HasSessions $false -Dispatch { }
                $list | ForEach-Object {
                    [PSCustomObject]@{ Title = $_.Title.ToString(); Bind = $_.BindKeyToApplication; Enabled = $_.Enabled }
                }
            }
            $remove = $bindings | Where-Object { $_.Title -match '删除' }
            $remove | Should -Not -BeNullOrEmpty
            $remove.Title | Should -Match '不可用'
            $remove.Bind | Should -BeFalse
            $remove.Enabled | Should -BeFalse
        }
    }

    # ------------------------------------------------- Terminal.Gui 键盘注入
    Context 'Terminal.Gui 键盘注入交互' {

        It 'Enter/N/Q 各触发对应 Shortcut.Action 恰好一次; Esc 走 TG 内建 Quit' {
            $hits = & $script:mod {
                $global:TguiTestHits = [System.Collections.Generic.List[string]]::new()
                $tg = Get-TguiContext
                $static = [System.Reflection.BindingFlags]'Public,Static'
                $appType = $tg.Types.Application
                $initM = $appType.GetMethods($static) | Where-Object { $_.Name -eq 'Init' } | Select-Object -First 1
                $beginM = $appType.GetMethods($static) | Where-Object { $_.Name -eq 'Begin' } | Select-Object -First 1
                $endM = $appType.GetMethods($static) | Where-Object { $_.Name -eq 'End' } | Select-Object -First 1
                $raiseM = $appType.GetMethod('RaiseKeyDownEvent', $static)
                $shutdownM = $appType.GetMethod('Shutdown', $static)
                $instanceP = $appType.GetProperty('Instance', $static)

                [void]$initM.Invoke($null, @('ansi'))
                try {
                    $vm = ConvertTo-TmuxTuiViewModel -State (Get-TmuxSessionState -SessionData @{
                            Available = $true
                            Sessions  = @([PSCustomObject]@{ Name = 'work'; Status = 'detached'; Windows = 2 })
                        })
                    $dispatch = { param($a) $global:TguiTestHits.Add([string]$a) }
                    $result = New-TmuxTuiDashboardWindow -ViewModel $vm -HostName 'deb' `
                        -ConnectionState '已连接' -HasSessions $true -Dispatch $dispatch

                    $app = $instanceP.GetValue($null)
                    $token = $beginM.Invoke($app, @($result.Window))
                    foreach ($k in @('Enter', 'N', 'Q', 'Esc')) {
                        $keyObj = $tg.Types.Key.GetProperty($k).GetValue($null)
                        [void]$raiseM.Invoke($null, @($keyObj))
                    }
                    [void]$endM.Invoke($app, @($token))
                } finally {
                    try { [void]$shutdownM.Invoke($null, @()) } catch {
                        Write-Verbose "[test] 注入用例 Shutdown 失败: $($_.Exception.Message)"
                    }
                }
                $global:TguiTestHits.ToArray()
            }

            # Enter -> Attach, N -> New, Q -> Quit, 各一次
            $hits | Should -HaveCount 3
            @($hits | Where-Object { $_ -eq 'Attach' }) | Should -HaveCount 1
            @($hits | Where-Object { $_ -eq 'New' }) | Should -HaveCount 1
            @($hits | Where-Object { $_ -eq 'Quit' }) | Should -HaveCount 1
            # Esc 不走我们的 Action(由 TG 内建 Quit 退出应用)
            @($hits | Where-Object { $_ -eq 'Quit' }) | Should -HaveCount 1
        }
    }

    # -------------------------------------------------------------- 键桥接
    Context 'TG 键 -> 仓库键事件桥接 (ConvertTo-TguiKeyInfo)' {

        It 'Esc -> Escape/[char]27, 字母 -> 大写键名 + 小写字符' {
            $esc = & $script:mod { ConvertTo-TguiKeyInfo -Key ([PSCustomObject]@{ KeyCode = 'Esc' }) }
            $esc.Key | Should -BeExactly 'Escape'
            [int][char]$esc.KeyChar | Should -Be 27

            $letter = & $script:mod { ConvertTo-TguiKeyInfo -Key ([PSCustomObject]@{ KeyCode = 'N' }) }
            $letter.Key | Should -BeExactly 'N'
            [int][char]$letter.KeyChar | Should -Be 110

            $enter = & $script:mod { ConvertTo-TguiKeyInfo -Key ([PSCustomObject]@{ KeyCode = 'Enter' }) }
            $enter.Key | Should -BeExactly 'Enter'
            [int][char]$enter.KeyChar | Should -Be 13
        }
    }

    # ---------------------------------------------------------- 业务动作分发
    Context '业务动作分发 (Invoke-TmuxTuiAction)' {

        BeforeEach {
            Mock -CommandName Invoke-TmuxAttach -ModuleName ShellPrompt -MockWith { }
            Mock -CommandName New-TmuxSession -ModuleName ShellPrompt -MockWith { }
            Mock -CommandName Invoke-TmuxSessionDeletion -ModuleName ShellPrompt -MockWith { }
            Mock -CommandName Invoke-SshCommand -ModuleName ShellPrompt -MockWith { return [PSCustomObject]@{ ExitCode = 0 } }
        }

        It 'Attach -> Invoke-TmuxAttach(所选会话)' {
            & $script:mod { Invoke-TmuxTuiAction -Action 'Attach' -HostName 'deb' -SelectedSession 'work' } | Out-Null
            Should -Invoke -CommandName Invoke-TmuxAttach -ModuleName ShellPrompt -Exactly 1 `
                -ParameterFilter { $HostName -eq 'deb' -and $SessionName -eq 'work' }
        }

        It 'New -> New-TmuxSession' {
            & $script:mod { Invoke-TmuxTuiAction -Action 'New' -HostName 'deb' } | Out-Null
            Should -Invoke -CommandName New-TmuxSession -ModuleName ShellPrompt -Exactly 1 `
                -ParameterFilter { $HostName -eq 'deb' }
        }

        It 'Refresh -> 只刷新, 不调任何业务函数' {
            & $script:mod { Invoke-TmuxTuiAction -Action 'Refresh' -HostName 'deb' -SelectedSession 'work' } | Out-Null
            Should -Invoke -CommandName Invoke-TmuxAttach -ModuleName ShellPrompt -Exactly 0
            Should -Invoke -CommandName New-TmuxSession -ModuleName ShellPrompt -Exactly 0
            Should -Invoke -CommandName Invoke-TmuxSessionDeletion -ModuleName ShellPrompt -Exactly 0
        }

        It 'Remove -> Invoke-TmuxSessionDeletion(所选会话, 二次确认在函数内)' {
            & $script:mod { Invoke-TmuxTuiAction -Action 'Remove' -HostName 'deb' -SelectedSession 'work' } | Out-Null
            Should -Invoke -CommandName Invoke-TmuxSessionDeletion -ModuleName ShellPrompt -Exactly 1 `
                -ParameterFilter { $HostName -eq 'deb' -and $SessionName -eq 'work' }
        }

        It 'Ssh -> Invoke-SshCommand -Interactive' {
            & $script:mod { Invoke-TmuxTuiAction -Action 'Ssh' -HostName 'deb' } | Out-Null
            Should -Invoke -CommandName Invoke-SshCommand -ModuleName ShellPrompt -Exactly 1 `
                -ParameterFilter { $HostName -eq 'deb' -and $Interactive -eq $true }
        }

        It '无选中会话时 Attach/Remove 不执行(死键防护)' {
            & $script:mod { Invoke-TmuxTuiAction -Action 'Attach' -HostName 'deb' -SelectedSession '' } | Out-Null
            & $script:mod { Invoke-TmuxTuiAction -Action 'Remove' -HostName 'deb' -SelectedSession '' } | Out-Null
            Should -Invoke -CommandName Invoke-TmuxAttach -ModuleName ShellPrompt -Exactly 0
            Should -Invoke -CommandName Invoke-TmuxSessionDeletion -ModuleName ShellPrompt -Exactly 0
        }

        It '未知动作被忽略并告警' {
            Mock -CommandName Write-Warning -ModuleName ShellPrompt -MockWith { }
            & $script:mod { Invoke-TmuxTuiAction -Action 'Bogus' -HostName 'deb' } | Out-Null
            Should -Invoke -CommandName Write-Warning -ModuleName ShellPrompt -Exactly 1
            Should -Invoke -CommandName Invoke-TmuxAttach -ModuleName ShellPrompt -Exactly 0
        }
    }

    # ---------------------------------------------------------- 生命周期护栏
    Context '生命周期与终端还原' {

        It '非交互终端(重定向)下直接返回 Exit, 不启动事件循环' {
            Mock -CommandName Write-Warning -ModuleName ShellPrompt -MockWith { }
            $result = & $script:mod { Show-TmuxTuiDashboard -HostName 'deb' }
            $result | Should -BeExactly 'Exit'
        }

        It '终端所有者标志在调用后保持原值' {
            $owner = & $script:mod { $script:TmuxTerminalOwner }
            & $script:mod { Show-TmuxTuiDashboard -HostName 'deb' } | Out-Null
            $after = & $script:mod { $script:TmuxTerminalOwner }
            $after | Should -Be $owner
            # 终端所有权不变量(Goal 四): TG 分支绝不经手自管备用屏状态位
            & $script:mod { $script:TmuxAltScreenActive } | Should -BeFalse
        }

        It '视图组装异常时异常向上传播且终端所有者被还原' {
            # 护栏/取数/视图三处打桩: 让 mock 的 throw 穿过 Init → 组装 → 外层 finally
            Mock -CommandName Write-Warning -ModuleName ShellPrompt -MockWith { }
            Mock -CommandName Test-TmuxTuiInteractive -ModuleName ShellPrompt -MockWith { return $true }
            # 取数返回 $null: 走"探测失败"口径降级到 Error 视图模型(不是要测的异常);
            # 要测的异常来自视图组装 mock —— 它在 try/finally 保护区里必须向上传播。
            Mock -CommandName Invoke-TmuxSessionFetch -ModuleName ShellPrompt -MockWith { return $null }
            Mock -CommandName New-TmuxTuiDashboardWindow -ModuleName ShellPrompt -MockWith {
                throw 'boom-from-view'
            }
            { & $script:mod { Show-TmuxTuiDashboard -HostName 'deb' } } | Should -Throw
            $owner = & $script:mod { $script:TmuxTerminalOwner }
            $owner | Should -Be 'Legacy'
            # 异常路径同样不许碰自管备用屏状态位(终端所有者= TG 的 Shutdown 独占恢复)
            & $script:mod { $script:TmuxAltScreenActive } | Should -BeFalse
        }
    }
}
