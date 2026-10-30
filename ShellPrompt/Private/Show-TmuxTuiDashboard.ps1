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
    $runGeneric = $tg.Types.Application.GetMethods($staticFlags) |
        Where-Object { $_.Name -eq 'Run' -and $_.IsGenericMethod } |
        Select-Object -First 1
    $runTyped = $runGeneric.MakeGenericMethod($tg.Types.Window)
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

    # 终端所有者: TG 分支期间让 Enter/Exit-TmuxAlternateScreen 静音,
    # 保证"备用屏只有一个所有者"(Goal 四: 禁止重复嵌套备用屏幕)。
    $previousOwner = $script:TmuxTerminalOwner
    $script:TmuxTerminalOwner = 'Tgui'

    # 终端已被 TG 接管(Init 成功)的标记: 异常路径据此补 Shutdown
    $tgInitialized = $false

    try {
        while ($true) {
            # ---- 取数(业务层, 失败自动降级到 Error 视图模型) ----
            try {
                $raw = Invoke-TmuxSessionFetch -HostName $HostName
                $merged = @()
                if ($raw) { $merged = @($raw.Sessions | Where-Object { $null -ne $_ }) }
                $state = Get-TmuxSessionState -SessionData $raw -Sessions $merged
            } catch {
                $raw = $null
                $state = $null
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
            $screen = $screenProperty.GetValue($null)
            $screenWidth = 120
            $screenHeight = 35
            if ($null -ne $screen) {
                try {
                    $screenWidth = [int]$screen.Width
                    $screenHeight = [int]$screen.Height
                } catch {
                    Write-Verbose "[Show-TmuxTuiDashboard] 读取屏幕尺寸失败(用默认值): $($_.Exception.Message)"
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
                                if ($w -ne $global:TguiLayoutWidth -or $h -ne $global:TguiLayoutHeight) {
                                    $global:TguiResizeDetected = $true
                                    if ($global:TguiWindowRef -and $global:TguiRequestStopMethod) {
                                        $stopArgs = [object[]]::CreateInstance([System.Object], 1)
                                        $stopArgs[0] = $global:TguiWindowRef
                                        [void]$global:TguiRequestStopMethod.Invoke($null, $stopArgs)
                                    }
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

            # ---- 事件循环: Run<Window>(handler, driver) 到 RequestStop/Quit ----
            try {
                $runTyped.Invoke($null, @($errorHandler, $driverName))
            } catch {
                Write-Warning "[Show-TmuxTuiDashboard] Terminal.Gui Run 失败: $($_.Exception.Message)"
                return 'Exit'
            } finally {
                # 无论 Run 正常还是异常, 都交还终端(还原光标/鼠标/粘贴/备用屏)
                try { $shutdownMethod.Invoke($null, @()) } catch {
                    Write-Verbose "[Show-TmuxTuiDashboard] Run finally 内 Shutdown 失败: $($_.Exception.Message)"
                }
                # 已交还: 外层 finally 不再重复 Shutdown
                $tgInitialized = $false
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
    }
}
