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
                # SSH config 支持多模式: Host myserver *.example.com
                # 只取第一个别名作为有效主机名（后续模式含通配符应忽略）
                $alias = ($matches[1] -split '\s+')[0]
                if ($alias -and $alias -notmatch '[*?]') {
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