# Get-SshConfigHosts.ps1

function Get-SshConfigHosts {
    try {
        $sshConfig = Join-Path $HOME ".ssh\config"
        if (-not (Test-Path $sshConfig -ErrorAction Stop)) { 
            return @() 
        }
        
        $hosts = @()
        foreach ($line in (Get-Content $sshConfig -Encoding UTF8 -ErrorAction Stop)) {
            if ($line -match '^Host\s+(.+)$') {
                $alias = $matches[1].Trim()
                if ($alias -and $alias -notmatch '\*') {
                    $hosts += $alias
                }
            }
        }
        
        return $hosts | Select-Object -Unique
    } catch {
        # SSH config 读取失败时返回空列表，不阻塞模块加载
        if ($Global:TUI_Logger) {
            $Global:TUI_Logger.Warning("读取 SSH config 失败: $($_.Exception.Message)")
        }
        return @()
    }
}