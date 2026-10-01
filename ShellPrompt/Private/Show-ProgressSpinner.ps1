# Show-ProgressSpinner.ps1 - 加载动画组件
# P2-1: 提供单帧 spinner 打印 + 纯函数帧查询
# P2-4: 新增 Invoke-WithProgress 封装(调用方传入 ScriptBlock, 内部 spin 循环 + 自动完成态)
# 设计原则:
# 1. 纯函数 Get-SpinnerFrame 抽离帧序列(便于 Pester 单元测试)
# 2. Show-ProgressSpinner 是 I/O 包装, 通过 -PassThru 返回帧数据跳过实际渲染
# 3. PS 5.1 兼容: 不使用 Start-ThreadJob (仅 PS 7+), 改为单帧 API + 调用方控制循环
# 4. 调用方负责: 在耗时操作前打 1 帧, 操作中按需刷新, 完成后打完成态
# 5. Invoke-WithProgress: 阻塞式工作流封装, 接受 ScriptBlock, spin 循环直到 ScriptBlock 返回或超时

# 内置 spinner 样式: 5 套 unicode 字符序列
# 每套包含 FrameCount 帧, 循环播放; 全部是 unicode 宽字符, 终端宽度稳定
$script:SpinnerStyles = @{
    # 盲文点阵 (默认), 视觉柔和, 10 帧循环
    'Braille' = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
    # ASCII 兼容回退, 在不支持 unicode 的终端自动启用
    'Ascii'   = @('-', '\', '|', '/')
    # 进度块动画, 强调"进行中"
    'Blocks'  = @('▁', '▂', '▃', '▄', '▅', '▆', '▇', '█', '▇', '▆', '▅', '▄', '▃', '▂')
    # 圆点脉冲, 适合"等待/扫描"
    'Dots'    = @('.  ', '.. ', '...', ' ..', '  .', '   ')
    # 箭头旋转, 强调"加载方向"
    'Arrows'  = @('←', '↖', '↑', '↗', '→', '↘', '↓', '↙')
}

# 动画结束态符号: ✓ / ✗
$script:SpinnerDoneGlyphs = @{
    Success = '✓'
    Failure = '✗'
    Pending = '·'
}

function Get-SpinnerFrame {
    <#
    .SYNOPSIS
        根据 Frame 索引返回单帧 spinner 字符(纯函数, 无 I/O)

    .DESCRIPTION
        P2-1 抽离的纯函数, 便于 Pester 单元测试。
        Frame 索引超出范围时按 FrameCount 取模, 保证始终返回有效字符;
        负数索引也会正确回绕(取模结果修正为正)。

    .PARAMETER Frame
        帧索引(0-based, 负数也合法, 会先做模运算)

    .PARAMETER Style
        spinner 样式名(默认 'Braille'), 取自 $script:SpinnerStyles
        未知样式回退到 Braille

    .OUTPUTS
        [string] 单个 unicode 字符
    #>
    [CmdletBinding()]
    [OutputType([string])]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '')]
param(
        [Parameter(Mandatory = $true)]
        [int]$Frame,

        [Parameter(Mandatory = $false)]
        [string]$Style = 'Braille'
    )

    if (-not $script:SpinnerStyles.ContainsKey($Style)) {
        $Style = 'Braille'
    }
    $seq = $script:SpinnerStyles[$Style]
    $count = $seq.Count
    if ($count -eq 0) { return ' ' }

    # 处理负数帧: PowerShell 的 % 运算符对负数返回负数, 需要修正
    $idx = ($Frame % $count + $count) % $count
    return $seq[$idx]
}

function Get-SpinnerSequence {
    <#
    .SYNOPSIS
        返回指定样式的完整帧序列(纯函数)

    .DESCRIPTION
        供调用方预先缓存帧序列, 避免在动画循环中反复访问 $script: 作用域

    .PARAMETER Style
        spinner 样式名

    .OUTPUTS
        [string[]] 帧字符数组
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Style = 'Braille'
    )

    if (-not $script:SpinnerStyles.ContainsKey($Style)) {
        $Style = 'Braille'
    }
    return $script:SpinnerStyles[$Style]
}

function Show-ProgressSpinner {
    <#
    .SYNOPSIS
        在终端打印 spinner 帧或完成态(单帧写入, 不阻塞)

    .DESCRIPTION
        轻量级单帧 API, 调用方负责循环调度:
          for ($i=0; $i -lt $maxIter; $i++) {
              Show-ProgressSpinner -Frame $i -Message "加载中 ($i/$maxIter)"
              Start-Sleep -Milliseconds 80
              $result = Do-SomeWork
              if ($result) { break }
          }
          Show-ProgressSpinner -Done -Status Success -Message "完成"

        通过 -PassThru 可跳过 console 写入, 仅返回结构化数据(测试模式)。

    .PARAMETER Message
        spinner 旁边的提示文本

    .PARAMETER Frame
        帧索引(0-based, 负数回绕)

    .PARAMETER Style
        spinner 样式 (Braille / Ascii / Blocks / Dots / Arrows)

    .PARAMETER Done
        切换到完成态模式, 配合 -Status 输出 ✓/✗/·

    .PARAMETER Status
        完成态类型 (Success / Failure / Pending), 仅在 -Done 时生效

    .PARAMETER PassThru
        测试模式: 不写控制台, 返回 [PSCustomObject]@{ Glyph, Message, Frame, Style, IsDone, Status }

    .EXAMPLE
        Show-ProgressSpinner -Frame 0 -Message "正在加载"
        Show-ProgressSpinner -Done -Status Success -Message "加载完成"
    #>
    [CmdletBinding(DefaultParameterSetName = 'Frame')]
    [OutputType([void], ParameterSetName = 'Frame')]
    [OutputType([void], ParameterSetName = 'Done')]
    [OutputType([PSCustomObject], ParameterSetName = 'FramePassThru')]
    [OutputType([PSCustomObject], ParameterSetName = 'DonePassThru')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false, ParameterSetName = 'Frame')]
        [Parameter(Mandatory = $false, ParameterSetName = 'FramePassThru')]
        [int]$Frame = 0,

        [Parameter(Mandatory = $false, ParameterSetName = 'Frame')]
        [Parameter(Mandatory = $false, ParameterSetName = 'FramePassThru')]
        [ValidateSet('Braille', 'Ascii', 'Blocks', 'Dots', 'Arrows')]
        [string]$Style = 'Braille',

        [Parameter(Mandatory = $true, ParameterSetName = 'Done')]
        [Parameter(Mandatory = $true, ParameterSetName = 'DonePassThru')]
        [switch]$Done,

        [Parameter(Mandatory = $false, ParameterSetName = 'Done')]
        [Parameter(Mandatory = $false, ParameterSetName = 'DonePassThru')]
        [ValidateSet('Success', 'Failure', 'Pending')]
        [string]$Status = 'Success',

        [Parameter(Mandatory = $true, ParameterSetName = 'FramePassThru')]
        [Parameter(Mandatory = $true, ParameterSetName = 'DonePassThru')]
        [switch]$PassThru
    )

    $primary = Get-CachedConfig -Section 'Colors' -Key 'FreshGreen' -Default "`e[38;2;137;209;133m"
    $muted   = Get-CachedConfig -Section 'Colors' -Key 'MidGray'    -Default "`e[38;2;100;100;100m"
    $errorColor = "`e[38;2;220;80;80m"  # 红色, 完成态失败
    $rst     = Get-CachedConfig -Section 'Colors' -Key 'Rst'        -Default "`e[0m"

    if ($Done) {
        $glyph = $script:SpinnerDoneGlyphs[$Status]
        $color = if ($Status -eq 'Failure') { $errorColor } else { $primary }
        $payload = [PSCustomObject]@{
            Glyph   = $glyph
            Message = $Message
            Frame   = -1
            Style   = ''
            IsDone  = $true
            Status  = $Status
        }
        if ($PassThru) { return $payload }
        # \r 回行首, \e[K 清行尾, \n 结束本行
        [Console]::Write("`r${color}${glyph}${rst}  ${muted}${Message}${rst}`e[K`n")
        return
    }

    $glyph = Get-SpinnerFrame -Frame $Frame -Style $Style
    $payload = [PSCustomObject]@{
        Glyph   = $glyph
        Message = $Message
        Frame   = $Frame
        Style   = $Style
        IsDone  = $false
        Status  = ''
    }
    if ($PassThru) { return $payload }
    # \r 回行首, \e[K 清行尾(避免上次输出残留)
    [Console]::Write("`r${primary}${glyph}${rst}  ${muted}${Message}${rst}`e[K")
}

function Invoke-WithProgress {
    <#
    .SYNOPSIS
        接受 ScriptBlock, 在执行期间动画显示 spinner (P2-4 封装)

    .DESCRIPTION
        行为约定:
          1. 调用 -ScriptBlock 之前先打 1 帧 spinner (Frame 0)
          2. 主循环: 轮询 -PollScript 结果 (间隔 -IntervalMs ms), 每帧刷新一次 spinner
          3. -PollScript 返回 $true 时认作"完成", 跳出循环打 Success 完成态
          4. -PollScript 拋异常或 -ScriptBlock 拋异常 -> 打 Failure 完成态 + 重新拋出
          5. -TimeoutSeconds 超时 (默认 60s) -> 打 Failure + 拋 TimeoutException
          6. 若 -SuppressConsole 置位 (用于测试 / Pester), 不写 console, 仅返回结构化对象

        用法 1 - 同步封装: 只在前后打一帧一状态
          Invoke-WithProgress -Message "加载主机列表" -ScriptBlock { $hosts = Get-SshConfigHosts; return $hosts }
        用法 2 - 轮询封装: 跨秒级 SSH 探测轮询
          Invoke-WithProgress -Message "探测远程 tmux" `
                              -ScriptBlock { ssh探测调用 } `
                              -PollScript { $global:ProbeResult -ne $null } `
                              -TimeoutSeconds 10

    .PARAMETER Message
        spinner 主提示文本

    .PARAMETER ScriptBlock
        主操作(同步执行, 返回值会作为函数输出)

    .PARAMETER PollScript
        可选轮询脚本: 返回 $true 时结束 spinner; 不传则 ScriptBlock 结束后立即完成

    .PARAMETER IntervalMs
        轮询间隔, 默认 80ms

    .PARAMETER TimeoutSeconds
        最长等待秒数, 默认 60s

    .PARAMETER Style
        spinner 样式, 默认 Braille

    .PARAMETER SuccessMessage
        成功完成时显示的提示; 不传则用 -Message + "完成"

    .PARAMETER FailureMessage
        失败时显示的提示; 不传则用 -Message + "失败"

    .PARAMETER SuppressConsole
        测试模式: 不写 console, 返回 [PSCustomObject]@{ Result, Frames, Status, ElapsedMs }

    .OUTPUTS
        不传 -SuppressConsole: void
        传 -SuppressConsole:  [PSCustomObject]@{ Result, Frames, Status, ElapsedMs }
    #>
    [CmdletBinding()]
    [OutputType([void])]
    [OutputType([PSCustomObject])]
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

    if (-not $SuccessMessage) { $SuccessMessage = "${Message}完成" }
    if (-not $FailureMessage) { $FailureMessage = "${Message}失败" }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $frames = New-Object System.Collections.Generic.List[int]
    $frameIdx = 0
    $finalStatus = 'Success'
    $result = $null
    $timedOut = $false

    # 推一帧作为初始状态
    $frames.Add($frameIdx)
    if (-not $SuppressConsole) {
        Show-ProgressSpinner -Message $Message -Frame $frameIdx -Style $Style
    }
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
                    # 重新拋出让 outer catch 统一处理 (含 SuppressConsole 模式)
                    throw $pollError
                }
                $frames.Add($frameIdx)
                if (-not $SuppressConsole) {
                    Show-ProgressSpinner -Message $Message -Frame $frameIdx -Style $Style
                }
                $frameIdx++
                if ($done) { break }
                if ($stopwatch.Elapsed.TotalSeconds -ge $deadline) {
                    $timedOut = $true
                    $finalStatus = 'Failure'
                    break
                }
            }
        } else {
            # 同步模式: ScriptBlock 本身可能耗时长, 期间用 .NET Thread 轮询控制台刷新 spinner
            # 避免 Start-ThreadJob(仅 PS 7+), 用 [System.Threading.Thread]::SpinWait 仅
            # 作为间隔等待, 不用额外线程
            $result = & $ScriptBlock
        }
    } catch {
        $finalStatus = 'Failure'
        $result = $_
        # SuppressConsole 模式也拋出原异常, 使调用方可统一 catch (与 timeout 处理一致)
        if ($SuppressConsole) {
            $stopwatch.Stop()
            throw $_
        }
    }

    $stopwatch.Stop()

    if ($timedOut) {
        if (-not $SuppressConsole) {
            Show-ProgressSpinner -Done -Status Failure -Message $FailureMessage
        }
        # SuppressConsole 模式仍抛异常, 使调用方可统一 catch 测试 timeout
        throw [System.TimeoutException]::new("Invoke-WithProgress 超时 (${TimeoutSeconds}s): $Message")
    }

    $finalMsg = if ($finalStatus -eq 'Success') { $SuccessMessage } else { $FailureMessage }
    if (-not $SuppressConsole) {
        Show-ProgressSpinner -Done -Status $finalStatus -Message $finalMsg
    }

    if ($SuppressConsole) {
        return [PSCustomObject]@{
            Result    = $result
            Frames    = @($frames)
            Status    = $finalStatus
            ElapsedMs = [int]$stopwatch.ElapsedMilliseconds
        }
    }

    # 失败时重新拋出原异常
    if ($finalStatus -eq 'Failure' -and $result -is [System.Exception]) {
        throw $result
    }
}
