# Show-ProgressSpinner.ps1 - 加载动画组件 (单轨 Spectre)
# P2-1: 提供单帧 spinner 打印 + 纯函数帧查询
# P2-4: 新增 Invoke-WithProgress 封装(调用方传入 ScriptBlock, 内部 spin 循环 + 自动完成态)
# v2.0 (单轨 Spectre):
#   1) 唯一渲染出口 = PwshSpectreConsole 的 Write-SpectreHost / Invoke-SpectreCommandWithStatus
#   2) 已删除 legacy ANSI 路径与双轨探测(Test-SpectreSpinnerAvailable / -ForceLegacy)
#   3) 运行时硬依赖 PowerShell 7.4+ 与仓库内置 Modules/PwshSpectreConsole
# 设计原则:
# 1. 纯函数 Get-SpinnerFrame 抽离帧序列(便于 Pester 单元测试)
# 2. Show-ProgressSpinner 是 I/O 包装, 通过 -PassThru 返回帧数据跳过实际渲染
# 3. 单帧 API: 不使用 Start-ThreadJob, 改为调用方控制循环
# 4. 调用方负责: 在耗时操作前打 1 帧, 操作中按需刷新, 完成后打完成态
# 5. Invoke-WithProgress: 阻塞式工作流封装, 接受 ScriptBlock, spin 循环直到 ScriptBlock 返回或超时

# ESC 码(0x1B)。仅用于 Spectre markup 无法表达的光标控制(回行首 / 清行尾)
$script:Esc = [char]27

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

function Get-SpinnerStyleMapping {
    <#
    .SYNOPSIS
        将 ShellPrompt spinner 样式名映射到 Spectre.Spinner.Known 枚举字符串

    .DESCRIPTION
        映射规则:
          Dots    → Dots6   (用户原始诉求即"6 个点的加载动画")
          Braille → Dots3   (盲文点阵最接近的 Spectre 内置样式)
          Ascii   → Ascii   (直接对应)
          Blocks  → Block1  (进度块最接近的 Spectre 内置样式)
          Arrows  → Arrow   (直接对应)
          其它     → Dots6   (安全回退)

        本函数是纯函数, 便于 Pester 单元测试覆盖所有分支。
        Invoke-WithProgress 用本函数把 ShellPrompt 样式名翻译成 Spectre 的 Spinner 名称。

    .PARAMETER Style
        ShellPrompt spinner 样式名 (Braille/Ascii/Blocks/Dots/Arrows)

    .OUTPUTS
        [string] Spectre.Spinner.Known 枚举名称 (例如 'Dots6', 'Ascii', 'Arrow')
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Style = 'Braille'
    )

    $map = @{
        'Dots'    = 'Dots6'
        'Braille' = 'Dots3'
        'Ascii'   = 'Ascii'
        'Blocks'  = 'Block1'
        'Arrows'  = 'Arrow'
    }
    if ($map.ContainsKey($Style)) { return $map[$Style] }
    return 'Dots6'
}

function ConvertTo-SpectrePlainText {
    <#
    .SYNOPSIS
        把纯文本转义为 Spectre markup 安全字符串

    .DESCRIPTION
        Write-SpectreHost 的 -Message 参数按 Spectre markup 解析, 裸 '[' 会被当成
        样式标记起始符(例如 "[0K" 会被解析失败或误渲染)。本函数把 '[' 双写为 '[[',
        依据 Spectre markup 转义规则还原为字面量方括号。
        放在 Private/ 供所有走 Write-SpectreHost 的 UI 路径共用, 是单轨改造后
        "纯文本 vs markup" 的统一边界。

    .PARAMETER Text
        待转义的原始文本(可含 '[' 字符)

    .OUTPUTS
        [string] markup 安全字符串
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Text
    )

    if ([string]::IsNullOrEmpty($Text)) { return '' }
    return $Text -replace '\[', '[['
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

        v2.0 单轨渲染: 非 -PassThru 时统一走 Write-SpectreHost, 无 legacy ANSI 兜底。
        Spectre.Console 没有原生的"单帧 spinner"概念(其 Spinner 是
        Invoke-SpectreCommandWithStatus 包裹整段 ScriptBlock 的), 因此这里用
        Write-SpectreHost 输出一行(回行首 + 清行尾), 语义等价于旧单帧写入,
        且在 Spectre Live 渲染上下文中能被正确 Refresh() 重绘。

        通过 -PassThru 可跳过 console 写入, 仅返回结构化数据(测试模式)。

    .PARAMETER Message
        spinner 旁边的提示文本(按 Spectre markup 规则做转义, 裸 '[' 安全)

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

    # ---- PassThru: 纯数据通道, 不触碰 Spectre (测试与上层编排复用) ----
    if ($Done) {
        $payload = [PSCustomObject]@{
            Glyph   = $script:SpinnerDoneGlyphs[$Status]
            Message = $Message
            Frame   = -1
            Style   = ''
            IsDone  = $true
            Status  = $Status
        }
    } else {
        $payload = [PSCustomObject]@{
            Glyph   = (Get-SpinnerFrame -Frame $Frame -Style $Style)
            Message = $Message
            Frame   = $Frame
            Style   = $Style
            IsDone  = $false
            Status  = ''
        }
    }
    if ($PassThru) { return $payload }

    # ---- 单轨渲染: 统一走 Write-SpectreHost ----
    # 主题色由 Get-CachedConfig 提供, 以裸 ESC 表达(Spectre markup 的 24 位真彩语法
    # 是 [rgb(r,g,b)], 与配置层存储的 ESC 串不同源, 保持一致避免二次转换)。
    $colorTable = Resolve-ColorTable -Name 'Primary', 'Muted', 'Rst'
    $primary   = $colorTable.Primary
    $muted     = $colorTable.Muted
    $errorColor = "$Esc[38;2;220;80;80m"
    $rst       = $colorTable.Rst

    $glyph = $payload.Glyph
    $color = if ($Status -eq 'Failure' -and $Done) { $errorColor } else { $primary }

    # 关键: Write-SpectreHost 的 -Message 按 Spectre markup 解析, 整行里的 '[' 会被当成
    # 样式标记起始符(包括 ESC 段的 [38;2;...m 与清行尾的 [0K)。因此对"拼好的整行"统一
    # 做 '[' -> '[[' 转义, Spectre 会还原为字面量 '[' 并原样写向终端, 从而让既有
    # ESC 序列与主题色照常生效, 同时 Message 中的裸方括号(如 tmux [session]) 不会被误解析。
    $line = "`r${color}${glyph}${rst}  ${muted}${Message}${rst}$Esc[0K"
    $safeLine = ConvertTo-SpectrePlainText -Text $line

    if ($Done) {
        Write-SpectreHost ($safeLine + "`n")
    } else {
        Write-SpectreHost $safeLine
    }
}
