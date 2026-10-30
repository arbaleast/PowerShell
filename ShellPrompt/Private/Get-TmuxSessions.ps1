# Get-TmuxSessions.ps1 - 通过 SSH 获取远程 tmux 会话列表
# 性能优化: 合并"探测 tmux 可用性 + 列出会话"为单次 SSH 调用,启动时间 -50%
# 缓存: 模块级缓存 tmux 可用性,避免反复探测同一主机
#
# 解析策略(2026-10-18 补强):
#   主路径  = tmux list-sessions -F 精确字段(会话名放在最后, 允许含空格/冒号)
#   回退路径 = tmux ls 人类可读输出(容错正则, 允许缺 (created ...) / 缺状态标记)
#   两条路径产出统一形状 Name/Status/Windows, 调用方无需感知差异。
#   任何异常(远端无 tmux / 输出为空 / 输出异常)都只降级为空集合, 绝不 throw。

$script:TmuxAvailabilityCache = @{}
$script:TmuxSessionFormatPrefix = 'TMUX_SESSION'
$script:TmuxSessionsBeginMarker = 'TMUX_SESSIONS_BEGIN'
$script:TmuxSessionsEndMarker = 'TMUX_SESSIONS_END'

function Get-TmuxProbeCommand {
    <#
    .SYNOPSIS
        构建远程 tmux 探测命令(单次 SSH 同时返回版本/机器可读会话/ls 兜底输出)
    .DESCRIPTION
        输出结构(用标记行切段, 避免会话名本身含特殊字符时切段错乱):
            TMUX_VERSION=<version>
            TMUX_SESSIONS_BEGIN
            TMUX_SESSION <attached客户端数> <窗口数> <会话名>
            ...
            TMUX_SESSIONS_END
            <tmux ls 人类可读输出>
        会话名放在 format 串最后, 因此可以包含空格; 即便含冒号也不会与分隔符冲突。
    .OUTPUTS
        string
    .EXAMPLE
        Get-TmuxProbeCommand
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # 修 2026-06-27: 避免 `$()` 子 shell 在某些 sshd 配置(非交互式 PATH 不完整)下
    # 输出被吞, 改用 `command -v` 拿绝对路径, 再用绝对路径跑 `tmux -V`。
    # 修 2026-10-01 (v1.3.2 hotfix): `command -v` 失败时多路径穷举, 命中第一个可执行即用。
    $binLookup = 'TMUX_BIN=$(command -v tmux 2>/dev/null || for p in /usr/bin/tmux /usr/local/bin/tmux /snap/bin/tmux /opt/homebrew/bin/tmux /usr/sbin/tmux; do [ -x "$p" ] && echo "$p" && break; done); '
    $versionProbe = 'TMUX_V=$("$TMUX_BIN" -V 2>/dev/null); printf "TMUX_VERSION=%s\n" "${TMUX_V:-}"; '
    # 机器可读段: 老版本 tmux 不支持 -F 时该段为空, 由后续 ls 段兜底
    $machineList = 'printf "TMUX_SESSIONS_BEGIN\n"; "$TMUX_BIN" list-sessions -F "TMUX_SESSION #{session_attached} #{session_windows} #{session_name}" 2>/dev/null; printf "TMUX_SESSIONS_END\n"; '
    $humanList = '"$TMUX_BIN" ls 2>/dev/null; true'

    return ($binLookup + $versionProbe + $machineList + $humanList)
}

function ConvertFrom-TmuxProbeOutput {
    <#
    .SYNOPSIS
        把远程探测输出切分为 版本号 / 机器可读会话行 / tmux ls 行
    .DESCRIPTION
        以 TMUX_SESSIONS_BEGIN / TMUX_SESSIONS_END 标记行切段, 标记之前的行视为版本段,
        标记之后的行视为 ls 段。切段对任何顺序/缺失都容错。
    .PARAMETER Output
        远程探测命令的原始标准输出
    .OUTPUTS
        PSCustomObject(.Version/.SessionLines/.LsLines)
    .EXAMPLE
        ConvertFrom-TmuxProbeOutput -Output $raw
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Output
    )

    $lines = if ($Output) { $Output -split "`r?`n" } else { @() }
    $version = ''
    $sessionLines = [System.Collections.Generic.List[string]]::new()
    $lsLines = [System.Collections.Generic.List[string]]::new()
    $phase = 'version'

    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if (-not $trimmed) { continue }
        if ($trimmed -eq $script:TmuxSessionsBeginMarker) { $phase = 'sessions'; continue }
        if ($trimmed -eq $script:TmuxSessionsEndMarker) { $phase = 'ls'; continue }
        switch ($phase) {
            'version' {
                if ($trimmed -match '^TMUX_VERSION=(.*)$') { $version = $matches[1].Trim() }
            }
            'sessions' { $sessionLines.Add($trimmed) }
            'ls' { $lsLines.Add($trimmed) }
        }
    }

    # 版本号可能带 "tmux " 前缀, 统一去掉只留版本号
    $version = ($version -replace '^tmux\s+', '').Trim()

    return [PSCustomObject]@{
        Version      = $version
        SessionLines = $sessionLines.ToArray()
        LsLines      = $lsLines.ToArray()
    }
}

function ConvertFrom-TmuxSessionFormat {
    <#
    .SYNOPSIS
        解析 tmux list-sessions -F 机器可读行
    .DESCRIPTION
        行格式: TMUX_SESSION <attached客户端数> <窗口数> <会话名>
        会话名位于最后, 因此允许包含空格与冒号; 无法解析的行被忽略(不抛异常)。
    .PARAMETER Lines
        机器可读会话行数组
    .OUTPUTS
        List[PSCustomObject](.Name/.Status/.Windows)
    .EXAMPLE
        ConvertFrom-TmuxSessionFormat -Lines @('TMUX_SESSION 1 2 my session')
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[PSCustomObject]])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$Lines
    )

    $result = [System.Collections.Generic.List[PSCustomObject]]::new()
    if (-not $Lines) { return $result }

    $prefix = $script:TmuxSessionFormatPrefix
    foreach ($line in $Lines) {
        $trimmed = $line.Trim()
        if (-not $trimmed.StartsWith("$prefix ")) { continue }
        if ($trimmed -notmatch '^TMUX_SESSION\s+(?<attached>\d+)\s+(?<windows>\d+)\s+(?<name>.+)$') { continue }
        $attachedClients = [int]$matches['attached']
        $result.Add([PSCustomObject]@{
                Name    = $matches['name'].Trim()
                Status  = if ($attachedClients -gt 0) { 'attached' } else { 'detached' }
                Windows = [int]$matches['windows']
            })
    }

    return $result
}

function ConvertFrom-TmuxLsOutput {
    <#
    .SYNOPSIS
        解析 tmux ls 人类可读输出(容错回退路径)
    .DESCRIPTION
        标准形态: <会话名>: <N> window(s) (created <日期>) [attached]
        容错点:
          - 会话名允许含空格/冒号(名称非贪婪匹配 + 回溯到最后一个 ": N windows" 组合)
          - 冒号后的空格可有可无("my session:1 windows" 同样可解析)
          - (created ...) 可缺失
          - attached 标记大小写不敏感, 缺失即视为 detached
    .PARAMETER Lines
        tmux ls 输出行数组
    .OUTPUTS
        List[PSCustomObject](.Name/.Status/.Windows)
    .EXAMPLE
        ConvertFrom-TmuxLsOutput -Lines @('btop: 1 windows (created Thu Oct 16 22:35:52 2025) [attached]')
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[PSCustomObject]])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$Lines
    )

    $result = [System.Collections.Generic.List[PSCustomObject]]::new()
    if (-not $Lines) { return $result }

    # 会话名用非贪婪匹配, 命中第一个 ": <数字> windows" 组合即止; 含冒号的会话名
    # 由正则回溯自动覆盖(贪婪到最后一个可解析的冒号)。
    # 冒号后允许 0 个或多个空格, 兼容 "name:1 windows" 这种紧凑写法。
    $lsRegex = '^(?<name>.+?):\s*(?<windows>\d+)\s+windows?\b(?<rest>.*)$'
    foreach ($line in $Lines) {
        $trimmed = $line.Trim()
        if (-not $trimmed) { continue }
        if ($trimmed -notmatch $lsRegex) { continue }
        # 注意: 必须先把捕获组取出来, 再做第二次匹配。
        # 用 -match 判断 attached 会重写 $matches, 导致 name/windows 捕获组丢失。
        $name = $matches['name']
        $windows = [int]$matches['windows']
        $rest = $matches['rest']
        $isAttached = [regex]::IsMatch($rest, 'attached', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $result.Add([PSCustomObject]@{
                Name    = $name.Trim()
                Status  = if ($isAttached) { 'attached' } else { 'detached' }
                Windows = $windows
            })
    }

    return $result
}

function Test-TmuxNetworkError {
    <#
    .SYNOPSIS
        判断 SSH 标准错误是否属于网络故障(而非"远端没有 tmux")
    .DESCRIPTION
        命中网络错误特征时, 上层会把 Available 置为 $false 并跳过缓存写入,
        避免 DNS/网络恢复后仍被脏缓存误判。
    .PARAMETER ErrorText
        SSH 标准错误文本
    .OUTPUTS
        bool
    .EXAMPLE
        Test-TmuxNetworkError -ErrorText 'ssh: connect to host x port 22: Connection refused'
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$ErrorText
    )

    if ([string]::IsNullOrEmpty($ErrorText)) { return $false }

    $networkErrorPatterns = @(
        'Could not resolve hostname',
        'Name or service not known',
        'Connection refused',
        'No route to host',
        'Connection timed out',
        'Operation timed out',
        'ssh: connect to host .* port .*: '
    )
    foreach ($pattern in $networkErrorPatterns) {
        if ($ErrorText -match $pattern) { return $true }
    }
    return $false
}

function Invoke-TmuxProbe {
    <#
    .SYNOPSIS
        执行一次远程 tmux 探测, 并把任何异常转换为失败结果。
    .DESCRIPTION
        ssh.exe 缺失 / 进程启动失败 / 远端 shell 异常都可能抛异常,
        此类异常必须降级为"探测失败"结果, 绝不能冒泡到调用方阻断整个菜单。
    .PARAMETER HostName
        远程主机名
    .PARAMETER ConnectTimeout
        SSH 连接超时(秒)
    .OUTPUTS
        PSCustomObject(.Output/.Error/.ExitCode)
    .EXAMPLE
        Invoke-TmuxProbe -HostName 'debian' -ConnectTimeout 5
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $false)]
        [int]$ConnectTimeout = 5
    )

    try {
        $probeCmd = Get-TmuxProbeCommand
        return Invoke-SshCommand -HostName $HostName -RemoteCommand $probeCmd -CaptureOutput `
            -ConnectTimeout $ConnectTimeout -PassThru
    } catch {
        # 降级: 异常转成探测失败结果, 由上层按"无可用会话"处理
        # (TimedOut=$false: 异常路径是启动失败等, 不是等待超时; 超时由正常返回路径携带)
        return [PSCustomObject]@{
            Output   = ''
            Error    = $_.Exception.Message
            ExitCode = -1
            TimedOut = $false
        }
    }
}

function Get-TmuxAvailability {
    <#
    .SYNOPSIS
        探测远程主机 tmux 是否可用(单次 SSH,带 30s TTL 缓存)
    .DESCRIPTION
        同时返回 tmux 版本号、机器可读会话行与 ls 兜底输出, 后续解析无需再次 SSH。
        网络故障时 Available=$false 且跳过缓存写入, 保证恢复后可自愈。
    .PARAMETER HostName
        远程主机名
    .PARAMETER ConnectTimeout
        SSH 连接超时(秒)
    .PARAMETER Force
        跳过 TTL 缓存, 强制重新探测
    .OUTPUTS
        PSCustomObject(.Available/.Version/.RawLs/.RawSessions/.ExitCode/.Error/.NetworkError/.TimedOut/.CheckedAt)
    .EXAMPLE
        Get-TmuxAvailability -HostName 'debian'
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $false)]
        [int]$ConnectTimeout = 5,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    # TTL 缓存: 30 秒内命中直接返回, 过期后重新探测。
    # 兼容旧缓存条目(无 CheckedAt 字段), 视为过期重新探测, 避免脏数据。
    if (-not $Force -and $script:TmuxAvailabilityCache.ContainsKey($HostName)) {
        $cached = $script:TmuxAvailabilityCache[$HostName]
        $hasCheckedAt = $cached.PSObject.Properties.Name -contains 'CheckedAt'
        if ($hasCheckedAt) {
            $cacheAge = [DateTime]::UtcNow - $cached.CheckedAt
            if ($cacheAge.TotalSeconds -lt 30) {
                return $cached
            }
        }
    }

    $result = Invoke-TmuxProbe -HostName $HostName -ConnectTimeout $ConnectTimeout

    $output = if ($result) { $result.Output } else { '' }
    $exitCode = if ($result) { $result.ExitCode } else { -1 }
    $errorOut = if ($result) { $result.Error } else { '' }

    $parsed = ConvertFrom-TmuxProbeOutput -Output $output
    $version = $parsed.Version

    # 兜底: 解析不到版本行时, 看 stderr 里有没有 "tmux X.Y" 字样
    # (某些 sshd 包装器把 tmux -V 输出到 stderr)
    if (-not $version -and $errorOut -and $errorOut -match 'tmux\s+(\d+\.\d+[a-z]?)') {
        $version = $matches[1]
    }

    $isNetworkError = Test-TmuxNetworkError -ErrorText $errorOut

    # TimedOut(2026-10-29 契约扩展): SSH 等待超时(被 Kill)与"远端命令失败"是两回事,
    # 上层据此给出不同提示。旧缓存条目无此字段时按 $false 处理。
    $timedOut = if ($result -and $null -ne $result.PSObject.Properties['TimedOut']) {
        [bool]$result.TimedOut
    } else { $false }

    $info = [PSCustomObject]@{
        Available    = if ($isNetworkError) { $false } else { -not [string]::IsNullOrEmpty($version) }
        Version      = $version
        RawLs        = ($parsed.LsLines -join "`n")
        RawSessions  = ($parsed.SessionLines -join "`n")
        ExitCode     = $exitCode
        Error        = $errorOut
        NetworkError = $isNetworkError
        TimedOut     = $timedOut
        CheckedAt    = [DateTime]::UtcNow
    }

    # 网络错误时跳过缓存写入, 避免脏缓存阻塞后续恢复后的探测
    if (-not $isNetworkError) {
        $script:TmuxAvailabilityCache[$HostName] = $info
    }
    return $info
}

function Get-TmuxSessions {
    <#
    .SYNOPSIS
        获取远程 tmux 会话列表(复用 Get-TmuxAvailability 的探测结果,免第二次 SSH)
    .DESCRIPTION
        解析顺序: 机器可读 list-sessions -F 优先, 解析不到任何会话时回退 tmux ls 容错解析。
        远端无 tmux / 输出为空 / 输出异常时返回空集合, 不抛异常。
        契约扩展(2026-10-29 审计): 返回值同时携带探测结果(Available/Error/ExitCode/
        NetworkError), 让调用方能区分"查询成功但确实没有会话"与"查询失败被折叠成空集合";
        原有键(Sessions/RawOutput/Version)保持不变, 向后兼容。
    .PARAMETER HostName
        远程主机名
    .PARAMETER ConnectTimeout
        SSH 连接超时(秒)
    .PARAMETER Force
        跳过 TTL 缓存, 强制重新探测
    .OUTPUTS
        hashtable(.Sessions/.RawOutput/.Version/.Available/.Error/.ExitCode/.NetworkError/.TimedOut)
    .EXAMPLE
        Get-TmuxSessions -HostName 'debian'
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $false)]
        [int]$ConnectTimeout = 5,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    $info = Get-TmuxAvailability -HostName $HostName -ConnectTimeout $ConnectTimeout -Force:$Force

    # 用 List 承载会话, 保证空结果时 .Count 依然可靠(数组在空值时会被解包成 $null)
    $sessionList = [System.Collections.Generic.List[PSCustomObject]]::new()
    if ($info.Available) {
        $machineLines = @($info.RawSessions -split "`r?`n" | Where-Object { $_ })
        foreach ($session in (ConvertFrom-TmuxSessionFormat -Lines $machineLines)) {
            $sessionList.Add($session)
        }
        if ($sessionList.Count -eq 0) {
            # 老版本 tmux 不支持 -F 或 server 未运行 -> 回退 tmux ls 容错解析
            $lsLines = @($info.RawLs -split "`r?`n" | Where-Object { $_ })
            foreach ($session in (ConvertFrom-TmuxLsOutput -Lines $lsLines)) {
                $sessionList.Add($session)
            }
        }
    }

    return @{
        Sessions  = $sessionList
        RawOutput = $info.RawLs
        Version   = $info.Version
        # 契约扩展(2026-10-29 审计): 携带同一次探测的结果, 供调用方区分
        # "查询成功但没有会话"(Available=$true 且 Sessions 为空)与
        # "查询失败被折叠成空集合"(Available=$false)。只追加, 不影响旧调用方。
        Available    = $info.Available
        Error        = $info.Error
        ExitCode     = $info.ExitCode
        NetworkError = $info.NetworkError
        TimedOut     = $info.TimedOut
    }
}
