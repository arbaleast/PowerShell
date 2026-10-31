# Get-ConsoleUiBackend.ps1 - 交互式 UI 主轨 (Terminal.Gui v2 ALC) 可用性检测
# 职责边界: 只做"检测 + 判定", 不渲染任何 UI, 不做业务装配。
# 判定结果写入 $script:ConsoleUiBackend, 供 Show-HostSelector 等在调用前做可用性断言。
#
# 单轨说明 (2026-10-30 PSTui 移除):
#   交互式 UI 只有一条轨: 独立 AssemblyLoadContext 加载仓库内 vendored 的
#   Modules/Terminal.Gui/<ver>/Terminal.Gui.dll(Get-TguiContext 承担, 版本钉 2.4.10)。
#   原 PSTui(Out-ConsoleGridView)轨与其命令冲突检测随 Modules/PSTui 删除一并移除;
#   ALC 隔离使"默认加载上下文里的同名 Terminal.Gui"不再构成类型身份冲突,
#   因此旧的那组冲突模块探测(Out-ConsoleGridView 来源 / ConsoleGuiTools 等)不再保留。
#   Backend 恒为 'TerminalGui'; 可用性信息由 Available / Reason 承载,
#   不可用时由调用方给出明确错误。

function Test-ConsoleUiTguiAssembly {
    <#
    .SYNOPSIS
        在仓库 Modules/Terminal.Gui/ 下探测 vendored Terminal.Gui.dll(不加载)。

    .DESCRIPTION
        只做文件系统层探测: 仓库根 Modules/Terminal.Gui/<版本>/Terminal.Gui.dll,
        取可解析为版本号的最大目录。不加载任何程序集, 启动期开销可忽略。
        与 Get-TguiContext 的定位逻辑(选最高版本目录)保持一致,
        但本函数刻意不抛错 —— 不可用是合法状态, 由 Available/Reason 表达。

    .OUTPUTS
        PSCustomObject: Version / Path; 未找到时返回 $null

    .EXAMPLE
        $probe = Test-ConsoleUiTguiAssembly
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $tguiRoot = Join-Path -Path $repoRoot -ChildPath (Join-Path -Path 'Modules' -ChildPath 'Terminal.Gui')
    if (-not (Test-Path -LiteralPath $tguiRoot -PathType Container)) {
        return $null
    }

    $best = $null
    $bestVersion = $null
    foreach ($sub in @(Get-ChildItem -LiteralPath $tguiRoot -Directory -ErrorAction SilentlyContinue)) {
        $parsed = $null
        if (-not [version]::TryParse($sub.Name, [ref]$parsed)) { continue }
        if (-not (Test-Path -LiteralPath (Join-Path $sub.FullName 'Terminal.Gui.dll') -PathType Leaf)) { continue }
        if ($null -eq $bestVersion -or $parsed -gt $bestVersion) {
            $bestVersion = $parsed
            $best = $sub
        }
    }

    if ($null -eq $best) {
        return $null
    }
    return [PSCustomObject]@{
        Version = $bestVersion
        Path    = $best.FullName
    }
}

function Test-ConsoleUiInteractive {
    <#
    .SYNOPSIS
        检测当前宿主是否具备交互式控制台

    .DESCRIPTION
        TGUI 事件循环在输入重定向的宿主上会永久阻塞
        (实测: 无 TTY 环境 Terminal.Gui 的 Init 不抛异常, Run 永不返回),
        因此非交互宿主(管道 / CI / 重定向)无法使用 Terminal.Gui 主轨。

        判断策略(与 Test-TmuxTuiInteractive / 两条 TGUI 编排护栏同口径):
        - 第一信号(前置): 输入或输出被重定向(Pester / CI / 管道)必然非交互 ——
          复用 Test-TmuxTuiInteractive 判定, 避免断言层与护栏层出现分歧
          (2026-10-31 Windows CI 实证: 仅用宿主层判定时, ConPTY 下 RawUI 可用
          会判"可用", 而 TGUI 编排层按重定向判禁用, Assert-ConsoleUiReady 不再抛错)。
        - 第二信号: $host.Name -eq 'ConsoleHost' 代表真实交互终端
        - 第三信号: $host.UI.RawUI 是否可正常访问(BufferSize / CursorPosition)
        - 辅助信号: [Console]::IsInputRedirected (在 scoop pwsh 下有 bug, 仅作非 ConsoleHost 的 fallback)

        注: [Console]::IsInputRedirected 在 scoop pwsh / Windows Terminal 环境下
        会错误返回 true(即使终端完全交互), 因此不能作为主要判断依据。

    .OUTPUTS
        PSCustomObject: Ok / Reason
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    # 第一信号(前置): 重定向终端(与 TGUI 编排护栏 Test-TmuxTuiInteractive 同口径)。
    # 断言层必须与编排层同判: 否则上层放行、下层在触碰 TG 前静默跳过,
	# Assert-ConsoleUiReady 的"可定位终止错误"契约就落空(CI 实证)。
    if (-not (Test-TmuxTuiInteractive)) {
        return [PSCustomObject]@{
            Ok     = $false
            Reason = '输入/输出已重定向, Terminal.Gui 事件循环会永久阻塞 (Test-TmuxTuiInteractive)'
        }
    }

    # 第二信号: PowerShell Host 名称
    $isConsoleHost = ($host.Name -eq 'ConsoleHost')

    # 第二信号: 尝试访问 RawUI(只有在真实控制台下才完全可用)
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
            'stdin 已重定向, Terminal.Gui 事件循环会永久阻塞'
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
        综合检测, 判定交互式 UI 主轨 (Terminal.Gui v2 ALC) 的可用性

    .DESCRIPTION
        组合两项检测:
          1. vendored Terminal.Gui v2 可发现(仓库 Modules/Terminal.Gui/<ver>/);
          2. 当前环境为交互式终端。
        通过才认为 TerminalGui 主轨可用 (Available = $true)。
        自研 ANSI 降级轨(2026-10-18)与 PSTui 轨(2026-10-30)均已移除,
        因此 Backend 恒为 'TerminalGui'; 不可用时由调用方依据 Reason
        给出明确错误, 不再自动切换后端。

    .OUTPUTS
        PSCustomObject: Backend / Available / Reason / TerminalGuiVersion

    .EXAMPLE
        $backend = Get-ConsoleUiBackend
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $checks = [System.Collections.Generic.List[string]]::new()

    # 检测 1: vendored Terminal.Gui v2 程序集可发现
    $tgui = Test-ConsoleUiTguiAssembly
    $tguiVersion = if ($null -ne $tgui) { $tgui.Version.ToString() } else { '' }
    if ($null -eq $tgui) {
        $checks.Add('未在仓库 Modules/Terminal.Gui/ 中发现 Terminal.Gui.dll') | Out-Null
    }

    # 检测 2: 交互式终端
    $tty = Test-ConsoleUiInteractive
    if (-not $tty.Ok) { $checks.Add($tty.Reason) | Out-Null }

    $available = ($null -ne $tgui) -and $tty.Ok
    $reason = if ($available) {
        "Terminal.Gui $tguiVersion + PowerShell $($PSVersionTable.PSVersion) 就绪"
    } else {
        ($checks -join '; ')
    }

    return [PSCustomObject]@{
        Backend            = 'TerminalGui'
        Available          = $available
        Reason             = $reason
        TerminalGuiVersion = $tguiVersion
    }
}

function Get-ConsoleUiState {
    <#
    .SYNOPSIS
        惰性获取交互式 UI 主轨判定结果 (带缓存)

    .DESCRIPTION
        首次调用时执行 Get-ConsoleUiBackend 并缓存到 $script:ConsoleUiBackend,
        后续调用直接复用缓存。检测异常时返回 Available=$false 的降级对象,
        保证调用方总能拿到可诊断的结构而不会因检测异常崩掉。

    .OUTPUTS
        PSCustomObject: Backend / Available / Reason / TerminalGuiVersion
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
            Backend            = 'TerminalGui'
            Available          = $false
            Reason             = "主轨检测异常: $($_.Exception.Message)"
            TerminalGuiVersion = ''
        }
    }

    if ($script:ConsoleUiBackend.Available) {
        Write-Verbose "[ShellPrompt] Console UI backend = TerminalGui (vendored TerminalGui $($script:ConsoleUiBackend.TerminalGuiVersion))"
    } else {
        # 主轨不可用不构成错误(例如 stdin 被重定向/无 TTY 的 CI 场景),
        # 因此只用 Write-Verbose 记录, 避免向 stderr 写入噪声。
        # 真正需要弹菜单时, 由 Assert-ConsoleUiReady 抛出可定位的终止错误。
        Write-Verbose "[ShellPrompt] 交互式 UI 主轨 (Terminal.Gui v2) 当前不可用: $($script:ConsoleUiBackend.Reason)"
    }

    return $script:ConsoleUiBackend
}

function Assert-ConsoleUiReady {
    <#
    .SYNOPSIS
        断言交互式 UI 主轨 (Terminal.Gui v2 ALC) 当前可用, 不可用则抛出可定位的终止错误

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

    throw ("[ShellPrompt] $Feature 需要交互式 UI 主轨 (Terminal.Gui v2), 但当前环境不可用: " +
        "$($state.Reason)。请确认仓库 Modules/Terminal.Gui/ 目录完整、PowerShell >= 7.6, " +
        '且当前为交互式终端 (stdin 未重定向)。')
}
