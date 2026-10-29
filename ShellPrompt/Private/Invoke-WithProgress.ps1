# Invoke-WithProgress.ps1 - ScriptBlock 执行期间的进度封装
# 职责: 把调用方传入的 -ScriptBlock 包装进 Spectre.Console 的
#       Invoke-SpectreCommandWithStatus, 由 Spectre 负责 spinner 的完整生命周期
#       (启动 spinner -> 等待 ScriptBlock 完成 -> 结束)。
# 唯一渲染出口: PwshSpectreConsole 的 Invoke-SpectreCommandWithStatus (单轨)。
# 依赖: Get-SpinnerStyleMapping.ps1 (ShellPrompt 样式名 -> Spectre spinner 名)。
# 异常语义: ScriptBlock 抛出的异常由 Invoke-SpectreCommandWithStatus 原样抛出。
#
# 2026-10-29 精简(依据"无生产调用方即死代码"原则):
#   删除 Invoke-WithProgressPolling 轮询封装(约 165 行)与随之失去意义的
#   -PollScript / -IntervalMs / -TimeoutSeconds / -SuppressConsole / -SuccessMessage /
#   -FailureMessage 六个参数; 同时把只剩一层转发的 Invoke-WithProgressSpectre
#   合并进本函数, 保持"一函数一文件"。
#   依据: 三个生产调用点(Start-TmuxSession.ps1 的"加载主机列表" / "检测远程 tmux" /
#   "获取远程 tmux 会话")全部只传 -Message + -ScriptBlock, 从未进入过轮询分支;
#   轮询分支唯一的消费者是它自己的单元测试。Spectre.Console 的
#   Start-AnsiConsoleStatus 本身没有 timeout 概念, 轮询分支宣称的"硬超时"
#   从未在生产链路上生效过; 而"完成检测"(PollScript)当前也没有生产需求 ——
#   三个调用点的 ScriptBlock 都是一次性阻塞命令, 返回即完成。

function Invoke-WithProgress {
    <#
    .SYNOPSIS
        接受 ScriptBlock, 在执行期间用 Spectre.Console 显示进度动画

    .DESCRIPTION
        把调用方传入的 -ScriptBlock 透传给 Invoke-SpectreCommandWithStatus, 由
        Spectre.Console 的 Start-AnsiConsoleStatus 完整生命周期渲染
        (启动 spinner -> 等待 ScriptBlock 完成 -> 结束)。
        样式名通过 Get-SpinnerStyleMapping 从 ShellPrompt 风格
        (Braille/Ascii/Blocks/Dots/Arrows) 翻译为 Spectre.Spinner.Known 字符串
        (Dots3/Ascii/Material/...)。

        能力边界 (Spectre API 自身限制, 非版本回退):
          Spectre.Console 没有 timeout / poll 语义, 因此本封装不提供
          -TimeoutSeconds / -PollScript; 需要超时由调用方自行处理。

        异常透传: ScriptBlock 抛出的异常由 Invoke-SpectreCommandWithStatus 原样抛出。

    .PARAMETER Message
        spinner 主提示文本 (映射为 Spectre -Title)

    .PARAMETER ScriptBlock
        主操作 (透传给 Invoke-SpectreCommandWithStatus)

    .PARAMETER Style
        ShellPrompt 样式名 (Braille/Ascii/Blocks/Dots/Arrows) — 翻译为 Spectre spinner

    .OUTPUTS
        [object] ScriptBlock 的返回值

    .EXAMPLE
        Invoke-WithProgress -Message "加载主机列表" -ScriptBlock { Get-SshConfigHosts }
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
