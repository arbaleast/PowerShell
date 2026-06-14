# Get-SshConfigHosts.ps1
# 优化: 进程级 mtime 缓存，避免每次 Tab 补全都重新读取 ~/.ssh/config

# 脚本级缓存：缓存解析结果与源文件最后修改时间
$script:_SshHostsCache = $null
$script:_SshHostsCacheMtime = [DateTime]::MinValue

function Get-SshConfigHosts {
    try {
        $sshConfig = Join-Path $HOME ".ssh\config"
        if (-not (Test-Path $sshConfig -ErrorAction Stop)) {
            return @()
        }

        # 算法优化: 仅当文件 mtime 变化时重新解析
        $currentMtime = (Get-Item $sshConfig -ErrorAction Stop).LastWriteTimeUtc
        if ($null -ne $script:_SshHostsCache -and $script:_SshHostsCacheMtime -eq $currentMtime) {
            return $script:_SshHostsCache
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

        # 写入缓存
        $script:_SshHostsCache = @($hosts | Select-Object -Unique)
        $script:_SshHostsCacheMtime = $currentMtime
        return $script:_SshHostsCache
    } catch {
        # SSH config 读取失败时返回空列表，不阻塞模块加载
        if ($Global:TUI_Logger) {
            $Global:TUI_Logger.Warning("读取 SSH config 失败: $($_.Exception.Message)")
        }
        return @()
    }
}
