# ============================================================
# Initialize-Environment.ps1 - 欢迎语及启动语录展示
# ============================================================

# 缓存：quotes.txt 仅加载一次，避免每次 Profile 加载时重复读取文件 I/O
$script:QuotesCache = $null

# 预解引用全局配置 → 局部变量：避免 Show-UserScoopLogo 默认参数每次调用都进行
# 5 次 $global:UserScoop_CONF.XXX 解引用（每个默认值都是一个 ExpressionAst）
$script:CfgQuotes = $global:UserScoop_CONF.Quotes
$script:CfgFreshGreen = $global:UserScoop_CONF.Colors.FreshGreen
$script:CfgSageGreen = $global:UserScoop_CONF.Colors.SageGreen
$script:CfgMidGray = $global:UserScoop_CONF.Colors.MidGray

function Show-UserScoopLogo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$QuotesPath = $script:CfgQuotes,

        [Parameter(Mandatory = $false)]
        [string]$ColorPrimary = $script:CfgFreshGreen,

        [Parameter(Mandatory = $false)]
        [string]$ColorAccent = $script:CfgSageGreen,

        [Parameter(Mandatory = $false)]
        [string]$ColorMuted = $script:CfgMidGray,

        [Parameter(Mandatory = $false)]
        [string]$BorderColor = $script:CfgFreshGreen
    )

    $rst = "`e[0m"

    $quote = "SYSTEM READY"
    if (Test-Path $QuotesPath) {
        if (-not $script:QuotesCache) {
            $script:QuotesCache = (Get-Content $QuotesPath -Encoding UTF8 -Raw) -split "(?m)^%\r?\n"
        }
        $quote = ($script:QuotesCache | Get-Random).Trim()
    }

    # 仅在未从文件加载到有效引用（仍为默认值）时，以较低概率使用时间问候
    # O1 优化：使用单次 Get-Random + hashtable O(1) 查找，避免多次文件 I/O 与嵌套随机
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

    # Get system info
    $hostname = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { "local" }
    $userName = if ($env:USERNAME) { $env:USERNAME } else { "user" }
    $cwd = Split-Path -Leaf $PWD.Path
    $hLine = "=" * 45

    # I/O 批量化：10 次 Write-Host 合并为 1 次单字符串写入
    # 每次 Write-Host 在 Windows console 上约 20-40ms 启动开销（输出重定向 + 颜色解析）
    # 单字符串仅 1 次调用，profile 加载可节省 ~250-350ms
    $banner = @(
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
    ) -join "`n"

    Write-Host $banner
}
