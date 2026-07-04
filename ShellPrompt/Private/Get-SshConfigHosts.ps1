# Get-SshConfigHosts.ps1 - 读取 ~/.ssh/config 中的 Host 别名
# 进程级 mtime 缓存: 仅当源文件 mtime 变化时重新解析,
# 避免每次 Tab 补全都重读 ~/.ssh/config。

# 脚本级缓存：缓存解析结果与源文件最后修改时间
$script:_SshHostsCache = $null
$script:_SshHostsCacheMtime = [DateTime]::MinValue

function Get-SshConfigHosts {
    try {
        $sshConfig = Join-Path $HOME ".ssh\config"
        # 一次 Get-Item 替代 Test-Path + Get-Item
        $configItem = Get-Item $sshConfig -ErrorAction SilentlyContinue
        if (-not $configItem) {
            return @()
        }

        # 算法优化: 仅当文件 mtime 变化时重新解析
        $currentMtime = $configItem.LastWriteTimeUtc
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
        return @()
    }
}
