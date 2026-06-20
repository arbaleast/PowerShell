# ShellPrompt.psm1 - Module Entry Point

# Load configuration first
if (-not (Get-Variable -Name 'UserScoop_CONF' -Scope Global -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\Private\Initialize-Config.ps1"
}

# Load all module scripts
Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1", "$PSScriptRoot\Public\*.ps1" | ForEach-Object {
    if ($_.Name -eq 'Initialize-Config.ps1') { return }
    try {
        . $_.FullName
    } catch {
        Write-Warning "[ShellPrompt] Failed to load $($_.Name): $($_.Exception.Message)"
    }
}

# User config override
$userConfigPath = Join-Path $HOME ".ShellPrompt\config.ps1"
if (Test-Path $userConfigPath) {
    try {
        . $userConfigPath
    } catch {
        Write-Host "[ShellPrompt] User config failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# SSH Config auto-completion
$sshHosts = Get-SshConfigHosts
if ($sshHosts.Count -gt 0) {
    Register-ArgumentCompleter -CommandName 'Start-TmuxSession' -ParameterName 'HostName' -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $hosts = Get-SshConfigHosts
        $hosts | Where-Object { $_ -like "*$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}

# Explicitly export the public API.
# PowerShell 5.1 does NOT auto-export functions from script modules — FunctionsToExport
# in the .psd1 is just a recommendation; the module must opt in via Export-ModuleMember,
# otherwise ExportedFunctions is empty and `Get-Command -Module ShellPrompt -Name <fn>`
# returns $null (which broke the `sss` / Start-TmuxSession wrapper).
Export-ModuleMember -Function 'Show-UserScoopLogo', 'Start-TmuxSession', 'reload'
