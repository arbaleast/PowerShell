# ============================================================
# Invoke-SshCommand.ps1 - SSH 远程命令执行辅助函数
# 功能: 统一管理 SSH 连接，防止命令注入
# 安全策略:
#   - HostName 参数输入验证（拒绝 shell 特殊字符）
#   - 远程命令字符串由调用方转义用户变量
#   - 使用 Start-Process 传递参数数组（避免 cmd.exe 解释）
# 变更记录:
#   - [2026-05-23] 新增 -PassThru 参数，返回 SSH 进程退出码供调用方校验
#   - [2026-05-25] 新增 -SkipHostKeyCheck 参数，默认 false 更安全
#   - [2026-06-04] 交互式 SSH 返回后自动重置终端状态（鼠标追踪、备选屏幕缓冲区等）
# ============================================================

# ============================================================
# Reset-TerminalMode - 重置终端状态
# SSH/tmux 会话可能启用鼠标追踪、备选屏幕缓冲区等特性
# 断开后需要重置，否则本地终端显示异常
# ============================================================
function Reset-TerminalMode {
    # 1. 禁用所有鼠标追踪模式（确保完整清除）
    [Console]::Write("`e[?1000l")   # 禁用按钮事件鼠标追踪
    [Console]::Write("`e[?1002l")   # 禁用拖拽事件鼠标追踪
    [Console]::Write("`e[?1003l")   # 禁用所有鼠标追踪（部分终端）
    [Console]::Write("`e[?1006l")   # 禁用扩展鼠标模式（SGR）
    
    # 2. 退出备选屏幕缓冲区（tmux/SSH 可能切换到备选缓冲区）
    [Console]::Write("`e[?1049l")
    
    # 3. 显示光标（可能被远程会话隐藏）
    [Console]::Write("`e[?25h")
    
    # 4. 重置字符属性（颜色、粗体等）
    [Console]::Write("`e[m")
    
    # 5. 重置终端软属性（DECSC 参数）
    [Console]::Write("`e[!p")
}

# 将用户输入的值进行 POSIX shell 单引号转义
# 原理: ' -> '\''（关闭单引号 -> 转义单引号 -> 重新开启单引号）
# 这是 POSIX shell 标准的安全转义方式
# 示例: "test'session" -> "test'\''session"（在远程 shell 中保持为字面值）
function ConvertTo-SshEscapedString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowEmptyString()]
        [string]$Value
    )
    # 对每个单引号进行转义: ' -> '\''
    return "'" + ($Value -replace "'", "'\''") + "'"
}

function Invoke-SshCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
                # 验证主机名只能包含字母、数字、点、短横线和下划线
                # 拒绝空格、管道符、与号、分号、反引号、括号、花括号、引号等 shell 特殊字符
                if ($_ -match '[\s|&;`$(){}<>#@!*?\[\]~"]') {
                    throw "主机名包含非法字符，仅允许字母、数字、点、短横线和下划线"
                }
                return $true
            })]
        [string]$HostName,

        # 远程命令字符串（可选，不提供则直接 SSH 登录）
        [Parameter(Mandatory = $false, Position = 1)]
        [string]$RemoteCommand,

        # 是否为交互式连接（分配 PTY），用于 tmux attach/new-session 等需要终端交互的场景
        [switch]$Interactive,

        # 捕获标准输出，用于获取远程命令执行结果
        [switch]$CaptureOutput,

        # SSH 连接超时（秒）
        [int]$ConnectTimeout = 5,

        # 跳过 SSH 主机密钥检查（仅在信任网络中使用，默认关闭）
        [switch]$SkipHostKeyCheck,

        # PassThru: 在 CaptureOutput 模式下，返回包含 Output 和 ExitCode 的对象
        # 调用方可通过 ExitCode 判断远程命令是否执行成功
        [switch]$PassThru
    )

    # 构建 SSH 参数列表
    $sshArgs = New-Object System.Collections.ArrayList

    # 基础连接参数
    [void]$sshArgs.Add("-o")
    [void]$sshArgs.Add("ConnectTimeout=$ConnectTimeout")

    # 仅在显式启用时才跳过主机密钥检查（默认关闭，更安全）
    if ($SkipHostKeyCheck) {
        [void]$sshArgs.Add("-o")
        [void]$sshArgs.Add("StrictHostKeyChecking=no")
        [void]$sshArgs.Add("-o")
        [void]$sshArgs.Add("UserKnownHostsFile=NUL")
    }

    # 如果是交互式连接，分配 PTY（-t 标志）
    if ($Interactive) {
        [void]$sshArgs.Add("-t")
    }

    # 主机名作为独立参数传递（不会被 shell 解释）
    [void]$sshArgs.Add($HostName)

    # 如果提供了远程命令，则附加到参数列表
    # 注意：此字符串将传递到远程主机的 /bin/sh -c 执行
    # 调用方需自行转义用户提供的变量值（使用 ConvertTo-SshEscapedString）
    if ($PSBoundParameters.ContainsKey('RemoteCommand')) {
        [void]$sshArgs.Add($RemoteCommand)
    }

    if ($CaptureOutput) {
        # 捕获输出模式：重定向标准输出到临时文件
        $tempFile = [System.IO.Path]::GetTempFileName()
        try {
            # 启动 ssh.exe 进程，捕获 stdout
            $process = Start-Process -FilePath "ssh.exe" -ArgumentList $sshArgs.ToArray() -NoNewWindow -Wait -RedirectStandardOutput $tempFile -PassThru

            # 读取输出内容（Get-Content -Raw 已返回纯文本字符串）
            $output = Get-Content $tempFile -Raw

            # 如果启用了 -PassThru，返回包含 Output 和 ExitCode 的对象
            if ($PassThru) {
                return [PSCustomObject]@{
                    Output   = $output
                    ExitCode = $process.ExitCode
                }
            }

            # 兼容旧调用方式：直接返回输出字符串
            return $output
        } finally {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
    } else {
        # 非捕获模式：直接运行，输出显示在终端
        # 交互式 SSH 返回后必须重置终端状态（鼠标追踪、备选屏幕缓冲区等）
        if ($PassThru) {
            $process = Start-Process -FilePath "ssh.exe" -ArgumentList $sshArgs.ToArray() -NoNewWindow -Wait -PassThru
            Reset-TerminalMode
            return [PSCustomObject]@{
                Output   = ""
                ExitCode = $process.ExitCode
            }
        }
        Start-Process -FilePath "ssh.exe" -ArgumentList $sshArgs.ToArray() -NoNewWindow -Wait
        # SSH 进程结束后重置终端状态
        Reset-TerminalMode
    }
}
