# Invoke-SshCaptureOutput.ps1 - 通过 .NET Process 执行 SSH 并捕获标准输出
# 三个关键设计:
# - Close stdin 后立即 EOF
# - 并行读 stdout/stderr 避免死锁
# - WaitForExit 带超时 + Kill 兜底, 保证 ssh 卡死时上层不被拖死
# 2026-10-29 SSH 可靠性审计修复:
# - 命令行拼接委托共享纯函数 ConvertTo-SshArgumentLine (算法逐字节不变, 与非捕获路径复用)
# - 启动失败 (ssh.exe 缺失/无法启动) 显式抛出含 ssh.exe 的异常, 与"远端命令失败"区分
# - 超时后 ExitCode 固定回填 -1 并置 TimedOut=$true, 不再沿用 Kill 后的信号退出码
#   (实测 Kill 后为 137, 会与远端"被信号杀死 128+N"的合法退出码撞车, 调用方无法区分)
# - 读 ExitCode 前用 HasExited 守卫; $proc.Dispose() 移入 finally, 异常路径不再泄漏进程句柄
# - stdout/stderr 读任务故障 (Wait/Result 抛 AggregateException) 降级为"读失败", 不再冒泡

function Invoke-SshCaptureOutput {
    <#
    .SYNOPSIS
        通过 .NET Process 执行 SSH 命令并捕获标准输出

    .DESCRIPTION
        以非交互方式 (BatchMode=yes) 执行 SSH 命令并捕获标准输出和标准错误。
        使用 .NET Process 而非 Start-Process 以实现精细的 I/O 重定向。
        适用于探测远程主机状态（如 tmux 可用性）等需要解析返回值的场景。

    .PARAMETER ArgumentList
        SSH 参数数组（由 Get-SshArgs 构建）

    .PARAMETER ConnectTimeout
        连接超时（秒），用于计算等待时间

    .PARAMETER PassThru
        返回包含 Output、Error、ExitCode 和 TimedOut 的对象而非纯文本;
        TimedOut=$true 表示等待超时后 Kill 了 ssh 进程 (此时 ExitCode 固定为 -1),
        正常退出时 ExitCode 为 ssh 的真实退出码 (0-255)。

    .EXAMPLE
        $result = Invoke-SshCaptureOutput -ArgumentList $args -ConnectTimeout 5 -PassThru
    #>
    [CmdletBinding()]
    [OutputType([string])]
param(
        [Parameter(Mandatory = $true)]
        [array]$ArgumentList,

        [Parameter(Mandatory = $false)]
        [int]$ConnectTimeout = 5,

        [Parameter(Mandatory = $false)]
        [switch]$PassThru
    )

    # 委托共享纯函数按 CommandLineToArgvW 规则拼命令行
    # (2026-10-29 从内联代码抽出, 算法逐字节不变; 与 Invoke-SshCommand 非捕获路径共用)
    $argumentLine = ConvertTo-SshArgumentLine -Argument $ArgumentList

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'ssh.exe'
    $psi.Arguments = $argumentLine
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    # 启动失败 (ssh.exe 缺失/无权限) 必须与"远端命令失败"区分:
    # 抛出可操作异常 (消息含 ssh.exe), 由调用方降级处理 (Invoke-TmuxProbe 会转成 ExitCode=-1)。
    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
    } catch {
        throw "启动 ssh.exe 失败 (进程未能创建, 与远端命令失败无关): $($_.Exception.Message)"
    }

    # 返回契约 (2026-10-29, 内部扩展): TimedOut=超时后被 Kill;
    # ExitCode 正常退出=ssh 真实退出码, 超时/读不到=-1 (不用 Kill 后的信号码, 避免与远端 128+N 撞车)
    $timedOut = $false
    $readNotes = [System.Collections.Generic.List[string]]::new()
    $exitCode = -1
    $output = ''
    $errOut = ''
    try {
        # 关闭 stdin 后立即 EOF
        $proc.StandardInput.Close()

        # 并行读 stdout/stderr 避免死锁
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()

        $safeConnect = [Math]::Max($ConnectTimeout, 1)
        $waitMs = $safeConnect * 1000 + 10000
        if (-not $proc.WaitForExit($waitMs)) {
            $timedOut = $true
            # Kill 整棵进程树 (2026-10-29): 只 Kill 父进程时, 残留子进程会继续持有 stdout/stderr
            # 管道, 把下方 drain 拖满 2+2 秒且最终拿不到任何输出; 实测 Kill($true) 后管道立即 EOF。
            # Kill 失败 (进程已自行退出/权限不足)不致命: 由下方 HasExited 守卫兜底。
            try { $proc.Kill($true) } catch { }
            $proc.WaitForExit(2000) | Out-Null
        }

        # 进程退出后等待读任务完成, 防止丢尾部输出
        # 2026-10-29: 读任务故障时 Wait/Result 会抛 AggregateException —— 捕获后按"读失败"
        # 契约降级 (记入读失败说明, 不冒泡, 也不跳过下方 finally 的 Dispose)。
        # drain 超时 (任务仍在运行) 维持既有行为: 丢弃引用, 对应输出置空。
        $drainMs = 2000
        $outDone = $false
        $errDone = $false
        try { $outDone = $outTask.Wait($drainMs) } catch {
            $readNotes.Add("stdout 读取失败: $($_.Exception.GetBaseException().Message)")
        }
        if ($outDone) {
            try { $output = $outTask.Result } catch {
                $readNotes.Add("stdout 读取失败: $($_.Exception.GetBaseException().Message)")
            }
        }
        try { $errDone = $errTask.Wait($drainMs) } catch {
            $readNotes.Add("stderr 读取失败: $($_.Exception.GetBaseException().Message)")
        }
        if ($errDone) {
            try { $errOut = $errTask.Result } catch {
                $readNotes.Add("stderr 读取失败: $($_.Exception.GetBaseException().Message)")
            }
        }

        # 解码 Windows 中文版 ssh.exe 中文错误消息里的八进制转义
        if ($errOut -match '\\(\d{3})') {
            $errOut = [regex]::Replace($errOut, '\\(\d{3})', {
                param($m) [char][Convert]::ToByte($m.Groups[1].Value, 8)
            })
        }

        # HasExited 守卫: 进程仍存活时读 ExitCode 会抛 InvalidOperationException
        # (Windows 文档行为; Linux 实测返回 $null) —— 统一回填 -1。
        # 超时路径直接保留 -1, 不读 Kill 后的信号退出码。
        if (-not $timedOut -and $proc.HasExited) {
            try { $exitCode = $proc.ExitCode } catch { $exitCode = -1 }
        }
    } finally {
        # 2026-10-29: 无论读任务/ExitCode 读取是否抛异常, 进程句柄都必须释放 (原实现会跳过)
        $proc.Dispose()
    }

    # 读失败说明并入 Error 字段 (契约: 读失败不抛异常, 由调用方从 Error 可见)
    if ($readNotes.Count -gt 0) {
        $note = ($readNotes -join '; ')
        $errOut = if ([string]::IsNullOrEmpty($errOut)) { $note } else { "$errOut`n$note" }
    }

    # stderr 有内容则写入 PowerShell 错误流, 避免静默丢弃
    if (-not [string]::IsNullOrEmpty($errOut)) {
        [Console]::Error.WriteLine($errOut)
    }

    if ($PassThru) {
        return [PSCustomObject]@{
            Output   = $output
            Error    = $errOut
            ExitCode = $exitCode
            TimedOut = $timedOut
        }
    }

    # 兼容旧调用方式：直接返回输出字符串
    return $output
}
