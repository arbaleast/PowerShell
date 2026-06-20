# Show-UserScoopLogo.ps1 - 欢迎语及启动语录展示
# 优化: 引入 $script:_QuotesCache (mtime + 内容快照) 避免每次 profile 加载读盘;
#       4 段三层回退颜色 -> Get-CachedConfig 一次调用;
#       静态布局部分提前拼接避免每次展开 @()。

function Show-UserScoopLogo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$QuotesPath,

        [Parameter(Mandatory = $false)]
        [string]$ColorPrimary,

        [Parameter(Mandatory = $false)]
        [string]$ColorAccent,

        [Parameter(Mandatory = $false)]
        [string]$ColorMuted,

        [Parameter(Mandatory = $false)]
        [string]$BorderColor
    )

    # 默认值解析（走预热缓存快路径，0 命中回退到硬编码）
    if (-not $QuotesPath) { $QuotesPath = Get-CachedConfig -Section 'Paths'  -Key 'Quotes'    -Default '' }
    if (-not $ColorPrimary) { $ColorPrimary = Get-CachedConfig -Section 'Colors' -Key 'FreshGreen' -Default "`e[38;2;137;209;133m" }
    if (-not $ColorAccent) { $ColorAccent = Get-CachedConfig -Section 'Colors' -Key 'SageGreen'  -Default "`e[38;2;159;177;159m" }
    if (-not $ColorMuted) { $ColorMuted = Get-CachedConfig -Section 'Colors' -Key 'MidGray'    -Default "`e[38;2;100;100;100m" }
    if (-not $BorderColor) { $BorderColor = Get-CachedConfig -Section 'Colors' -Key 'FreshGreen' -Default "`e[38;2;137;209;133m" }

    $rst = Get-CachedConfig -Section 'Colors' -Key 'Rst' -Default "`e[0m"
    $quote = "SYSTEM READY"

    if (Test-Path $QuotesPath) {
        # mtime + 内容快照缓存: 文件未变化时复用上次的随机抽取结果
        # 避免每次 profile 加载 (或 reload) 都读取并 -split 整个 quotes 文件
        $fileInfo = Get-Item $QuotesPath
        $mtime = $fileInfo.LastWriteTimeUtc.Ticks
        $cacheHit = $false
        if ($script:_QuotesCache -and $script:_QuotesCache.Path -eq $QuotesPath -and $script:_QuotesCache.MTime -eq $mtime) {
            $lines = $script:_QuotesCache.Lines
            $cacheHit = $true
        }
        if (-not $cacheHit) {
            $lines = (Get-Content $QuotesPath -Encoding UTF8 -Raw) -split "(?m)^%\r?\n"
            $script:_QuotesCache = @{
                Path  = $QuotesPath
                MTime = $mtime
                Lines = $lines
            }
        }
        if ($lines -and $lines.Count -gt 0) {
            # 过滤空串/纯空白: Get-Random -InputObject 不接受空字符串 (会抛 ParameterArgumentValidationError)
            $validLines = @($lines | Where-Object { $_ -and $_.Trim() })
            if ($validLines.Count -gt 0) {
                $quote = ($validLines | Get-Random).Trim()
                if (-not $quote) { $quote = "SYSTEM READY" }
            }
        }
    }

    if ($quote -eq "SYSTEM READY" -and (Get-Random -Minimum 0 -Maximum 100) -lt 15) {
        $h = (Get-Date).Hour
        $timeGreeting = switch ($true) {
            ($h -in 0..5) { "Night mode. Rest well." }
            ($h -in 18..20) { "Beautiful sunset." }
            default { $null }
        }
        if ($timeGreeting) { $quote = $timeGreeting }
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $hostname = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { "local" }
    $userName = if ($env:USERNAME) { $env:USERNAME } else { "user" }
    $cwd = Split-Path -Leaf $PWD.Path
    $hLine = "=" * 45

    # 静态布局: banner 模板只拼接一次,所有可变量已在上方完成字符串插值
    $bannerLines = @(
        ''
        "  $BorderColor--< $ColorMuted$userName@$hostname$BorderColor >--[ $ColorAccent$cwd$BorderColor ]--[ ${ColorPrimary}SHELL PROMPT$BorderColor ]$rst"
        "  $BorderColor|$rst"
        "  $BorderColor|$rst  $BorderColor~$rst"
        "  $BorderColor|$rst  ${ColorPrimary}DONE$rst  ${ColorPrimary}$quote$rst"
        "  $BorderColor|$rst  $ColorMuted$timestamp$rst"
        "  $BorderColor|$rst"
        "  $BorderColor|$rst  $BorderColor~$rst"
        "  $BorderColor+$hLine---$rst"
        ''
    )
    $banner = $bannerLines -join "`n"

    Write-Host $banner
}
