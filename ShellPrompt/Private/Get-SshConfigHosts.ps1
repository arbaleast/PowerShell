# Get-SshConfigHosts.ps1

function Get-SshConfigHosts {
    $sshConfig = Join-Path $HOME ".ssh\config"
    if (-not (Test-Path $sshConfig)) { return @() }
    
    $hosts = @()
    foreach ($line in Get-Content $sshConfig -Encoding UTF8) {
        if ($line -match '^Host\s+(.+)$') {
            $alias = $matches[1].Trim()
            if ($alias -and $alias -notmatch '\*') {
                $hosts += $alias
            }
        }
    }
    
    return $hosts | Select-Object -Unique
}