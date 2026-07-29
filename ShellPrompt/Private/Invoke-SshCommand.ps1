# Invoke-SshCommand.ps1 - SSH 远程命令执行辅助
# 防止命令注入: 主机名校验 + 调用方自行转义用户变量。
# 非捕获模式下, 通过 Save-OriginalTerminalState 保存状态, finally 调用 Reset-TerminalMode 统一恢复。

function Invoke-SshCommand {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
                # 验证主机名只能包含字母、数字、点、短横线和下划线
                if (-not (Test-SshHostName -HostName $_)) {
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
        [switch]$PassThru
    )

    # 委托 Get-SshArgs 构建 SSH 参数列表
    $sshArgs = Get-SshArgs -HostName $HostName -RemoteCommand $RemoteCommand `
        -Interactive:$Interactive -ConnectTimeout $ConnectTimeout `
        -SkipHostKeyCheck:$SkipHostKeyCheck -CaptureOutput:$CaptureOutput

    if ($CaptureOutput) {
        # 捕获输出路径: 委托 Invoke-SshCaptureOutput
        return Invoke-SshCaptureOutput -ArgumentList $sshArgs -ConnectTimeout $ConnectTimeout -PassThru:$PassThru
    }

    # 非捕获路径: 直接运行，输出显示在终端
    Save-OriginalTerminalState
    try {
        if ($PassThru) {
            $process = Start-Process -FilePath 'ssh.exe' -ArgumentList $sshArgs.ToArray() -NoNewWindow -Wait -PassThru
            return [PSCustomObject]@{
                Output   = ''
                Error    = ''
                ExitCode = $process.ExitCode
            }
        }
        Start-Process -FilePath 'ssh.exe' -ArgumentList $sshArgs.ToArray() -NoNewWindow -Wait
    } finally {
        # 无论 Interactive 与否都需恢复: 非交互式也修改了 OutputEncoding/TERM
        Reset-TerminalMode
    }
}
