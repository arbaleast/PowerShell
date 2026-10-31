# Get-SshHostDetail.ps1 - 远端主机详情探测服务(仪表盘右侧卡片的**取数端**)
#
# 背景 (2026-10-31 sss 仪表盘重构):
#   仪表盘右侧 Connection / Activity 卡片需要**真实**远端数据(远端主机名 / uptime /
#   负载 / tmux 会话数 / 连通性)。这类数据只能通过网络拿到, 因此有两条硬约束:
#     1. **UI 线程绝不调用本函数** —— 由编排层经 Start-SshHostDetailTask 丢到后台线程,
#        左侧列表的键盘交互不依赖本函数返回;
#     2. **失败不抛业务异常** —— 一律返回带 ErrorCode 的对象, 让上层如实呈现
#        "加载中 / 无数据 / 失败" 三态; 禁止为了把卡片填满而伪造数据。
#
# 一次 SSH 往返拿全部字段: 组合命令用标记行(HOSTNAME= / UPTIME= / LOAD= / TMUX=)
# 分段 —— 远端输出里即便出现同名文本, 也只认"行首标记"这一种形态, 切段不会错乱。
# 复用既有 SSH 执行层(Get-SshArgs / Invoke-SshCaptureOutput), 不重写任何 SSH 逻辑。
#
# 错误码口径与 Get-TmuxSessions.ps1 的 Test-TmuxNetworkError / 认证关键字判定对齐
# (E_SSH_TIMEOUT / E_SSH_UNREACHABLE / E_SSH_AUTH / E_SSH_FAILED / E_UNKNOWN),
# 但**不直接调用**该文件里的函数: 本文件要能在后台线程作业里独立 dot-source,
# 不带入 tmux 会话缓存的整套脚本级状态。

function Get-SshHostDetailCommand {
    <#
    .SYNOPSIS
        构建"一次往返拿全部详情"的远端组合命令。

    .DESCRIPTION
        输出为标记行文本, 由 ConvertFrom-SshHostDetailOutput 解析:
            HOSTNAME=<远端 hostname>
            UPTIME=<uptime -p 原文, 无 -p 支持时回退 uptime>
            LOAD=</proc/loadavg 前三段>
            TMUX=<tmux 会话数 | unknown>
        tmux 缺失时输出 TMUX=unknown(不是 0): "远端没有 tmux" 与 "远端有 tmux 但
        当前 0 个会话" 是两件事, 前者是"无法判定"($null), 后者才是 0。

    .OUTPUTS
        string

    .EXAMPLE
        Get-SshHostDetailCommand
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # 全部写法都是 POSIX sh + 常见 coreutils; 任何一段缺失只让对应标记行为空, 不中断命令。
    # 注意: 本字符串最终作为**单个 argv** 交给 ssh, 内层双引号由 ConvertTo-SshArgumentLine
    # 按 CRT 规则转义, 与产出 tmux 探测命令的 Get-TmuxProbeCommand 同一套写法。
    $parts = @(
        'printf "HOSTNAME=%s\n" "$(hostname 2>/dev/null)"'
        'printf "UPTIME=%s\n" "$(uptime -p 2>/dev/null || uptime 2>/dev/null)"'
        'printf "LOAD=%s\n" "$(head -1 /proc/loadavg 2>/dev/null | cut -d" " -f1-3)"'
        'TMUX_BIN=$(command -v tmux 2>/dev/null)'
        'if [ -n "$TMUX_BIN" ]; then printf "TMUX=%s\n" "$("$TMUX_BIN" list-sessions 2>/dev/null | wc -l)"; else printf "TMUX=unknown\n"; fi'
        'true'
    )
    return ($parts -join '; ')
}

function ConvertFrom-SshHostDetailOutput {
    <#
    .SYNOPSIS
        解析远端组合命令的标记行输出。

    .DESCRIPTION
        只认行首标记(^HOSTNAME= / ^UPTIME= / ^LOAD= / ^TMUX=), 其余行忽略。
        任何一段缺失都退化为空值/ $null, **绝不用默认值冒充真实数据**:
          - TmuxSessionCount: 只有远端明确回了整数才是整数, 'unknown' 或缺失一律 $null。

    .PARAMETER Output
        远端命令的标准输出原文。

    .OUTPUTS
        PSCustomObject(.RemoteHostname/.Uptime/.Load/.TmuxSessionCount/.HasMarker)

    .EXAMPLE
        ConvertFrom-SshHostDetailOutput -Output "HOSTNAME=deb`nUPTIME=up 3 days`nLOAD=0.1 0.2 0.3`nTMUX=2"
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Output
    )

    $remoteHostname = ''
    $uptime = ''
    $load = ''
    $tmuxSessionCount = $null
    $hasMarker = $false

    if (-not [string]::IsNullOrEmpty($Output)) {
        foreach ($line in ($Output -split "`r?`n")) {
            $trimmed = $line.Trim()
            if (-not $trimmed) { continue }
            if ($trimmed -match '^HOSTNAME=(.*)$') {
                $remoteHostname = $matches[1].Trim()
                $hasMarker = $true
                continue
            }
            if ($trimmed -match '^UPTIME=(.*)$') {
                $uptime = $matches[1].Trim()
                $hasMarker = $true
                continue
            }
            if ($trimmed -match '^LOAD=(.*)$') {
                $load = $matches[1].Trim()
                $hasMarker = $true
                continue
            }
            if ($trimmed -match '^TMUX=(.*)$') {
                $hasMarker = $true
                $rawCount = $matches[1].Trim()
                # 'unknown' = 远端没有 tmux 可执行文件 ⇒ 无法判定, 不是"0 个会话"
                $parsedCount = 0
                if ([int]::TryParse($rawCount, [ref]$parsedCount) -and $parsedCount -ge 0) {
                    $tmuxSessionCount = $parsedCount
                }
                continue
            }
        }
    }

    return [PSCustomObject]@{
        RemoteHostname   = $remoteHostname
        Uptime           = $uptime
        Load             = $load
        TmuxSessionCount = $tmuxSessionCount
        HasMarker        = $hasMarker
    }
}

function Test-SshHostDetailAuthError {
    <#
    .SYNOPSIS
        判断 SSH 标准错误是否属于认证/主机密钥类失败。

    .DESCRIPTION
        关键字口径与仓库既有 SSH 失败分类保持一致(见 Get-TmuxSessions.ps1 的网络
        错误判定): 认证失败与"网络不可达"要给用户不同的行动指引, 不能混为一谈。

    .PARAMETER ErrorText
        SSH 标准错误文本。

    .OUTPUTS
        bool

    .EXAMPLE
        Test-SshHostDetailAuthError -ErrorText 'Permission denied (publickey).'
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$ErrorText
    )

    if ([string]::IsNullOrEmpty($ErrorText)) { return $false }

    $patterns = @(
        'Permission denied'
        'Host key verification failed'
        'Too many authentication failures'
        'Authentication failed'
        'no matching host key type'
        'REMOTE HOST IDENTIFICATION HAS CHANGED'
    )
    foreach ($pattern in $patterns) {
        if ($ErrorText -match $pattern) { return $true }
    }
    return $false
}

function Test-SshHostDetailNetworkError {
    <#
    .SYNOPSIS
        判断 SSH 标准错误是否属于网络不可达类失败。

    .DESCRIPTION
        模式列表与 Get-TmuxSessions.ps1 的 Test-TmuxNetworkError 对齐(DNS / 拒绝 /
        无路由 / 超时), 保证同一类故障在两个界面上的分类一致。

    .PARAMETER ErrorText
        SSH 标准错误文本。

    .OUTPUTS
        bool

    .EXAMPLE
        Test-SshHostDetailNetworkError -ErrorText 'ssh: connect to host x port 22: Connection refused'
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$ErrorText
    )

    if ([string]::IsNullOrEmpty($ErrorText)) { return $false }

    $patterns = @(
        'Could not resolve hostname'
        'Name or service not known'
        'Connection refused'
        'No route to host'
        'Connection timed out'
        'Operation timed out'
        'ssh: connect to host .* port .*: '
    )
    foreach ($pattern in $patterns) {
        if ($ErrorText -match $pattern) { return $true }
    }
    return $false
}

function Get-SshHostDetailErrorCode {
    <#
    .SYNOPSIS
        把探测结果折算成用户可见错误码。

    .DESCRIPTION
        判定顺序(短路): 超时 > 认证 > 网络 > 远端非 0 退出。退出码 0 且未超时返回空串
        (成功)。只做分类, 不产生任何文案 —— 文案由调用方按界面语言拼装。

    .PARAMETER TimedOut
        SSH 等待是否超时(被 Kill)。

    .PARAMETER ExitCode
        ssh 退出码(0 = 成功)。

    .PARAMETER ErrorText
        SSH 标准错误文本。

    .OUTPUTS
        string

    .EXAMPLE
        Get-SshHostDetailErrorCode -TimedOut $false -ExitCode 255 -ErrorText 'Permission denied (publickey).'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [bool]$TimedOut = $false,

        [Parameter(Mandatory = $false)]
        [int]$ExitCode = 0,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$ErrorText = ''
    )

    if ($TimedOut) { return 'E_SSH_TIMEOUT' }
    if ($ExitCode -eq 0) { return '' }
    if (Test-SshHostDetailAuthError -ErrorText $ErrorText) { return 'E_SSH_AUTH' }
    if (Test-SshHostDetailNetworkError -ErrorText $ErrorText) { return 'E_SSH_UNREACHABLE' }
    return 'E_SSH_FAILED'
}

function ConvertTo-SshHostDetailResult {
    <#
    .SYNOPSIS
        构造统一的详情结果对象(Get-SshHostDetail / Receive-SshHostDetailTask 共用)。

    .DESCRIPTION
        字段形状是 UI 层与后台作业层的**共同契约**, 只在这里定义一次:
        无论成功、失败、未完成, 调用方拿到的都是同一套字段, 不必分支出错类型。
        ErrorMessage 会进状态栏 / 卡片单行, 因此在这里统一折叠换行并截断。

    .PARAMETER HostName
        查询目标主机名(入参原样回填)。

    .PARAMETER Status
        Online / Offline / Unknown。

    .PARAMETER ErrorCode
        失败错误码(成功为空串)。

    .PARAMETER ErrorMessage
        失败原因摘要(自动折叠空白并截断到 200 字符)。

    .PARAMETER RemoteHostname
        远端 hostname 输出(未拿到为空串)。

    .PARAMETER Uptime
        uptime 原文(未拿到为空串)。

    .PARAMETER Load
        负载前三段(未拿到为空串)。

    .PARAMETER TmuxSessionCount
        远端 tmux 会话数; 无法判定时 $null(不填 0)。

    .PARAMETER ElapsedMs
        本次探测耗时(毫秒)。

    .PARAMETER CheckedAt
        探测完成时刻(本地时间)。

    .OUTPUTS
        PSCustomObject

    .EXAMPLE
        ConvertTo-SshHostDetailResult -HostName 'deb' -Status 'Online' -TmuxSessionCount 2
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Online', 'Offline', 'Unknown')]
        [string]$Status = 'Unknown',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$ErrorCode = '',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$ErrorMessage = '',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$RemoteHostname = '',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Uptime = '',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Load = '',

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$TmuxSessionCount = $null,

        [Parameter(Mandatory = $false)]
        [int]$ElapsedMs = 0,

        [Parameter(Mandatory = $false)]
        [datetime]$CheckedAt = (Get-Date)
    )

    $statusText = switch ($Status) {
        'Online' { '在线' }
        'Offline' { '离线' }
        default { '未知' }
    }

    # 失败摘要进单行展示位: 换行会撕坏布局, 过长会挤掉其他卡片字段
    $safeMessage = ''
    if (-not [string]::IsNullOrEmpty($ErrorMessage)) {
        $safeMessage = ($ErrorMessage -replace '\s+', ' ').Trim()
        if ($safeMessage.Length -gt 200) {
            $safeMessage = $safeMessage.Substring(0, 200)
        }
    }

    return [PSCustomObject]@{
        Host             = $HostName
        Status           = $Status
        StatusText       = $statusText
        ErrorCode        = $ErrorCode
        ErrorMessage     = $safeMessage
        RemoteHostname   = $RemoteHostname
        Uptime           = $Uptime
        Load             = $Load
        TmuxSessionCount = $TmuxSessionCount
        ElapsedMs        = $ElapsedMs
        CheckedAt        = $CheckedAt
    }
}

function Get-SshHostDetail {
    <#
    .SYNOPSIS
        探测一台 SSH 主机的远端详情(单次往返, 失败不抛业务异常)。

    .DESCRIPTION
        一次 ssh 往返拿齐: 连通性(Status) / 远端主机名 / uptime / 负载 / tmux 会话数。
        任何失败(超时、网络、认证、远端非 0 退出、ssh.exe 无法启动)都换算成
        Status + ErrorCode + ErrorMessage 返回, 由上层决定怎么展示。

        **不要在 UI 线程直接调用**: 单次等待窗口可达 TimeoutSec+10 秒。UI 侧请用
        Start-SshHostDetailTask 提交到后台线程, 再用 Receive-SshHostDetailTask 轮询。

    .PARAMETER HostName
        目标主机名(必须是 ssh config 里的别名或合法主机名)。

    .PARAMETER Port
        SSH 端口; 0(默认) = 不覆盖, 沿用 ~/.ssh/config 与 ssh 默认值。

    .PARAMETER User
        登录用户; 空(默认) = 不覆盖, 沿用 ~/.ssh/config 与 ssh 默认值。

    .PARAMETER TimeoutSec
        连接/等待超时(秒), 同时作为 ssh -o ConnectTimeout 的值。默认 6。

    .PARAMETER ProbeScript
        测试注入点: 给出时**不执行真实 SSH**, 改为调用该脚本块。脚本块收到一个
        参数哈希表(HostName/Port/User/TimeoutSec/ArgumentList), 需返回与
        Invoke-SshCaptureOutput -PassThru 同形状的对象
        (Output/Error/ExitCode/TimedOut)。生产路径不传此参数。

    .OUTPUTS
        PSCustomObject(Host/Status/StatusText/ErrorCode/ErrorMessage/RemoteHostname/
        Uptime/Load/TmuxSessionCount/ElapsedMs/CheckedAt)

    .EXAMPLE
        $detail = Get-SshHostDetail -HostName 'deb' -TimeoutSec 5
        if ($detail.Status -eq 'Online') { $detail.Uptime }

    .EXAMPLE
        $detail = Get-SshHostDetail -HostName 'deb' -ProbeScript { param($a) [PSCustomObject]@{ Output = 'HOSTNAME=deb'; Error = ''; ExitCode = 0; TimedOut = $false } }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 65535)]
        [int]$Port = 0,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$User = '',

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 120)]
        [int]$TimeoutSec = 6,

        [Parameter(Mandatory = $false)]
        [scriptblock]$ProbeScript
    )

    # ---- 入参护栏: 非法即抛终止错误(与"探测失败"区分: 这是调用方编程错误) ----
    # 主机名与 ~/.ssh/config 别名都会作为 ssh 的 destination, 必须过白名单,
    # 否则 "-oProxyCommand=..." 形态会被 ssh 当成选项在本机执行(见 Test-SshHostName)。
    if (-not (Test-SshHostName -HostName $HostName)) {
        throw "非法主机名: '$HostName'。仅允许字母、数字、点、短横线和下划线, 且不得以 '-' 开头。"
    }
    # User 会拼成 `ssh -l <user>` 的实参, 同一道白名单护栏不可省。
    if ($User -and $User -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
        throw "非法用户名: '$User'。仅允许字母、数字、点、短横线和下划线, 且不得以 '-' 开头。"
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $raw = $null
    $probeFailure = ''

    try {
        $sshArgs = Get-SshArgs -HostName $HostName -RemoteCommand (Get-SshHostDetailCommand) `
            -CaptureOutput -ConnectTimeout $TimeoutSec

        # Port/User 覆盖参数必须插在 destination **之前**(ssh 只接受前置 -p/-l);
        # 调用方没给就完全不插入, 保持 ~/.ssh/config 的既有语义。
        if ($Port -gt 0 -or $User) {
            $override = [System.Collections.ArrayList]::new()
            if ($User) {
                [void]$override.Add('-l')
                [void]$override.Add($User)
            }
            if ($Port -gt 0) {
                [void]$override.Add('-p')
                [void]$override.Add([string]$Port)
            }
            $destinationIndex = $sshArgs.IndexOf($HostName)
            if ($destinationIndex -ge 0) {
                $sshArgs.InsertRange($destinationIndex, $override)
            }
        }

        if ($ProbeScript) {
            # 注入点同时把最终参数列表交出去, 测试可据此断言 -p/-l 的位置与转义
            $probeContext = @{
                HostName     = $HostName
                Port         = $Port
                User         = $User
                TimeoutSec   = $TimeoutSec
                ArgumentList = $sshArgs
            }
            $raw = & $ProbeScript $probeContext
        }
        else {
            $raw = Invoke-SshCaptureOutput -ArgumentList $sshArgs -ConnectTimeout $TimeoutSec -PassThru
        }
    }
    catch {
        # ssh.exe 缺失 / 进程无法创建 / 注入脚本抛错: 归 "无法执行探测"(Unknown),
        # 与"连上了但失败"(Offline)分开 —— 前者不是主机的状态, 是本机执行环境的问题。
        $probeFailure = $_.Exception.Message
    }

    $stopwatch.Stop()
    $elapsedMs = [int]$stopwatch.ElapsedMilliseconds

    if ($probeFailure) {
        return ConvertTo-SshHostDetailResult -HostName $HostName -Status 'Unknown' `
            -ErrorCode 'E_UNKNOWN' -ErrorMessage "探测无法执行: $probeFailure" -ElapsedMs $elapsedMs
    }

    # ---- 归一化探测结果(缺字段按最保守的失败语义处理, 不乐观假定成功) ----
    $output = ''
    $errorText = ''
    $exitCode = -1
    $timedOut = $false
    if ($null -ne $raw) {
        if ($null -ne $raw.PSObject.Properties['Output']) { $output = [string]$raw.Output }
        if ($null -ne $raw.PSObject.Properties['Error']) { $errorText = [string]$raw.Error }
        if ($null -ne $raw.PSObject.Properties['ExitCode']) { $exitCode = [int]$raw.ExitCode }
        if ($null -ne $raw.PSObject.Properties['TimedOut']) { $timedOut = [bool]$raw.TimedOut }
    }

    $parsed = ConvertFrom-SshHostDetailOutput -Output $output
    $errorCode = Get-SshHostDetailErrorCode -TimedOut $timedOut -ExitCode $exitCode -ErrorText $errorText

    $status = 'Unknown'
    if ($timedOut -or $exitCode -ne 0) {
        $status = 'Offline'
    }
    elseif ($exitCode -eq 0) {
        $status = 'Online'
    }

    $message = ''
    if ($status -ne 'Online') {
        if ($timedOut) {
            $message = "SSH 探测超时(等待窗口 ${TimeoutSec}s)"
        }
        elseif ($errorText) {
            $message = $errorText
        }
        elseif ($exitCode -ne 0) {
            $message = "ssh 退出码 $exitCode"
        }
        else {
            $message = '未取得探测结果'
        }
    }

    return ConvertTo-SshHostDetailResult -HostName $HostName -Status $status -ErrorCode $errorCode `
        -ErrorMessage $message -RemoteHostname $parsed.RemoteHostname -Uptime $parsed.Uptime `
        -Load $parsed.Load -TmuxSessionCount $parsed.TmuxSessionCount -ElapsedMs $elapsedMs
}
