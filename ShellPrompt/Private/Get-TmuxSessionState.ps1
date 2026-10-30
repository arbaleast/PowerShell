# Get-TmuxSessionState.ps1 - tmux 会话探测结果的**状态化**归一(数据层)
# 职责: 把 Get-TmuxSessions 的原始返回值(会话数组 + 探测元数据)归一成一个状态对象,
#       让 UI 层不需要再自己判断"是空列表还是探测失败""超时还是网络不可达"。
#
# 为什么需要它(2026-10-30 TUI 重构):
#   旧流程把分支散落在 Start-TmuxSession 里: Available/TimedOut/NetworkError 各自
#   拼一句 Write-Warning, 空列表与探测失败在界面上**长得一样**(都是"没有会话")。
#   现在统一收敛成 Status / ErrorCode / ErrorMessage, UI 层据此渲染带错误码的占位面板。
#
# 纯函数: 只读入参, 不发网络请求、不写控制台 —— Pester 可独立覆盖。

function Get-TmuxErrorCode {
    <#
    .SYNOPSIS
        把 tmux 探测结果映射为稳定的错误码。

    .DESCRIPTION
        判定顺序(先特指后泛化):
          1. E_SSH_TIMEOUT     - SSH 等待超时(被 Kill), 与"远端命令失败"是两回事;
          2. E_SSH_UNREACHABLE - 网络不可达 / 端口拒绝 / DNS 失败;
          3. E_SSH_AUTH        - 认证或主机密钥校验失败;
          4. E_SSH_FAILED      - SSH 进程或远端命令失败(退出码非 0);
          5. E_NO_TMUX         - 命令跑通了但拿不到 tmux 版本(远端没装 tmux / server 未运行);
          6. E_UNKNOWN         - 没有任何探测信息(理论上不可达, 兜底用)。

        探测成功(Available=$true)时返回空串。

    .PARAMETER SessionData
        Get-TmuxSessions 的返回值(hashtable); 也接受同形状 PSCustomObject

    .OUTPUTS
        [string] 错误码; 无错误时为空串

    .EXAMPLE
        Get-TmuxErrorCode -SessionData @{ Available = $false; TimedOut = $true }
        # -> E_SSH_TIMEOUT
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$SessionData
    )

    if ($null -eq $SessionData) { return 'E_UNKNOWN' }

    $available = $SessionData.Available
    if ($null -ne $available -and [bool]$available) { return '' }

    $errorText = [string]$SessionData.Error
    $exitCode = $SessionData.ExitCode
    $exitCodeValue = if ($null -eq $exitCode) { 0 } else { [int]$exitCode }

    if ($SessionData.TimedOut) { return 'E_SSH_TIMEOUT' }
    if ($SessionData.NetworkError) { return 'E_SSH_UNREACHABLE' }

    if ($errorText) {
        $authPatterns = @(
            'Permission denied'
            'Authentication failed'
            'Too many authentication failures'
            'publickey'
            'Host key verification failed'
            'Host key has changed'
        )
        foreach ($pattern in $authPatterns) {
            if ($errorText -match [regex]::Escape($pattern)) { return 'E_SSH_AUTH' }
        }
    }

    if ($exitCodeValue -ne 0) { return 'E_SSH_FAILED' }

    # 命令跑通(退出码 0)却拿不到 tmux 版本: 远端没有 tmux 或 tmux server 未运行
    return 'E_NO_TMUX'
}

function Get-TmuxSessionState {
    <#
    .SYNOPSIS
        把 tmux 会话探测结果归一为状态对象(UI 层的唯一输入)。

    .DESCRIPTION
        返回对象的字段:
          Status       - Ok(有会话) / Empty(确实没有会话) / Error(探测失败)
          Context      - Normal / Error, 供工具条切换文案(刷新 vs 重试)
          Sessions     - 会话数组(恒为数组, 空列表也是空数组)
          ErrorCode    - 稳定错误码(见 Get-TmuxErrorCode), 无错误时为空串
          ErrorMessage - 面向用户的一句话说明
          Hint         - 降级指引(如"按 r 重试 · 按 s 直连 SSH")
          Version      - 远端 tmux 版本号

        契约要点: "查询成功但确实没有会话"(Empty)与"查询失败"(Error)严格区分 ——
        前者不是故障, 不应显示错误码与降级指引。

    .PARAMETER SessionData
        Get-TmuxSessions 的返回值(hashtable); 也接受同形状 PSCustomObject

    .PARAMETER Sessions
        可选: 直接指定会话数组(用于在归一化前按上一轮顺序重排行序)。
        不提供时取 SessionData.Sessions。

    .OUTPUTS
        PSCustomObject(.Status/.Context/.Sessions/.ErrorCode/.ErrorMessage/.Hint/.Version)

    .EXAMPLE
        Get-TmuxSessionState -SessionData $sessionData
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$SessionData,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [array]$Sessions
    )

    # 注意: PowerShell 变量名**大小写不敏感**, 局部变量不能叫 $sessions ——
    # 那会把参数 $Sessions 直接覆盖成空数组(曾经踩过: 会话永远解析为 0 条)。
    $sessionList = @()
    if ($null -ne $Sessions) {
        $sessionList = @($Sessions | Where-Object { $null -ne $_ })
    } elseif ($null -ne $SessionData) {
        $rawSessions = $SessionData.Sessions
        if ($null -ne $rawSessions) { $sessionList = @($rawSessions | Where-Object { $null -ne $_ }) }
    }

    $availableRaw = if ($null -ne $SessionData) { $SessionData.Available } else { $null }
    # SessionData 本身为 $null = 连探测结果都没有 => 无法确认 tmux 可用, 按 Error 兜底
    # (走进 Get-TmuxErrorCode($null) -> E_UNKNOWN), 而不是折叠成"没有会话"。
    $available = if ($null -eq $SessionData) { $false }
        elseif ($null -eq $availableRaw) { $true }
        else { [bool]$availableRaw }

    $version = ''
    if ($null -ne $SessionData) {
        $version = [string]$SessionData.Version
    }

    $status = if (-not $available) { 'Error' } elseif ($sessionList.Count -gt 0) { 'Ok' } else { 'Empty' }

    $errorCode = ''
    $errorMessage = ''
    $hint = ''
    if ($status -eq 'Error') {
        $errorCode = Get-TmuxErrorCode -SessionData $SessionData
        $errorMessage = switch ($errorCode) {
            'E_SSH_TIMEOUT' { 'SSH 连接超时, 未能获取 tmux 会话列表' }
            'E_SSH_UNREACHABLE' { '无法连接远程主机(网络不可达或端口被拒绝)' }
            'E_SSH_AUTH' { 'SSH 认证失败(检查密钥 / known_hosts)' }
            'E_SSH_FAILED' { 'SSH 命令执行失败, 未能获取 tmux 会话列表' }
            'E_NO_TMUX' { '远端未安装 tmux, 或 tmux server 未运行' }
            default { '未能获取 tmux 会话列表' }
        }
        $hint = '按 r 重试 · 按 s 直连 SSH'
    } elseif ($status -eq 'Empty') {
        $errorMessage = '远端当前没有 tmux 会话'
        $hint = '按 n 新建会话 · 按 r 刷新 · 按 s 直连 SSH'
    }

    return [PSCustomObject]@{
        Status       = $status
        Context      = if ($status -eq 'Error') { 'Error' } else { 'Normal' }
        Sessions     = $sessionList
        ErrorCode    = $errorCode
        ErrorMessage = $errorMessage
        Hint         = $hint
        Version      = $version
    }
}
