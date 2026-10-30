# ConvertTo-SshArgumentLine.ps1 - 把 SSH 参数数组拼成一条进程命令行
#
# 为什么需要它 (2026-10-29 SSH 可靠性审计):
#   ProcessStartInfo.Arguments 与 Start-Process -ArgumentList 最终都是"一条命令行字符串",
#   由平台参数解析器 (Windows CommandLineToArgvW / .NET ParseArgv) 重新拆成 argv:
#   - 含空白或双引号的元素若不加引号, 会被拆成多个 argv, 其中裸双引号还会被当成分隔符吃掉,
#     导致远端命令被改写 (如 tmux kill-session -t 'a"b' 实际打到 'ab' 会话上);
#   - 加引号后, 内部双引号必须写成 \", 反斜杠按捕获路径既有算法翻倍 (见下方"算法不变"声明)。
#   两条 SSH 执行路径共用本函数, 保证同一份参数在捕获/非捕获路径下生成完全相同的命令行。
#
# 算法不变声明 (2026-10-29): 逐元素规则与重构前 Invoke-SshCaptureOutput 的内联代码逐字节一致
#   (仅"含空白/双引号才加引号"时翻倍反斜杠、双引号转义为 \"; 不含则原样), 不做算法改动。
#   tmux 探测命令依赖该行为, 由 Tests/Invoke-SshCaptureOutput.Tests.ps1 的钉死用例守护。

function ConvertTo-SshArgumentLine {
    <#
    .SYNOPSIS
        把 SSH 参数数组拼接为一条按 CRT 规则转义的进程命令行字符串

    .DESCRIPTION
        逐元素处理: 含空白或双引号的元素用双引号包裹 (包裹时反斜杠翻倍、双引号转义为 \"),
        不含的元素原样保留; 最后用单个空格连接。
        远端命令在 Get-SshArgs 中始终作为单个数组元素传入, 经本函数后仍是命令行里的
        一个整体 (含空白时被引号包裹), 不会被拆成多个 argv 元素。

    .PARAMETER Argument
        参数数组 (由 Get-SshArgs 构建的字符串序列)

    .OUTPUTS
        [string] 拼接完成的命令行

    .EXAMPLE
        ConvertTo-SshArgumentLine -Argument @('-o', 'BatchMode=yes', 'host', 'tmux ls')
        # -> -o BatchMode=yes host "tmux ls"
    #>
    [CmdletBinding()]
    [OutputType([string])]
param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$Argument
    )

    # 手动按 CommandLineToArgvW 规则引号包裹每个参数
    # (ProcessStartInfo.Arguments 需要单条命令行字符串, 参数间转义规则自行维护)
    $escaped = $Argument | ForEach-Object {
        $a = [string]$_
        if ($a -match '\s|"') {
            # 含空格或双引号 → 用双引号包裹, 内部双引号转义为 \"、反斜杠翻倍
            # (反斜杠翻倍为既有算法, tmux 探测命令依赖它, 不得改动)
            '"' + ($a -replace '\\', '\\' -replace '"', '\"') + '"'
        } else {
            $a
        }
    }
    return ($escaped -join ' ')
}
