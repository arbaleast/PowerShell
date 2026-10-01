# Invoke-SshCaptureOutput.ps1 - 通过 .NET Process 执行 SSH 并捕获标准输出
# 三个关键设计:
# - Close stdin 后立即 EOF
# - 并行读 stdout/stderr 避免死锁
# - WaitForExit 带超时 + Kill 兑底, 保证 ssh 卡死时上层不被拖死

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
        返回包含 Output、Error 和 ExitCode 的对象而非纯文本

    .EXAMPLE
        $result = Invoke-SshCaptureOutput -ArgumentList $args -ConnectTimeout 5 -PassThru
    #>
    [CmdletBinding()]
    [OutputType([string])]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '')]
param(
        [Parameter(Mandatory = $true)]
        [array]$ArgumentList,

        [Parameter(Mandatory = $false)]
        [int]$ConnectTimeout = 5,

        [Parameter(Mandatory = $false)]
        [switch]$PassThru
    )

    # 手动按 CommandLineToArgvW 规则引号包裹每个参数
    # (WinPS 5.1 跑 .NET Framework 4.x, 没有 ArgumentList 集合)
    $escaped = $ArgumentList | ForEach-Object {
        $a = [string]$_
        if ($a -match '\s|"') {
            # 含空格或双引号 → 用双引号包裹, 内部双引号转义为 `\"`
            '"' + ($a -replace '\\', '\\' -replace '"', '\"') + '"'
        } else {
            $a
        }
    }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'ssh.exe'
    $psi.Arguments = $escaped -join ' '
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)

    # 关闭 stdin 后立即 EOF
    $proc.StandardInput.Close()

    # 并行读 stdout/stderr 避免死锁
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()

    $safeConnect = [Math]::Max($ConnectTimeout, 1)
    $waitMs = $safeConnect * 1000 + 10000
    if (-not $proc.WaitForExit($waitMs)) {
        try { $proc.Kill() } catch { }
        $proc.WaitForExit(2000) | Out-Null
    }

    # 进程退出后等待读任务完成, 防止丢尾部输出
    $drainMs = 2000
    if (-not $outTask.Wait($drainMs)) { $outTask = $null }
    if (-not $errTask.Wait($drainMs)) { $errTask = $null }
    $output = if ($outTask) { $outTask.Result } else { '' }
    $errOut = if ($errTask) { $errTask.Result } else { '' }

    # 解码 Windows 中文版 ssh.exe 中文错误消息里的八进制转义
    if ($errOut -match '\\(\d{3})') {
        $errOut = [regex]::Replace($errOut, '\\(\d{3})', {
            param($m) [char][Convert]::ToByte($m.Groups[1].Value, 8)
        })
    }

    $exitCode = $proc.ExitCode
    $proc.Dispose()

    # stderr 有内容则写入 PowerShell 错误流, 避免静默丢弃
    if (-not [string]::IsNullOrEmpty($errOut)) {
        [Console]::Error.WriteLine($errOut)
    }

    if ($PassThru) {
        return [PSCustomObject]@{
            Output   = $output
            Error    = $errOut
            ExitCode = $exitCode
        }
    }

    # 兼容旧调用方式：直接返回输出字符串
    return $output
}
