# ============================================================
# Initialize-Environment.ps1 - 终端环境初始化
# 包含 Starship、Fnm、PSReadLine 配置及启动语录展示
# ============================================================

function Initialize-Environment {
    [CmdletBinding()]
    param()

    $Host.UI.RawUI.WindowTitle = "Terminal"

    # Starship
    if (Get-Command starship -ErrorAction SilentlyContinue) {
        Invoke-Expression (& starship init powershell)
    } else {
        Write-Host " [Warn] Starship 未安装或未加入 PATH" -ForegroundColor Yellow
    }

    # Fnm
    if (Get-Command fnm -ErrorAction SilentlyContinue) {
        $fnmEnv = (& fnm env --use-on-cd) -join "`n"
        Invoke-Expression $fnmEnv
    }

    # PSReadLine
    Import-Module PSReadLine -ErrorAction SilentlyContinue
    if (Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue) {
        Set-PSReadLineOption -PredictionSource History
        Set-PSReadLineOption -PredictionViewStyle InlineView
        Set-PSReadLineOption -EditMode Windows

        Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
        Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
        Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
        Set-PSReadLineKeyHandler -Key 'Ctrl+f'  -Function AcceptSuggestion
    }
}

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
        [string]$BorderColor = $global:UserScoop_CONF.Colors.MintGreen
    )

    $rst = "`e[0m"

    $quote = "SYSTEM READY"
    if (Test-Path $QuotesPath) {
        $lines = (Get-Content $QuotesPath -Encoding UTF8 -Raw) -split "(?m)^%\r?\n"
        $quote = ($lines | Get-Random).Trim()
    }

    $h = (Get-Date).Hour
    if ((Get-Random -Max 100) -lt 40) {
        if ($h -in 0..5) {
            $quote = "Night mode. Rest well."
        } elseif ($h -in 18..20) {
            $quote = "Beautiful sunset."
        }
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    # Get system info
    $hostname = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { "local" }
    $userName = if ($env:USERNAME) { $env:USERNAME } else { "user" }
    $cwd = $PWD.Path.Split('\')[-1]
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
