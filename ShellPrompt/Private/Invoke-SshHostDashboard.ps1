# Invoke-SshHostDashboard.ps1 - SSH 主机仪表盘的 **事件循环编排层**
#
# 背景 (2026-10-31 sss 仪表盘重构 · Goal 四 性能主战场):
#   旧主机选择器用 TableView 渲染, 上下键移动选中时 TG 把**整张表**标脏,
#   每次按键都重绘整表(实测 15ms/次, 见 .agent_cache/dash-probe/p13-rowproto.ps1),
#   在 Windows Terminal 上就是用户报的 100~200ms 延迟。
#   新仪表盘改为"每行一组 Label"的复合列表, 移动选中时**只重刷旧/新两行**
#   (实测 4.4ms/次, 脏区 = 两行)。
#
# ★ 本编排层的硬约束(逐条对应 Goal 四):
#   1. **键盘热路径里绝不做网络/文件 I/O**:
#      KeyDown 回调只做内存态更新(改两行的 Text/Scheme + 改详情 Label 的 Text)。
#      连"提交后台探测"都不放在按键回调里 —— Start-ThreadJob 自身有 ~50ms 的
#      runspace 创建开销, 放在按键路径上就是白给的延迟。提交动作交给
#      **AddTimeout 心跳**(在主循环里跑, 与按键处理错开)。
#   2. **不重建 View**: 分类切换 / 搜索过滤都只重填列表槽位
#      (Set-SshHostListScroll), 不重新 New-SshHostDashboardWindow。
#      只有**终端缩放**才重建(几何变了, 必须重排)。
#   3. **详情面板分两级**: 选中主机后**先立即**用本地数据刷新
#      (Set-SshHostDetailBasic, 无网络), 远端数据**后到**(异步)。
#   4. **旧请求不许覆盖新选择**: 每次选择变化生成新的请求标识
#      ("<host>#<seq>"), 详情回填前校验 RequestId + 主机名双重匹配;
#      主机切换时旧的在飞请求被**显式取消**(Stop-Job)。
#   5. **不重复查询**: 探测结果按主机名缓存(DetailByHost), 回到已探测过的
#      主机直接回填缓存, 不再发请求。
#
# ★ 为什么用 Application.AddTimeout 而不是自己开线程轮询:
#   TG 2.4.10 的 Application.AddTimeout(TimeSpan, Func<bool>) 在**主循环**里
#   触发, 回调本身就在 UI 线程上 —— 于是"后台作业的结果回填 UI"不需要任何
#   跨线程调度原语, 天然满足 Goal 四-3 的"把结果调度回 UI 线程"。
#   回调返回 true 表示继续注册, 返回 false 表示停止(实测 p33 已验证)。
#   Application.Invoke(Action) 在 UI 线程上调用是**同步**执行的(p32/p33 实测),
#   因此可作为"从非 UI 线程调度回 UI"的兜底通道。
#
# ★ 键位事实来源: 本编排层的 KeyDown 处理器是**唯一**的键位实现;
#   底栏(New-SshHostDashboardWindow 的 ShortcutBar)是纯展示件, 文案与本文件
#   的实际行为一一对应(Goal 三-4 "快捷键必须与实际操作一致")。
#
# ★ 事件订阅的生命周期: TG 的 Shutdown 会清空 Application 事件订阅
#   (2.4.10 实测), 而 Application.Instance 不随周期变化 —— 因此"已订阅"
#   的去重标记必须在 Shutdown 之后清掉, 否则第二轮 resize 不再触发重建
#   (与 Show-TmuxTuiDashboard 同一坑, 见 tui-dashboard.md §2.11)。

function Invoke-SshHostDashboard {
    <#
    .SYNOPSIS
        运行 SSH 主机仪表盘的交互循环, 返回选中的主机或 $null(取消)。

    .DESCRIPTION
        编排层职责:
          - 数据装配: 主机档案 + 本地活动历史 -> 行视图模型(Get-SshHostDashboardRow);
          - 分类导航: 分类名由真实档案推导(Get-SshHostCategoryList), 切换分类
            只做**本地过滤**(Select-SshHostByCategory), **不发任何 SSH 请求**;
          - 键盘: ↑↓ 移动选中 / Enter 连接 / / 搜索 / Tab 切换区域 /
            ←→ 切换分类 / Esc 返回;
          - 异步详情: 远端探测走后台线程作业(Start-SshHostDetailTask),
            由 AddTimeout 心跳非阻塞收割, 旧请求按 RequestId 丢弃;
          - 缩放: ScreenChanged 报数 -> RequestStop -> 按新几何重建整窗。

        **非交互终端护栏**: 输入/输出被重定向时直接返回 $null ——
        TG 的 Init 在无 TTY 环境不抛异常但事件循环会永久阻塞
        (与 Test-TmuxTuiInteractive 的既有约定一致)。

    .PARAMETER Profiles
        主机档案数组(Get-SshHostProfile 产物)。空则直接返回 $null。

    .PARAMETER Activity
        本地活动历史数组(Get-SshHostActivity -All 产物), 可为空。

    .PARAMETER AllowedHosts
        主机白名单(来自 Show-HostSelector 的 -Hosts 契约); 为空表示不过滤。

    .PARAMETER LastHost
        上次使用的主机名(列表置顶 + 标题带右半展示)。

    .PARAMETER InitialFilter
        初始搜索过滤文本。

    .PARAMETER Title
        标题带左半文本(缺省 'ShellPrompt · SSH 主机')。

    .PARAMETER TitleSuffix
        标题带后缀(如天气串), 直接接在标题文本之后。

    .OUTPUTS
        PSCustomObject(.HostName/.Profile/.Row) 或 $null(用户取消 / 非交互环境)。

    .EXAMPLE
        $picked = Invoke-SshHostDashboard -Profiles $profiles -LastHost 'deb'
        if ($picked) { $picked.HostName }
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [object[]]$Profiles = @(),

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [object[]]$Activity = @(),

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$AllowedHosts = @(),

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$LastHost = '',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$InitialFilter = '',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Title = '',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$TitleSuffix = ''
    )

    # ---- 非交互终端护栏(必须在触碰 TG 之前) ----
    if (-not (Test-TmuxTuiInteractive)) {
        Write-Warning '[Invoke-SshHostDashboard] 当前不是交互式终端(输入/输出被重定向), 已跳过 SSH 主机仪表盘。'
        return $null
    }

    if (-not $Profiles -or @($Profiles).Count -eq 0) { return $null }

    # ---- 主机白名单(Show-HostSelector 的 -Hosts 契约: 只显示被点名的���机) ----
    $effectiveProfiles = @($Profiles)
    if ($AllowedHosts -and @($AllowedHosts).Count -gt 0) {
        $allowed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($h in $AllowedHosts) {
            if (-not [string]::IsNullOrWhiteSpace($h)) { [void]$allowed.Add([string]$h) }
        }
        $effectiveProfiles = @($effectiveProfiles | Where-Object { $null -ne $_ -and $allowed.Contains([string]$_.Name) })
    }
    if ($effectiveProfiles.Count -eq 0) { return $null }

    $tg = Get-TguiContext
    $theme = Get-SshHostDashboardTheme -Tgui $tg

    # ---- Application 反射句柄(与既有仪表盘同一套过滤条件) ----
    $static = [System.Reflection.BindingFlags]'Public,Static'
    $initMethod = $tg.Types.Application.GetMethods($static) |
        Where-Object { $_.Name -eq 'Init' } | Select-Object -First 1
    $shutdownMethod = $tg.Types.Application.GetMethod('Shutdown', $static)
    # 非泛型 Run(IRunnable, Func<Exception,bool>): 泛型 Run<T> 内部 new 全新实例,
    # 组装好的窗口从不上屏(见 tui-dashboard.md §2.10)。
    $runMethod = $tg.Types.Application.GetMethods($static) |
        Where-Object {
            $_.Name -eq 'Run' -and
            -not $_.IsGenericMethodDefinition -and
            $_.GetParameters().Count -eq 2 -and
            $_.GetParameters()[0].ParameterType.IsAssignableFrom($tg.Types.Window)
        } |
        Select-Object -First 1
    if ($null -eq $runMethod) {
        Write-Warning '[Invoke-SshHostDashboard] Terminal.Gui 缺少 Run(IRunnable, Func) 重载, 已中止。'
        return $null
    }
    $stopMethod = $tg.Types.Application.GetMethods($static) |
        Where-Object { $_.Name -eq 'RequestStop' } | Select-Object -First 1
    $instanceProperty = $tg.Types.Application.GetProperty('Instance', $static)
    $screenProperty = $tg.Types.Application.GetProperty('Screen', $static)
    $addTimeoutMethod = $tg.Types.Application.GetMethods($static) |
        Where-Object { $_.Name -eq 'AddTimeout' } | Select-Object -First 1
    # 注: Application.RemoveTimeout 不需要显式调用 —— 心跳令牌随 Shutdown 失效,
    #     Shutdown 后重新 Init + AddTimeout 即是新一轮心跳(见 tui-dashboard.md §2.11)。

    # ---- 编排状态(跨重建保留) ----
    $state = New-SshHostDashboardState -Profiles $effectiveProfiles -Activity $Activity `
        -LastHost $LastHost -Category 'All' -Filter $InitialFilter -Theme $theme -Tgui $tg

    $global:TguiDashState = $state
    $global:TguiDashStopMethod = $stopMethod
    $global:TguiDashError = $null
    $global:TguiDashAction = $null
    $global:TguiDashResized = $false
    $global:TguiDashScreenW = 0
    $global:TguiDashScreenH = 0
    $global:TguiDashSubscribedApp = $null
    $global:TguiDashAppInstance = $null
    $global:TguiDashTimeoutToken = $null
    $global:TguiDashAppliedFilter = $InitialFilter
    $global:TguiDashLayoutW = 0
    $global:TguiDashLayoutH = 0

    $tgInitialized = $false

    try {
        while ($true) {
            # ================= 1. 装配行数据(纯本地, 无网络) =================
            $rows = @(Get-SshHostDashboardRowList -State $state)
            $state.Rows = $rows

            # 初始选中: 上次使用的主机优先, 否则第一行
            $selectedIndex = -1
            if ($state.LastHost) {
                for ($i = 0; $i -lt $rows.Count; $i++) {
                    if ([string]$rows[$i].Name -eq $state.LastHost) { $selectedIndex = $i; break }
                }
            }
            if ($selectedIndex -lt 0 -and $rows.Count -gt 0) { $selectedIndex = 0 }
            $state.SelectedIndex = $selectedIndex
            $state.SelectedHost = if ($selectedIndex -ge 0) { [string]$rows[$selectedIndex].Name } else { '' }

            # ================= 2. 组装整窗 =================
            $lastHostText = ''
            if ($state.LastHost) { $lastHostText = "上次: $($state.LastHost)" }
            $titleText = if ([string]::IsNullOrWhiteSpace($Title)) { 'ShellPrompt · SSH 主机' } else { $Title }
            if (-not [string]::IsNullOrWhiteSpace($TitleSuffix)) { $titleText = "$titleText$TitleSuffix" }

            $result = New-SshHostDashboardWindow -Rows $rows -Title $titleText `
                -Categories $state.Categories -ActiveCategory $state.Category `
                -SelectedIndex $selectedIndex -Theme $theme `
                -InfoText (Get-SshHostDashboardInfoText -State $state) `
                -SearchText $state.Filter -SearchActive $state.SearchActive `
                -LastHostText $lastHostText `
                -WindowWidth $state.WindowWidth -WindowHeight $state.WindowHeight

            if ($null -eq $result) { return $null }

            $state.Window = $result.Window
            $state.ListView = $result.ListView
            $state.DetailPanel = $result.DetailPanel
            $state.CategoryBar = @($result.CategoryBar)
            $state.InfoLabel = $result.InfoLabel
            $state.SearchField = $result.SearchField
            $state.SearchPrompt = $result.SearchPrompt
            $state.ShortcutBar = $result.ShortcutBar

            # 分类栏方案登记随重建清空(新窗口 = 新 Label, 旧登记不再有效)
            $state.CategorySchemes = @{}

            # ================= 3. 选中态落地(重建后) =================
            if ($selectedIndex -ge 0) {
                Update-SshHostDashboardSelection -State $state -NewIndex $selectedIndex
            }

            # ================= 4. 挂事件 =================
            Register-SshHostDashboardKeyHandler -State $state

            # 缩放监听: ScreenChanged -> 报数 + 单次 RequestStop
            $appInstance = $instanceProperty.GetValue($null)
            if ($global:TguiDashSubscribedApp -ne $appInstance) {
                try {
                    $appInstance.add_ScreenChanged({
                            try {
                                $app = $global:TguiDashAppInstance
                                if ($null -eq $app) { return }
                                $cur = $app.Screen
                                $w = [int]$cur.Width
                                $h = [int]$cur.Height
                                if ($w -le 0 -or $h -le 0) { return }
                                $global:TguiDashScreenW = $w
                                $global:TguiDashScreenH = $h
                                if ($w -eq $global:TguiDashLayoutW -and $h -eq $global:TguiDashLayoutH) { return }
                                $global:TguiDashResized = $true
                                if ($global:TguiDashState -and $global:TguiDashState.Window -and $global:TguiDashStopMethod) {
                                    $stopArgs = [object[]]::CreateInstance([System.Object], 1)
                                    $stopArgs[0] = $global:TguiDashState.Window
                                    [void]$global:TguiDashStopMethod.Invoke($null, $stopArgs)
                                }
                            }
                            catch {
                                Write-Verbose "[Invoke-SshHostDashboard] ScreenChanged 回调失败: $($_.Exception.Message)"
                            }
                        })
                    $global:TguiDashSubscribedApp = $appInstance
                }
                catch {
                    Write-Verbose "[Invoke-SshHostDashboard] 订阅 ScreenChanged 失败: $($_.Exception.Message)"
                }
            }
            $global:TguiDashAppInstance = $appInstance

            # ================= 5. Init =================
            try {
                try {
                    $tg.Types.Application.GetProperty('AppModel', $static).SetValue(
                        $null, $tg.Types.AppModel.GetProperty('FullScreen').GetValue($null))
                }
                catch {
                    Write-Verbose "[Invoke-SshHostDashboard] 设置 AppModel 失败(用默认值): $($_.Exception.Message)"
                }
                $initMethod.Invoke($null, @('ansi'))
                $tgInitialized = $true
            }
            catch {
                Write-Warning "[Invoke-SshHostDashboard] Terminal.Gui Init 失败: $($_.Exception.Message)"
                return $null
            }

            # ================= 5b. 初始焦点 =================
            # 必须**显式**把焦点给列表容器: 本窗有两个可聚焦子视图(列表 / 搜索框),
            # 不能依赖 TG "自动选第一个" 的隐式行为 —— 焦点一旦落在隐藏的搜索框,
            # 方向键就永远到不了列表(表现为"界面出来了但按键没反应")。
            # 搜索态时则聚焦搜索框(过滤文本需要保留)。
            try {
                if ($state.FocusArea -eq 'Search' -and $null -ne $state.SearchField) {
                    [void]$state.SearchField.SetFocus()
                }
                else {
                    [void]$state.ListView.View.SetFocus()
                }
            }
            catch {
                Write-Verbose "[Invoke-SshHostDashboard] 设置初始焦点失败: $($_.Exception.Message)"
            }

            # ================= 6. 尺寸记账 =================
            $screenWidth = $state.WindowWidth
            $screenHeight = $state.WindowHeight
            if ($global:TguiDashScreenW -gt 0 -and $global:TguiDashScreenH -gt 0) {
                $screenWidth = [int]$global:TguiDashScreenW
                $screenHeight = [int]$global:TguiDashScreenH
            }
            else {
                $screen = $screenProperty.GetValue($null)
                if ($null -ne $screen) {
                    try {
                        $screenWidth = [int]$screen.Width
                        $screenHeight = [int]$screen.Height
                    }
                    catch {
                        Write-Verbose "[Invoke-SshHostDashboard] 读取屏幕尺寸失败(用默认值): $($_.Exception.Message)"
                    }
                }
            }
            if ($screenWidth -lt 40) { $screenWidth = 40 }
            if ($screenHeight -lt 10) { $screenHeight = 10 }
            $state.WindowWidth = $screenWidth
            $state.WindowHeight = $screenHeight
            $global:TguiDashLayoutW = $screenWidth
            $global:TguiDashLayoutH = $screenHeight

            # ================= 7. 心跳(异步探测的非阻塞收割) =================
            if ($null -ne $addTimeoutMethod) {
                $tick = [System.Func[bool]]{
                    try {
                        Update-SshHostDashboardProbe -State $global:TguiDashState
                    }
                    catch {
                        Write-Verbose "[Invoke-SshHostDashboard] 心跳回调失败: $($_.Exception.Message)"
                    }
                    return $true
                }
                $timeSpan = [TimeSpan]::FromMilliseconds(120)
                $global:TguiDashTimeoutToken = $addTimeoutMethod.Invoke($null, @($timeSpan, $tick))
            }

            # ================= 8. 事件循环 =================
            $global:TguiDashAction = $null
            $global:TguiDashResized = $false
            try {
                $runArgs = [object[]]::CreateInstance([System.Object], 2)
                $runArgs[0] = $result.Window
                $runArgs[1] = [System.Func[[exception], [bool]]]{
                        param($ex)
                        $global:TguiDashError = $ex
                        $false
                    }
                [void]$runMethod.Invoke($null, $runArgs)
            }
            catch {
                Write-Warning "[Invoke-SshHostDashboard] Terminal.Gui Run 失败: $($_.Exception.Message)"
                return $null
            }
            finally {
                try { $shutdownMethod.Invoke($null, @()) } catch {
                    Write-Verbose "[Invoke-SshHostDashboard] Run finally 内 Shutdown 失败: $($_.Exception.Message)"
                }
                # Shutdown 会清空 Application 事件订阅 —— 清掉"本轮已订阅"标记
                $global:TguiDashSubscribedApp = $null
                # 心跳令牌随会话失效
                $global:TguiDashTimeoutToken = $null
                $tgInitialized = $false
            }

            # ================= 9. 消费渲染异常 =================
            $runError = $global:TguiDashError
            if ($null -ne $runError) {
                $global:TguiDashError = $null
                Write-Warning "[Invoke-SshHostDashboard] Terminal.Gui 渲染异常: $($runError.GetType().Name): $($runError.Message)"
            }

            # ================= 10. 分派 =================
            $action = [string]$global:TguiDashAction
            $resized = [bool]$global:TguiDashResized

            if ($action -eq 'Connect') {
                $picked = $state.SelectedRow
                if ($null -ne $picked) {
                    $hostProfile = $null
                    foreach ($p in @($state.Profiles)) {
                        if ($null -ne $p -and [string]$p.Name -eq [string]$picked.Name) { $hostProfile = $p; break }
                    }
                    return [PSCustomObject]@{
                        HostName = [string]$picked.Name
                        Profile  = $hostProfile
                        Row      = $picked
                    }
                }
                return $null
            }

            if ($action -eq 'Quit') { return $null }

            if ($resized) {
                # 纯缩放: 按新几何重建(保留分类/过滤/选中/探测缓存)
                continue
            }

            # 没有待处理动作: TG 内建 Quit(Esc)路径 -> 用户取消
            return $null
        }
    }
    finally {
        if ($tgInitialized) {
            try { $shutdownMethod.Invoke($null, @()) } catch {
                Write-Verbose "[Invoke-SshHostDashboard] 外层 finally 补偿 Shutdown 失败: $($_.Exception.Message)"
            }
            $tgInitialized = $false
        }
        # 收尾: 停掉后台探测作业(不留孤儿 runspace)
        if ($null -ne $state.DetailProbe) {
            Stop-SshHostDashboardProbe -Probe $state.DetailProbe
            $state.DetailProbe = $null
        }
        $global:TguiDashState = $null
        $global:TguiDashStopMethod = $null
        $global:TguiDashAppInstance = $null
        $global:TguiDashSubscribedApp = $null
        $global:TguiDashTimeoutToken = $null
        $global:TguiDashAction = $null
        $global:TguiDashResized = $false
        $global:TguiDashError = $null
        $global:TguiDashScreenW = 0
        $global:TguiDashScreenH = 0
    }
}

function New-SshHostDashboardState {
    <#
    .SYNOPSIS
        构造仪表盘的编排状态对象(数据部分, 纯本地, 不碰终端)。

    .DESCRIPTION
        把"状态"从编排主流程里拆出来, 好处有二:
          1. 编排层只管"事件循环 + 视图装配", 状态构造一目了然;
          2. **可单测** —— 测试可以只造状态、不进事件循环, 直接验证
             "分类切换不发请求""旧请求不覆盖新选择"这类契约。

        状态字段:
          Profiles/Activity/ActivityMap  数据源(活动按主机名索引, 大小写不敏感)
          Categories/Category/Filter      分类与搜索过滤
          Rows                            当前视图的行模型(由 Get-SshHostDashboardRowList 填)
          SelectedIndex/SelectedHost      选中态
          StatusByHost/DetailByHost       探测结果缓存(真实数据, 不伪造)
          DetailProbe                     在飞的后台探测句柄
          ActiveRequestId/RequestSeq      请求标识(丢弃旧请求的唯一凭据)
          Window/ListView/DetailPanel/... 视图句柄(装配阶段填)
          Perf                            关键路径耗时计数

    .PARAMETER Profiles
        主机档案数组。

    .PARAMETER Activity
        本地活动历史数组。

    .PARAMETER LastHost
        上次使用的主机名。

    .PARAMETER Category
        初始分类(缺省 'All')。

    .PARAMETER Filter
        初始搜索过滤文本。

    .PARAMETER Theme
        Get-SshHostDashboardTheme 产物。

    .PARAMETER Tgui
        Get-TguiContext 产物。

    .OUTPUTS
        PSCustomObject 状态对象。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Profiles,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [object[]]$Activity = @(),

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$LastHost = '',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Category = 'All',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Filter = '',

        [Parameter(Mandatory = $true)]
        [object]$Theme,

        [Parameter(Mandatory = $true)]
        [object]$Tgui
    )

    # ---- 活动历史索引(按主机名, 大小写不敏感) ----
    $activityMap = @{}
    foreach ($a in @($Activity)) {
        if ($null -eq $a) { continue }
        $aKey = [string](Get-SshHostProp -Object $a -Name 'Host')
        if (-not [string]::IsNullOrWhiteSpace($aKey)) { $activityMap[$aKey.ToLowerInvariant()] = $a }
    }

    return [PSCustomObject]@{
        Profiles        = @($Profiles)
        Activity        = @($Activity)
        ActivityMap     = $activityMap
        LastHost        = $LastHost
        Categories      = @(Get-SshHostCategoryList -Profiles $Profiles)
        Category        = $Category
        Filter          = $Filter
        SearchActive    = $false
        FocusArea       = 'List'
        Rows            = @()
        SelectedIndex   = -1
        SelectedHost    = ''
        StatusByHost    = @{}
        DetailByHost    = @{}
        DetailProbe     = $null
        ActiveRequestId = ''
        RequestSeq      = 0
        Window          = $null
        ListView        = $null
        DetailPanel     = $null
        CategoryBar     = @()
        CategorySchemes = @{}
        InfoLabel       = $null
        SearchField     = $null
        SearchPrompt    = $null
        ShortcutBar     = $null
        WindowWidth     = 120
        WindowHeight    = 35
        Action          = $null
        SelectedRow     = $null
        Theme           = $Theme
        Tgui            = $Tgui
        Perf            = [PSCustomObject]@{
            KeyHandlerMs = 0.0
            SelectionMs  = 0.0
            DrawMs       = 0.0
            DetailLoadMs = 0.0
            KeyCount     = 0
            ProbeCount   = 0
        }
    }
}

function Get-SshHostDashboardRowList {
    <#
    .SYNOPSIS
        按当前分类 + 过滤文本算出列表行(纯本地, 不发任何请求)。

    .DESCRIPTION
        流程: 分类过滤(Select-SshHostByCategory) -> 文本过滤/排序/映射
        (Get-SshHostDashboardRow) -> 回填**已探测到的**状态缓存。
        状态缓存只来自真实探测结果(DetailByHost / StatusByHost), 没有记录
        的一律 Unknown(灰) —— 绝不猜。

    .PARAMETER State
        编排状态对象。

    .OUTPUTS
        行视图模型数组。
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$State
    )

    $filtered = @(Select-SshHostByCategory -Profiles $State.Profiles -Category $State.Category)
    $rows = @(Get-SshHostDashboardRow -Profile $filtered -Activity $State.Activity `
            -LastHost $State.LastHost -Filter $State.Filter)

    foreach ($row in $rows) {
        $key = ([string]$row.Name).ToLowerInvariant()
        if ($State.StatusByHost.ContainsKey($key)) {
            Set-SshHostDashboardRowStatus -Row $row -Status ([string]$State.StatusByHost[$key])
        }
    }
    return $rows
}

function Set-SshHostDashboardRowStatus {
    <#
    .SYNOPSIS
        就地更新一行的状态展示字段(状态点字符 / 文案 / 配色角色)。

    .PARAMETER Row
        行视图模型对象(PSCustomObject, 字段可写)。

    .PARAMETER Status
        'Online' | 'Offline' | 'Unknown'。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Row,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Status = 'Unknown'
    )

    if ($null -eq $Row) { return }
    $presentation = Get-SshHostStatusPresentation -Status $Status
    $Row.Status = $presentation.Status
    $Row.StatusText = $presentation.StatusText
    $Row.StatusGlyph = $presentation.StatusGlyph
    $Row.StatusRole = $presentation.StatusRole
}

function Get-SshHostDashboardInfoText {
    <#
    .SYNOPSIS
        生成信息行文本(分类 / 计数 / 探测状态)。

    .PARAMETER State
        编排状态对象。

    .OUTPUTS
        [string] 信息行文本。
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$State
    )

    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add("分类 $($State.Category)")
    $parts.Add("$(@($State.Rows).Count)/$(@($State.Profiles).Count) 台")
    if ($State.Filter) { $parts.Add("筛选 '$($State.Filter)'") }
    if ($null -ne $State.DetailProbe) { $parts.Add('探测中…') }
    return ($parts -join ' · ')
}

function Update-SshHostDashboardSelection {
    <#
    .SYNOPSIS
        切换选中行: **只重刷旧/新两行**, 并立即刷新详情面板的本地字段。

    .DESCRIPTION
        这是键盘热路径的核心。全部工作都是内存态:
          1. Update-SshHostListSelection —— 只改两行的 Label.Text/Scheme,
             TG 的脏区机制因此只重画这两行(不重画整表);
          2. 详情面板 Set-SshHostDetailBasic —— 用**本地已知**数据立即落位
             (Host/Address/Port/User/Tags/Group/Provider/Region + 本地活动);
          3. 远端状态: 有缓存则立即回填, 没有则显示"探测中…";
          4. 生成新的请求标识(RequestId), 用于丢弃旧请求的迟到结果。

        **不发任何网络请求** —— 探测由 AddTimeout 心跳在主循环里发起。

    .PARAMETER State
        编排状态对象。

    .PARAMETER NewIndex
        新选中行下标。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [int]$NewIndex
    )

    $listView = $State.ListView
    if ($null -eq $listView) { return }

    # 参数: -Initial 已移除 —— 首次装配也走同一条"生成新请求标识"的路径,
    # 避免"心跳发起的探测 RequestId 与 ActiveRequestId 对不上"导致详情永不回填。
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $oldIndex = [int]$listView.SelectedIndex
    $changed = Update-SshHostListSelection -ListView $listView -OldIndex $oldIndex -NewIndex $NewIndex
    $State.SelectedIndex = $NewIndex
    $State.Perf.SelectionMs = $stopwatch.Elapsed.TotalMilliseconds

    # ★ 详情面板的落位**不能**因为"选中下标没变"而跳过:
    #   首次装配时 ListView 的 SelectedIndex 已经等于目标下标
    #   (New-SshHostListView 按 SelectedIndex 预置), Update-SshHostListSelection
    #   会因 old==new 返回 $false —— 若此处直接返回, 首屏详情面板就是空的,
    #   且 SelectedHost/ActiveRequestId 都不会被初始化(探测永远匹配不上)。
    $row = $listView.Rows[$NewIndex]
    $hostName = [string]$row.Name
    $hostChanged = ([string]$State.SelectedHost -ne $hostName)
    $State.SelectedHost = $hostName
    # 请求标识只在"主机真的变了"时才更新: 否则同一台主机的在飞探测会被
    # 自己刚生成的新标识判成"旧请求"而丢弃(详情永远停在"探测中")。
    if ($hostChanged -or [string]::IsNullOrWhiteSpace([string]$State.ActiveRequestId)) {
        $State.RequestSeq++
        $State.ActiveRequestId = "$hostName#$($State.RequestSeq)"
    }

    # 详情面板落位的条件: 选中行变了 / 主机变了 / 面板还是空的。
    $needsDetail = $changed -or $hostChanged
    if (-not $needsDetail -and $null -ne $State.DetailPanel) {
        $existing = $State.DetailPanel.Labels['Host']
        if ($null -eq $existing -or [string]::IsNullOrEmpty([string]$existing.Text)) { $needsDetail = $true }
    }
    if (-not $needsDetail) { return }

    # ---- 详情面板: 本地数据立即落位(无网络) ----
    if ($null -ne $State.DetailPanel) {
        $activity = $null
        $activityKey = $State.SelectedHost.ToLowerInvariant()
        if ($State.ActivityMap.ContainsKey($activityKey)) { $activity = $State.ActivityMap[$activityKey] }
        Set-SshHostDetailBasic -Panel $State.DetailPanel -Row $row -Activity $activity

        if ($State.DetailByHost.ContainsKey($activityKey)) {
            # 已有缓存的远端详情: 立即回填, **不重复查询**
            Set-SshHostDetailRemote -Panel $State.DetailPanel -Detail $State.DetailByHost[$activityKey]
        }
        else {
            Set-SshHostDetailState -Panel $State.DetailPanel -State 'Loading'
        }
    }

    # ---- 选中行必须可见(滚动时只重填变化的槽位) ----
    Sync-SshHostDashboardScroll -State $State
}

function Sync-SshHostDashboardScroll {
    <#
    .SYNOPSIS
        保证选中行在可视窗口内(需要时滚动并重填槽位)。

    .PARAMETER State
        编排状态对象。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$State
    )

    $listView = $State.ListView
    if ($null -eq $listView) { return }
    $index = [int]$State.SelectedIndex
    if ($index -lt 0) { return }

    $top = [int]$listView.Top
    $height = [int]$listView.Height
    $target = $top
    if ($index -lt $top) { $target = $index }
    elseif ($index -ge ($top + $height)) { $target = $index - $height + 1 }

    $maxTop = [Math]::Max(0, @($listView.Rows).Count - $height)
    if ($target -lt 0) { $target = 0 }
    if ($target -gt $maxTop) { $target = $maxTop }

    if ($target -ne $top) {
        Set-SshHostListScroll -ListView $listView -Top $target
    }
}

function Move-SshHostDashboardSelection {
    <#
    .SYNOPSIS
        上下移动选中(带边界夹取, 幂等)。

    .PARAMETER State
        编排状态对象。

    .PARAMETER Delta
        +1 下移 / -1 上移。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [int]$Delta
    )

    $listView = $State.ListView
    if ($null -eq $listView) { return }
    $count = @($listView.Rows).Count
    if ($count -eq 0) { return }

    $oldIndex = [int]$listView.SelectedIndex
    $newIndex = $oldIndex + $Delta
    if ($newIndex -lt 0) { $newIndex = 0 }
    if ($newIndex -ge $count) { $newIndex = $count - 1 }
    if ($newIndex -eq $oldIndex) { return }
    Update-SshHostDashboardSelection -State $State -NewIndex $newIndex
}

function Set-SshHostDashboardCategory {
    <#
    .SYNOPSIS
        切换顶部分类: **只做本地过滤**, 不发任何 SSH 请求。

    .DESCRIPTION
        分类切换是纯内存操作:
          1. 重新算行(Select-SshHostByCategory + Get-SshHostDashboardRow);
          2. 重填列表槽位(Set-SshHostListScroll);
          3. 保留选中: 原来那台主机还在新分类里就继续选中它,
             否则退到第一行(LastHost 优先);
          4. 只改"高亮换了"的那几个分类标签的方案(其余标签不动 -> 不标脏)。

        **分类切换不触发网络请求** —— 远端探测由心跳按"当前视图里还没探测过的
        主机"自行推进, 与分类切换本身解耦。

    .PARAMETER State
        编排状态对象。

    .PARAMETER Category
        目标分类名。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Category
    )

    if ([string]::IsNullOrWhiteSpace($Category)) { return }
    if ($Category -eq $State.Category) { return }
    if ($State.Categories -notcontains $Category) { return }

    $State.Category = $Category

    # ---- 重算行 + 重填列表 ----
    $rows = @(Get-SshHostDashboardRowList -State $State)
    $State.Rows = $rows
    $State.ListView.Rows = $rows

    # ---- 选中: 同一台主机优先保留 ----
    $previousHost = $State.SelectedHost
    $newIndex = -1
    for ($i = 0; $i -lt $rows.Count; $i++) {
        if ([string]$rows[$i].Name -eq $previousHost) { $newIndex = $i; break }
    }
    if ($newIndex -lt 0 -and $rows.Count -gt 0) { $newIndex = 0 }
    $State.ListView.SelectedIndex = -1
    Set-SshHostListScroll -ListView $State.ListView

    # ---- 分类高亮: 只改方案变了的标签 ----
    Update-SshHostDashboardCategoryBar -State $State

    # ---- 选中行落位 ----
    if ($newIndex -ge 0) {
        Update-SshHostDashboardSelection -State $State -NewIndex $newIndex
    }
    else {
        $State.SelectedIndex = -1
        $State.SelectedHost = ''
        if ($null -ne $State.DetailPanel) {
            Set-SshHostDetailBasic -Panel $State.DetailPanel -Row $null -Activity $null
        }
    }

    Update-SshHostDashboardInfoLine -State $State
}

function Update-SshHostDashboardCategoryBar {
    <#
    .SYNOPSIS
        同步分类栏的高亮方案(只改方案变了的标签, 其余不标脏)。

    .PARAMETER State
        编排状态对象。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$State
    )

    $theme = $State.Theme
    # 已应用方案登记在 **State** 上(而不是挂在 category item 上):
    # item 是 New-SshHostDashboardWindow 产出的纯数据对象, 不该被编排层
    # Add-Member 污染(那样测试里手工构造的状态就没有该字段, 会直接报错)。
    if ($null -eq $State.CategorySchemes) {
        $State.CategorySchemes = @{}
    }
    foreach ($item in @($State.CategoryBar)) {
        $name = [string]$item.Name
        $isActive = ($name -eq [string]$State.Category)
        $scheme = if ($isActive) { $theme.CategoryActive } else { $theme.Category }
        # 等值跳过: 避免把没变的标签也标脏(TG 的 Scheme 赋值不是幂等 no-op)
        if ($State.CategorySchemes.ContainsKey($name) -and $State.CategorySchemes[$name] -eq $scheme) { continue }
        [void]$item.Label.SetScheme($scheme)
        $State.CategorySchemes[$name] = $scheme
    }
}

function Update-SshHostDashboardInfoLine {
    <#
    .SYNOPSIS
        刷新信息行文本(分类 / 计数 / 筛选 / 探测态)。

    .PARAMETER State
        编排状态对象。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$State
    )

    if ($null -eq $State.InfoLabel) { return }
    $text = Get-SshHostDashboardInfoText -State $State
    $State.InfoLabel.Text = Get-SshHostListClip -Text $text -Width ([int]$State.WindowWidth)
}

function Set-SshHostDashboardFilter {
    <#
    .SYNOPSIS
        应用搜索过滤文本(纯本地过滤, 不发请求), 并保留选中。

    .PARAMETER State
        编排状态对象。

    .PARAMETER Filter
        过滤文本(空串 = 不过滤)。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$State,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Filter = ''
    )

    $State.Filter = $Filter
    $rows = @(Get-SshHostDashboardRowList -State $State)
    $State.Rows = $rows
    $State.ListView.Rows = $rows

    $previousHost = $State.SelectedHost
    $newIndex = -1
    for ($i = 0; $i -lt $rows.Count; $i++) {
        if ([string]$rows[$i].Name -eq $previousHost) { $newIndex = $i; break }
    }
    if ($newIndex -lt 0 -and $rows.Count -gt 0) { $newIndex = 0 }

    $State.ListView.SelectedIndex = -1
    Set-SshHostListScroll -ListView $State.ListView
    if ($newIndex -ge 0) {
        Update-SshHostDashboardSelection -State $State -NewIndex $newIndex
    }
    else {
        $State.SelectedIndex = -1
        $State.SelectedHost = ''
        if ($null -ne $State.DetailPanel) {
            Set-SshHostDetailBasic -Panel $State.DetailPanel -Row $null -Activity $null
        }
    }
    Update-SshHostDashboardInfoLine -State $State
}

function Set-SshHostDashboardFocusArea {
    <#
    .SYNOPSIS
        切换焦点区域(列表 <-> 搜索框), 并同步底栏文案。

    .DESCRIPTION
        底栏是**纯展示件**, 但必须与实际行为一致(Goal 三-4)。因此焦点在
        搜索框时, 底栏换成搜索态的键位说明(Enter 应用 / Esc 取消 / Tab 返回),
        焦点回列表时换回主键位说明。

    .PARAMETER State
        编排状态对象。

    .PARAMETER Area
        'List' | 'Search'。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [ValidateSet('List', 'Search')]
        [string]$Area
    )

    $State.FocusArea = $Area
    $State.SearchActive = ($Area -eq 'Search')

    if ($null -ne $State.SearchPrompt) { $State.SearchPrompt.Visible = $State.SearchActive }
    if ($null -ne $State.SearchField) { $State.SearchField.Visible = $State.SearchActive }
    if ($null -ne $State.InfoLabel) { $State.InfoLabel.Visible = (-not $State.SearchActive) }

    if ($Area -eq 'Search') {
        try { [void]$State.SearchField.SetFocus() } catch {
            Write-Verbose "[Set-SshHostDashboardFocusArea] 聚焦搜索框失败: $($_.Exception.Message)"
        }
    }
    else {
        try { [void]$State.ListView.View.SetFocus() } catch {
            Write-Verbose "[Set-SshHostDashboardFocusArea] 聚焦列表失败: $($_.Exception.Message)"
        }
    }

    Update-SshHostDashboardShortcutBar -State $State
}

function Update-SshHostDashboardShortcutBar {
    <#
    .SYNOPSIS
        按当前焦点区域刷新底部快捷键栏文本。

    .PARAMETER State
        编排状态对象。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$State
    )

    if ($null -eq $State.ShortcutBar) { return }

    # 键位定义与整窗装配共用 Get-SshHostShortcutDef(唯一事实来源),
    # 底栏文案因此**必然**与实际键位一致(Goal 三-4)。
    $defs = @(Get-SshHostShortcutDef -Area $State.FocusArea)
    $text = Get-SshHostShortcutText -Defs $defs -Width ([int]$State.WindowWidth)
    $State.ShortcutBar.Text = $text
}

function Register-SshHostDashboardKeyHandler {
    <#
    .SYNOPSIS
        挂载仪表盘的键盘/搜索事件处理器(编排层的唯一键位事实来源)。

    .DESCRIPTION
        挂载点与路由(2026-10-31 事件循环实测, 见 .agent_cache/dash-probe/p33):
          - TG 的 KeyDown **先到焦点视图, 再冒泡到父视图**; 焦点视图里把
            `Key.Handled` 置 true 即可阻止冒泡(p33 实测: child=1 / window=0)。
          - 因此: 列表容器(焦点在列表时)与 Window 各挂一个处理器,
            **列表里处理过的键一律置 Handled**, 不会双触发。

        键位:
          列表焦点: ↑↓ 移动 / Enter 连接 / / 搜索 / Tab 切到搜索 / ←→ 切分类 / Esc 退出
          搜索焦点: Enter 应用 / Tab 回列表 / Esc 取消并回列表
          (TextField 自己消费可打印字符)

    .PARAMETER State
        编排状态对象。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'eventSource', Justification = 'TG 事件处理器固定签名 (sender, key); sender 本层用不到')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$State
    )

    $global:TguiDashState = $State

    # ---- 列表容器的 KeyDown ----
    $State.ListView.View.add_KeyDown({
            param($eventSource, $key)
            $st = $global:TguiDashState
            if ($null -eq $st) { return }
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $handled = Invoke-SshHostDashboardKey -State $st -Key $key
                if ($handled) { $key.Handled = $true }
            }
            catch {
                Write-Verbose "[Invoke-SshHostDashboard] 列表 KeyDown 回调失败: $($_.Exception.Message)"
            }
            finally {
                $st.Perf.KeyHandlerMs = $stopwatch.Elapsed.TotalMilliseconds
                $st.Perf.KeyCount = $st.Perf.KeyCount + 1
            }
        })

    # ---- Window 的 KeyDown(焦点不在列表时兜底) ----
    $State.Window.add_KeyDown({
            param($eventSource, $key)
            $st = $global:TguiDashState
            if ($null -eq $st) { return }
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $handled = Invoke-SshHostDashboardKey -State $st -Key $key
                if ($handled) { $key.Handled = $true }
            }
            catch {
                Write-Verbose "[Invoke-SshHostDashboard] Window KeyDown 回调失败: $($_.Exception.Message)"
            }
            finally {
                $st.Perf.KeyHandlerMs = $stopwatch.Elapsed.TotalMilliseconds
                $st.Perf.KeyCount = $st.Perf.KeyCount + 1
            }
        })

    # ---- 搜索框的 KeyDown(Enter / Tab / Esc) ----
    if ($null -ne $State.SearchField) {
        $State.SearchField.add_KeyDown({
                param($eventSource, $key)
                $st = $global:TguiDashState
                if ($null -eq $st) { return }
                try {
                    if (Test-TguiQuitKey -Key $key) {
                        # Esc: 取消搜索并回到列表(不退出仪表盘)
                        $st.Filter = ''
                        $global:TguiDashAppliedFilter = ''
                        Set-SshHostDashboardFilter -State $st -Filter ''
                        try {
                            $st.SearchField.Text = ''
                        }
                        catch {
                            Write-Verbose "[Invoke-SshHostDashboard] 清空搜索框失败: $($_.Exception.Message)"
                        }
                        Set-SshHostDashboardFocusArea -State $st -Area 'List'
                        $key.Handled = $true
                        return
                    }
                    $code = [string]$key.KeyCode
                    if ($code -eq 'Enter') {
                        $global:TguiDashAppliedFilter = [string]$st.SearchField.Text
                        Set-SshHostDashboardFilter -State $st -Filter $global:TguiDashAppliedFilter
                        Set-SshHostDashboardFocusArea -State $st -Area 'List'
                        $key.Handled = $true
                        return
                    }
                    if ($code -eq 'Tab') {
                        $global:TguiDashAppliedFilter = [string]$st.SearchField.Text
                        Set-SshHostDashboardFilter -State $st -Filter $global:TguiDashAppliedFilter
                        Set-SshHostDashboardFocusArea -State $st -Area 'List'
                        $key.Handled = $true
                        return
                    }
                }
                catch {
                    Write-Verbose "[Invoke-SshHostDashboard] 搜索框 KeyDown 回调失败: $($_.Exception.Message)"
                }
            })

        # ---- 搜索框 TextChanged -> 实时过滤 ----
        # TextChanged 在回填同样的文本时也会触发 —— 用"已应用过滤"守卫,
        # 只对真正的用户输入放行, 否则与程序化回填互相触发成死循环。
        $State.SearchField.add_TextChanged({
                try {
                    $st = $global:TguiDashState
                    if ($null -eq $st) { return }
                    $text = [string]$st.SearchField.Text
                    if ($text -ceq [string]$global:TguiDashAppliedFilter) { return }
                    $global:TguiDashAppliedFilter = $text
                    Set-SshHostDashboardFilter -State $st -Filter $text
                }
                catch {
                    Write-Verbose "[Invoke-SshHostDashboard] TextChanged 回调失败: $($_.Exception.Message)"
                }
            })
    }
}

function Invoke-SshHostDashboardKey {
    <#
    .SYNOPSIS
        仪表盘按键语义的唯一实现(列表焦点与窗口兜底共用)。

    .DESCRIPTION
        返回 $true 表示该键已被消费(调用方应把 Key.Handled 置 true, 阻止
        冒泡与默认处理)。全部动作都是内存态 —— **不含任何网络/文件 I/O**。

    .PARAMETER State
        编排状态对象。

    .PARAMETER Key
        Terminal.Gui.Input.Key 实例。

    .OUTPUTS
        [bool] 是否消费了该键。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [object]$Key
    )

    $code = [string]$Key.KeyCode
    $grapheme = ''
    try { $grapheme = [string]$Key.AsGrapheme } catch { $grapheme = '' }

    # ---- Esc: 退出仪表盘 ----
    # Esc 在 TG 应用级键表里默认绑的是 Quit; 这里**不重复绑定**, 而是显式
    # 走 RequestStop 并标记 Handled, 保证"Esc 一定退出"这条契约不依赖
    # TG 内建行为(焦点在 TextField 等场景下内建 Quit 可能被视图消费掉)。
    if ($code -eq 'Esc' -or (Test-TguiQuitKey -Key $Key)) {
        $global:TguiDashAction = 'Quit'
        Request-SshHostDashboardStop -State $State
        return $true
    }

    # ---- 搜索焦点: 由搜索框自己的处理器接管(Enter/Tab/Esc) ----
    if ($State.FocusArea -eq 'Search') { return $false }

    switch ($code) {
        'CursorUp' {
            Move-SshHostDashboardSelection -State $State -Delta -1
            return $true
        }
        'CursorDown' {
            Move-SshHostDashboardSelection -State $State -Delta 1
            return $true
        }
        'Enter' {
            $rows = @($State.ListView.Rows)
            if ($State.SelectedIndex -ge 0 -and $State.SelectedIndex -lt $rows.Count) {
                $State.SelectedRow = $rows[$State.SelectedIndex]
                $global:TguiDashAction = 'Connect'
                Request-SshHostDashboardStop -State $State
            }
            return $true
        }
        'Tab' {
            Set-SshHostDashboardFocusArea -State $State -Area 'Search'
            return $true
        }
        'CursorLeft' {
            Move-SshHostDashboardCategory -State $State -Delta -1
            return $true
        }
        'CursorRight' {
            Move-SshHostDashboardCategory -State $State -Delta 1
            return $true
        }
    }

    # '/' -> 进入搜索
    if ($grapheme -eq '/') {
        Set-SshHostDashboardFocusArea -State $State -Area 'Search'
        return $true
    }

    return $false
}

function Move-SshHostDashboardCategory {
    <#
    .SYNOPSIS
        在分类栏里前后移动一个分类(纯本地, 不发请求)。

    .PARAMETER State
        编排状态对象。

    .PARAMETER Delta
        +1 后一个 / -1 前一个。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [int]$Delta
    )

    $categories = @($State.Categories)
    if ($categories.Count -eq 0) { return }
    $index = -1
    for ($i = 0; $i -lt $categories.Count; $i++) {
        if ([string]$categories[$i] -eq [string]$State.Category) { $index = $i; break }
    }
    if ($index -lt 0) { $index = 0 }
    $newIndex = $index + $Delta
    if ($newIndex -lt 0) { $newIndex = 0 }
    if ($newIndex -ge $categories.Count) { $newIndex = $categories.Count - 1 }
    if ($newIndex -eq $index) { return }
    Set-SshHostDashboardCategory -State $State -Category ([string]$categories[$newIndex])
}

function Request-SshHostDashboardStop {
    <#
    .SYNOPSIS
        请求结束事件循环(RequestStop), 让编排层回到分发逻辑。

    .PARAMETER State
        编排状态对象。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$State
    )

    $stopMethod = $global:TguiDashStopMethod
    if ($null -eq $stopMethod -or $null -eq $State.Window) { return }
    try {
        $stopArgs = [object[]]::CreateInstance([System.Object], 1)
        $stopArgs[0] = $State.Window
        [void]$stopMethod.Invoke($null, $stopArgs)
    }
    catch {
        Write-Verbose "[Request-SshHostDashboardStop] RequestStop 失败: $($_.Exception.Message)"
    }
}

function Update-SshHostDashboardProbe {
    <#
    .SYNOPSIS
        心跳: 非阻塞地推进远端详情探测(提交 / 收割 / 取消)。

    .DESCRIPTION
        在 AddTimeout 回调里运行 —— 回调本身就在 **UI 线程的主循环**上,
        因此"把后台作业的结果回填到 UI"不需要任何跨线程调度原语。

        状态机:
          1. 主机已切换 -> 在飞的详情请求**不再需要** -> 显式取消(Stop-Job);
          2. 在飞请求已完成 -> 收割:
               - 结果进 DetailByHost / StatusByHost 缓存;
               - 列表对应行就地刷新(只重画那一行);
               - 详情面板回填 —— **必须** RequestId 与主机名双重匹配,
                 否则旧请求会覆盖新选中的主机(Goal 七 性能验收硬指标);
          3. 选中主机还没有远端详情 -> 发起探测(详情优先);
          4. 否则挑一个"当前视图里还没探测过"的主机做巡检(填列表状态点)。

        **不在按键回调里做任何一步** —— 提交线程作业有 ~50ms 的 runspace
        创建开销, 放在热路径上就是白给的延迟。

    .PARAMETER State
        编排状态对象。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$State
    )

    # ---- 1. 取消不再需要的详情请求 ----
    if ($null -ne $State.DetailProbe -and [string]$State.DetailProbe.HostName -ne [string]$State.SelectedHost) {
        Stop-SshHostDashboardProbe -Probe $State.DetailProbe
        $State.DetailProbe = $null
    }

    # ---- 2. 收割在飞的详情请求 ----
    if ($null -ne $State.DetailProbe) {
        if (Test-SshHostDashboardTaskDone -Task $State.DetailProbe.Task) {
            $probe = $State.DetailProbe
            $State.DetailProbe = $null
            $detail = Receive-SshHostDetailTask -Task $probe
            if ($null -ne $detail) {
                Set-SshHostDashboardProbeResult -State $State -Probe $probe -Detail $detail
            }
        }
        return
    }

    # ---- 3. 详情优先: 选中主机还没有远端详情 ----
    $selectedKey = ([string]$State.SelectedHost).ToLowerInvariant()
    if ($selectedKey -and -not $State.DetailByHost.ContainsKey($selectedKey)) {
        Start-SshHostDashboardProbe -State $State -HostName $State.SelectedHost
        return
    }

    # ---- 4. 巡检: 当前视图里还没探测过的主机 ----
    $next = ''
    $listView = $State.ListView
    if ($null -ne $listView) {
        $rows = @($listView.Rows)
        $top = [int]$listView.Top
        $height = [int]$listView.Height
        for ($i = $top; $i -lt [Math]::Min($rows.Count, $top + $height); $i++) {
            $candidate = ([string]$rows[$i].Name).ToLowerInvariant()
            if (-not $candidate) { continue }
            if ($State.DetailByHost.ContainsKey($candidate)) { continue }
            $next = [string]$rows[$i].Name
            break
        }
    }
    if ($next) {
        Start-SshHostDashboardProbe -State $State -HostName $next
    }
}

function Start-SshHostDashboardProbe {
    <#
    .SYNOPSIS
        提交一次后台详情探测(立即返回, 不阻塞 UI)。

    .PARAMETER State
        编排状态对象。

    .PARAMETER HostName
        目标主机名。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$HostName
    )

    if ([string]::IsNullOrWhiteSpace($HostName)) { return }
    $key = $HostName.ToLowerInvariant()
    if ($State.DetailByHost.ContainsKey($key)) { return }

    $State.RequestSeq++
    # ★ 请求标识必须与"当前选中"严格对齐:
    #   详情探测由心跳发起(不在按键路径上), 因此这里不能自己造一个 id ——
    #   必须复用 ActiveRequestId, 否则探测结果的 RequestId 与 ActiveRequestId
    #   对不上, 详情面板会永远停在"探测中"(双保险的第一道就失效了)。
    #   巡检探测(非选中主机)用自己的 id, 且它的结果**永远不**回填详情面板。
    $isSelectedHost = ([string]$HostName -eq [string]$State.SelectedHost)
    if ($isSelectedHost) {
        $requestId = [string]$State.ActiveRequestId
        if ([string]::IsNullOrWhiteSpace($requestId)) {
            $State.ActiveRequestId = "$HostName#$($State.RequestSeq)"
            $requestId = [string]$State.ActiveRequestId
        }
    }
    else {
        $requestId = "$HostName#$($State.RequestSeq)"
    }
    try {
        $probe = Start-SshHostDetailTask -HostName $HostName -RequestId $requestId
        if ($null -eq $probe) { return }
        $State.DetailProbe = $probe
        $State.Perf.ProbeCount = $State.Perf.ProbeCount + 1
    }
    catch {
        Write-Verbose "[Start-SshHostDashboardProbe] 提交后台探测失败: $($_.Exception.Message)"
        # 提交失败: 记成"探测失败", 不让卡片永远停在"探测中"
        if ($null -ne $State.DetailPanel -and [string]$State.SelectedHost -eq [string]$HostName) {
            Set-SshHostDetailState -Panel $State.DetailPanel -State 'Error' -Text $_.Exception.Message
        }
    }
}

function Test-SshHostDashboardTaskDone {
    <#
    .SYNOPSIS
        判断后台作业是否已进入终态(只看状态, **绝不 Wait**)。

    .PARAMETER Task
        作业对象。

    .OUTPUTS
        [bool]
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Task
    )

    if ($null -eq $Task) { return $false }
    try {
        $state = [string]$Task.State
        return ($state -in @('Completed', 'Failed', 'Stopped'))
    }
    catch {
        return $false
    }
}

function Stop-SshHostDashboardProbe {
    <#
    .SYNOPSIS
        取消一次后台探测(停作业 + 清作业), 不留孤儿 runspace。

    .PARAMETER Probe
        Start-SshHostDetailTask 的返回值。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Probe
    )

    if ($null -eq $Probe) { return }
    $job = $Probe
    if ($null -ne $Probe.PSObject.Properties['Task']) { $job = $Probe.Task }
    if ($null -eq $job) { return }
    try {
        Stop-Job -Job $job -ErrorAction SilentlyContinue
    }
    catch {
        Write-Verbose "[Stop-SshHostDashboardProbe] Stop-Job 失败: $($_.Exception.Message)"
    }
    try {
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Verbose "[Stop-SshHostDashboardProbe] Remove-Job 失败: $($_.Exception.Message)"
    }
}

function Set-SshHostDashboardProbeResult {
    <#
    .SYNOPSIS
        把一次探测结果落到列表与详情面板(**带请求标识护栏**)。

    .DESCRIPTION
        护栏(Goal 七 硬指标"不发生旧请求覆盖新选中主机详情"):
          - 只有 RequestId 与当前 ActiveRequestId **一致**, 且主机名与当前
            选中主机一致, 才允许回填详情面板;
          - 列表的状态点按主机名回填(与"当前选中"无关, 是该主机的事实),
            因此旧请求的结果**不会**污染别人的状态。

    .PARAMETER State
        编排状态对象。

    .PARAMETER Probe
        发起本次探测的句柄(含 RequestId / HostName)。

    .PARAMETER Detail
        探测结果(Get-SshHostDetail 产物)。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [object]$Probe,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Detail
    )

    if ($null -eq $Detail) { return }

    $hostName = [string]$Probe.HostName
    if ([string]::IsNullOrWhiteSpace($hostName)) { return }
    $key = $hostName.ToLowerInvariant()

    # ---- 缓存(真实数据, 不伪造) ----
    $State.DetailByHost[$key] = $Detail
    $State.StatusByHost[$key] = [string]$Detail.Status

    # ---- 列表对应行就地刷新(只重画那一行) ----
    $listView = $State.ListView
    if ($null -ne $listView) {
        $rows = @($listView.Rows)
        for ($i = 0; $i -lt $rows.Count; $i++) {
            if ([string]$rows[$i].Name -ne $hostName) { continue }
            Set-SshHostDashboardRowStatus -Row $rows[$i] -Status ([string]$Detail.Status)
            Sync-SshHostListRow -ListView $listView -RowIndex $i
            break
        }
    }

    # ---- 详情面板回填(必须通过请求标识 + 主机名双重护栏) ----
    $requestId = [string]$Probe.RequestId
    $isCurrent = ($requestId -eq [string]$State.ActiveRequestId) -and
                 ([string]$State.SelectedHost -eq $hostName)
    if ($isCurrent -and $null -ne $State.DetailPanel) {
        Set-SshHostDetailRemote -Panel $State.DetailPanel -Detail $Detail
    }

    Update-SshHostDashboardInfoLine -State $State
}
