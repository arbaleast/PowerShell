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

        It '方向键(CursorDown/CursorUp)在表格内移动选中行, 首尾边界不越界' {
            # Goal 三-2: 上下方向键移动选中行 —— 由 TG 自己的 TableView 负责
            # (键盘选中归 TG, 见 Goal 二的职责划分), 因此这里用 TG 的按键注入
            # 走**真实事件链**验证, 而不是测我们自己的键位映射表。
            # 注: TG 2.4.10 的方向键静态属性名是 CursorUp/CursorDown(不是 UpArrow)。
            $nav = & $script:mod {
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
                            Sessions  = @(
                                [PSCustomObject]@{ Name = 'work'; Status = 'detached'; Windows = 2 }
                                [PSCustomObject]@{ Name = 'ci'; Status = 'attached'; Windows = 1 }
                                [PSCustomObject]@{ Name = 'ops'; Status = 'detached'; Windows = 3 }
                            )
                        })
                    $result = New-TmuxTuiDashboardWindow -ViewModel $vm -HostName 'deb' `
                        -ConnectionState '已连接' -HasSessions $true -Dispatch { } `
                        -WindowWidth 120 -WindowHeight 35 -SelectedIndex 0
                    $tableView = $result.Table
                    $app = $instanceP.GetValue($null)
                    $token = $beginM.Invoke($app, @($result.Window))
                    try {
                        $trail = [System.Collections.Generic.List[int]]::new()
                        $trail.Add([int]$tableView.Value.SelectedCell.Y)
                        foreach ($k in @('CursorDown', 'CursorDown', 'CursorDown', 'CursorUp', 'CursorUp', 'CursorUp')) {
                            $keyObj = $tg.Types.Key.GetProperty($k).GetValue($null)
                            [void]$raiseM.Invoke($null, @($keyObj))
                            $trail.Add([int]$tableView.Value.SelectedCell.Y)
                        }
                        $trail.ToArray()
                    } finally {
                        [void]$endM.Invoke($app, @($token))
                    }
                } finally {
                    try { [void]$shutdownM.Invoke($null, @()) } catch {
                        Write-Verbose "[test] 方向键用例 Shutdown 失败: $($_.Exception.Message)"
                    }
                }
            }

            # 初始第 0 行 -> 下 -> 下 -> 下(到底, 停住) -> 上 -> 上 -> 上(到顶, 停住)
            @($nav) | Should -Be @(0, 1, 2, 2, 1, 0, 0)
        }

        It '导航后按 Enter: 触发附着, 且编排层读回的是被导航到的那一行(不是第 0 行)' {
            # Goal 三-2 + 四-5 + 六-4: Enter 附着"当前选中会话"。
            # 编排层读回契约: Value.SelectedCell.Y -> SessionRows[idx].Name。
            $testHits = [System.Collections.Generic.List[string]]::new()
            $r = & $script:mod {
                param($hits)
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
                            Sessions  = @(
                                [PSCustomObject]@{ Name = 'work'; Status = 'detached'; Windows = 2 }
                                [PSCustomObject]@{ Name = 'ci'; Status = 'attached'; Windows = 1 }
                            )
                        })
                    $dispatch = { param($a) $hits.Add([string]$a) }
                    $result = New-TmuxTuiDashboardWindow -ViewModel $vm -HostName 'deb' `
                        -ConnectionState '已连接' -HasSessions $true -Dispatch $dispatch `
                        -WindowWidth 120 -WindowHeight 35 -SelectedIndex 0
                    $app = $instanceP.GetValue($null)
                    $token = $beginM.Invoke($app, @($result.Window))
                    try {
                        # 先下移一行, 再按 Enter
                        $down = $tg.Types.Key.GetProperty('CursorDown').GetValue($null)
                        [void]$raiseM.Invoke($null, @($down))
                        $enter = $tg.Types.Key.GetProperty('Enter').GetValue($null)
                        [void]$raiseM.Invoke($null, @($enter))
                    } finally {
                        [void]$endM.Invoke($app, @($token))
                    }
                    # 编排层读回(与 Show-TmuxTuiDashboard 同一契约)
                    $rowIndex = [int]$result.Table.Value.SelectedCell.Y
                    $name = if ($rowIndex -ge 0 -and $rowIndex -lt @($vm.SessionRows).Count) {
                        @($vm.SessionRows)[$rowIndex].Name
                    } else { $null }
                    [PSCustomObject]@{
                        Hits    = @($hits.ToArray())
                        RowIndex = $rowIndex
                        Name    = $name
                    }
                } finally {
                    try { [void]$shutdownM.Invoke($null, @()) } catch {
                        Write-Verbose "[test] Enter 导航用例 Shutdown 失败: $($_.Exception.Message)"
                    }
                }
            } $testHits

            # Enter 触发附着动作(恰好一次)
            @($r.Hits | Where-Object { $_ -eq 'Attach' }) | Should -HaveCount 1
            # 选中的是第 1 行 —— 名字必须是 'ci', 绝不是第 0 行的 'work'
            $r.RowIndex | Should -Be 1
            $r.Name | Should -Be 'ci'
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

    # -------------------------------------------- 事件循环 Run 重载契约(回归护栏)
    # 2026-10-30 真机故障根因: 编排层调的是**泛型** Application.Run<Window>(handler, driver),
    #   该重载约束为 `where T : IRunnable, new()`, 实测 IL(ApplicationImpl.Run<T>) 内部
    #   **new 一个全新的 T** 再交给 Run(IRunnable, ...) 跑完即 Dispose —— 组装好的仪表盘
    #   从不上屏, 真机表现为「只剩边框、内容全无」(空 Window 只画边框, 应用级键表仍可用)。
    #   本组用例锁死"必须用非泛型 Run(IRunnable, Func) 跑组装好的窗口"这条契约。
    Context '事件循环 Run 重载契约(回归护栏)' {

        It 'Terminal.Gui 提供唯一的非泛型 Run(IRunnable, Func) 重载, 首参接受 Window' {
            $count = & $script:mod {
                $tg = Get-TguiContext
                $static = [System.Reflection.BindingFlags]'Public,Static'
                @($tg.Types.Application.GetMethods($static) | Where-Object {
                        $_.Name -eq 'Run' -and
                        -not $_.IsGenericMethodDefinition -and
                        $_.GetParameters().Count -eq 2 -and
                        $_.GetParameters()[0].ParameterType.IsAssignableFrom($tg.Types.Window)
                    }).Count
            }
            $count | Should -Be 1
        }

        It '泛型 Run<T> 带 new() 约束(内部会造空窗)⇒ 不得用于运行已组装窗口' {
            $info = & $script:mod {
                $tg = Get-TguiContext
                $static = [System.Reflection.BindingFlags]'Public,Static'
                $genericRun = $tg.Types.Application.GetMethods($static) |
                    Where-Object { $_.Name -eq 'Run' -and $_.IsGenericMethodDefinition } |
                    Select-Object -First 1
                $gp = $genericRun.GetGenericArguments()[0]
                [PSCustomObject]@{
                    HasNewConstraint = $gp.GenericParameterAttributes.HasFlag([System.Reflection.GenericParameterAttributes]::DefaultConstructorConstraint)
                    Constraints      = (($gp.GetGenericParameterConstraints() | ForEach-Object { $_.Name }) -join ',')
                }
            }
            $info.HasNewConstraint | Should -BeTrue
            $info.Constraints | Should -Be 'IRunnable'
        }

        It '编排层不使用泛型 Run(源码不得出现 MakeGenericMethod)' {
            $source = Get-Content -Raw -Path (Join-Path -Path $moduleRoot -ChildPath 'Private/Show-TmuxTuiDashboard.ps1')
            $source | Should -Not -Match 'MakeGenericMethod'
            # 必须把**组装好的窗口实例**交给 Run
            $source | Should -Match '\$runArgs\[0\]\s*=\s*\$result\.Window'
        }

        It '组装好的窗口实例可被 Terminal.Gui 直接 Begin(跑的就是它本身)' {
            $isRunning = & $script:mod {
                $tg = Get-TguiContext
                $static = [System.Reflection.BindingFlags]'Public,Static'
                $appType = $tg.Types.Application
                $initM = $appType.GetMethods($static) | Where-Object { $_.Name -eq 'Init' } | Select-Object -First 1
                $beginM = $appType.GetMethods($static) | Where-Object { $_.Name -eq 'Begin' } | Select-Object -First 1
                $endM = $appType.GetMethods($static) | Where-Object { $_.Name -eq 'End' } | Select-Object -First 1
                $shutdownM = $appType.GetMethod('Shutdown', $static)
                $instanceP = $appType.GetProperty('Instance', $static)

                [void]$initM.Invoke($null, @('ansi'))
                $observed = $false
                try {
                    $vm = ConvertTo-TmuxTuiViewModel -State (Get-TmuxSessionState -SessionData @{
                            Available = $true
                            Sessions  = @([PSCustomObject]@{ Name = 'work'; Status = 'detached'; Windows = 2 })
                        })
                    $result = New-TmuxTuiDashboardWindow -ViewModel $vm -HostName 'deb' `
                        -ConnectionState '已连接' -HasSessions $true -Dispatch { }

                    $app = $instanceP.GetValue($null)
                    $token = $beginM.Invoke($app, @($result.Window))
                    # Begin 之后, **这个实例**才是正在跑的那个(IsRunning=True)
                    $observed = [bool]$result.Window.IsRunning
                    [void]$endM.Invoke($app, @($token))
                } finally {
                    try { [void]$shutdownM.Invoke($null, @()) } catch {
                        Write-Verbose "[test] Run 契约用例 Shutdown 失败: $($_.Exception.Message)"
                    }
                }
                $observed
            }
            $isRunning | Should -BeTrue
        }
    }

    # ------------------------------- Init 周期与事件订阅(2026-10-30 回归护栏)
    # 仪表盘的 while 循环每轮都是 Init -> Run -> Shutdown(附着/新建/删除/刷新后回仪表盘)。
    # 2.4.10 实测: Shutdown 会**清空** Application 上的事件订阅, 而 Application.Instance
    # 在 Init -> Shutdown -> Init 之间是**同一个对象** ⇒ 只按实例标识去重的订阅守卫
    # 会在第二轮误判"已订阅", 导致第一次交互之后 resize 不再触发重建。
    Context 'Init 周期与 ScreenChanged 订阅(回归护栏)' {

        It 'Shutdown 清空事件订阅, 且 Instance 在 Init 周期之间不变(所以守卫必须另设标记)' {
            $facts = & $script:mod {
                $tg = Get-TguiContext
                $static = [System.Reflection.BindingFlags]'Public,Static'
                $appType = $tg.Types.Application
                $initM = $appType.GetMethods($static) | Where-Object { $_.Name -eq 'Init' } | Select-Object -First 1
                $shutM = $appType.GetMethod('Shutdown', $static)
                $instP = $appType.GetProperty('Instance', $static)

                $handlerCount = {
                    param($app)
                    $f = $app.GetType().GetField('ScreenChanged', [System.Reflection.BindingFlags]'NonPublic,Instance,Public')
                    if ($null -eq $f) { return -1 }
                    $v = $f.GetValue($app)
                    if ($null -eq $v) { return 0 }
                    return @($v.GetInvocationList()).Count
                }

                [void]$initM.Invoke($null, @('ansi'))
                try {
                    $app1 = $instP.GetValue($null)
                    $before = & $handlerCount $app1
                    # 回调签名必须与 ScreenChanged 委托一致(两参), 但本用例只关心
                    # 订阅计数, 不消费事件内容 —— 故显式丢弃两个参数, 既保持签名
                    # 又不触发 PSReviewUnusedParameter。
                    $app1.add_ScreenChanged({
                            param($oldScreen, $newScreen)
                            $null = $oldScreen
                            $null = $newScreen
                        })
                    $subscribed = & $handlerCount $app1
                    [void]$shutM.Invoke($null, @())
                    $afterShutdown = & $handlerCount $app1
                    # 第二轮 Init: 同一对象?
                    [void]$initM.Invoke($null, @('ansi'))
                    $app2 = $instP.GetValue($null)
                    $sameInstance = [object]::ReferenceEquals($app1, $app2)
                    [void]$shutM.Invoke($null, @())
                    [PSCustomObject]@{
                        Before      = $before
                        Subscribed  = $subscribed
                        AfterShut   = $afterShutdown
                        SameInstance = $sameInstance
                    }
                } finally {
                    # 清理 Shutdown: 重复调用可能抛(已 Init->Shutdown->Init 过),
                    # 此处吞掉异常属预期, 但必须留痕以免触发空 catch 告警。
                    try { [void]$shutM.Invoke($null, @()) } catch { Write-Verbose "[test] 清理期 Shutdown 抛出(预期内): $($_.Exception.Message)" }
                }
            }
            # 订阅确实挂上了
            $facts.Subscribed | Should -BeGreaterThan $facts.Before
            # Shutdown 把它清掉了 —— 这是"守卫必须另设标记"的根据
            $facts.AfterShut | Should -Be 0
            # Instance 不变 —— 只按实例标识去重是不够的
            $facts.SameInstance | Should -BeTrue
        }

        It '编排层在 Shutdown 之后清掉"本轮已订阅"标记(否则第二轮不再订阅)' {
            $source = Get-Content -Raw -Path (Join-Path -Path $moduleRoot -ChildPath 'Private/Show-TmuxTuiDashboard.ps1')
            # Shutdown 调用之后必须紧跟一次标记清理
            $source | Should -Match '(?s)Shutdown 失败.*?\$global:TguiSubscribedApp\s*=\s*\$null'
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
