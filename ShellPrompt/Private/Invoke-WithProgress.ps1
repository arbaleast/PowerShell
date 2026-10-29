# Invoke-WithProgress.ps1 - ScriptBlock 执行期间的进度封装
# 依赖 Show-ProgressSpinner.ps1 中的 Get-SpinnerStyleMapping 函数 (样式名翻译)
# P2-4: 原始封装实现; P2-5: 提取为独立文件以符合"一函数一文件"规范
# v2.0 (单轨 Spectre):
#   1) 已删除版本双轨 (无 Test-SpectreSpinnerAvailable 探测, 无 -ForceLegacy, 无 PS 5.1 分支)
#   2) 保留的两条路径是"功能形态"差异, 不是版本回退:
#        - 同步封装  → Invoke-SpectreCommandWithStatus (Spectre 完整动画生命周期)
#        - 轮询封装  → 静默轮询 (Spectre API 无 poll / 无硬超时 / 无法抑制控制台)
#   3) 轮询路径服务于 -PollScript / -SuppressConsole / -TimeoutSeconds 三个真实能力缺口,
#      调用方 (Start-TmuxSession 的 SSH 探测) 与 Pester 隔离测试都依赖它
# 设计原则: 现有 3 个生产调用 (Start-TmuxSession.ps1) 全部是同步无 PollScript → 走 Spectre 路径
# v2.1 (进度渲染单轨化): 轮询封装不再自绘 spinner (控制台渲染统一由 Spectre 负责),
#   只保留轮询 / 硬超时 / 结构化返回三项能力; Show-ProgressSpinner 因此暂无生产调用方。

# 注意: Show-ProgressSpinner.ps1 中定义的 spinner 样式/符号变量与 Get-SpinnerStyleMapping
# 会被本文件 dot-source 时一同加载到 module scope, 因此这里不需要重复定义。

function Invoke-WithProgressSpectre {
    <#
    .SYNOPSIS
        (同步封装) 把 ScriptBlock 包装到 Invoke-SpectreCommandWithStatus 中执行

    .DESCRIPTION
        把调用方传入的 -ScriptBlock 透传给 Invoke-SpectreCommandWithStatus, 由 Spectre.Console
        的 Start-AnsiConsoleStatus 完整生命周期渲染 (启动 spinner → 等待 ScriptBlock 完成 → 结束)。
        样式名通过 Get-SpinnerStyleMapping 从 ShellPrompt 风格 (Braille/Ascii/...) 翻译为
        Spectre.Spinner.Known 字符串 (Dots3/Ascii/...)。

        能力边界 (Spectre API 自身限制, 非版本回退):
          - 不支持 -TimeoutSeconds (Start-AnsiConsoleStatus 无 timeout)
          - 不支持 -PollScript  (无同步轮询语义)
          - 不支持 -SuppressConsole (无法抑制控制台输出)
        调用上述参数时, Invoke-WithProgress 会路由到轮询封装路径。

        异常透传: ScriptBlock 抛出的异常由 Invoke-SpectreCommandWithStatus 原样抛出。

    .PARAMETER Message
        spinner 主提示文本 (映射为 Spectre -Title)

    .PARAMETER ScriptBlock
        主操作 (透传给 Invoke-SpectreCommandWithStatus)

    .PARAMETER Style
        ShellPrompt 样式名 (Braille/Ascii/Blocks/Dots/Arrows) — 翻译为 Spectre spinner

    .OUTPUTS
        [object] ScriptBlock 的返回值 (Invoke-SpectreCommandWithStatus 直接 return)
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Braille', 'Ascii', 'Blocks', 'Dots', 'Arrows')]
        [string]$Style = 'Braille'
    )

    $spectreStyle = Get-SpinnerStyleMapping -Style $Style
    # Invoke-SpectreCommandWithStatus -Title 是 Mandatory, 用 -Message 填充
    # 返回值即 ScriptBlock 的 return 值 (透传)
    Invoke-SpectreCommandWithStatus -Title $Message -Spinner $spectreStyle -ScriptBlock $ScriptBlock
}

function Invoke-WithProgressPolling {
    <#
    .SYNOPSIS
        (轮询封装) 静默轮询 + 硬超时 + 结构化返回, 覆盖 Spectre API 的能力缺口

    .DESCRIPTION
        进度渲染已单轨化到 Spectre (Invoke-WithProgressSpectre), 本封装只保留
        Spectre 不具备的能力, 且不写控制台:
          1. -PollScript 同步轮询 (跨秒级 SSH 探测场景)
          2. -TimeoutSeconds 硬超时 (到点抛 TimeoutException)
          3. -SuppressConsole 结构化返回 (Pester 隔离断言 Frames/ElapsedMs)

        行为约定:
          1. 轮询模式主循环: 轮询 -PollScript (间隔 -IntervalMs ms), 每轮记一帧
          2. -PollScript 返回 $true 时认作"完成", 跳出循环
          3. -PollScript / -ScriptBlock 抛异常 -> 标记 Failure 并重新抛出
          4. -TimeoutSeconds 超时 (默认 60s) -> 抛 TimeoutException
          5. 同步模式 (无 -PollScript) 下 ScriptBlock 一次性执行完,
             Frames 恒为 @(0), 因此仅供 -SuppressConsole 隔离测试使用

    .PARAMETER Message
        spinner 主提示文本

    .PARAMETER ScriptBlock
        主操作 (同步执行, 返回值作为函数输出)

    .PARAMETER PollScript
        可选轮询脚本: 返回 $true 时结束轮询; 不传则 ScriptBlock 结束后立即完成

    .PARAMETER IntervalMs
        轮询间隔, 默认 80ms

    .PARAMETER TimeoutSeconds
        最长等待秒数, 默认 60s

    .PARAMETER Style
        兼容保留参数 (渲染已单轨化到 Spectre, 本封装不再写控制台)

    .PARAMETER SuccessMessage
        兼容保留参数 (渲染已单轨化到 Spectre, 本封装不再写控制台)

    .PARAMETER FailureMessage
        兼容保留参数 (渲染已单轨化到 Spectre, 本封装不再写控制台)

    .PARAMETER SuppressConsole
        测试模式: 返回 [PSCustomObject]@{ Result, Frames, Status, ElapsedMs }

    .OUTPUTS
        传 -SuppressConsole: [PSCustomObject]@{ Result, Frames, Status, ElapsedMs }
        未传 -SuppressConsole: ScriptBlock 的返回值
    #>
    [CmdletBinding()]
    [OutputType([void])]
    [OutputType([PSCustomObject])]
    [OutputType([object])]
    # Style/SuccessMessage/FailureMessage 仅为签名兼容保留, 静默路径不消费
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Style/SuccessMessage/FailureMessage 为签名兼容保留参数, 静默路径不使用')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [Parameter(Mandatory = $false)]
        [scriptblock]$PollScript,

        [Parameter(Mandatory = $false)]
        [ValidateRange(20, 2000)]
        [int]$IntervalMs = 80,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 600)]
        [int]$TimeoutSeconds = 60,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Braille', 'Ascii', 'Blocks', 'Dots', 'Arrows')]
        [string]$Style = 'Braille',

        [Parameter(Mandatory = $false)]
        [string]$SuccessMessage,

        [Parameter(Mandatory = $false)]
        [string]$FailureMessage,

        [Parameter(Mandatory = $false)]
        [switch]$SuppressConsole
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $frames = New-Object System.Collections.Generic.List[int]
    $frameIdx = 0
    $finalStatus = 'Success'
    $result = $null
    $timedOut = $false

    # 推一帧作为初始状态
    $frames.Add($frameIdx)
    $frameIdx++

    try {
        if ($PollScript) {
            # 轮询模式: 在主线程同步执行 ScriptBlock 一次, 然后轮询 PollScript
            # (调用方需保证 ScriptBlock 是"启动后返回"型的, 如 ssh 探查后台运行)
            $result = & $ScriptBlock
            $deadline = $stopwatch.Elapsed.TotalSeconds + $TimeoutSeconds
            while ($true) {
                Start-Sleep -Milliseconds $IntervalMs
                $done = $false
                $pollError = $null
                try {
                    $done = [bool](& $PollScript)
                } catch {
                    $pollError = $_
                }
                if ($null -ne $pollError) {
                    # 重新抛出让 outer catch 统一处理
                    throw $pollError
                }
                $frames.Add($frameIdx)
                $frameIdx++
                if ($done) { break }
                if ($stopwatch.Elapsed.TotalSeconds -ge $deadline) {
                    $timedOut = $true
                    $finalStatus = 'Failure'
                    break
                }
            }
        } else {
            # 同步模式: ScriptBlock 一次性执行完
            $result = & $ScriptBlock
        }
    } catch {
        $finalStatus = 'Failure'
        $result = $_
        # SuppressConsole 模式也抛出原异常, 使调用方可统一 catch (与 timeout 处理一致)
        if ($SuppressConsole) {
            $stopwatch.Stop()
            throw $_
        }
    }

    $stopwatch.Stop()

    if ($timedOut) {
        # 静默模式同样抛异常, 使调用方可统一 catch 测试 timeout
        throw [System.TimeoutException]::new("Invoke-WithProgress 超时 (${TimeoutSeconds}s): $Message")
    }

    if ($SuppressConsole) {
        return [PSCustomObject]@{
            Result    = $result
            Frames    = @($frames)
            Status    = $finalStatus
            ElapsedMs = [int]$stopwatch.ElapsedMilliseconds
        }
    }

    # 失败时重新抛出原异常
    if ($finalStatus -eq 'Failure' -and $result -is [System.Exception]) {
        throw $result
    }

    # 静默模式同样需要透传 ScriptBlock 的返回值, 否则调用方拿到的会是 $null
    return $result
}

function Invoke-WithProgress {
    <#
    .SYNOPSIS
        接受 ScriptBlock, 在执行期间动画显示 spinner

    .DESCRIPTION
        调度层: 按"能力形态"路由, 不做版本探测 (v2.0 单轨)。

        路由规则 (短路求值, 顺序即优先级):
          1. 显式传 -PollScript  → 轮询封装 (Spectre 无同步轮询语义)
          2. 置 -SuppressConsole  → 轮询封装 (Spectre 无法抑制控制台, 供 Pester 隔离断言)
          3. 显式调低 -TimeoutSeconds → 轮询封装 (Spectre 的 Start-AnsiConsoleStatus 无硬超时)
          4. 其它                 → 同步封装 (Invoke-SpectreCommandWithStatus 完整动画)

        用法 1 - 同步封装 (默认, 走 Spectre 完整动画):
          Invoke-WithProgress -Message "加载主机列表" -ScriptBlock { $hosts = Get-SshConfigHosts; return $hosts }
        用法 2 - 轮询封装 (跨秒级 SSH 探测):
          Invoke-WithProgress -Message "探测远程 tmux" `
                              -ScriptBlock { ssh探测调用 } `
                              -PollScript { $global:ProbeResult -ne $null } `
                              -TimeoutSeconds 10
        用法 3 - 隔离测试 (不写控制台, 返回结构化 Frames/ElapsedMs):
          Invoke-WithProgress -Message "t" -ScriptBlock { 42 } -SuppressConsole

        注: 轮询封装为静默路径 (进度渲染单轨化到 Spectre), 不会在控制台输出动画。

    .PARAMETER Message
        spinner 主提示文本

    .PARAMETER ScriptBlock
        主操作 (同步执行, 返回值会作为函数输出)

    .PARAMETER PollScript
        可选轮询脚本: 返回 $true 时结束轮询; 不传则走 Spectre 同步封装

    .PARAMETER IntervalMs
        轮询间隔, 默认 80ms (仅轮询封装生效)

    .PARAMETER TimeoutSeconds
        最长等待秒数, 默认 60s。
        默认值 60 走 Spectre 同步封装 (该路径不实现硬超时);
        显式传入小于默认值的值则路由到轮询封装以获得超时保护。

    .PARAMETER Style
        spinner 样式, 默认 Braille (经 Get-SpinnerStyleMapping 翻译为 Spectre 样式)

    .PARAMETER SuccessMessage
        成功完成时显示的提示; 不传则用 -Message + "完成" (仅轮询封装使用)

    .PARAMETER FailureMessage
        失败时显示的提示; 不传则用 -Message + "失败" (仅轮询封装使用)

    .PARAMETER SuppressConsole
        测试模式: 路由到轮询封装, 返回 [PSCustomObject]@{ Result, Frames, Status, ElapsedMs }

    .OUTPUTS
        同步封装 (默认): ScriptBlock 的返回值
        轮询封装 -SuppressConsole: [PSCustomObject]@{ Result, Frames, Status, ElapsedMs }
        轮询封装 控制台模式:    ScriptBlock 的返回值
    #>
    [CmdletBinding()]
    [OutputType([void])]
    [OutputType([PSCustomObject])]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [Parameter(Mandatory = $false)]
        [scriptblock]$PollScript,

        [Parameter(Mandatory = $false)]
        [ValidateRange(20, 2000)]
        [int]$IntervalMs = 80,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 600)]
        [int]$TimeoutSeconds = 60,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Braille', 'Ascii', 'Blocks', 'Dots', 'Arrows')]
        [string]$Style = 'Braille',

        [Parameter(Mandatory = $false)]
        [string]$SuccessMessage,

        [Parameter(Mandatory = $false)]
        [string]$FailureMessage,

        [Parameter(Mandatory = $false)]
        [switch]$SuppressConsole
    )

    # 路由: 轮询能力缺口 (PollScript / SuppressConsole / 显式短超时) → 轮询封装;
    #       其余 → Spectre 同步封装
    $needsPolling = $SuppressConsole `
                    -or $PSBoundParameters.ContainsKey('PollScript') `
                    -or ($PSBoundParameters.ContainsKey('TimeoutSeconds') -and $TimeoutSeconds -lt 60)

    if ($needsPolling) {
        $splat = @{} + $PSBoundParameters
        return Invoke-WithProgressPolling @splat
    }

    # 同步封装: Spectre.Console 自身无 timeout / poll 支持, 上面已把相关参数路由走
    return Invoke-WithProgressSpectre -Message $Message -ScriptBlock $ScriptBlock -Style $Style
}
