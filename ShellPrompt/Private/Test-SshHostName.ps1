function Test-SshHostName {
    <#
    .SYNOPSIS
        验证 SSH 主机名是否合法（仅允许字母、数字、点、短横线和下划线）

    .DESCRIPTION
        用于 [ValidateScript] 参数校验或运行时断言, 防止命令注入。

    .PARAMETER HostName
        待校验的主机名

    .EXAMPLE
        Test-SshHostName -HostName "my-server.lan" → $true

    .EXAMPLE
        Test-SshHostName -HostName "my;server" → $false
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName
    )
    # 拒绝所有 shell 特殊字符（空格、管道、与号、分号、反引号、美元符号等）
    return $HostName -notmatch '[\s|&;`$(){}<>#@!*?\[\]~"]'
}
