# Read-TmuxActionKey.ps1 - 读取一次按键(单键事件循环的输入原语)
# 职责: 从控制台读**一个**键, 归一化成 token 交给上层分发。
# 归一化约定:
#   单字符  -> 该字符(转小写); ESC -> 'ESC'; Enter -> 'ENTER'; Ctrl-C/不可用 -> ''
#
# 为什么不用 Read-Host:
#   Read-Host 读的是**一行**文本, 用户必须按回车, 高频操作(刷新/新建/直连)会被
#   "打字 + 回车"拖慢; [Console]::ReadKey 才是真正的单键读取。
#
# 为什么保留 -KeyReader 注入口:
#   真实按键读取依赖交互式终端, 自动化测试无法驱动; 注入读取器后,
#   Show-TmuxActionBar 的分发逻辑可被 Pester 完整覆盖(见 Tests/Show-TmuxActionBar.Tests.ps1)。

function Read-TmuxActionKey {
    <#
    .SYNOPSIS
        读取一次按键并归一化成 token。

    .DESCRIPTION
        默认实现用 [Console]::ReadKey($true) 读取单键(不回显), 返回:
          - 单字符: 该字符的小写形式;
          - ESC: 'ESC'; Enter: 'ENTER'; 退格: 'BACKSPACE';
          - 输入被重定向/读取失败/Ctrl-C: 空串(上层按"无输入"处理)。

        注入 -KeyReader 时直接使用注入器的返回值(测试用), 不触碰真实控制台。

    .PARAMETER KeyReader
        可选的按键读取脚本块, 返回 token 字符串。不提供时读真实控制台。

    .OUTPUTS
        [string] 归一化后的按键 token; 无输入时为空串

    .EXAMPLE
        Read-TmuxActionKey -KeyReader { 'n' }
        # -> n
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [scriptblock]$KeyReader
    )

    # 注入口: 测试与非交互环境走这里, 不读真实控制台
    if ($KeyReader) {
        $token = & $KeyReader
        if ($null -eq $token) { return '' }
        return ([string]$token).Trim()
    }

    try {
        # 输入被重定向(管道/非交互宿主)时 ReadKey 会抛异常; 提前判定更干净
        if ([Console]::IsInputRedirected) { return '' }
        $info = [Console]::ReadKey($true)
    } catch {
        # Ctrl-C / 宿主不支持 / 终端异常: 一律按"无输入"处理, 绝不冒泡打断管理器
        return ''
    }

    if ($null -eq $info) { return '' }

    if ($info.Key -eq [ConsoleKey]::Escape) { return 'ESC' }
    if ($info.Key -eq [ConsoleKey]::Enter) { return 'ENTER' }
    if ($info.Key -eq [ConsoleKey]::Backspace) { return 'BACKSPACE' }

    $char = [string]$info.KeyChar
    if ([string]::IsNullOrEmpty($char)) { return '' }
    return $char.ToLowerInvariant()
}
