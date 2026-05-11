function Show-UserScoopLogo
{
    $quote = "SYSTEM ACTIVE"
    if (Test-Path $global:UserScoop_CONF.Quotes)
    {
        # 优化：快速读取随机行，而不是全部加载进内存再分割
        $lines = (Get-Content $global:UserScoop_CONF.Quotes -Encoding UTF8 -Raw) -split "(?m)^%\r?\n"
        $quote = ($lines | Get-Random).Trim()
    }

    $h = (Get-Date).Hour
    if ((Get-Random -Max 100) -lt 40)
    {
        if ($h -in 0..5)
        { $quote = "Night mode. Rest well."
        } elseif ($h -in 18..20)
        { $quote = "Beautiful sunset."
        }
    }

    Write-Host "`n  $($global:UserScoop_CONF.Colors.Cyan)* ACTIVE $($global:UserScoop_CONF.Colors.Rst) -- $(Get-Date -Format 'HH:mm')"
    Write-Host "`n    $quote`n" -ForegroundColor White
    Write-Host "  $($global:UserScoop_CONF.Colors.Gray)$("-" * 46)$($global:UserScoop_CONF.Colors.Rst)"
}

$Host.UI.RawUI.WindowTitle = "Terminal"

# 1. 安全加载 Starship (主题)
if (Get-Command starship -ErrorAction SilentlyContinue)
{
    Invoke-Expression (&starship init powershell)
} else
{
    Write-Host " [Warn] Starship 未安装或未加入环境变量 PATH" -ForegroundColor Yellow
}

# 2. 安全加载 Fnm (Node 管理器，若不需要可注释掉)
if (Get-Command fnm -ErrorAction SilentlyContinue)
{
    # 修复：将 fnm 返回的字符串数组拼接成一个单一的字符串
    $fnmEnv = (&fnm env --use-on-cd) -join "`n"
    Invoke-Expression $fnmEnv
}

# 3. 强制重新加载并配置 PSReadLine (自动补全与历史记录)
Import-Module PSReadLine -ErrorAction SilentlyContinue
if (Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue)
{
    Set-PSReadLineOption -PredictionSource History
    Set-PSReadLineOption -PredictionViewStyle InlineView  # 推荐使用 Inline 视图，比 List 更整洁
    Set-PSReadLineOption -EditMode Windows

    # 绑定上下方向键，支持基于已输入前缀的历史记录搜索
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    Set-PSReadLineKeyHandler -Key 'Ctrl+f' -Function AcceptSuggestion
}
