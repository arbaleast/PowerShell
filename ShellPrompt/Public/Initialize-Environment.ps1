# ============================================================
# Initialize-Environment.ps1 - 欢迎语及启动语录展示
# ============================================================

# 缓存：quotes.txt 仅加载一次，避免每次 Profile 加载时重复读取文件 I/O
$script:QuotesCache = $null

function Show-UserScoopLogo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$QuotesPath = $global:UserScoop_CONF.Quotes,

        [Parameter(Mandatory = $false)]
        [string]$ColorPrimary = $global:UserScoop_CONF.Colors.FreshGreen,

        [Parameter(Mandatory = $false)]
        [string]$ColorAccent = $global:UserScoop_CONF.Colors.SageGreen,

        [Parameter(Mandatory = $false)]
        [string]$ColorMuted = $global:UserScoop_CONF.Colors.MidGray,

        [Parameter(Mandatory = $false)]
        [string]$BorderColor = $global:UserScoop_CONF.Colors.FreshGreen
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

    # Header
    Write-Host ""
    Write-Host "  $BorderColor--< $ColorMuted$userName@$hostname$BorderColor >--[ $ColorAccent$cwd$BorderColor ]--[ ${ColorPrimary}SHELL PROMPT$BorderColor ]$rst"
    Write-Host "  $BorderColor|$rst"
    Write-Host "  $BorderColor|$rst  $BorderColor~$rst"
    Write-Host "  $BorderColor|$rst  ${ColorPrimary}DONE$rst  ${ColorPrimary}$quote$rst"
    Write-Host "  $BorderColor|$rst  $ColorMuted$timestamp$rst"
    Write-Host "  $BorderColor|$rst"
    Write-Host "  $BorderColor|$rst  $BorderColor~$rst"
    Write-Host "  $BorderColor+$hLine---$rst"

    Write-Host ""
}
