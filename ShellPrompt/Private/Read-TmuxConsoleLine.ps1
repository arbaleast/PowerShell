# Read-TmuxConsoleLine.ps1 - 文本输入模式(状态机 Input 态)的单行输入读取器
#
# 背景 (2026-10-30 第三轮 TUI 修复):
#   New-TmuxSession 原先用 [Console]::ReadLine() 读会话名: ReadLine 读的是
#   "一行按下 Enter 才算"的宿主行编辑, 退格/输入法切换/控制字符在
#   自绘 HUD 界面下的表现完全不受我们控制, 旁边的键位循环还会把打字过程
#   当作未识别按键刷出 "未识别的按键 ''" 红色错误。
#
# 状态机语义 (Input 态唯一职责):
#   - Enter  -> 提交, 返回缓冲区(允许空串: 上层按"使用随机名称"处理);
#   - Esc    -> 取消, 返回 $null(上层据此放弃创建);
#   - Backspace -> 删掉缓冲区最后一个字符并重绘(空缓冲退格静默忽略);
#   - 可见 KeyChar (\x20-\x7E 与 \xA0 以上的中文等) -> 追加缓冲区;
#   - 其余一切(功能键无 KeyChar、C0 控制字符 \x00-\x1F、DEL、C1 段) ->
#     **静默忽略, 绝不打印任何错误** —— 与 Normal 态动作条事件循环严格分离。
#
# 测试注入口: -KeyReader 注入按键序列(PSCustomObject{Key/KeyChar}), 规避
# 真实控制台交互; 默认路径读完真实 [Console]::ReadKey($true)。

function Read-TmuxConsoleLine {
    <#
    .SYNOPSIS
        Input 态单行文本输入读取器(状态机): Enter 提交 / Esc 取消 / Backspace 退格。

    .DESCRIPTION
        在 -Row(1 基 ANSI 行) 处维护输入缓冲区的单行编辑循环:
          - 提示符与缓冲区随每次按键重绘(清行到行尾, 防残影);
          - Backspace 删除最后一个字符(空缓冲静默忽略);
          - 只接收可见字符(\x20-\x7E 与 \xA0 以上的 BMP 字符);
          - 其余按键全部静默忽略 —— 没有错误输出, 没有日志刷屏。

        .Key/.KeyChar 在真实与注入路径下都按同形状对象读取:
        真实路径是 [ConsoleKeyInfo], 注入路径是 PSCustomObject{Key/KeyChar}。

        -Inline 开关切换重绘方式(2026-10-30 TGUI 迁移):
          - 默认(绝对定位): \e[<Row>;<Col+1>H 定位 -> 写缓冲 -> \e[K 清到行尾。
            只适用于"本模块持有全屏备用屏"的场景, 可以把输入行画在屏幕任意行。
          - -Inline(就地重绘): \r 回行首 -> 写缓冲 -> \e[K 清到行尾, 完全不做
            绝对定位。适用于终端是普通屏的场景(TGUI 仪表盘路径): 绝对定位会写到
            任意位置并留下残影, 内联重绘只在当前行内自我清理。
            前提: 调用方保证输入区起点在行首(列 0), 否则 \r 会覆盖提示语。

    .PARAMETER Row
        输入行在终端的 1 基行号(重绘用; -Inline 模式下不使用)

    .PARAMETER Column
        缓冲区文本起始的 .NET CursorLeft(0 基), 默认 7(与 New-TmuxSession HUD 对齐;
        -Inline 模式下不使用)

    .PARAMETER Inline
        就地重绘模式: 不发绝对定位序列, 只在当前行内 \r + 缓冲 + \e[K 重画。

    .PARAMETER KeyReader
        可选按键注入器(测试用): 每次调用返回一个含 .Key/.KeyChar 的对象,
        返回 $null 表示输入流结束(按取消处理)。不提供时读真实控制台。

    .OUTPUTS
        [string] Enter 提交的输入(可为空串); $null = Esc 取消 / 输入流结束

    .EXAMPLE
        $name = Read-TmuxConsoleLine -Row 14 -Column 7

    .EXAMPLE
        $name = Read-TmuxConsoleLine -Row 1 -Inline
    #>
    # Row/Column/Inline 在 $redraw scriptblock 闭包内使用; PSSA 的参数静态分析识别不了
    # scriptblock 内的使用, 显式抑制(与其他 Private 文件同处理)。
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Row')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Column')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Inline')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 9999)]
        [int]$Row,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 9999)]
        [int]$Column = 7,

        [Parameter(Mandatory = $false)]
        [switch]$Inline,

        [Parameter(Mandatory = $false)]
        [scriptblock]$KeyReader
    )

    # 清行重绘: 绝对定位模式 \e[<Row>;<Col>H 定位 -> 写缓冲 -> \e[K 清到行尾;
    # 内联模式 \r 回行首 -> 写缓冲 -> \e[K 清到行尾(不定位, 只在当前行内自清理)。
    # 光标自然落在缓冲文本末尾(协议保证), 不用 .NET 的 CursorLeft/CursorVisible ——
    # 那两个 setter 在重定向控制台下会抛 IOException, 测试环境/管道场景直接翻车。
    $redraw = {
        if ($Inline) {
            [Console]::Write("`r" + $buffer + "`e[K")
        } else {
            [Console]::Write("`e[${Row};$(($Column + 1))H" + $buffer + "`e[K")
        }
    }

    $buffer = ''
    & $redraw

    while ($true) {
        if ($KeyReader) {
            $info = & $KeyReader
        } else {
            try {
                # 输入被重定向(管道/非交互宿主)时 ReadKey 会抛异常, 提前判定返回取消
                if ([Console]::IsInputRedirected) { return $null }
                $info = [Console]::ReadKey($true)
            } catch {
                # Ctrl-C / 宿主不支持 / 终端异常: 按取消处理, 绝不冒泡打断管理器
                return $null
            }
        }
        if ($null -eq $info) { return $null }

        # 状态机 Input 态分支: Enter / Esc / Backspace / 可见字符 / 其余静默
        $keyName = [string]$info.Key
        if ($keyName -eq [ConsoleKey]::Enter.ToString()) {
            return $buffer
        }
        if ($keyName -eq [ConsoleKey]::Escape.ToString()) {
            & $redraw
            return $null
        }
        if ($keyName -eq [ConsoleKey]::Backspace.ToString()) {
            if ($buffer.Length -gt 0) {
                $buffer = $buffer.Substring(0, $buffer.Length - 1)
                & $redraw
            }
            # 空缓冲的退格: 静默忽略
            continue
        }

        $keyChar = [char]$info.KeyChar
        $code = [int]$keyChar
        # 可见字符: ASCII 可打印段 \x20-\x7E, 与 \xA0 以上的 BMP(中文等宽字符);
        # \x00-\x1F(C0) / 0x7F(DEL) / 0x80-0x9F(C1) 一律静默忽略, 不打印错误
        if ($keyChar -ne "`0" -and
            (($code -ge 0x20 -and $code -ne 0x7F) -or $code -ge 0xA0)) {
            $buffer += [string]$keyChar
            & $redraw
        }
        # 其余按键: 无 KeyChar 的功能键 / 控制字符 -> 静默忽略
    }
}
