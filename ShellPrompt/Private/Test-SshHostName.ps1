function Test-SshHostName {
    <#
    .SYNOPSIS
        验证 SSH 目标地址是否合法（白名单：字母、数字、点、短横线和下划线）

    .DESCRIPTION
        用于 [ValidateScript] 参数校验或运行时断言, 防止命令注入。

        采用白名单而非黑名单。历史实现用否定式黑名单, 放行了 "-oProxyCommand=..." 这类
        ssh 选项形态: ssh 的 getopt 会把它解析成 -o 选项, 于是 ProxyCommand 在**本机**执行。
        (实测: ssh -oProxyCommand="touch /tmp/x" somehost 会在本机创建 /tmp/x)

        两条硬约束:
        1. 目标地址整体必须匹配 ^[A-Za-z0-9][A-Za-z0-9._-]*$ —— 首字符只能是字母或数字,
           因此不可能以 '-' 开头, 不会被 ssh 当成选项; 同时排除 '=' ':' '/' 等字符。
        2. 可选的 user@ 前缀（仅 -AllowUserPrefix）: user 部分按同一白名单校验。

    .PARAMETER HostName
        待校验的目标地址

    .PARAMETER AllowUserPrefix
        允许可选的 user@ 前缀（Copy-SshPublicKey 的 -RemoteHost 文档格式 [user@]hostname）

    .EXAMPLE
        Test-SshHostName -HostName "my-server.lan" → $true

    .EXAMPLE
        Test-SshHostName -HostName "-oProxyCommand=calc" → $false

    .EXAMPLE
        Test-SshHostName -HostName "user@example.com" -AllowUserPrefix → $true
    #>
    [CmdletBinding()]
    [OutputType([bool])]
param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $false)]
        [switch]$AllowUserPrefix
    )

    if ([string]::IsNullOrWhiteSpace($HostName)) { return $false }

    $target = $HostName
    if ($AllowUserPrefix) {
        # 取最后一个 '@' 作为 user/host 分隔符（user 本身不允许再含 '@'）
        $at = $HostName.LastIndexOf('@')
        if ($at -ge 0) {
            $user = $HostName.Substring(0, $at)
            $target = $HostName.Substring($at + 1)
            if ($user -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { return $false }
        }
    }

    # 首字符必须是字母或数字 —— 这是"不得以 '-' 开头"的具体实现
    return ($target -match '^[A-Za-z0-9][A-Za-z0-9._-]*$')
}
