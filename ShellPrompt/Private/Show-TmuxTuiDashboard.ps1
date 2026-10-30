# Show-TmuxTuiDashboard.ps1 - **Terminal.Gui v2 直接驱动的 sss 仪表盘编排层**(阶段 B)
#
# 背景 (2026-10-30 TGUI 迁移 · 阶段 B):
#   目标: 让 `sss` 的 tmux 管理器仪表盘**真正跑在 Terminal.Gui v2 上**
#   (独立 TGUI, 不走 PSTui GridView), 布局由"状态区 + 会话表 + 快捷键栏"
#   组成; 业务层沿用既有 PowerShell 函数(Invoke-TmuxSessionFetch /
#   Get-TmuxSessionState / Invoke-TmuxAttach / New-TmuxSession /
#   Invoke-TmuxSessionDeletion / Invoke-SshCommand),
#   TGUI 只负责布局/绘制/键盘/缩放, **不重写任何 SSH/tmux 业务逻辑**。
#
# 2.4.10 实测 API(反射探针 .agent_cache/tgui-probe/REPORT.md; 严禁按文档示例假定):
#   Application: Terminal.Gui.App.Application
#     Init(driverName: 'windows'/'dotnet'/'ansi' — DriverRegistry 仅注册这三个)
#     Run[TRunnable][IRunnable](Func<Exception,bool> errorHandler, string driver)
#     RequestStop(IRunnable) -- 让 Run() 从事件循环 return(动作回调退出)
#     Shutdown() -- 交还终端(还原光标/鼠标/粘贴/**备用屏**)
#     Instance / Screen / AppModel
#   TableView: 无 SelectedRow —— 选中读 `Value.SelectedCell`(Point).Y
#   Shortcut: BindKeyToApplication=$true 才登记到**应用级**键表(真实按键才到达
#             Action); Command 必须保持 NotBound(与 Accept 同时出现会死循环崩进程)
#   Esc: 应用级键表**默认已绑定 Esc -> Quit**; 再登记会抛
#        "A binding for Esc exists" —— 故 Esc 退出走 TG 内建 Quit 路径。
#
# 驱动选择: 固定 **'ansi'** —— DriverRegistry 里只有 windows/dotnet/ansi 三个,
#   'dotnet' 驱动的 NetInput **无视 AppModel 无条件发 1049**(备用屏),
#   'ansi' 驱动才让 AppModel 生效 ⇒ 统一用 'ansi' 才能保证
#   "TG 是唯一终端所有者"(不与仓库自有 \e[?1049h/l 双层嵌套),
#   且 Windows Terminal 与 Linux 行为一致。
#
# 生命周期(唯一终端所有者规则):
#   TG 分支**不使用** Enter/Exit-TmuxAlternateScreen —— 通过
#   $script:TmuxTerminalOwner='Tgui' 让那对辅助函数整体静音(TG 自管备用屏)。
#   全屏业务子动作(tmux attach / 新建 / SSH 直连): Run 已退出 + 已 Shutdown
#   —— 主屏直接调业务函数, 结束后主循环重新 Init(自然恢复仪表盘)。
#
# dispatch 模式: Shortcut.Action → `$global:TguiPendingAction` + RequestStop
#   (Shortcut 内部动作文本已内联在 New-TmuxTuiShortcutList 建立,
#    global 变量回写是 2.4.10 事件循环跨会话触发的唯一可靠通路)。

function Show-TmuxTuiDashboard {
    <#
    .SYNOPSIS
        编排 TGUI(主循环)驱动的 tmux 会话仪表盘(阶段 B)。

    .DESCRIPTION
        编排规则:
          - while($true) 每轮: 取数(Invoke-TmuxSessionFetch→Get-TmuxSessionState)
            → 视图模型(ConvertTo-TmuxTuiViewModel) → 组装(New-TmuxTuiDashboardWindow)
            → Application.Init(driver) → Run<Window>(window) → Shutdown → 分发 Action;
          - dispatch: Shortcut.Action 把动作值写 `$global:TguiPendingAction`,
            `Application.RequestStop(window)` 让 Run 返回(事件循环自然退出);
          - 行序/选中: `PreviousSelected` 跨轮保留(幸存即保留, 消失即 $null);
          - 空态/错误: Mode 分型(Empty Label/Error Label, 不伪造会话行);
          - Attach/New/Ssh 全屏业务: Run 已退出 + Shutdown —— 主屏直接调
            业务函数, 结束后主循环重新 Init(自然恢复仪表盘);
          - 缩放: Application.ScreenChanged → RequestStop → 用新尺寸重建整窗
            (列计划随宽度重算, 窄窗口自动隐藏次要列)。

        非交互终端(输入/输出被重定向)直接返回 'Exit' —— TG 的 Init 在无 TTY
        环境**不抛异常**(实测), 但事件循环会永远阻塞, 必须提前护栏。

    .PARAMETER HostName
        当前 SSH 主机名

    .PARAMETER InitialSelected
        上一轮选中并希望保留的会话名(选中保留)

    .OUTPUTS
        [string] 'Exit'(用户主动退出 / Q / Esc / Ctrl-C)

    .EXAMPLE
        $result = Show-TmuxTuiDashboard -HostName deb
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$HostName,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$InitialSelected = ''
    )

    # ---- 非交互终端护栏(必须在触碰 TG 之前) ----
    # 探针实测: 无 TTY 容器里 Init('windows'/'dotnet'/'ansi') **全部成功**,
    # 随后 Run() 永久阻塞 —— Pester/CI 重定向环境下会挂死整个测试进程。
    if (-not (Test-TmuxTuiInteractive)) {
        Write-Warning '[Show-TmuxTuiDashboard] 当前不是交互式终端(输入/输出被重定向), 已跳过 TGUI 仪表盘。'
        return 'Exit'
    }

    $tg = Get-TguiContext

    # ---- Application 反射调用句柄 ----
    $staticFlags = [System.Reflection.BindingFlags]'Public,Static'
    $initMethod = $tg.Types.Application.GetMethods($staticFlags) |
        Where-Object { $_.Name -eq 'Init' } | Select-Object -First 1
    $shutdownMethod = $tg.Types.Application.GetMethod('Shutdown', $staticFlags)
    # ★ 必须用**非泛型** Run(IRunnable, Func<Exception,bool>) 把组装好的窗口交给 TG。
    #   泛型 Run<T> 的约束是 `where T : IRunnable, new()`; 2026-10-30 IL 实测
    #   (ApplicationImpl.Run<TRunnable>): 它内部 **new 一个全新的 T**, 交给
    #   Run(IRunnable, ...) 跑完再 Dispose —— 也就是"组装好的仪表盘从不上屏",
    #   真机表现为「只剩边框、内容全无」(空 Window 只画边框, Esc/应用级键表仍可用)。
    #   证据: .agent_cache/tgui-probe/p61-run-callee.ps1 / p62-appimpl-run.ps1。
    $runMethod = $tg.Types.Application.GetMethods($staticFlags) |
        Where-Object {
            $_.Name -eq 'Run' -and
            -not $_.IsGenericMethodDefinition -and
            $_.GetParameters().Count -eq 2 -and
            $_.GetParameters()[0].ParameterType.IsAssignableFrom($tg.Types.Window)
        } |
        Select-Object -First 1
    if ($null -eq $runMethod) {
        Write-Warning '[Show-TmuxTuiDashboard] Terminal.Gui 缺少 Run(IRunnable, Func) 重载, 已中止。'
        return 'Exit'
    }
    $stopMethod = $tg.Types.Application.GetMethods($staticFlags) |
        Where-Object { $_.Name -eq 'RequestStop' } | Select-Object -First 1
    $instanceProperty = $tg.Types.Application.GetProperty('Instance', $staticFlags)
    $screenProperty = $tg.Types.Application.GetProperty('Screen', $staticFlags)

    $driverName = 'ansi'
    $errorHandler = [System.Func[[exception], [bool]]]{ param($ex)
        $global:TguiError = $ex
        # 返回 $false = 不吞异常, Run 结束
        $false
    }

    # ---- 状态 ----
    $state = $null    # Get-TmuxSessionState 产物, null 意为重取
    $previousSelected = $InitialSelected
    $selected = $null

    # ScreenChanged 事件报数(0 = 还没有有效报数, 建窗回退 Post-Init Screen 读取)。
    # 跨 Init 周期保留: 终端真实尺寸不会因 TG 周期翻转而变化。
    $global:TguiScreenW = 0
    $global:TguiScreenH = 0

    # 终端所有者: TG 分支期间让 Enter/Exit-TmuxAlternateScreen 静音,
    # 保证"备用屏只有一个所有者"(Goal 四: 禁止重复嵌套备用屏幕)。
    $previousOwner = $script:TmuxTerminalOwner
    $script:TmuxTerminalOwner = 'Tgui'

    # 终端已被 TG 接管(Init 成功)的标记: 异常路径据此补 Shutdown
    $tgInitialized = $false

    try {
        while ($true) {
            # ---- 取数(业务层, 失败自动降级到 Error 视图模型) ----
            # ★ 只在"状态失效"时取数(2026-10-30 真机风暴修复):
            #   之前每轮循环开头**无条件**重新 SSH 取数 —— 纯缩放重建也会重打
            #   "获取远程 tmux 会话"动画; 与 legacy 轨的"$state 为空才取数"不一致。
            #   纯缩放(continue 到循环顶)复用上一轮 $state, 不打网络。
            if ($null -eq $state) {
                try {
                    $raw = Invoke-TmuxSessionFetch -HostName $HostName
                    $merged = @()
                    if ($raw) { $merged = @($raw.Sessions | Where-Object { $null -ne $_ }) }
                    $state = Get-TmuxSessionState -SessionData $raw -Sessions $merged
                } catch {
                    $raw = $null
                    $state = $null
                }
            }

            # ---- 视图模型 ----
            $vm = ConvertTo-TmuxTuiViewModel -State $state -PreviousSelected $previousSelected

            # 选中行下标(视图模型行序 == 表格行序)
            $selectedIndex = -1
            if ($vm.SelectedSession) {
                $rows = @($vm.SessionRows)
                for ($i = 0; $i -lt $rows.Count; $i++) {
                    if ($rows[$i].Name -eq $vm.SelectedSession) { $selectedIndex = $i; break }
                }
            }

            # dispatch: Shortcut.Action 的动作值写 global:TguiPendingAction,
            # 并 RequestStop 让 Run 从事件循环返回。
            # 载荷只走 global —— TG 事件循环回调会换 runtime 会话, 闭包局部变量不可见。
            $global:TguiPendingAction = $null
            $global:TguiResizeDetected = $false
            $dispatch = { param($a)
                $global:TguiPendingAction = $a
                if ($global:TguiWindowRef -and $global:TguiRequestStopMethod) {
                    $stopArgs = [object[]]::CreateInstance([System.Object], 1)
                    $stopArgs[0] = $global:TguiWindowRef
                    [void]$global:TguiRequestStopMethod.Invoke($null, $stopArgs)
                }
            }

            # ---- Init: 先拿到 TG 的屏幕尺寸, 再按该尺寸组装窗口 ----
            try {
                # AppModel 显式置 FullScreen: 让 'ansi' 驱动走备用屏
                # (内联模式会与仓库自有 1049 包装冲突)
                try {
                    $tg.Types.Application.GetProperty('AppModel', $staticFlags).SetValue($null, $tg.Types.AppModel.GetProperty('FullScreen').GetValue($null))
                } catch {
                    Write-Verbose "[Show-TmuxTuiDashboard] 设置 AppModel 失败(用默认值): $($_.Exception.Message)"
                }
                $initMethod.Invoke($null, @($driverName))
                # 标记"终端已被 TG 接管": 从这一刻起, 任何异常都必须由
                # 外层 finally 负责 Shutdown(否则备用屏/光标留在备用状态)。
                $tgInitialized = $true
            } catch {
                Write-Warning "[Show-TmuxTuiDashboard] Terminal.Gui Init 失败: $($_.Exception.Message)"
                return 'Exit'
            }

            $appInstance = $instanceProperty.GetValue($null)
            # ---- 记账值: **优先用上一轮 ScreenChanged 的报数**(2026-10-30 风暴修复) ----
            # Post-Init 的 Screen 读取在某些宿主上是 0/陈旧值(真机风暴根因): 记账值
            # 与事件报数必然错位 => 每个 ScreenChanged 都触发整窗重建 => 配合旧
            # "每轮无条件取数"就是取数风暴。现在事件报数(>0 才有效)是第一手数据:
            # 建窗尺寸优先取它; 记账值(TguiLayoutWidth/Height)恒等于**本轮建窗尺寸**,
            # 事件逐轮对齐后 mismatch 消失 —— 真实缩放仍按"报数 != 建窗尺寸"触发单次重建。
            $screenWidth = 120
            $screenHeight = 35
            if ($global:TguiScreenW -gt 0 -and $global:TguiScreenH -gt 0) {
                $screenWidth = [int]$global:TguiScreenW
                $screenHeight = [int]$global:TguiScreenH
            } else {
                $screen = $screenProperty.GetValue($null)
                if ($null -ne $screen) {
                    try {
                        $screenWidth = [int]$screen.Width
                        $screenHeight = [int]$screen.Height
                    } catch {
                        Write-Verbose "[Show-TmuxTuiDashboard] 读取屏幕尺寸失败(用默认值): $($_.Exception.Message)"
                    }
                }
            }
            if ($screenWidth -lt 40) { $screenWidth = 40 }
            if ($screenHeight -lt 10) { $screenHeight = 10 }

            $global:TguiLayoutWidth = $screenWidth
            $global:TguiLayoutHeight = $screenHeight

            # ---- 组装窗口(状态区 + 会话表 + 快捷键栏) ----
            $connectionState = if ($vm.Mode -eq 'Error') { '连接失败' } else { '已连接' }
            $result = New-TmuxTuiDashboardWindow -ViewModel $vm -HostName $HostName `
                -ConnectionState $connectionState -HasSessions ($vm.Mode -eq 'Session') `
                -Dispatch $dispatch -WindowWidth $screenWidth -WindowHeight $screenHeight `
                -SelectedIndex $selectedIndex

            $global:TguiRequestStopMethod = $stopMethod
            $global:TguiWindowRef = $result.Window

            # ---- 取消双保险: TableView.KeyDown 直判 Esc / Ctrl+C(2026-10-31 真机修复) ----
            # 真机取证(Diag-TguiKeys, Windows Terminal + a692909): 其它 Shortcut 键
            # 正常, 唯 Esc/Ctrl+C 无反应; 日志显示两键都**到达**焦点 TableView
            # (VIEW KeyDown: Esc / C,CtrlMask), 但 2.4.10 应用级命令绑定在视图处理
            # 之后才轮到, TableView 消费了 Esc 便永远到不了 Quit; Ctrl+C 在 TG 无
            # Quit 绑定(p22 事实)。按主机选择器 FilterField 同一契约("取消必须
            # 随时可达")在视图处理之前兜底: 直接置 Quit + RequestStop。
            # RequestStop 幂等, 与 TG 内建 Esc->Quit 双路径重入无害。
            $result.Table.add_KeyDown({
                    try {
                        $kArg = $args[1]
                        if ($null -eq $kArg) { return }
                        $keyCode = [string]$kArg.KeyCode
                        if ($keyCode -eq 'Esc' -or
                            ($keyCode -eq 'C' -and [bool]$kArg.IsCtrl)) {
                            $global:TguiPendingAction = 'Quit'
                            if ($global:TguiWindowRef -and $global:TguiRequestStopMethod) {
                                $stopArgs = [object[]]::CreateInstance([System.Object], 1)
                                $stopArgs[0] = $global:TguiWindowRef
                                [void]$global:TguiRequestStopMethod.Invoke($null, $stopArgs)
                            }
                        }
                    } catch {
                        Write-Verbose "[Show-TmuxTuiDashboard] Table KeyDown 取消兜底失败: $($_.Exception.Message)"
                    }
                })

            # ---- 缩放监听: ScreenChanged -> 标记 + RequestStop(重建整窗) ----
            # 探针实测: PowerShell 的 add_<Event> 语法**能**把脚本块转成
            # Terminal.Gui 的 ALC 泛型委托(EventHandler<EventArgs<Rectangle>>),
            # 事件在 TG 事件循环线程上触发 —— 与 Shortcut.Action 同一条通路。
            if ($global:TguiSubscribedApp -ne $appInstance) {
                try {
                    # 无 param: TG 事件触发时参数落到 $args, 正文只读 global 状态 ——
                    # 避免与 PSSA 自动变量名单($sender/$e/$eventArgs...)相撞。
                    $appInstance.add_ScreenChanged({
                            try {
                                $app = $global:TguiAppInstance
                                if ($null -eq $app) { return }
                                $cur = $app.Screen
                                $w = [int]$cur.Width
                                $h = [int]$cur.Height
                                # 零尺寸守卫(2026-10-30 PTY 实测): 部分终端 resize
                                # 瞬间()/未设 winsize 的 PTY 会报 0x0 —— 此时切断
                                # 重建风暴(ScreenChanged 只在下轮循环用到,
                                # 0 尺寸不是有效缩放), 待真实尺寸到来再重建。
                                if ($w -le 0 -or $h -le 0) { return }
                                # ★ 事件报数是第一手数据(2026-10-30 风暴修复):
                                #   存进 TguiScreenW/H, 下一轮建窗优先取它(而非
                                #   Post-Init 可能 0/陈旧的 Screen 读取)。
                                $global:TguiScreenW = $w
                                $global:TguiScreenH = $h
                                # mismatch 判定恒对比**本轮建窗尺寸**(记账值);
                                # 且每个循环轮次只放行**一次**重建(stop 已发出后,
                                # 同一尺寸的后续事件不再 RequestStop) —— 真缩放
                                # 重建一次, 防御同轮事件风叠造成风暴。
                                if ($w -eq $global:TguiLayoutWidth -and $h -eq $global:TguiLayoutHeight) {
                                    return
                                }
                                if ($global:TguiResizeDetected) { return }
                                $global:TguiResizeDetected = $true
                                if ($global:TguiWindowRef -and $global:TguiRequestStopMethod) {
                                    $stopArgs = [object[]]::CreateInstance([System.Object], 1)
                                    $stopArgs[0] = $global:TguiWindowRef
                                    [void]$global:TguiRequestStopMethod.Invoke($null, $stopArgs)
                                }
                            } catch {
                                # 缩放监听失败不影响主流程, 只记日志
                                Write-Verbose "[Show-TmuxTuiDashboard] ScreenChanged 回调失败: $($_.Exception.Message)"
                            }
                        })
                    $global:TguiSubscribedApp = $appInstance
                } catch {
                    Write-Verbose "[Show-TmuxTuiDashboard] 订阅 ScreenChanged 失败(缩放改为按键时检测): $($_.Exception.Message)"
                }
            }
            $global:TguiAppInstance = $appInstance

            # ---- 事件循环: Run(组装好的窗口, handler) 到 RequestStop/Quit ----
            try {
                $global:TguiError = $null
                # 传参用 object[] 手工构造: 避免 @() 展开/包装问题
                $runArgs = [object[]]::CreateInstance([System.Object], 2)
                $runArgs[0] = $result.Window
                $runArgs[1] = $errorHandler
                [void]$runMethod.Invoke($null, $runArgs)
            } catch {
                Write-Warning "[Show-TmuxTuiDashboard] Terminal.Gui Run 失败: $($_.Exception.Message)"
                return 'Exit'
            } finally {
                # 无论 Run 正常还是异常, 都交还终端(还原光标/鼠标/粘贴/备用屏)
                try { $shutdownMethod.Invoke($null, @()) } catch {
                    Write-Verbose "[Show-TmuxTuiDashboard] Run finally 内 Shutdown 失败: $($_.Exception.Message)"
                }
                # ★ Shutdown 会**清空** Application 上的事件订阅(2.4.10 实测:
                #   ScreenChanged 的处理器数 1 -> 0), 而 Application.Instance 在
                #   Init -> Shutdown -> Init 之间是**同一个对象**(ReferenceEquals=True)。
                #   ⇒ 只按实例标识去重的订阅守卫会在第二轮误判"已订阅"而跳过,
                #   结果是第一次交互(附着/新建/删除/刷新)之后 resize 不再触发重建。
                #   所以 Shutdown 之后必须清掉"本轮已订阅"标记, 让下一轮重新订阅。
                $global:TguiSubscribedApp = $null
                # 已交还: 外层 finally 不再重复 Shutdown
                $tgInitialized = $false
            }

            # ---- 消费 errorHandler 捕获的异常 ----
            # errorHandler 只把异常存进 $global:TguiError 并结束事件循环;
            # 此前全链路无人读它 ⇒ 任何渲染/布局异常都变成"仪表盘无声退出"。
            $runError = $global:TguiError
            if ($null -ne $runError) {
                $global:TguiError = $null
                Write-Warning "[Show-TmuxTuiDashboard] Terminal.Gui 渲染异常: $($runError.GetType().Name): $($runError.Message)"
            }

            # ---- 读回选中行(TableView 无 SelectedRow, 用 Value.SelectedCell.Y) ----
            $selected = $null
            try {
                $tableValue = $result.Table.Value
                if ($null -ne $tableValue) {
                    $rowIndex = [int]$tableValue.SelectedCell.Y
                    $rows = @($vm.SessionRows)
                    if ($rowIndex -ge 0 -and $rowIndex -lt $rows.Count) {
                        $selected = $rows[$rowIndex].Name
                    }
                }
            } catch {
                Write-Verbose "[Show-TmuxTuiDashboard] 读取选中行失败: $($_.Exception.Message)"
            }

            $action = $global:TguiPendingAction
            $resized = [bool]$global:TguiResizeDetected

            if ($resized -and $null -eq $action) {
                # 纯缩放(没按键): 用新尺寸重建整窗后继续 —— 列计划随宽度重算
                continue
            }

            if ($null -eq $action -or $action -eq 'Quit') { return 'Exit' }

            # ---- 业务分发(Invoke-TmuxTuiAction 是唯一事实来源) ----
            # 删除走**仪表盘当前选中行**, 不再弹嵌套 PSTui 列表;
            # 二次确认屏障(Read-SpectreConfirm)在 Invoke-TmuxSessionDeletion 里, 不可绕过。
            $outcome = Invoke-TmuxTuiAction -Action $action -HostName $HostName `
                -SelectedSession $selected -State $state
            $previousSelected = $outcome.PreviousSelected
            $state = $null
        }
    } finally {
        # 终端还原(Goal 四: 正常退出 / 异常 / Ctrl-C 都要还原终端):
        # Init 之后、Run 的 finally 之前若抛异常(例如视图组装失败),
        # 终端仍处于 TG 接管状态 —— 这里补一次 Shutdown 交还光标/备用屏。
        # ★ 不变量(2026-10-30 审计#6): $global:Tgui* 的写点全部在 Run 调用之前,
        #   本 finally 是唯一清理点 —— 涵盖 Init 失败的提前 return 'Exit'(:190)
        #   与 Run 失败的 return 'Exit'(:266), 任何路径都不留悬挂的
        #   WindowRef/PendingAction/AppInstance/SubscribedApp 全局。
        if ($tgInitialized) {
            try { $shutdownMethod.Invoke($null, @()) } catch {
                Write-Verbose "[Show-TmuxTuiDashboard] 外层 finally 补偿 Shutdown 失败: $($_.Exception.Message)"
            }
            $tgInitialized = $false
        }
        # 终端所有者还原(异常/Ctrl+C 路径同样走到)
        $script:TmuxTerminalOwner = $previousOwner
        $global:TguiWindowRef = $null
        $global:TguiPendingAction = $null
        $global:TguiAppInstance = $null
        $global:TguiSubscribedApp = $null
        # 事件报数归零: 下一次进入仪表盘重新按"Screen 读取 -> 事件对齐"起步,
        # 不携带上一次会话的陈旧报数(编排契约: 本函数无跨调用会话状态)。
        $global:TguiScreenW = 0
        $global:TguiScreenH = 0
    }
}
