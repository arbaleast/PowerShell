# ============================================================
# Initialize-Environment.ps1 — 终端环境初始化
# 包含 Starship、Fnm、PSReadLine 配置及启动语录展示
# ============================================================

function Initialize-Environment
{
    [CmdletBinding()]
    param()

    $Host.UI.RawUI.WindowTitle = "Terminal"

    # Starship
    if (Get-Command starship -ErrorAction SilentlyContinue)
    {
        Invoke-Expression (& starship init powershell)
    } else
    {
        Write-Host " [Warn] Starship 未安装或未加入 PATH" -ForegroundColor Yellow
    }

    # Fnm
    if (Get-Command fnm -ErrorAction SilentlyContinue)
    {
        $fnmEnv = (& fnm env --use-on-cd) -join "`n"
        Invoke-Expression $fnmEnv
    }

    # PSReadLine
    Import-Module PSReadLine -ErrorAction SilentlyContinue
    if (Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue)
    {
        Set-PSReadLineOption -PredictionSource History
        Set-PSReadLineOption -PredictionViewStyle InlineView
        Set-PSReadLineOption -EditMode Windows

        Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
        Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
        Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
        Set-PSReadLineKeyHandler -Key 'Ctrl+f' -Function AcceptSuggestion
    }
}

function Show-UserScoopLogo
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$QuotesPath = $global:UserScoop_CONF.Quotes,

        [Parameter(Mandatory = $false)]
        [string]$ColorCyan = $global:UserScoop_CONF.Colors.Cyan,

        [Parameter(Mandatory = $false)]
        [string]$ColorGray = $global:UserScoop_CONF.Colors.Gray
    )

    $quote = "SYSTEM ACTIVE"
    if (Test-Path $QuotesPath)
    {
        $lines = (Get-Content $QuotesPath -Encoding UTF8 -Raw) -split "(?m)^%\r?\n"
        $quote = ($lines | Get-Random).Trim()
    }

    $h = (Get-Date).Hour
    if ((Get-Random -Max 100) -lt 40)
    {
        if ($h -in 0..5)
        {
            $quote = "Night mode. Rest well."
        } elseif ($h -in 18..20)
        {
            $quote = "Beautiful sunset."
        }
    }

    Write-Host ""
    Write-Host "  ${ColorCyan}* ACTIVE ${ColorGray}-- $(Get-Date -Format 'HH:mm')"
    Write-Host ""
    Write-Host "    $quote" -ForegroundColor White
    Write-Host ""
    Write-Host "  ${ColorGray}$('─' * 46)"
}
