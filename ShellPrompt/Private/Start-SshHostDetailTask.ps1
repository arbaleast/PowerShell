# Start-SshHostDetailTask.ps1 - 远端详情探测的**后台任务**封装(提交端 + 非阻塞收割端)
#
# 背景 (2026-10-31 sss 仪表盘重构):
#   右侧详情卡片的数据要经过网络(单次 SSH 往返)。UI 线程一旦直接调用
#   Get-SshHostDetail, 键盘事件就会被网络阻塞(等待窗口可达 TimeoutSec+10 秒),
#   "上下移动选中立即响应" 的验收线直接失守。
#
# 职责划分(与既有 Submit/Receive-TmuxBackgroundTask 同一套模式):
#   - Start-SshHostDetailTask   : 把一次探测丢到**线程作业**(同进程 runspace, ~50ms 启动),
#                                 立即返回任务句柄; 不触碰任何 UI 状态;
#   - Receive-SshHostDetailTask : **非阻塞**收割 —— 作业未完成返回 $null(绝不 Wait),
#                                 完成/失败归一成与 Get-SshHostDetail 完全相同的字段形状。
#
# 两个函数都不写全局变量、不操作 UI, 由编排层(Invoke-SshHostDashboard)驱动:
#   每轮 UI tick 调用 Receive-SshHostDetailTask, 用**请求标识**(RequestId)丢弃
#   "旧主机迟到的结果", 防止旧请求覆盖新选中的详情。
#
# 依赖解析: 线程作业是独立 runspace, 拿不到模块作用域, 因此必须把要 dot-source 的
# Private 文件列进依赖表 —— 这里直接复用 Submit-TmuxBackgroundTask(它已实现
# "-DependencyFile -> InitializationScript" 的解析与缺失即抛错), 不重复造一套。

function Start-SshHostDetailTask {
    <#
    .SYNOPSIS
        在后台线程提交一次主机详情探测, 立即返回任务句柄。

    .DESCRIPTION
        用 Submit-TmuxBackgroundTask(Start-ThreadJob)把 Get-SshHostDetail 丢到后台,
        因此**不阻塞调用方**(UI 线程可以继续处理按键)。

        返回句柄里的 RequestId 由调用方给出并原样带回: 编排层用它做"旧结果丢弃"的
        唯一凭据 —— 只有与当前选中主机一致的 RequestId 才允许写入详情卡片。

        提交失败(模块私有目录未初始化 / 依赖文件缺失)抛终止错误, 不静默降级:
        调用方应捕获并让卡片显示"详情加载失败", 而不是假装加载中。

    .PARAMETER HostName
        目标主机名(与 Get-SshHostDetail -HostName 相同)。

    .PARAMETER RequestId
        调用方生成的请求标识(约定用主机名 + 序号, 如 'deb#3'), 只做载荷透传。

    .PARAMETER Port
        SSH 端口; 0 = 不覆盖(沿用 ssh config)。

    .PARAMETER User
        登录用户; 空 = 不覆盖(沿用 ssh config)。

    .PARAMETER TimeoutSec
        连接/等待超时(秒), 默认 6。

    .PARAMETER ProbeScript
        测试注入点(仅测试用): 透传给后台作业里的 Get-SshHostDetail -ProbeScript,
        从而完全不触网。生产路径不传。

    .OUTPUTS
        PSCustomObject(.Task/.RequestId/.HostName/.StartedAt)

    .EXAMPLE
        $job = Start-SshHostDetailTask -HostName 'deb' -RequestId 'deb#1'
        # 之后每轮 UI tick: $detail = Receive-SshHostDetailTask -Task $job

    .EXAMPLE
        $job = Start-SshHostDetailTask -HostName 'deb' -RequestId 'deb#1' -ProbeScript { param($a) [PSCustomObject]@{ Output = 'HOSTNAME=deb'; Error = ''; ExitCode = 0; TimedOut = $false } }
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RequestId,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 65535)]
        [int]$Port = 0,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$User = '',

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 120)]
        [int]$TimeoutSec = 6,

        [Parameter(Mandatory = $false)]
        [scriptblock]$ProbeScript
    )

    # 与 Get-SshHostDetail 同一道入参护栏: 非法主机名在这里就失败, 不进作业队列
    if (-not (Test-SshHostName -HostName $HostName)) {
        throw "非法主机名: '$HostName'。仅允许字母、数字、点、短横线和下划线, 且不得以 '-' 开头。"
    }

    if (-not $PSCmdlet.ShouldProcess($HostName, 'Start SSH host detail probe in background')) {
        return $null
    }

    # 作业脚本块: 第一个位置参数接收 -Argument 哈希表(Submit-TmuxBackgroundTask 契约)
    $jobScript = {
        param($a)
        Get-SshHostDetail -HostName $a.HostName -Port $a.Port -User $a.User `
            -TimeoutSec $a.TimeoutSec -ProbeScript $a.ProbeScript
    }

    # 依赖表: 作业 runspace 里要能解析 Get-SshHostDetail 的全部调用链
    #   Get-SshHostDetail -> Get-SshArgs / Invoke-SshCaptureOutput / Test-SshHostName
    #   Get-SshArgs       -> Test-SshHostName
    #   Invoke-SshCaptureOutput -> ConvertTo-SshArgumentLine
    $dependencyFiles = @(
        'Test-SshHostName.ps1'
        'ConvertTo-SshArgumentLine.ps1'
        'Invoke-SshCaptureOutput.ps1'
        'Get-SshArgs.ps1'
        'Get-SshHostDetail.ps1'
    )

    $handle = Submit-TmuxBackgroundTask -ScriptBlock $jobScript -DependencyFile $dependencyFiles `
        -Argument @{
        HostName    = $HostName
        Port        = $Port
        User        = $User
        TimeoutSec  = $TimeoutSec
        ProbeScript = $ProbeScript
    } -Name "ssh-host-detail:$RequestId"

    return [PSCustomObject]@{
        Task      = $handle.Task
        RequestId = $RequestId
        HostName  = $HostName
        StartedAt = Get-Date
    }
}

function Receive-SshHostDetailTask {
    <#
    .SYNOPSIS
        非阻塞收割主机详情后台任务; 未完成返回 $null。

    .DESCRIPTION
        **绝不调用 Wait-Job**: 只看作业状态(Completed / Failed / Stopped)就立刻返回,
        保证 UI 线程每帧调用也不会卡顿。

        归一化契约(与 Get-SshHostDetail 的返回字段完全一致, 调用方无需分支):
          - Completed 且有结果   -> 原样返回该详情对象;
          - Completed 但无结果   -> Status='Unknown', ErrorCode='E_UNKNOWN';
          - Failed / Stopped     -> Status='Unknown', ErrorCode='E_UNKNOWN', ErrorMessage 带原因。
        无论哪种终态, 作业都会在这里被 Remove-Job 清理(每个任务只收割一次)。

    .PARAMETER Task
        Start-SshHostDetailTask 的返回值(也接受裸作业对象); $null 时返回 $null。

    .OUTPUTS
        PSCustomObject(详情结果) 或 $null(作业尚未结束)

    .EXAMPLE
        $detail = Receive-SshHostDetailTask -Task $job
        if ($null -ne $detail) { $detail.Status }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Task
    )

    if ($null -eq $Task) { return $null }

    # 句柄既可能是 Start-SshHostDetailTask 的包装对象(.Task), 也可能是裸作业对象
    $job = $Task
    if ($null -ne $Task.PSObject.Properties['Task']) { $job = $Task.Task }
    if ($null -eq $job) { return $null }

    $hostName = ''
    if ($null -ne $Task.PSObject.Properties['HostName']) { $hostName = [string]$Task.HostName }

    # 只看状态, 不等: 未到终态一律按"还在跑"返回 $null
    $state = [string]$job.State
    if ($state -notin @('Completed', 'Failed', 'Stopped')) { return $null }

    try {
        $jobError = $null
        $output = @(Receive-Job -Job $job -ErrorAction SilentlyContinue -ErrorVariable jobError)

        if ($state -ne 'Completed') {
            $reason = '后台探测作业未正常完成'
            if ($jobError -and @($jobError).Count -gt 0) {
                $first = @($jobError)[0]
                $reason = if ($first.Exception) { $first.Exception.Message } else { [string]$first }
            }
            return ConvertTo-SshHostDetailResult -HostName $hostName -Status 'Unknown' `
                -ErrorCode 'E_UNKNOWN' -ErrorMessage "详情探测失败($state): $reason"
        }

        if ($jobError -and @($jobError).Count -gt 0) {
            $first = @($jobError)[0]
            $message = if ($first.Exception) { $first.Exception.Message } else { [string]$first }
            return ConvertTo-SshHostDetailResult -HostName $hostName -Status 'Unknown' `
                -ErrorCode 'E_UNKNOWN' -ErrorMessage "详情探测失败: $message"
        }

        # 作业可能夹杂 Write-Verbose/警告等输出: 只认最后一个带 Status 字段的对象
        $detail = $null
        foreach ($item in $output) {
            if ($null -ne $item -and $null -ne $item.PSObject.Properties['Status']) {
                $detail = $item
            }
        }
        if ($null -eq $detail) {
            return ConvertTo-SshHostDetailResult -HostName $hostName -Status 'Unknown' `
                -ErrorCode 'E_UNKNOWN' -ErrorMessage '详情探测作业没有返回结果'
        }
        return $detail
    }
    finally {
        # 消费即清理: 线程作业持有 runspace, 不释放会随交互次数累积
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }
}
