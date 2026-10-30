# Submit-WttrPrefetch.ps1 / Receive-WttrPrefetch.ps1
#   标题区天气的**后台预取**(异步非阻塞)
#
# 职责:
#   Submit-WttrPrefetch  - 在后台线程抓一次 wttr.in 原始响应, 句柄挂在 $script:_WttrPrefetchTask;
#   Receive-WttrPrefetch - 收割已完成的预取结果并写回模块缓存($script:_WttrCache),
#                          让 Get-WttrTitleSuffix 的同步路径直接命中缓存, 不再发 HTTP。
#
# 为什么(2026-10-30 TUI 重构):
#   标题区天气是在**拼标题之前**同步取的, 冷缓存下要等一次 HTTP(超时 5s),
#   首屏因此被网络卡住。预取把它挪到后台, 与 SSH 探测并行, 渲染不再等网络。
#
# 语义:
#   - 预取只写"成功且非空"的响应(与 Get-WttrWeather 的缓存策略一致, 不缓存故障空串);
#   - 预取未完成时不阻塞: Receive-WttrPrefetch 直接返回 $false, 标题区按"无天气"渲染;
#   - 预取失败(网络不通)同样返回 $false, 静默降级。

$script:_WttrPrefetchTask = $null

function Submit-WttrPrefetch {
    <#
    .SYNOPSIS
        在后台线程预取标题区天气(wttr.in 原始响应)。

    .DESCRIPTION
        提交一个线程作业抓取 wttr.in 的 j1 响应, 句柄存入 $script:_WttrPrefetchTask。
        天气功能关闭时不提交, 直接返回 $null。

    .PARAMETER CacheMinutes
        缓存有效期(分钟), 默认 10(与 Get-WttrWeather 的默认一致)

    .OUTPUTS
        任务句柄 PSCustomObject(.Task/.Name); 未提交时为 $null

    .EXAMPLE
        Submit-WttrPrefetch | Out-Null
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 1440)]
        [int]$CacheMinutes = 10
    )

    # 功能开关: 与 Get-WttrTitleSuffix 判定一致, 关闭时不做无用功
    if (-not ($script:Config -and $script:Config.Weather -and [bool]$script:Config.Weather.Enabled)) {
        return $null
    }

    try {
        $script:_WttrPrefetchTask = Submit-TmuxBackgroundTask -ScriptBlock {
                param($argument)
                Get-WttrWeather -Format CustomUrl -Url $argument.Url -CacheMinutes $argument.CacheMinutes
            } -Argument @{ Url = $script:_WttrTitleUrl; CacheMinutes = $CacheMinutes } `
            -DependencyFile @('Get-WttrWeather.ps1')
    } catch {
        Write-Verbose "[Submit-WttrPrefetch] 天气预取提交失败: $($_.Exception.Message)"
        $script:_WttrPrefetchTask = $null
    }

    return $script:_WttrPrefetchTask
}

function Receive-WttrPrefetch {
    <#
    .SYNOPSIS
        收割已完成的后台天气预取并写回模块缓存。

    .DESCRIPTION
        任务未完成时返回 $false(不等待, 标题区按无天气渲染);
        完成后取回原始响应, 写入 $script:_WttrCache(键与 Get-WttrWeather 的缓存键一致),
        于是后续 Get-WttrWeather 会命中缓存, 不再发 HTTP。

    .OUTPUTS
        [bool] 是否成功收割并写入缓存

    .EXAMPLE
        Receive-WttrPrefetch
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $task = $script:_WttrPrefetchTask
    if ($null -eq $task) { return $false }

    # 未完成的预取保留在句柄里, 下次再收割(不提前丢弃)
    $job = $task.Task
    if ($null -eq $job -or $job.State -ne 'Completed') { return $false }

    $received = Receive-TmuxBackgroundTask -Task $task -TimeoutSeconds 0
    $script:_WttrPrefetchTask = $null

    if (-not $received.Succeeded) {
        Write-Verbose "[Receive-WttrPrefetch] 天气预取失败: $($received.ErrorMessage)"
        return $false
    }

    $raw = [string]$received.Result
    if ([string]::IsNullOrWhiteSpace($raw)) { return $false }

    if ($null -eq $script:_WttrCache) {
        $script:_WttrCache = @{
            Result    = ''
            FetchedAt = [datetime]::MinValue
            CacheKey  = $null
        }
    }
    $script:_WttrCache.Result = $raw
    $script:_WttrCache.FetchedAt = [datetime]::UtcNow
    $script:_WttrCache.CacheKey = "CustomUrl|$($script:_WttrTitleUrl)"
    return $true
}
