<#
.SYNOPSIS
立即强制刷新 wttr.in 缓存并把单行结果打印到控制台

.DESCRIPTION
供用户在终端手动调用以越过默认 10 分钟缓存(例如体感温度异常、刚出机场)。
强制以 -CacheMinutes 0 调用 Get-WttrWeather -Format Short 重新抓取一次,
命中串行输出 Write-Host, 不修改模块作用域缓存(模块仍然按 10 分钟 TTL 复用)。

.EXAMPLE
PS> Update-Weather
Shanghai: 🌫 +18°C

.OUTPUTS
[void] 无返回值; 副作用为控制台输出与一次 wttr.in 请求
#>
function Update-Weather {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param()

    # 0. ShouldProcess 守卫(满足 PSUseShouldProcessForStateChangingFunctions)
    # Update-Weather 是只读副作用(写控制台 + 一次性网络请求, 不持久化任何状态),
    # 不真正可被 -WhatIf 取消 -- 此处保留调用以满足 PSSA 静态分析, 默认 WhatIf=$true 时就 return.
    if (-not $PSCmdlet.ShouldProcess('wttr.in', '强制刷新并打印单行天气')) { return }

    # 1. 模块作用域内调用 Get-WttrWeather -Format Short -CacheMinutes 0 绕过缓存
    $text = ''
    try {
        $mod = Get-Module -Name 'ShellPrompt'
        if ($mod) {
            $raw = & $mod { Get-WttrWeather -Format Short -CacheMinutes 0 }
            if ($null -ne $raw) { $text = ([string]$raw).Trim() }
        } else {
            Write-Warning '[Update-Weather] ShellPrompt 模块未加载, 无法刷新天气'
            return
        }
    } catch {
        Write-Warning "[Update-Weather] 刷新失败: $($_.Exception.Message)"
        return
    }

    # 2. 空串(网络/超时)给用户清晰反馈, 不抛异常
    if ([string]::IsNullOrWhiteSpace($text)) {
        Write-Host '[Update-Weather] wttr.in 未返回内容(可能超时或被限流)' -ForegroundColor Yellow
        return
    }

    # 3. 正常: 串行输出
    Write-Host $text
}