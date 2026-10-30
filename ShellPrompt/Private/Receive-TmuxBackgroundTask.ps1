# Receive-TmuxBackgroundTask.ps1 - 后台线程任务的收割端
# 职责: 等待任务完成并把结果/失败原因归一成统一形状。
#
# 契约: 本函数**消费**任务(无论成功失败都会 Remove-Job), 因此每个任务只能收割一次。
#   - Succeeded    : 任务是否正常跑完
#   - Result       : 脚本块的返回值(失败时为 $null)
#   - ErrorMessage : 失败原因(超时 / 作业内异常)
#   - TimedOut     : 是否因等待超时被放弃

function Receive-TmuxBackgroundTask {
    <#
    .SYNOPSIS
        等待后台任务完成并返回归一化结果。

    .DESCRIPTION
        等待 -TimeoutSeconds 秒; 超时则放弃并清理作业(TimedOut=$true)。
        作业内抛出的异常通过 Receive-Job 的错误变量捕获, 转成 ErrorMessage,
        绝不向调用方冒泡(后台失败必须能被上层降级, 而不是打断界面)。

    .PARAMETER Task
        任务句柄(Submit-TmuxBackgroundTask 的返回值); 也接受裸作业对象。为 $null 时直接返回失败结果

    .PARAMETER TimeoutSeconds
        最长等待秒数, 默认 30。传 0 表示"只收割已完成的任务", 未完成则按未就绪处理。

    .OUTPUTS
        PSCustomObject(.Succeeded/.Result/.ErrorMessage/.TimedOut)

    .EXAMPLE
        $r = Receive-TmuxBackgroundTask -Task $task -TimeoutSeconds 20
        if ($r.Succeeded) { $r.Result }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Task,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 600)]
        [int]$TimeoutSeconds = 30
    )

    if ($null -eq $Task) {
        return [PSCustomObject]@{
            Succeeded    = $false
            Result       = $null
            ErrorMessage = '后台任务未启动'
            TimedOut     = $false
        }
    }

    # 句柄可能是 Submit-TmuxBackgroundTask 的包装对象(.Task), 也可能是裸作业对象
    $job = $Task
    if ($Task.PSObject.Properties['Task']) {
        $job = $Task.Task
    }
    if ($null -eq $job) {
        return [PSCustomObject]@{
            Succeeded    = $false
            Result       = $null
            ErrorMessage = '后台任务句柄无效'
            TimedOut     = $false
        }
    }

    $completed = $null
    try {
        $completed = Wait-Job -Job $job -Timeout $TimeoutSeconds
    } catch {
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        return [PSCustomObject]@{
            Succeeded    = $false
            Result       = $null
            ErrorMessage = "等待后台任务失败: $($_.Exception.Message)"
            TimedOut     = $false
        }
    }

    if ($null -eq $completed) {
        # 超时(或 TimeoutSeconds=0 且任务未完成): 放弃该任务
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        return [PSCustomObject]@{
            Succeeded    = $false
            Result       = $null
            ErrorMessage = "后台任务未在 ${TimeoutSeconds}s 内完成"
            TimedOut     = $true
        }
    }

    $jobError = $null
    $output = Receive-Job -Job $job -ErrorAction SilentlyContinue -ErrorVariable jobError
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue

    if ($jobError -and @($jobError).Count -gt 0) {
        $first = @($jobError)[0]
        $message = if ($first.Exception) { $first.Exception.Message } else { [string]$first }
        return [PSCustomObject]@{
            Succeeded    = $false
            Result       = $null
            ErrorMessage = $message
            TimedOut     = $false
        }
    }

    return [PSCustomObject]@{
        Succeeded    = $true
        Result       = $output
        ErrorMessage = ''
        TimedOut     = $false
    }
}
