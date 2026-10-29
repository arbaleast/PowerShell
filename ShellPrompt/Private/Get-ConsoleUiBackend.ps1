# Get-ConsoleUiBackend.ps1 - 控制台 UI 主轨 (GridView) 可用性检测
# 职责边界: 只做"检测 + 判定", 不渲染任何 UI。
# 四个检测函数各自独立可测, Get-ConsoleUiBackend 负责编排与综合判定。
# 判定结果写入 $script:ConsoleUiBackend, 供 Show-HostSelector / Show-SessionManager /
# Show-TmuxSessionList 在调用前做可用性断言。
#
# 单轨说明 (2026-10-18 起):
#   自研 ANSI 降级轨 (AnsiFallback) 已整体移除, 控制台 UI 只有 PSTui GridView 一条轨。
#   本文件不再返回 'AnsiFallback', Backend 恒为 'GridView';
#   可用性信息由 Available / Reason / Conflicts 承载, 不可用时由调用方给出明确错误。
#
# 已知能力缺口 (PSTui 相对历史自研 ANSI 菜单):
#   1. 行级颜色/危险红 -> 用 State 文本 + '⚠' 符号表达
#   2. 底部帮助文本     -> 菜单上方一行 Spectre 提示行表达
#   3. 实时键盘过滤     -> -Focus Filter 表格筛选框 (可在 $script:Config.UI.GridViewFocus 切换)
#   4. Disabled 渲染    -> State 列文本标注 + 选中后阻断

# 会与 PSTui 争用 Terminal.Gui 运行时或提供同名命令的历史模块。
# 注: PwshSpectreConsole 走 Spectre.Console, 不绑定 Terminal.Gui, 因此不在此列。
$script:ConsoleUiConflictModules = @(
    'Microsoft.PowerShell.ConsoleGuiTools'
    'ConsoleMonster'
    'PoshTui'
    'PsUi'
)

function Get-ConsoleUiModuleOnDisk {
    <#
    .SYNOPSIS
        在 PSModulePath 中按目录结构发现模块, 返回版本与路径(不加载 manifest)

    .DESCRIPTION
        性能替代方案: `Get-Module -ListAvailable` 会对 PSModulePath 上的每个模块
        做 manifest 解析与元数据装载, 在 profile 启动期是显著的固定开销(实测单次
        数十至数百毫秒)。本函数只做文件系统层面的目录查找 + 版本目录名解析,
        语义上与 "模块是否可被发现" 等价, 但不触发任何模块自动加载。

        版本解析优先级:
          1) 版本子目录名(可解析为 [version] 时取最大者)
          2) 无版本子目录时, 读取同级 .psd1 的 ModuleVersion 字段
          3) 都拿不到时返回 0.0

    .OUTPUTS
        PSCustomObject: Name / Version / Path; 未找到时返回 $null
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $seenRoots = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($root in ($env:PSModulePath -split [IO.Path]::PathSeparator)) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        $base = $null
        try { $base = [System.IO.Path]::GetFullPath($root) } catch { continue }
        if (-not $seenRoots.Add($base)) { continue }

        $dir = Join-Path $base $Name
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }

        # 版本子目录: 取可解析为版本号的最大者
        $bestSub = $null
        $bestVer = $null
        foreach ($sub in @(Get-ChildItem -LiteralPath $dir -Directory -ErrorAction SilentlyContinue)) {
            $parsed = $null
            if ([version]::TryParse($sub.Name, [ref]$parsed)) {
                if ($null -eq $bestVer -or $parsed -gt $bestVer) {
                    $bestVer = $parsed
                    $bestSub = $sub
                }
            }
        }
        if ($null -ne $bestVer) {
            return [PSCustomObject]@{
                Name    = $Name
                Version = $bestVer
                Path    = $bestSub.FullName
            }
        }

        # 无版本子目录: 读取同级 manifest 的 ModuleVersion
        $version = [version]'0.0'
        $manifest = Join-Path $dir "$Name.psd1"
        if (Test-Path -LiteralPath $manifest -PathType Leaf) {
            try {
                $text = [System.IO.File]::ReadAllText($manifest)
                if ($text -match "(?m)^\s*ModuleVersion\s*=\s*'([^']+)'") {
                    $version = [version]$Matches[1]
                }
            } catch {
                # manifest 读取失败不影响"可发现"判定, 退化为 0.0
                Write-Verbose "[ShellPrompt] 读取 PSTui manifest 失败, 版本退化为 0.0: $($_.Exception.Message)"
            }
        }
        return [PSCustomObject]@{
            Name    = $Name
            Version = $version
            Path    = $dir
        }
    }

    return $null
}

function Test-ConsoleUiHostPrerequisite {
    <#
    .SYNOPSIS
        检测宿主前提: PowerShell 版本门槛 + PSTui 模块可发现性

    .DESCRIPTION
        版本门槛来自 ShellPrompt.psd1 的 PowerShellVersion (7.6), 与模块加载门槛一致。
        PSTui 的发现刻意使用 -ListAvailable(不触发 PowerShell 模块自动加载),
        避免在 profile 加载期就把 PSTui 拉进会话。

    .OUTPUTS
        PSCustomObject: Ok / Reason / Details / PstuiVersion
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $details = [System.Collections.Generic.List[string]]::new()

    # 前提 1: PowerShell 版本
    $psOk = $PSVersionTable.PSVersion -ge [version]'7.6'
    if (-not $psOk) {
        $details.Add("PowerShell $($PSVersionTable.PSVersion) 低于门槛 7.6") | Out-Null
    }

    # 前提 2: PSTui 可发现(按目录结构查找, 不加载 manifest 元数据, 不触发自动加载)
    $pstui = Get-ConsoleUiModuleOnDisk -Name 'PSTui'
    if ($null -eq $pstui) {
        $details.Add('未在 PSModulePath 中发现 PSTui 模块') | Out-Null
    }

    $ok = $psOk -and ($null -ne $pstui)
    $reason = if ($ok) {
        "PowerShell $($PSVersionTable.PSVersion) + PSTui $($pstui.Version) 就绪"
    } else {
        ($details -join '; ')
    }

    return [PSCustomObject]@{
        Ok           = $ok
        Reason       = $reason
        Details      = $details.ToArray()
        PstuiVersion = if ($null -ne $pstui) { $pstui.Version.ToString() } else { '' }
    }
}

function Test-ConsoleUiCommandConflict {
    <#
    .SYNOPSIS
        检测 Out-ConsoleGridView 命令来源冲突

    .DESCRIPTION
        使用 -ListAvailable 枚举磁盘上所有提供同名命令的模块(不触发自动加载)。
        只要出现 PSTui 以外的来源, 或历史冲突模块可被发现, 即判定为冲突。
        之前实测: 不加 -ListAvailable 时 Get-Command 会触发模块自动加载,
        导致检测本身改变会话状态, 因此这里必须带 -ListAvailable。

        性能说明: 早前使用 `-ListAvailable -All` 以枚举同名命令的全部来源,
        实测该形态会触发全量模块元数据装载(单次约 250ms), 是启动期的主要开销。
        去掉 -All 后仍会返回"所有提供该命令的模块"(每个模块取最高版本),
        而冲突判定只关心"是否存在 PSTui 以外的来源", 因此判定语义等价。

    .OUTPUTS
        PSCustomObject: Ok / Conflicts / Reason
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $conflicts = [System.Collections.Generic.List[string]]::new()

    $providers = @(Get-Command -Name 'Out-ConsoleGridView' -ListAvailable -ErrorAction SilentlyContinue)
    $sources = @($providers | ForEach-Object { $_.ModuleName } |
        Where-Object { $_ } | Sort-Object -Unique)
    foreach ($s in $sources) {
        if ($s -ne 'PSTui') {
            $conflicts.Add("同名命令来源: $s") | Out-Null
        }
    }

    # 历史冲突模块: ConsoleGuiTools 自带 Terminal.Gui 分支, 加载后会与 PSTui 争用
    # 使用目录级发现(等价于 -ListAvailable 的"可被发现"语义), 避免 manifest 元数据装载开销
    foreach ($name in $script:ConsoleUiConflictModules) {
        $found = Get-ConsoleUiModuleOnDisk -Name $name
        if ($null -ne $found) {
            $conflicts.Add("发现历史冲突模块: $name ($($found.Version))") | Out-Null
        }
    }

    $ok = ($conflicts.Count -eq 0)
    $reason = if ($ok) {
        "Out-ConsoleGridView 唯一来源为 PSTui, 无历史冲突模块"
    } else {
        ($conflicts -join '; ')
    }
    return [PSCustomObject]@{
        Ok        = $ok
        Conflicts = $conflicts.ToArray()
        Reason    = $reason
    }
}

function Test-ConsoleUiTerminalGuiConflict {
    <#
    .SYNOPSIS
        检测 Terminal.Gui 运行时争用

    .DESCRIPTION
        PSTui 1.0.5 依赖 Terminal.Gui v2 主版本。若在弹窗前进程中已经加载了
        主版本不为 2 的 Terminal.Gui 程序集, PSTui 首次弹窗绑定会失败。
        由于 PSTui 对 Terminal.Gui 是懒加载, 模块加载期通常尚未绑定, 因此本检测
        在启动期执行是安全的。

    .OUTPUTS
        PSCustomObject: Ok / Conflicts / TerminalGuiVersion / Reason
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $conflicts = [System.Collections.Generic.List[string]]::new()
    $loadedVersion = ''

    # 集合上直接取 .Version 会枚举成数组, 必须显式 Select-Object -First 1 收敛为标量
    $loaded = @([System.AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -eq 'Terminal.Gui' } |
        Select-Object -First 1)
    if ($loaded.Count -gt 0) {
        $loadedVersion = $loaded[0].GetName().Version.ToString()
        $major = $loaded[0].GetName().Version.Major
        if ($major -ne 2) {
            $conflicts.Add("已加载的 Terminal.Gui 主版本为 $major (期望 2): $loadedVersion") | Out-Null
        }
    }

    # 已经加载的历史冲突模块即便没带 TG, 也要拦: 它们在弹窗时会自行加载
    foreach ($name in $script:ConsoleUiConflictModules) {
        $loadedMod = @(Get-Module -Name $name -ErrorAction SilentlyContinue)
        if ($loadedMod.Count -gt 0) {
            $conflicts.Add("冲突模块已加载进会话: $name ($($loadedMod[0].Version))") | Out-Null
        }
    }

    $ok = ($conflicts.Count -eq 0)
    $reason = if ($ok) {
        if ($loadedVersion) { "Terminal.Gui $loadedVersion 与 PSTui v2 兼容" } else { 'Terminal.Gui 尚未绑定 (PSTui 懒加载), 无争用' }
    } else {
        ($conflicts -join '; ')
    }
    return [PSCustomObject]@{
        Ok                 = $ok
        Conflicts          = $conflicts.ToArray()
        TerminalGuiVersion = $loadedVersion
        Reason             = $reason
    }
}

function Test-ConsoleUiInteractive {
    <#
    .SYNOPSIS
        检测当前宿主是否具备交互式控制台

    .DESCRIPTION
        PSTui 的 Out-ConsoleGridView 在输入重定向下会抛 PSNotSupportedException
        (实测: "Not supported in this environment (when input is redirected)."),
        因此非交互宿主(管道 / CI / 重定向)无法使用 GridView 主轨。

        判断策略(双重信号, 优先使用 PowerShell 宿主层而非 .NET Console API):
        - 第一信号: $host.Name -eq 'ConsoleHost' 代表真实交互终端
        - 第二信号: $host.UI.RawUI 是否可正常访问(BufferSize / CursorPosition)
        - 辅助信号: [Console]::IsInputRedirected (在 scoop pwsh 下有 bug, 仅作非 ConsoleHost 的 fallback)

        注: [Console]::IsInputRedirected 在 scoop pwsh / Windows Terminal 环境下
        会错误返回 true(即使终端完全交互), 因此不能作为主要判断依据。

    .OUTPUTS
        PSCustomObject: Ok / Reason
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    # 第一信号: PowerShell Host 名称
    # ConsoleHost 代表真实交互终端(scoop pwsh / Windows Terminal / VS Code 集成终端)
    $isConsoleHost = ($host.Name -eq 'ConsoleHost')

    # 第二信号: 尝试访问 RawUI(只有在真实控制台下才完全可用)
    # 在 pipe / redirect / CI 环境下, RawUI 通常会抛异常或返回无效值
    $rawUiWorks = $false
    try {
        if ($host.UI.RawUI) {
            $null = $host.UI.RawUI.CursorPosition  # 验证 RawUI 方法可调用
            $size = $host.UI.RawUI.BufferSize
            # 能读到有效 buffer size 说明 RawUI 真正可用
            $rawUiWorks = ($size.Width -gt 0 -and $size.Height -gt 0)
        }
    } catch {
        $rawUiWorks = $false
    }

    $ok = $false
    $reason = ''

    if ($isConsoleHost -and $rawUiWorks) {
        # ConsoleHost + RawUI 正常 -> 交互终端
        $ok = $true
        $reason = '交互式控制台 (ConsoleHost + RawUI 正常)'
    } elseif ($isConsoleHost -and -not $rawUiWorks) {
        # ConsoleHost 但 RawUI 异常 -> 可能是非交互的 ConsoleHost, 保守处理
        $ok = $false
        $reason = 'ConsoleHost 但 RawUI 异常, 可能非交互'
    } else {
        # 非 ConsoleHost 环境 -> 使用 [Console]::IsInputRedirected 作为辅助判断
        $inputRedirected = $true
        try {
            $inputRedirected = [Console]::IsInputRedirected
        } catch {
            $inputRedirected = $true
        }

        $ok = (-not $inputRedirected)
        $reason = if ($ok) {
            '交互式控制台 (stdin 未重定向)'
        } else {
            'stdin 已重定向, PSTui GridView 会抛 PSNotSupportedException'
        }
    }

    return [PSCustomObject]@{
        Ok     = $ok
        Reason = $reason
    }
}

function Get-ConsoleUiBackend {
    <#
    .SYNOPSIS
        综合四项检测, 判定控制台 UI 主轨 (GridView) 的可用性

    .DESCRIPTION
        编排 Test-ConsoleUiHostPrerequisite / Test-ConsoleUiCommandConflict /
        Test-ConsoleUiTerminalGuiConflict / Test-ConsoleUiInteractive,
        全部通过才认为 GridView 主轨可用 (Available = $true)。
        自研 ANSI 降级轨已移除, 因此 Backend 恒为 'GridView';
        不可用时由调用方依据 Reason 给出明确错误, 不再自动切换后端。

    .OUTPUTS
        PSCustomObject: Backend / Available / Reason / Conflicts / PstuiVersion / TerminalGuiVersion
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $conflicts = [System.Collections.Generic.List[string]]::new()

    $host1 = Test-ConsoleUiHostPrerequisite
    $pstuiVersion = $host1.PstuiVersion

    $cmd = Test-ConsoleUiCommandConflict
    foreach ($c in $cmd.Conflicts) { $conflicts.Add($c) | Out-Null }

    $tg = Test-ConsoleUiTerminalGuiConflict
    $tgVersion = $tg.TerminalGuiVersion
    foreach ($c in $tg.Conflicts) { $conflicts.Add($c) | Out-Null }

    $tty = Test-ConsoleUiInteractive

    $available = $host1.Ok -and $cmd.Ok -and $tg.Ok -and $tty.Ok
    $reasons = [System.Collections.Generic.List[string]]::new()
    foreach ($r in @($host1, $cmd, $tg, $tty)) {
        if (-not $r.Ok) { $reasons.Add($r.Reason) | Out-Null }
    }

    $reason = if ($available) { $host1.Reason } else { ($reasons -join ' | ') }

    return [PSCustomObject]@{
        Backend            = 'GridView'
        Available          = $available
        Reason             = $reason
        Conflicts          = $conflicts.ToArray()
        PstuiVersion       = $pstuiVersion
        TerminalGuiVersion = $tgVersion
    }
}

function Get-ConsoleUiState {
    <#
    .SYNOPSIS
        惰性获取控制台 UI 主轨判定结果 (带缓存)

    .DESCRIPTION
        首次调用时执行 Get-ConsoleUiBackend 并缓存到 $script:ConsoleUiBackend,
        后续调用直接复用缓存。检测异常时返回 Available=$false 的降级对象,
        保证调用方总能拿到可诊断的结构而不会因检测异常崩掉。

    .OUTPUTS
        PSCustomObject: Backend / Available / Reason / Conflicts / PstuiVersion / TerminalGuiVersion
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    if ($script:ConsoleUiBackend) {
        return $script:ConsoleUiBackend
    }

    try {
        $script:ConsoleUiBackend = Get-ConsoleUiBackend
    } catch {
        $script:ConsoleUiBackend = [PSCustomObject]@{
            Backend            = 'GridView'
            Available          = $false
            Reason             = "主轨检测异常: $($_.Exception.Message)"
            Conflicts          = @()
            PstuiVersion       = ''
            TerminalGuiVersion = ''
        }
    }

    if ($script:ConsoleUiBackend.Available) {
        Write-Verbose "[ShellPrompt] Console UI backend = GridView (PSTui $($script:ConsoleUiBackend.PstuiVersion))"
    } else {
        # 主轨不可用不构成错误(例如 stdin 被重定向/无 TTY 的 CI 场景),
        # 因此只用 Write-Verbose 记录, 避免向 stderr 写入噪声。
        # 真正需要弹菜单时, 由 Assert-ConsoleUiReady 抛出可定位的终止错误。
        Write-Verbose "[ShellPrompt] 控制台 UI 主轨 (PSTui GridView) 当前不可用: $($script:ConsoleUiBackend.Reason)"
    }

    return $script:ConsoleUiBackend
}

function Assert-ConsoleUiReady {
    <#
    .SYNOPSIS
        断言控制台 UI 主轨 (GridView) 当前可用, 不可用则抛出可定位的终止错误

    .DESCRIPTION
        单轨化之后没有备用渲染实现, 因此在真正要弹窗前必须显式检查。
        通过 Get-ConsoleUiState 惰性获取判定结果(首次调用时现场检测, 之后复用缓存);
        该调用正是"首次弹菜单"的触发点, 不可用时给出明确错误。

    .PARAMETER Feature
        触发检查的功能名, 拼进错误信息便于定位(如 'SSH 主机选择器')。

    .OUTPUTS
        无返回值; 不可用时 throw
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Feature = '控制台菜单'
    )

    $state = Get-ConsoleUiState

    if ($state.Available) {
        return
    }

    throw ("[ShellPrompt] $Feature 需要控制台 UI 主轨 (PSTui GridView), 但当前环境不可用: " +
        "$($state.Reason)。请确认已安装 PSTui (仓库 Modules/PSTui/)、PowerShell >= 7.6, " +
        '且当前为交互式终端 (stdin 未重定向)。')
}
