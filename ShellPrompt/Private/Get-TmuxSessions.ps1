# Get-TmuxSessions.ps1 - 通过 SSH 获取远程 tmux 会话列表
# 性能优化: 合并"探测 tmux 可用性 + 列出会话"为单次 SSH 调用,启动时间 -50%
# 缓存: 模块级缓存 tmux 可用性,避免反复探测同一主机

$script:_TmuxAvailabilityCache = @{}

function Get-TmuxAvailability {
    <#
    .SYNOPSIS
    探测远程主机 tmux 是否可用(单次 SSH,带缓存)
    .DESCRIPTION
    同时返回 tmux 版本号(若可用),后续解析无需再次 SSH。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $false)]
        [int]$ConnectTimeout = 5,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    # TTL 缓存: 30 秒内命中直接返回,过期后重新探测。
    # 兼容旧缓存条目（无 CheckedAt 字段），视为过期重新探测，避免脏数据。
    if (-not $Force -and $script:_TmuxAvailabilityCache.ContainsKey($HostName)) {
        $cached = $script:_TmuxAvailabilityCache[$HostName]
        $hasCheckedAt = $cached.PSObject.Properties.Name -contains 'CheckedAt'
        if ($hasCheckedAt) {
            $cacheAge = [DateTime]::UtcNow - $cached.CheckedAt
            if ($cacheAge.TotalSeconds -lt 30) {
                return $cached
            }
        }
    }

    # 单次 SSH 探测 + 列出所有 session
    # 输出格式:
    #   line 1: TMUX_VERSION=<ver or "">  (空字符串表示无 tmux)
    #   line 2+: 原始 `tmux ls` 输出(若有)
    #
    # 修 2026-06-27: 避免 `$()` 子 shell 在某些 sshd 配置(非交互式 PATH 不完整)下
    # 输出被吞,改用 `command -v` 拿绝对路径,再用绝对路径跑 `tmux -V`。
    # 绝对路径是 sshd 唯一能保证找到 tmux 的方式(不受 PATH/login profile 影响)。
    $probeCmd = 'TMUX_BIN=$(command -v tmux 2>/dev/null || echo /usr/bin/tmux); ' +
    'TMUX_V=$("$TMUX_BIN" -V 2>/dev/null); ' +
    'printf "TMUX_VERSION=%s\n" "${TMUX_V:-}"; ' +
    '"$TMUX_BIN" ls 2>/dev/null; ' +
    'true'
    $result = Invoke-SshCommand -HostName $HostName -RemoteCommand $probeCmd -CaptureOutput -ConnectTimeout $ConnectTimeout -PassThru

    $output = if ($result) { $result.Output } else { '' }
    $exitCode = if ($result) { $result.ExitCode } else { -1 }
    $errorOut = if ($result) { $result.Error } else { '' }

    $versionLine = ''
    $tmuxLsOutput = ''
    if ($output) {
        $newlineIdx = $output.IndexOf("`n")
        if ($newlineIdx -ge 0) {
            $versionLine = $output.Substring(0, $newlineIdx).Trim()
            $tmuxLsOutput = $output.Substring($newlineIdx + 1)
        } else {
            $versionLine = $output.Trim()
        }
    }

    # 解析版本号: "TMUX_VERSION=tmux 3.3a" -> "3.3a"
    $version = ''
    if ($versionLine -match '^TMUX_VERSION=(.+)$') { $version = $matches[1].Trim() }
    # 去掉可能的前缀 "tmux "
    $version = $version -replace '^tmux\s+', ''

    # 兜底: 解析不到版本行时,看 stderr 里有没有 "tmux X.Y" 字样
    # (某些 sshd 包装器把 tmux -V 输出到 stderr)
    if (-not $version -and $errorOut -and $errorOut -match 'tmux\s+(\d+\.\d+[a-z]?)') {
        $version = $matches[1]
    }

    # 网络错误分类: 将网络故障与"远程无 tmux"区分开。
    # 命中以下模式则标记 NetworkError, Available 置 $false,
    # 且跳过缓存写入,避免 DNS 恢复后因脏缓存持续误判。
    $networkErrorPatterns = @(
        'Could not resolve hostname',
        'Name or service not known',
        'Connection refused',
        'No route to host',
        'Connection timed out',
        'Operation timed out',
        'ssh: connect to host .* port .*: '
    )
    $isNetworkError = $false
    if ($errorOut) {
        foreach ($pattern in $networkErrorPatterns) {
            if ($errorOut -match $pattern) {
                $isNetworkError = $true
                break
            }
        }
    }

    $info = [PSCustomObject]@{
        Available    = if ($isNetworkError) { $false } else { -not [string]::IsNullOrEmpty($version) }
        Version      = $version
        RawLs        = $tmuxLsOutput
        ExitCode     = $exitCode
        Error        = $errorOut
        NetworkError = $isNetworkError
        CheckedAt    = [DateTime]::UtcNow
    }

    # 网络错误时跳过缓存写入,避免脏缓存阻塞后续恢复后的探测
    if (-not $isNetworkError) {
        $script:_TmuxAvailabilityCache[$HostName] = $info
    }
    return $info
}

function Get-TmuxSessions {
    <#
    .SYNOPSIS
    获取远程 tmux 会话列表(已包含在 Get-TmuxAvailability 探测结果里,免第二次 SSH)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $false)]
        [int]$ConnectTimeout = 5,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    $info = Get-TmuxAvailability -HostName $HostName -ConnectTimeout $ConnectTimeout -Force:$Force
    $output = $info.RawLs

    $sessionList = [System.Collections.Generic.List[PSCustomObject]]::new(8)
    if ($info.Available -and $output) {
        # 优化: 单次正则同时提取 name + attached 状态
        # 模式: <name>: <N> windows (created <date>) [attached]
        $tmuxLineRegex = '^(?<name>[^:]+):\s+\d+\s+windows?\s+\(created[^)]*\)(?<attached>\s+attached)?'
        foreach ($line in ($output -split "`n")) {
            $trimmed = $line.TrimEnd()
            if ([string]::IsNullOrEmpty($trimmed)) { continue }
            if ($trimmed -match $tmuxLineRegex) {
                $name = $matches['name'].Trim()
                $status = if ($matches['attached']) { 'attached' } else { 'detached' }
                $sessionList.Add([PSCustomObject]@{ Name = $name; Status = $status })
            }
        }
    }

    return @{
        Sessions  = $sessionList
        RawOutput = $output
        Version   = $info.Version
    }
}
