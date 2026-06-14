. "$PSScriptRoot\..\ShellPrompt\Private\Initialize-Config.ps1"
. "$PSScriptRoot\..\ShellPrompt\Public\Initialize-Environment.ps1"
Show-UserScoopLogo

$script:ActualRoot = (Resolve-Path "$PSScriptRoot\..").Path
. "$script:ActualRoot\Microsoft.PowerShell_profile.ps1"

Write-Host "---PROMPT-TEST---"
Write-Host "OriginalPrompt type: $($script:OriginalPrompt.GetType().FullName)"
Write-Host "OriginalPrompt value: [$($script:OriginalPrompt)]"

try {
    $r = prompt
    Write-Host "prompt() returned type: $($r.GetType().FullName)"
    Write-Host "prompt() value: [$r]"
} catch {
    Write-Host "ERR calling prompt: $($_.Exception.Message)"
}

Write-Host "---END---"
