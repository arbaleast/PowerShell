# Get-TmuxRefreshedSession.ps1 - 用户触发的会话列表刷新
# 职责: 执行刷新脚本块并把结果归一化为会话数组(过滤 $null, 保证调用方可直接 .Count)。

function Get-TmuxRefreshedSession {
    <#
    .SYNOPSIS
        执行刷新脚本块, 返回归一化后的会话数组。

    .DESCRIPTION
        刷新语义完全由用户触发(菜单中的"⟳ 刷新会话列表"项), 不引入定时器或后台轮询。
        归一化规则: 过滤掉 $null 元素并包装成数组, 避免调用方拿到 @($null) 这类
        "看起来有一个元素"的结果, 也避免空结果被 PowerShell 展开成 $null。

    .PARAMETER SessionRefresher
        刷新脚本块, 返回新的会话数组(Get-TmuxSessions 的 .Sessions)

    .OUTPUTS
        会话数组(可能为空数组)

    .EXAMPLE
        $sessions = Get-TmuxRefreshedSession -SessionRefresher $refresher
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '')]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$SessionRefresher
    )

    $refreshed = & $SessionRefresher
    if (-not $refreshed) {
        return , @()
    }
    return , @($refreshed | Where-Object { $null -ne $_ })
}
