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

    Write-Host "`n  ${ColorCyan}* ACTIVE ${ColorGray}-- $(Get-Date -Format 'HH:mm')"
    Write-Host "`n    $quote`n" -ForegroundColor White
    Write-Host "  ${ColorGray}$('─' * 46)"
}

# ============================================================
# 终端初始化（启动时执行一次）
# ============================================================

$Host.UI.RawUI.WindowTitle = "Terminal"

# 1. 安全加载 Starship
if (Get-Command starship -ErrorAction SilentlyContinue)
{
    Invoke-Expression (&starship init powershell)
} else
{
    Write-Host " [Warn] Starship 未安装或未加入 PATH" -ForegroundColor Yellow
}

# 2. 安全加载 Fnm
if (Get-Command fnm -ErrorAction SilentlyContinue)
{
    $fnmEnv = (& fnm env --use-on-cd) -join "`n"
    Invoke-Expression $fnmEnv
}

# 3. PSReadLine 配置
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
