# Invoke-TguiHostSelector.ps1 - SSH 主机选择器的 **Terminal.Gui v2 事件循环编排**
#
# 背景 (2026-10-30 PSTui 移除 · 主机选择器迁移):
#   原 GridView 轨(PSTui Out-ConsoleGridView)删除后, 主机选择器的交互循环
#   改为与 Show-TmuxTuiDashboard 同构的 "Init → Run → Shutdown → 分发" 编排。
#   业务逻辑(SSH 配置读取、LastHost、Disabled 阻断)全部留在 Show-HostSelector
#   分发器层; 本函数只负责布局/绘制/键盘/缩放/过滤循环。
#
# 生命周期(与仪表盘同一套, 不重复实现终端管理):
#   - 驱动固定 'ansi' + AppModel=FullScreen(TG 独管备用屏, 不与自有 1049 嵌套);
#   - while($true) 每轮: 过滤 → 组装(New-TguiHostSelectorWindow) → Init → Run
#     → Shutdown → 处理 PendingAction;
#   - Enter: 应用级 Shortcut → PendingAction='Select' → RequestStop → Run 返回
#     → 读回 $table.Value.SelectedCell.Y → 返回该行;
#   - Esc: TG 内建 Esc->Quit(Run 返回, 无待处理动作) → 返回 $null(取消);
#   - Ctrl-C: TG 内建 Quit 路径 → 同上(取消);
#   - 过滤(TextField.TextChanged): 写 PendingAction='Filter' + RequestStop,
#     编排层用新 过滤文本 重建整窗(TableView Source 2.4.10 构造后不可替换,
#     探针 p70 实测; 过滤与缩放共用同一条重建路);
#   - 缩放: ScreenChanged → 报数记账 + 单次 RequestStop → 重建(与仪表盘同构)。
#
# refactor注: 非交互护栏(重定向会导致 Run 永久阻塞)必须在触碰 TG 之前,
#   与仪表盘共用 Test-TmuxTuiInteractive 判定。

function Invoke-TguiHostSelector {
    <#
    .SYNOPSIS
        运行主机选择器交互循环, 返回选中行或 $null(取消)。

    .DESCRIPTION
        调用方契约: 传入过滤前的全量行数据与标题; 返回选中的行对象
        (Get-HostSelectorRow 产物, .Value = 主机名), 用户 Esc/取消 返回 $null。

    .PARAMETER Rows
        行数据(Get-HostSelectorRow 产物)。

    .PARAMETER Title
        标题(含主机数/weather 后缀, 调用方拼接)。

    .OUTPUTS
        [PSCustomObject] 选中行, 或 $null(用户取消/非交互环境)。

    .EXAMPLE
        $selected = Invoke-TguiHostSelector -Rows $rows -Title 'SSH 主机选择器'
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Rows,

        [Parameter(Mandatory = $false)]
        [string]$Title = 'SSH 主机选择器'
    )

    # ---- 非交互终端护栏(必须在触碰 TG 之前; 重定向环境下 Run 会永久阻塞) ----
    if (-not (Test-TmuxTuiInteractive)) {
        Write-Warning '[Invoke-TguiHostSelector] 当前不是交互式终端(输入/输出被重定向), 已跳过主机选择器。'
        return $null
    }

    if (-not $Rows -or @($Rows).Count -eq 0) {
        return $null
    }

    $tg = Get-TguiContext

    # ---- Application 反射调用句柄(与仪表盘同一套过滤条件) ----
    $staticFlags = [System.Reflection.BindingFlags]'Public,Static'
    $initMethod = $tg.Types.Application.GetMethods($staticFlags) |
        Where-Object { $_.Name -eq 'Init' } | Select-Object -First 1
    $shutdownMethod = $tg.Types.Application.GetMethod('Shutdown', $staticFlags)
    # 非泛型 Run(IRunnable, Func<Exception,bool>): 泛型 Run<T> 内部 new 全新实例,
    # 组装好的窗口从不上屏(仪表盘轨实测教训)。
    $runMethod = $tg.Types.Application.GetMethods($staticFlags) |
        Where-Object {
            $_.Name -eq 'Run' -and
            -not $_.IsGenericMethodDefinition -and
            $_.GetParameters().Count -eq 2 -and
            $_.GetParameters()[0].ParameterType.IsAssignableFrom($tg.Types.Window)
        } |
        Select-Object -First 1
    if ($null -eq $runMethod) {
        Write-Warning '[Invoke-TguiHostSelector] Terminal.Gui 缺少 Run(IRunnable, Func) 重载, 已中止。'
        return $null
    }
    $stopMethod = $tg.Types.Application.GetMethods($staticFlags) |
        Where-Object { $_.Name -eq 'RequestStop' } | Select-Object -First 1
    $instanceProperty = $tg.Types.Application.GetProperty('Instance', $staticFlags)
    $screenProperty = $tg.Types.Application.GetProperty('Screen', $staticFlags)

    $driverName = 'ansi'
    $errorHandler = [System.Func[[exception], [bool]]]{ param($ex)
        $global:TguiHostSelError = $ex
        $false
    }

    # ---- 状态(跨重建保留) ----
    $filter = ''
    $previousHost = ''
    $selectedRow = $null

    $global:TguiHostSelPendingAction = $null
    $global:TguiHostSelResized = $false
    $global:TguiHostSelError = $null
    $global:TguiHostSelFilterText = $filter
    $global:TguiHostSelAppliedFilter = $filter
    $global:TguiHostSelScreenW = 0
    $global:TguiHostSelScreenH = 0
    $global:TguiHostSelSubscribedApp = $null
    $global:TguiHostSelFieldRef = $null

    # dispatch: 动作回调 → PendingAction + RequestStop(TG 事件循环跨会话,
    # 载荷走 global —— 与仪表盘同一条既有通路)。
    $dispatch = { param($a)
        $global:TguiHostSelPendingAction = $a
        if ($global:TguiHostSelWindowRef -and $global:TguiHostSelStopMethod) {
            $stopArgs = [object[]]::CreateInstance([System.Object], 1)
            $stopArgs[0] = $global:TguiHostSelWindowRef
            [void]$global:TguiHostSelStopMethod.Invoke($null, $stopArgs)
        }
    }

    $tgInitialized = $false

    try {
        while ($true) {
            # ---- 过滤(纯 PowerShell 业务无关过滤, 键列保留) ----
            $allRows = @($Rows)
            $appliedFilter = [string]$global:TguiHostSelAppliedFilter
            if ($appliedFilter) {
                $filtered = @($allRows | Where-Object {
                        $_.Host -and ($_.Host.IndexOf($appliedFilter, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
                    })
            } else {
                $filtered = $allRows
            }

            # ---- 初始行号(上次选中/确认的行, 幸存即保留) ----
            $selectedIndex = -1
            if ($previousHost) {
                for ($i = 0; $i -lt $filtered.Count; $i++) {
                    if ($filtered[$i].Host -eq $previousHost) { $selectedIndex = $i; break }
                }
                if ($selectedIndex -lt 0) { $previousHost = '' }
            }

            # ---- 组装窗口(标题/过滤文本回填/预选) ----
            $result = New-TguiHostSelectorWindow -Title $Title -Rows $filtered `
                -Filter $appliedFilter -Dispatch $dispatch -SelectedIndex $selectedIndex

            $global:TguiHostSelWindowRef = $result.Window
            $global:TguiHostSelStopMethod = $stopMethod
            $global:TguiHostSelFieldRef = $result.FilterField

            # ---- Init(AppModel=FullScreen: 'ansi' 驱动走备用屏) ----
            try {
                try {
                    $tg.Types.Application.GetProperty('AppModel', $staticFlags).SetValue($null, $tg.Types.AppModel.GetProperty('FullScreen').GetValue($null))
                } catch {
                    Write-Verbose "[Invoke-TguiHostSelector] 设置 AppModel 失败(用默认值): $($_.Exception.Message)"
                }
                $initMethod.Invoke($null, @($driverName))
                $tgInitialized = $true
            } catch {
                Write-Warning "[Invoke-TguiHostSelector] Terminal.Gui Init 失败: $($_.Exception.Message)"
                return $null
            }

            $appInstance = $instanceProperty.GetValue($null)

            # ---- 记账尺寸(事件报数优先, Post-Init Screen 读取兜底) ----
            $screenWidth = 120
            $screenHeight = 35
            if ($global:TguiHostSelScreenW -gt 0 -and $global:TguiHostSelScreenH -gt 0) {
                $screenWidth = [int]$global:TguiHostSelScreenW
                $screenHeight = [int]$global:TguiHostSelScreenH
            } else {
                $screen = $screenProperty.GetValue($null)
                if ($null -ne $screen) {
                    try {
                        $screenWidth = [int]$screen.Width
                        $screenHeight = [int]$screen.Height
                    } catch {
                        Write-Verbose "[Invoke-TguiHostSelector] 读取屏幕尺寸失败(用默认值): $($_.Exception.Message)"
                    }
                }
            }
            if ($screenWidth -lt 40) { $screenWidth = 40 }
            if ($screenHeight -lt 10) { $screenHeight = 10 }
            $global:TguiHostSelLayoutW = $screenWidth
            $global:TguiHostSelLayoutH = $screenHeight

            # ---- 初始焦点: 过滤框(打字即搜) ----
            try {
                [void]$result.FilterField.SetFocus()
            } catch {
                Write-Verbose "[Invoke-TguiHostSelector] 设置过滤框焦点失败: $($_.Exception.Message)"
            }

            # ---- TextChanged → 过滤重建(与缩放同一条 RequestStop 路径) ----
            # TextChanged 在回填同样的文本时也会触发 —— 用"已应用过滤"值守卫,
            # 只对真正的用户输入放行重建, 否则无限循环。
            $result.FilterField.add_TextChanged({
                    try {
                        $fieldRef = $global:TguiHostSelFieldRef
                        if ($null -eq $fieldRef) { return }
                        $text = [string]$fieldRef.Text
                        if ($text -ceq [string]$global:TguiHostSelAppliedFilter) { return }
                        $global:TguiHostSelFilterText = $text
                        $global:TguiHostSelPendingAction = 'Filter'
                        if ($global:TguiHostSelWindowRef -and $global:TguiHostSelStopMethod) {
                            $stopArgs = [object[]]::CreateInstance([System.Object], 1)
                            $stopArgs[0] = $global:TguiHostSelWindowRef
                            [void]$global:TguiHostSelStopMethod.Invoke($null, $stopArgs)
                        }
                    } catch {
                        Write-Verbose "[Invoke-TguiHostSelector] TextChanged 回调失败: $($_.Exception.Message)"
                    }
                })

            # ---- 缩放监听(ScreenChanged → 报数 + 单次 RequestStop) ----
            if ($global:TguiHostSelSubscribedApp -ne $appInstance) {
                try {
                    $appInstance.add_ScreenChanged({
                            try {
                                if ($global:TguiHostSelResized) { return }
                                $app = $global:TguiHostSelAppInstance
                                if ($null -eq $app) { return }
                                $cur = $app.Screen
                                $w = [int]$cur.Width
                                $h = [int]$cur.Height
                                if ($w -le 0 -or $h -le 0) { return }
                                $global:TguiHostSelScreenW = $w
                                $global:TguiHostSelScreenH = $h
                                if ($w -eq $global:TguiHostSelLayoutW -and $h -eq $global:TguiHostSelLayoutH) {
                                    return
                                }
                                $global:TguiHostSelResized = $true
                                if ($global:TguiHostSelWindowRef -and $global:TguiHostSelStopMethod) {
                                    $stopArgs = [object[]]::CreateInstance([System.Object], 1)
                                    $stopArgs[0] = $global:TguiHostSelWindowRef
                                    [void]$global:TguiHostSelStopMethod.Invoke($null, $stopArgs)
                                }
                            } catch {
                                Write-Verbose "[Invoke-TguiHostSelector] ScreenChanged 回调失败: $($_.Exception.Message)"
                            }
                        })
                    $global:TguiHostSelSubscribedApp = $appInstance
                } catch {
                    Write-Verbose "[Invoke-TguiHostSelector] 订阅 ScreenChanged 失败(缩放改为按键时检测): $($_.Exception.Message)"
                }
            }
            $global:TguiHostSelAppInstance = $appInstance

            # ---- 事件循环 ----
            $global:TguiHostSelPendingAction = $null
            $global:TguiHostSelResized = $false
            try {
                $runArgs = [object[]]::CreateInstance([System.Object], 2)
                $runArgs[0] = $result.Window
                $runArgs[1] = $errorHandler
                [void]$runMethod.Invoke($null, $runArgs)
            } catch {
                Write-Warning "[Invoke-TguiHostSelector] Terminal.Gui Run 失败: $($_.Exception.Message)"
                return $null
            } finally {
                try { $shutdownMethod.Invoke($null, @()) } catch {
                    Write-Verbose "[Invoke-TguiHostSelector] Run finally 内 Shutdown 失败: $($_.Exception.Message)"
                }
                # Shutdown 会清空 Application 事件订阅(2.4.10 实测) —— 清掉
                # "本轮已订阅"标记, 下一轮重新订阅(Event storm 第一手数据保障)。
                $global:TguiHostSelSubscribedApp = $null
                $tgInitialized = $false
            }

            # ---- 消费渲染异常(errorHandler 不再向上抛) ----
            $runError = $global:TguiHostSelError
            if ($null -ne $runError) {
                $global:TguiHostSelError = $null
                Write-Warning "[Invoke-TguiHostSelector] Terminal.Gui 渲染异常: $($runError.GetType().Name): $($runError.Message)"
            }

            # ---- 读回选中行(Selection 读回契约同仪表盘) ----
            $selectedRow = $null
            try {
                $tableValue = $result.Table.Value
                if ($null -ne $tableValue -and $filtered.Count -gt 0) {
                    $rowIndex = [int]$tableValue.SelectedCell.Y
                    if ($rowIndex -ge 0 -and $rowIndex -lt $filtered.Count) {
                        $selectedRow = $filtered[$rowIndex]
                    }
                }
            } catch {
                Write-Verbose "[Invoke-TguiHostSelector] 读取选中行失败: $($_.Exception.Message)"
            }

            $action = $global:TguiHostSelPendingAction
            $resized = [bool]$global:TguiHostSelResized

            if ($resized -and $null -eq $action) {
                # 纯缩放: 用新尺寸重建, 保留过滤/选中
                continue
            }

            switch ($action) {
                'Filter' {
                    $filter = [string]$global:TguiHostSelFilterText
                    $global:TguiHostSelAppliedFilter = $filter
                    continue
                }
                'Select' {
                    if ($null -eq $selectedRow) {
                        # 无匹配行时 Enter: 不退出也不崩溃, 回到事件循环
                        continue
                    }
                    return $selectedRow
                }
                default {
                    # $null(Esc/Ctrl-C 内建 Quit)等无待处理动作 → 用户取消
                    return $null
                }
            }
        }
    } finally {
        if ($tgInitialized) {
            try { $shutdownMethod.Invoke($null, @()) } catch {
                Write-Verbose "[Invoke-TguiHostSelector] 外层 finally 补偿 Shutdown 失败: $($_.Exception.Message)"
            }
            $tgInitialized = $false
        }
        $global:TguiHostSelWindowRef = $null
        $global:TguiHostSelStopMethod = $null
        $global:TguiHostSelFieldRef = $null
        $global:TguiHostSelActionDispatch = $null
        $global:TguiHostSelAppInstance = $null
        $global:TguiHostSelSubscribedApp = $null
        $global:TguiHostSelPendingAction = $null
        $global:TguiHostSelResized = $false
        $global:TguiHostSelError = $null
        $global:TguiHostSelScreenW = 0
        $global:TguiHostSelScreenH = 0
    }
}
