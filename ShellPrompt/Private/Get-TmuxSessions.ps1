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
$script:TmuxWindowsBeginMarker = 'TMUX_WINDOWS_BEGIN'
$script:TmuxWindowsEndMarker = 'TMUX_WINDOWS_END'
$script:TmuxPreviewBeginMarker = 'TMUX_PREVIEW_BEGIN'
$script:TmuxPreviewEndMarker = 'TMUX_PREVIEW_END'

function Get-TmuxProbeCommand {
    <#
    .SYNOPSIS
        构建远程 tmux 探测命令(单次 SSH 同时返回版本/机器可读会话/窗口拓扑/预览快照/ls 兜底输出)
    .DESCRIPTION
        输出结构(用标记行切段, 避免会话名本身含特殊字符时切段错乱):
            TMUX_VERSION=<version>
            TMUX_HOME=<远端用户 HOME>
            TMUX_SESSIONS_BEGIN
            TMUX_SESSION <attached客户端数> <窗口数> <创建时间戳> <活动时间戳> <会话名>
            ...
            TMUX_SESSIONS_END
            TMUX_WINDOWS_BEGIN
            TMUX_WSESSION <会话名>
            TMUX_WINDOW <窗口序号> <是否活动窗口> <分屏数> <窗口名>
            TMUX_PANE <窗口序号> <分屏序号> <是否活动分屏> <前台命令> <当前路径>
            ...
            TMUX_WINDOWS_END
            TMUX_PREVIEW_BEGIN
            TMUX_PREVSESSION <会话名>
            TMUX_PREVIEW <预览文本行>
            ...
            TMUX_PREVIEW_END
            <tmux ls 人类可读输出>

        设计约束(为什么这么绕):
          - **零额外往返**: 窗口拓扑 / 预览快照 / HOME 目录全部塞进同一条命令,
            UI 层永远不需要再发第二次 SSH。
          - **自由文本一律放最后**: 会话名/窗口名/路径都可能含空格, 所以每个格式串
            都把"可能含空格"的那个字段放在末尾, 解析时按"末尾吃掉剩余全部"处理;
            会话名含冒号也不冲突(冒号只在分隔符层面有意义, 字段本身不含分隔符)。
          - **逐会话循环**: 会话名含空格时不能用 `for s in $(...)` 拆词, 因此用
            `list-sessions -F "#{session_name}" | while read` 逐行取名, 再用
            `list-windows -t "$s"` / `list-panes -s -t "$s"` 精确取该会话的数据。
          - **老 tmux 容错**: list-windows/list-panes/capture-pane 任一不被支持时,
            对应段只是**空** —— 每条子命令都带 2>/dev/null 且用 `;` 串联, 任何一段失败
            都不会影响其它段, 更不会让整个探测失败。
          - **负载有界**: 预览用 `capture-pane -S -8 | tail -8`, 最多 8 行/会话。
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
    # 版本号 + 远端 HOME 目录(路径折叠 "~" 需要, 单独 SSH 一次不允许, 顺带打印)
    $versionProbe = 'TMUX_V=$("$TMUX_BIN" -V 2>/dev/null); printf "TMUX_VERSION=%s\n" "${TMUX_V:-}"; printf "TMUX_HOME=%s\n" "${HOME:-}"; '
    # 机器可读段: 老版本 tmux 不支持 -F 时该段为空, 由后续 ls 段兜底
    # session_created/session_activity 是较新的格式变量, 老 tmux 遇到**未知格式变量**
    # 会整条命令报错退出(不是输出空串) -> 因此先试完整格式, 拿不到任何输出时
    # 自动退回到三字段旧格式(attached/windows/name), 两种格式解析器都认。
    $machineList = 'printf "TMUX_SESSIONS_BEGIN\n"; TMUX_LS=$("$TMUX_BIN" list-sessions -F "TMUX_SESSION #{session_attached} #{session_windows} #{session_created} #{session_activity} #{session_name}" 2>/dev/null); if [ -n "$TMUX_LS" ]; then printf "%s\n" "$TMUX_LS"; else "$TMUX_BIN" list-sessions -F "TMUX_SESSION #{session_attached} #{session_windows} #{session_name}" 2>/dev/null; fi; printf "TMUX_SESSIONS_END\n"; '
    # 窗口拓扑段: 会话名 -> 窗口列表 + 分屏详情(命令/路径)。
    # list-panes -s 列出会话内**所有**窗口的分屏, 用 window_index 关联回窗口;
    # pane_id(%N) 一并带出, 预览快照用它做无歧义定位(会话名含冒号时仍能命中)。
    $windowList = 'printf "TMUX_WINDOWS_BEGIN\n"; "$TMUX_BIN" list-sessions -F "#{session_name}" 2>/dev/null | while IFS= read -r TMUX_S || [ -n "$TMUX_S" ]; do [ -n "$TMUX_S" ] || continue; printf "TMUX_WSESSION %s\n" "$TMUX_S"; "$TMUX_BIN" list-windows -t "$TMUX_S" -F "TMUX_WINDOW #{window_index} #{window_active} #{window_panes} #{window_name}" 2>/dev/null; "$TMUX_BIN" list-panes -s -t "$TMUX_S" -F "TMUX_PANE #{window_index} #{pane_index} #{pane_active} #{pane_current_command} #{pane_current_path}" 2>/dev/null; done; printf "TMUX_WINDOWS_END\n"; '
    # 预览快照段: 每个会话"活动窗口的活动分屏"的末尾 8 行纯文本。
    # 定位方式: 先取活动窗口序号, 再在所有分屏里挑 (窗口序号匹配 且 pane_active=1) 的
    # pane_id, 最后用 %N 定位 capture-pane —— 全程不依赖会话名, 名字含冒号也安全。
    # tail -8 保证负载有界(不加 -S 时 capture-pane 只给可见区, -S -8 会带上历史)。
    $previewList = 'printf "TMUX_PREVIEW_BEGIN\n"; "$TMUX_BIN" list-sessions -F "#{session_name}" 2>/dev/null | while IFS= read -r TMUX_S || [ -n "$TMUX_S" ]; do [ -n "$TMUX_S" ] || continue; TMUX_AW=$("$TMUX_BIN" list-windows -t "$TMUX_S" -F "#{window_index} #{window_active}" 2>/dev/null | while IFS= read -r TMUX_WL; do case "$TMUX_WL" in *\ 1) printf "%s" "${TMUX_WL%% *}"; break;; esac; done); [ -n "$TMUX_AW" ] || continue; TMUX_AP=$("$TMUX_BIN" list-panes -s -t "$TMUX_S" -F "#{window_index} #{pane_active} #{pane_id}" 2>/dev/null | while IFS=" " read -r TMUX_PW TMUX_PA TMUX_PID; do if [ "$TMUX_PA" = "1" ] && [ "$TMUX_PW" = "$TMUX_AW" ]; then printf "%s" "$TMUX_PID"; break; fi; done); [ -n "$TMUX_AP" ] || continue; printf "TMUX_PREVSESSION %s\n" "$TMUX_S"; "$TMUX_BIN" capture-pane -p -t "$TMUX_AP" -S -8 2>/dev/null | tail -8 | while IFS= read -r TMUX_L || [ -n "$TMUX_L" ]; do printf "TMUX_PREVIEW %s\n" "$TMUX_L"; done; done; printf "TMUX_PREVIEW_END\n"; '
    $humanList = '"$TMUX_BIN" ls 2>/dev/null; true'

    return ($binLookup + $versionProbe + $machineList + $windowList + $previewList + $humanList)
}

function ConvertFrom-TmuxProbeOutput {
    <#
    .SYNOPSIS
        把远程探测输出切分为 版本号 / HOME / 机器可读会话行 / 窗口拓扑行 / 预览行 / tmux ls 行
    .DESCRIPTION
        以 TMUX_SESSIONS_BEGIN / TMUX_SESSIONS_END / TMUX_WINDOWS_BEGIN / TMUX_WINDOWS_END /
        TMUX_PREVIEW_BEGIN / TMUX_PREVIEW_END 标记行切段。**标记行优先于阶段**: 任何标记
        出现都强制切换阶段, 因此老版本输出(只有 SESSIONS 段)与新版本输出都能正确切分,
        任何顺序/缺失都容错。
        TMUX_HOME 出现在版本段, 用于路径折叠("~"), 避免为此单独发一次 SSH。
    .PARAMETER Output
        远程探测命令的原始标准输出
    .OUTPUTS
        PSCustomObject(.Version/.HomePath/.SessionLines/.WindowLines/.PreviewLines/.LsLines)
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
    $homePath = ''
    $sessionLines = [System.Collections.Generic.List[string]]::new()
    $windowLines = [System.Collections.Generic.List[string]]::new()
    $previewLines = [System.Collections.Generic.List[string]]::new()
    $lsLines = [System.Collections.Generic.List[string]]::new()
    $phase = 'version'

    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if (-not $trimmed) { continue }

        # 预览段特殊处理: 内容行必须**原样**保留(前导缩进有意义), 且内容行本身
        # 可能恰好长得像某个标记行 —— 因此预览段内只认 PREVIEW_END 作为结束标记,
        # 其余一律当作内容, 绝不误切段。
        if ($phase -eq 'preview') {
            if ($trimmed -eq $script:TmuxPreviewEndMarker) { $phase = 'ls'; continue }
            # 会话头优先: 'TMUX_PREVSESSION' 也以 'TMUX_PREVIEW' 开头, 顺序不能反
            if ($trimmed.StartsWith('TMUX_PREVSESSION')) { $previewLines.Add($trimmed); continue }
            if ($line.StartsWith('TMUX_PREVIEW')) { $previewLines.Add(($line -replace "`r$", '')) }
            continue
        }

        # 标记行优先: 出现即切段(缺失标记的老输出按"默认落到 ls 段"容错)
        if ($trimmed -eq $script:TmuxSessionsBeginMarker) { $phase = 'sessions'; continue }
        if ($trimmed -eq $script:TmuxSessionsEndMarker) { $phase = 'ls'; continue }
        if ($trimmed -eq $script:TmuxWindowsBeginMarker) { $phase = 'windows'; continue }
        if ($trimmed -eq $script:TmuxWindowsEndMarker) { $phase = 'ls'; continue }
        if ($trimmed -eq $script:TmuxPreviewBeginMarker) { $phase = 'preview'; continue }
        if ($trimmed -eq $script:TmuxPreviewEndMarker) { $phase = 'ls'; continue }
        switch ($phase) {
            'version' {
                if ($trimmed -match '^TMUX_VERSION=(.*)$') { $version = $matches[1].Trim() }
                elseif ($trimmed -match '^TMUX_HOME=(.*)$') { $homePath = $matches[1].Trim() }
            }
            'sessions' { $sessionLines.Add($trimmed) }
            'windows' { $windowLines.Add($trimmed) }
            'ls' { $lsLines.Add($trimmed) }
        }
    }

    # 版本号可能带 "tmux " 前缀, 统一去掉只留版本号
    $version = ($version -replace '^tmux\s+', '').Trim()

    return [PSCustomObject]@{
        Version      = $version
        HomePath     = $homePath
        SessionLines = $sessionLines.ToArray()
        WindowLines  = $windowLines.ToArray()
        PreviewLines = $previewLines.ToArray()
        LsLines      = $lsLines.ToArray()
    }
}

function ConvertFrom-TmuxSessionFormat {
    <#
    .SYNOPSIS
        解析 tmux list-sessions -F 机器可读行
    .DESCRIPTION
        新格式行: TMUX_SESSION <attached客户端数> <窗口数> <创建时间戳> <活动时间戳> <会话名>
        旧格式行: TMUX_SESSION <attached客户端数> <窗口数> <会话名>  (老 tmux / 降级兜底)
        两种格式都要能解析: 创建/活动时间戳是**可选组**, 缺失时按"未知"(0)处理。
        会话名位于最后, 因此允许包含空格与冒号; 无法解析的行被忽略(不抛异常)。
    .PARAMETER Lines
        机器可读会话行数组
    .OUTPUTS
        List[PSCustomObject](.Name/.Status/.Windows/.Created/.Activity)
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
        # 可选组: 创建/活动时间戳(两位数字)存在时一并取出;
        # 若"最后一段全是数字"导致组不匹配, 正则会回退到"名字吃掉剩余全部"的分支,
        # 因此纯数字会话名(如 "2024")也不会被误当成时间戳。
        if ($trimmed -notmatch '^TMUX_SESSION\s+(?<attached>\d+)\s+(?<windows>\d+)(?:\s+(?<created>\d+)\s+(?<activity>\d+))?\s+(?<name>.+)$') { continue }
        $attachedClients = [int]$matches['attached']
        $created = 0
        $activity = 0
        if (-not [string]::IsNullOrEmpty($matches['created'])) { $created = [long]$matches['created'] }
        if (-not [string]::IsNullOrEmpty($matches['activity'])) { $activity = [long]$matches['activity'] }
        $result.Add([PSCustomObject]@{
                Name     = $matches['name'].Trim()
                Status   = if ($attachedClients -gt 0) { 'attached' } else { 'detached' }
                Windows  = [int]$matches['windows']
                Created  = $created
                Activity = $activity
            })
    }

    return $result
}

function ConvertFrom-TmuxWindowFormat {
    <#
    .SYNOPSIS
        解析窗口拓扑段(TMUX_WSESSION / TMUX_WINDOW / TMUX_PANE 行)
    .DESCRIPTION
        行格式:
            TMUX_WSESSION <会话名>            (会话名自由文本, 吃掉整行剩余部分)
            TMUX_WINDOW <窗口序号> <活动标记> <分屏数> <窗口名>   (窗口名吃掉剩余部分)
            TMUX_PANE  <窗口序号> <分屏序号> <活动标记> <前台命令> <当前路径>
        分屏信息按窗口序号归属; 窗口的 Command/Path 取该窗口**活动分屏**的值
        (没有活动分屏时取第一个分屏)。任何畸形行都被跳过, 绝不抛异常。
    .PARAMETER Lines
        窗口拓扑段原始行数组
    .OUTPUTS
        List[PSCustomObject](.Session/.Index/.Name/.Active/.Panes/.Command/.Path)
    .EXAMPLE
        ConvertFrom-TmuxWindowFormat -Lines @('TMUX_WSESSION work', 'TMUX_WINDOW 0 1 2 bash')
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

    $currentSession = ''
    $windows = [System.Collections.Generic.List[PSCustomObject]]::new()
    # 窗口序号 -> 该窗口的分屏列表(命令/路径)
    $panesByWindow = @{}

    foreach ($line in $Lines) {
        $trimmed = $line.Trim()
        if (-not $trimmed) { continue }

        if ($trimmed -match '^TMUX_WSESSION\s+(?<name>.+)$') {
            $currentSession = $matches['name'].Trim()
            continue
        }

        if ($trimmed -match '^TMUX_WINDOW\s+(?<index>\d+)\s+(?<active>\d+)\s+(?<panes>\d+)\s*(?<name>.*)$') {
            $windows.Add([PSCustomObject]@{
                    Session = $currentSession
                    Index   = [int]$matches['index']
                    Name    = $matches['name'].Trim()
                    Active  = ([int]$matches['active'] -gt 0)
                    Panes   = [int]$matches['panes']
                    Command = ''
                    Path    = ''
                })
            continue
        }

        if ($trimmed.StartsWith('TMUX_PANE ')) {
            # 字段: <窗口序号> <分屏序号> <活动标记> <前台命令> <当前路径...>
            # 路径可能含空格 -> 用 -split 的上限把"剩余全部"留给最后一个字段。
            # 前台命令按"单个不含空白的词"处理(tmux 的 pane_current_command 实践如此);
            # 万一它含空格, 退化结果是命令被截断 + 路径多出前缀, 不抛异常。
            $parts = @($trimmed.Substring('TMUX_PANE '.Length).Trim() -split '\s+', 5)
            if ($parts.Count -lt 4) { continue }
            $windex = 0
            $pindex = 0
            $isActive = $false
            if (-not [int]::TryParse($parts[0], [ref]$windex)) { continue }
            if (-not [int]::TryParse($parts[1], [ref]$pindex)) { continue }
            if ($parts[2] -eq '1') { $isActive = $true }
            $command = $parts[3]
            $path = ''
            if ($parts.Count -ge 5) { $path = $parts[4].Trim() }
            $paneInfo = [PSCustomObject]@{
                Index   = $pindex
                Active  = $isActive
                Command = $command
                Path    = $path
            }
            # 键必须带会话名: 不同会话的窗口序号会重复(都从 0 开始)
            $paneKey = "$currentSession|$windex"
            if (-not $panesByWindow.ContainsKey($paneKey)) {
                $panesByWindow[$paneKey] = [System.Collections.Generic.List[PSCustomObject]]::new()
            }
            $panesByWindow[$paneKey].Add($paneInfo)
            continue
        }
        # 其它行(垃圾/未来扩展)直接忽略
    }

    # 把分屏信息合并回窗口: 活动分屏优先, 否则取第一个
    foreach ($window in $windows) {
        $paneKey = "$($window.Session)|$($window.Index)"
        if ($panesByWindow.ContainsKey($paneKey)) {
            $panes = @($panesByWindow[$paneKey])
            $chosen = @($panes | Where-Object { $_.Active })
            if ($chosen.Count -eq 0) { $chosen = @($panes[0]) }
            $window.Command = [string]$chosen[0].Command
            $window.Path = [string]$chosen[0].Path
        }
        $result.Add($window)
    }

    return $result
}

function ConvertFrom-TmuxPreviewFormat {
    <#
    .SYNOPSIS
        解析预览快照段(TMUX_PREVSESSION / TMUX_PREVIEW 行)
    .DESCRIPTION
        行格式:
            TMUX_PREVSESSION <会话名>   (会话名吃掉整行剩余部分, 可含空格)
            TMUX_PREVIEW <预览文本行>   (文本行吃掉整行剩余部分, 可为空)
        没有会话头的预览行会被忽略; 文本原样返回(ANSI 转义在视图模型层剥离)。
    .PARAMETER Lines
        预览段原始行数组
    .OUTPUTS
        List[PSCustomObject](.Session/.Lines)
    .EXAMPLE
        ConvertFrom-TmuxPreviewFormat -Lines @('TMUX_PREVSESSION work', 'TMUX_PREVIEW $ ls')
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

    $currentSession = ''
    $buffer = [System.Collections.Generic.List[string]]::new()

    foreach ($line in $Lines) {
        # 会话头: 名字吃掉整行剩余部分(可含空格)
        $trimmed = $line.Trim()
        if (-not $trimmed) { continue }

        if ($trimmed -match '^TMUX_PREVSESSION\s+(?<name>.+)$') {
            if ($currentSession) {
                $result.Add([PSCustomObject]@{ Session = $currentSession; Lines = $buffer.ToArray() })
            }
            $currentSession = $matches['name'].Trim()
            $buffer = [System.Collections.Generic.List[string]]::new()
            continue
        }

        # 预览正文行: **保留前导缩进**(只去掉标记后的那一个分隔空格与尾部空白)
        if ($line.StartsWith('TMUX_PREVIEW')) {
            $text = $line.Substring('TMUX_PREVIEW'.Length)
            # 只剥掉标记自带的那一个分隔空格; 其后的缩进是快照内容的一部分
            if ($text.StartsWith(' ')) { $text = $text.Substring(1) }
            $buffer.Add(($text -replace '\s+$', ''))
            continue
        }
        # 其它行忽略
    }

    if ($currentSession) {
        $result.Add([PSCustomObject]@{ Session = $currentSession; Lines = $buffer.ToArray() })
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
        HomePath     = $parsed.HomePath
        RawLs        = ($parsed.LsLines -join "`n")
        RawSessions  = ($parsed.SessionLines -join "`n")
        RawWindows   = ($parsed.WindowLines -join "`n")
        RawPreview   = ($parsed.PreviewLines -join "`n")
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

    # 窗口拓扑 / 预览快照: 与会话同一次 SSH 往返里取回, 这里只做纯解析
    # 注意: 函数返回 List 会在管道里被展开成数组, 空集合则展开成 $null ——
    # 因此统一用 @() 包一层, 保证下游永远是"数组(可能为空)"。
    $windowLines = @($info.RawWindows -split "`r?`n" | Where-Object { $_ })
    $allWindows = @(ConvertFrom-TmuxWindowFormat -Lines $windowLines)
    $previewLines = @($info.RawPreview -split "`r?`n" | Where-Object { $_ })
    $allPreviews = @(ConvertFrom-TmuxPreviewFormat -Lines $previewLines)
    $homePath = [string]$info.HomePath

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

    # ---- 把窗口拓扑 / 预览快照挂到对应会话上(纯内存, 不再发 SSH) ----
    # 为什么在这里挂而不是在视图模型里查: 视图模型只拿到状态对象,
    # 没有窗口/预览数据源; 在数据层挂好, 上层就彻底不需要第二次网络访问。
    foreach ($session in $sessionList) {
        $sessionWindows = @($allWindows | Where-Object { $_.Session -eq $session.Name })
        $sessionPreview = @($allPreviews | Where-Object { $_.Session -eq $session.Name })
        $previewText = @()
        if ($sessionPreview.Count -gt 0) { $previewText = @($sessionPreview[0].Lines) }
        # 用 Add-Member 而不是重新构造对象: 保留解析器给出的字段形状(Name/Status/Windows/...)
        $session | Add-Member -NotePropertyName 'WindowList' -NotePropertyValue $sessionWindows -Force
        $session | Add-Member -NotePropertyName 'PreviewLines' -NotePropertyValue $previewText -Force
        $session | Add-Member -NotePropertyName 'HomePath' -NotePropertyValue $homePath -Force
        if (-not ($session.PSObject.Properties.Name -contains 'Created')) {
            $session | Add-Member -NotePropertyName 'Created' -NotePropertyValue ([long]0) -Force
        }
        if (-not ($session.PSObject.Properties.Name -contains 'Activity')) {
            $session | Add-Member -NotePropertyName 'Activity' -NotePropertyValue ([long]0) -Force
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
        # 契约扩展(2026-11 TUI 数据层): 窗口拓扑 / 预览快照 / 远端 HOME
        # —— 全部来自**同一次** SSH 往返, 视图层不再需要任何额外网络访问。
        Windows      = $allWindows
        Previews     = $allPreviews
        HomePath     = $homePath
    }
}
