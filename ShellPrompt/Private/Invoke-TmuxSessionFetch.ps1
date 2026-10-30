# Invoke-TmuxSessionFetch.ps1 - 远程 tmux 会话列表的**异步**获取(数据层入口)
# 职责: 在后台线程完成一次 SSH 探测, 把结果交给上层; 后台不可用时退回同步路径。
#
# 异步的意义(2026-10-30 TUI 重构):
#   旧流程在渲染主视图之前**串行**做了两次网络往返:
#     1) Get-TmuxAvailability (入口探测)  2) Get-TmuxSessions (列表探测)
#   加上标题区的 wttr.in 天气, 首屏最多要等 3 次网络往返。
#   现在:
#     - 入口探测被去掉(列表探测本身就带 Available/Version, 不需要额外一次 SSH);
#     - 列表探测与天气预取都放到后台线程并行进行, 主线程只收割结果。
#
# 降级契约: 后台任务提交失败 / 作业异常 / 超时, 一律退回同步调用 Get-TmuxSessions,
#   **不**把失败折叠成"没有会话" —— 错误码由 Get-TmuxSessionState 统一判定。

function Invoke-TmuxSessionFetch {
    <#
    .SYNOPSIS
        异步获取远程 tmux 会话列表(后台线程 + 同步兜底)。

    .DESCRIPTION
        正常路径: 提交后台任务(线程作业) -> 等待 -> 返回 Get-TmuxSessions 的原始返回值。
        降级路径: 后台任务提交失败、作业内异常或等待超时 -> 退回同步 Get-TmuxSessions。

        返回值与 Get-TmuxSessions 完全一致(hashtable: Sessions/Available/Version/Error/
        ExitCode/NetworkError/TimedOut), 因此上层无需区分数据来自哪条路径。

    .PARAMETER HostName
        远程主机名

    .PARAMETER TimeoutSeconds
        等待后台任务的最长秒数, 默认 30

    .PARAMETER NoSpinner
        不显示 Spectre 进度动画(测试或调用方自行控制输出时使用)

    .OUTPUTS
        [hashtable] Get-TmuxSessions 的原始返回值

    .EXAMPLE
        $raw = Invoke-TmuxSessionFetch -HostName 'debian'
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 600)]
        [int]$TimeoutSeconds = 30,

        [Parameter(Mandatory = $false)]
        [switch]$NoSpinner
    )

    # 依赖闭包: Get-TmuxSessions 的调用链(线程作业是独立 runspace, 拿不到模块私有函数)
    $dependencies = @(
        'Get-TmuxSessions.ps1'
        'Invoke-SshCommand.ps1'
        'Get-SshArgs.ps1'
        'Invoke-SshCaptureOutput.ps1'
        'ConvertTo-SshArgumentLine.ps1'
        'Test-SshHostName.ps1'
    )

    $task = $null
    try {
        $task = Submit-TmuxBackgroundTask -ScriptBlock {
                param($argument)
                Get-TmuxSessions -HostName $argument.HostName -Force
            } -Argument @{ HostName = $HostName } -DependencyFile $dependencies
    } catch {
        Write-Verbose "[Invoke-TmuxSessionFetch] 后台任务提交失败, 退回同步探测: $($_.Exception.Message)"
        $task = $null
    }

    if ($null -ne $task) {
        $received = if ($NoSpinner) {
            Receive-TmuxBackgroundTask -Task $task -TimeoutSeconds $TimeoutSeconds
        } else {
            Invoke-WithProgress -Message '获取远程 tmux 会话' -ScriptBlock {
                Receive-TmuxBackgroundTask -Task $task -TimeoutSeconds $TimeoutSeconds
            }
        }

        if ($received.Succeeded -and $null -ne $received.Result) {
            return $received.Result
        }
        Write-Verbose "[Invoke-TmuxSessionFetch] 后台探测未成功($($received.ErrorMessage)), 退回同步探测"
    }

    # 同步兜底: 保证后台路径不可用时功能不缺失
    if ($NoSpinner) {
        return Get-TmuxSessions -HostName $HostName -Force
    }
    return Invoke-WithProgress -Message '获取远程 tmux 会话' -ScriptBlock {
        Get-TmuxSessions -HostName $HostName -Force
    }
}
