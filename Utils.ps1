function Show-HermesLogo {
    $quote = "SYSTEM ACTIVE"
    if (Test-Path $global:HERMES_CONF.Quotes) {
        $lines = Get-Content $global:HERMES_CONF.Quotes -Encoding UTF8 -Raw
        $quote = ($lines -split "(?m)^%\r?\n" | Get-Random).Trim()
    }

    $h = (Get-Date).Hour
    if ((Get-Random -Max 100) -lt 40) {
        if ($h -in 0..5) { $quote = "Night mode. Rest well." }
        elseif ($h -in 18..20) { $quote = "Beautiful sunset." }
    }

    Clear-Host
    Write-Host "`n  $($global:HERMES_CONF.Colors.Cyan)* ACTIVE $($global:HERMES_CONF.Colors.Rst) -- $(Get-Date -Format 'HH:mm')"
    Write-Host "`n    $quote`n" -ForegroundColor White
    Write-Host "  $($global:HERMES_CONF.Colors.Gray)$("-" * 46)$($global:HERMES_CONF.Colors.Rst)"
}

function Import-CachedTool {
    param([string]$Name, [string]$Path, [string]$InitArgs)
    if (-not (Test-Path $Path)) { return }

    $cacheFile = Join-Path $env:TEMP "Hermes_$Name.ps1"
    if (-not (Test-Path $cacheFile)) {
        $cmd = "& '$Path' $InitArgs"
        Invoke-Expression $cmd | Out-File $cacheFile -Encoding UTF8
    }
    . $cacheFile
}

$Host.UI.RawUI.WindowTitle = "Hermes | G7"
Import-CachedTool -Name "Starship" -Path $global:HERMES_CONF.Starship -InitArgs "init powershell"
Import-CachedTool -Name "Fnm" -Path $global:HERMES_CONF.Fnm -InitArgs "env --use-on-cd"

if (Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue) {
    Set-PSReadLineOption -PredictionSource History -PredictionViewStyle ListView -EditMode Windows
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    Set-PSReadLineKeyHandler -Key 'Ctrl+f' -Function AcceptSuggestion
}
