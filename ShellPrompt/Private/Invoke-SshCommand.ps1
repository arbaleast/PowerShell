# Invoke-SshCommand.ps1 - SSH 远程命令执行辅助
# 防止命令注入: 主机名校验 + 调用方自行转义用户变量。
# 非捕获模式下,try 顶部将原始 OutputEncoding / InputEncoding / TERM
# 写入 $script:Original*,finally 调用 Reset-TerminalMode 统一恢复。

. "$PSScriptRoot\Reset-TerminalMode.ps1"

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
    # 调用方需自行用单引号包裹并转义内部单引号（`'` -> `'\''`）
    if ($PSBoundParameters.ContainsKey('RemoteCommand')) {
        [void]$sshArgs.Add($RemoteCommand)
    }

    if ($CaptureOutput) {
        # .NET Process 手动按 CommandLineToArgvW 规则引号包裹每个参数
        # (WinPS 5.1 跑 .NET Framework 4.x,没有 ArgumentList 集合)
        # 三个关键点: Close stdin 后立即 EOF、并行读 stdout/stderr 避免死锁、
        #            WaitForExit 带超时 + Kill 兑底,保证 ssh 卡死时上层不被拖死。
        $escaped = $sshArgs.ToArray() | ForEach-Object {
            $a = [string]$_
            if ($a -match '\s|"') {
                # 含空格或双引号 → 用双引号包裹,内部双引号转义为 `\"`
                '"' + ($a -replace '\\', '\\' -replace '"', '\"') + '"'
            } else {
                $a
            }
        }
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = "ssh.exe"
        $psi.Arguments = $escaped -join ' '
        $psi.UseShellExecute = $false
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $proc = [System.Diagnostics.Process]::Start($psi)

        $proc.StandardInput.Close()
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()

        $safeConnect = [Math]::Max($ConnectTimeout, 1)
        $waitMs = $safeConnect * 1000 + 10000
        if (-not $proc.WaitForExit($waitMs)) {
            try { $proc.Kill() } catch { }
            $proc.WaitForExit(2000) | Out-Null
        }

        # 进程退出后等待读任务完成,防止丢尾部输出
        $drainMs = 2000
        if (-not $outTask.Wait($drainMs)) { $outTask = $null }
        if (-not $errTask.Wait($drainMs)) { $errTask = $null }
        $output = if ($outTask) { $outTask.Result } else { '' }
        $errOut = if ($errTask) { $errTask.Result } else { '' }

        # 解码 Windows 中文版 ssh.exe 中文错误消息里的八进制转义(例如 \344\270\215...)
        # 否则终端上会看到一串 \xxx 而不是"不能解析指定的主机名。"
        if ($errOut -match '\\(\d{3})') {
            $errOut = [regex]::Replace($errOut, '\\(\d{3})', {
                param($m) [char][Convert]::ToByte($m.Groups[1].Value, 8)
            })
        }

        $exitCode = $proc.ExitCode
        $proc.Dispose()

        # stderr 有内容则写入 PowerShell 错误流,避免静默丢弃(ssh 鉴权失败、
        # 主机不可达等诊断信息会出现在这里)
        if (-not [string]::IsNullOrEmpty($errOut)) {
            [Console]::Error.WriteLine($errOut)
        }

        # 如果启用了 -PassThru，返回包含 Output、Error 和 ExitCode 的对象
        if ($PassThru) {
            return [PSCustomObject]@{
                Output   = $output
                Error    = $errOut
                ExitCode = $exitCode
            }
        }

        # 兼容旧调用方式：直接返回输出字符串
        return $output
    } else {
        # 非捕获模式：直接运行，输出显示在终端

        # 保存原始控制台状态到 $script:Original*,Reset-TerminalMode finally 统一恢复
        $script:OriginalOutputEncoding = [System.Console]::OutputEncoding
        $script:OriginalInputEncoding = [System.Console]::InputEncoding
        $script:OriginalTerm           = $env:TERM

        try {
            [System.Console]::OutputEncoding = [System.Text.Encoding]::UTF8
            [System.Console]::InputEncoding = [System.Text.Encoding]::UTF8

            # 设置终端类型，确保远程 tmux 正确渲染 Unicode 方块字符
            # Windows SSH 客户端不发送 TERM，远程 $TERM 为空导致 tmux 渲染失败
            $env:TERM = "xterm-256color"

            if ($PassThru) {
                $process = Start-Process -FilePath "ssh.exe" -ArgumentList $sshArgs.ToArray() -NoNewWindow -Wait -PassThru
                return [PSCustomObject]@{
                    Output   = ""
                    Error    = ""
                    ExitCode = $process.ExitCode
                }
            }
            Start-Process -FilePath "ssh.exe" -ArgumentList $sshArgs.ToArray() -NoNewWindow -Wait
        } finally {
            # 无论 Interactive 与否都需恢复: 非交互式也修改了 OutputEncoding/TERM
            Reset-TerminalMode
        }
    }
}
