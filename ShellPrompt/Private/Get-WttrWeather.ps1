# Get-WttrWeather.ps1 - wttr.in ASCII 天气短字符串获取
# 用途: 在 PowerShell 提示符中替换原 tmux 会话片段(< user@host >),
#       输出一行 ASCII 天气(如 "Shanghai: 🌫 +18°C")。
# 设计原则:
#   1. $script: 作用域缓存,避免全局污染,符合 AGENTS.md 命名规范。
#   2. 缓存命中期内不发起网络请求,降低 wttr.in 限流与每条命令的延迟。
#   3. 所有异常(超时/网络失败/远端空响应)一律返回空字符串,
#      由调用方决定如何降级(通常直接忽略,让 prompt 渲染回退到 Starship)。
#   4. 内部 HTTP 层独立为 Get-WttrHttpBody,便于 Pester 在模块作用域内 Mock。
#   5. 优选系统 curl.exe(Win10 1803+ / Server 2019+ / Linux / macOS),
#      缺失时回退到 PowerShell 内置 Invoke-RestMethod,零额外依赖。

# 天气缓存: { Result, FetchedAt, CacheKey }
#   Result    : 上次成功抓取的字符串(失败时绝不写入,避免污染下次命中)
#   FetchedAt : UTC 时间戳,用于计算 TTL 过期
#   CacheKey  : "Format|Url" 复合键,切换 Format / Url 时不会命中旧缓存
if ($null -eq $script:_WttrCache) {
    $script:_WttrCache = @{
        Result    = ''
        FetchedAt = [datetime]::MinValue
        CacheKey  = $null
    }
}

function Get-WttrFormatUrl {
    <#
    .SYNOPSIS
        根据 Format 枚举解析 wttr.in 请求 URL(纯函数,无 I/O)

    .DESCRIPTION
        内部辅助函数:把用户友好的 Format 映射为具体 URL。
        Short -> 紧凑单行 "城市: 图标 温度"(`?format=3`);
        Full  -> wttr.in 默认 ASCII 横幅(三日预报);
        CustomUrl -> 透传 -Url 参数。

    .PARAMETER Format
        格式枚举 (Short / Full / CustomUrl)

    .PARAMETER Url
        当 Format=CustomUrl 时使用的 URL;其它取值忽略。

    .OUTPUTS
        [string] 解析后的完整 URL;CustomUrl 模式下若 Url 为空则返回空串。
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Short', 'Full', 'CustomUrl')]
        [string] $Format,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Url
    )

    switch ($Format) {
        'Short'     { return 'https://wttr.in?format=3' }
        'Full'      { return 'https://wttr.in' }
        'CustomUrl' {
            if ([string]::IsNullOrWhiteSpace($Url)) { return '' }
            return $Url
        }
    }
}

function Get-WttrHttpBody {
    <#
    .SYNOPSIS
        抓取 wttr.in URL 的原始响应体(单次 HTTP,无缓存)

    .DESCRIPTION
        内部辅助函数:根据系统能力优选 curl.exe,缺失时回退 Invoke-RestMethod。
        任何错误(超时/连接失败/HTTP 4xx-5xx)统一抛出,caller 负责降级。

    .PARAMETER Uri
        完整 wttr.in URL

    .PARAMETER TimeoutSeconds
        单次请求超时(秒),默认 5

    .OUTPUTS
        [string] 响应体文本

    .NOTES
        使用 curl.exe 的 --fail 选项: HTTP 4xx/5xx 时退出码 22,
        据此判定请求失败,避免把 wttr.in 错误页面当作天气解析。
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Uri,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 60)]
        [int] $TimeoutSeconds = 5
    )

    # 优选 curl.exe(系统自带,跨平台一致,行为可预测)
    if (Get-Command -Name 'curl.exe' -ErrorAction SilentlyContinue) {
        $output = & curl.exe -sS -m $TimeoutSeconds --fail $Uri 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "curl.exe 退出码 $LASTEXITCODE (Uri=$Uri)"
        }
        if ($output -is [array]) {
            return ($output -join "`n").TrimEnd("`r", "`n")
        }
        return ([string]$output).TrimEnd("`r", "`n")
    }

    # 回退: PowerShell 内置 HTTP 客户端
    # 注意 PS 5.1 对 wttr.in 偶发 SNI/TLS 兼容问题,故仅作 fallback
    $response = Invoke-RestMethod -Uri $Uri -TimeoutSec $TimeoutSeconds -ErrorAction Stop
    if ($null -eq $response) { return '' }
    return ([string]$response).TrimEnd("`r", "`n")
}

function Get-WttrWeather {
    <#
    .SYNOPSIS
        获取 wttr.in 短格式天气字符串,带模块级缓存和错误兜底

    .DESCRIPTION
        面向 PowerShell 提示符调用的轻量天气获取函数。返回单行字符串(如
        "Shanghai: 🌫 +18°C"),适合拼接到 prompt 字符串中。

        核心特性:
        - 模块作用域缓存 ($script:_WttrCache),默认 10 分钟内复用同一份结果。
        - 单次 HTTP 超时 5 秒,可由 -TimeoutSeconds 覆盖。
        - 任何失败(超时/网络故障/远端返回空)统一返回空字符串,
          并通过 Write-Verbose 写诊断,绝不抛异常污染 prompt。
        - 优选 curl.exe(系统级,无依赖),缺失时回退 Invoke-RestMethod。

    .PARAMETER Format
        输出格式: Short (默认) / Full / CustomUrl。
        - Short    : `?format=3` 紧凑单行,推荐用于 prompt。
        - Full     : wttr.in 默认 ASCII 横幅(三日预报),适合侧边栏。
        - CustomUrl: 使用 -Url 参数指定的完整 URL。

    .PARAMETER Url
        当 -Format=CustomUrl 时使用的完整 URL。其它取值下被忽略。

    .PARAMETER CacheMinutes
        缓存有效期(分钟)。默认 10。设为 0 强制绕过缓存读取,立即重新抓取。

    .PARAMETER TimeoutSeconds
        单次 HTTP 请求超时(秒)。默认 5。

    .OUTPUTS
        [string] 天气短字符串;失败时返回空字符串。

    .EXAMPLE
        PS> Get-WttrWeather
        Shanghai: 🌫 +18°C

    .EXAMPLE
        PS> Get-WttrWeather -Format Full -CacheMinutes 30
        # 缓存 30 分钟,适合手动复检 ASCII 横幅

    .EXAMPLE
        PS> Get-WttrWeather -Format CustomUrl -Url 'https://wttr.in/Shanghai?format=3' -Verbose
        # 详细模式 + 完整 URL 控制
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet('Short', 'Full', 'CustomUrl')]
        [string] $Format = 'Short',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Url,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 1440)]
        [int] $CacheMinutes = 10,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 60)]
        [int] $TimeoutSeconds = 5
    )

    # 1. 计算复合缓存键:Format / Url 变化时不会命中旧缓存
    $cacheKey = "$Format|$Url"

    # 2. 缓存命中检查(允许 CacheMinutes=0 强制刷新)
    $cacheAge = ([datetime]::UtcNow - $script:_WttrCache.FetchedAt).TotalMinutes
    $isHit = ($CacheMinutes -gt 0) -and
             ($script:_WttrCache.CacheKey -eq $cacheKey) -and
             (-not [string]::IsNullOrEmpty($script:_WttrCache.Result)) -and
             ($cacheAge -lt $CacheMinutes)

    if ($isHit) {
        $remaining = [int]([math]::Max(0, ($CacheMinutes - $cacheAge) * 60))
        Write-Verbose "[Get-WttrWeather] 缓存命中 ($cacheKey, 剩余 ${remaining}s)"
        return $script:_WttrCache.Result
    }

    # 3. 解析目标 URL
    $resolvedUrl = Get-WttrFormatUrl -Format $Format -Url $Url
    if ([string]::IsNullOrWhiteSpace($resolvedUrl)) {
        Write-Verbose '[Get-WttrWeather] Format=CustomUrl 但 -Url 为空,返回空字符串'
        return ''
    }

    # 4. 抓取响应(任何异常都吞掉,绝不上抛污染 prompt)
    $raw = ''
    try {
        $raw = Get-WttrHttpBody -Uri $resolvedUrl -TimeoutSeconds $TimeoutSeconds
    }
    catch {
        Write-Verbose "[Get-WttrWeather] HTTP 失败: $($_.Exception.Message)"
        return ''
    }

    # 5. 规范化结果(去首尾空白,空响应视为失败)
    $normalized = ([string]$raw).Trim()
    if ([string]::IsNullOrEmpty($normalized)) {
        Write-Verbose '[Get-WttrWeather] 远端返回空内容,保持空字符串'
        return ''
    }

    # 6. 写入缓存(只缓存非空结果,避免缓存"故障空字符串")
    $script:_WttrCache.Result    = $normalized
    $script:_WttrCache.FetchedAt = [datetime]::UtcNow
    $script:_WttrCache.CacheKey  = $cacheKey

    Write-Verbose "[Get-WttrWeather] 抓取成功 ($resolvedUrl, 长度 $($normalized.Length))"
    return $normalized
}
