# Get-GridViewHostRow.ps1 - SSH 主机选择器的表格行构造
# 职责: 把主机列表转换为 GridView 行对象(LastHost 置顶 + State 标注)。

function Get-GridViewHostRow {
    <#
    .SYNOPSIS
        构造 SSH 主机选择器的 GridView 表格行。

    .DESCRIPTION
        无行级配色能力 -> 用 State 文字承载"上次使用/普通"语义;
        LastHost 置顶, 便于用户快速回到上次使用的主机。

    .PARAMETER Hosts
        主机名数组(来自 Get-SshConfigHosts)

    .PARAMETER LastHost
        上次使用的主机名(用于置顶 + State 标注), 为空时不做特殊处理

    .OUTPUTS
        PSCustomObject 数组(Host/State/Disabled/Value)

    .EXAMPLE
        $rows = Get-GridViewHostRow -Hosts $hosts -LastHost 'debian'
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Hosts,
        [Parameter(Mandatory = $false)][string]$LastHost = ""
    )

    # LastHost 置顶
    $orderedHosts = @($Hosts)
    if ($LastHost -and ($orderedHosts -contains $LastHost)) {
        $orderedHosts = @($LastHost) + @($orderedHosts | Where-Object { $_ -ne $LastHost })
    }

    $rows = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($h in $orderedHosts) {
        $isLast = ($h -eq $LastHost)
        # 2026-10-19 P0: 删 Desc 列(SSH 远程主机) — 与 Host 列重复, 释放 ~16 字宽度
        $rows.Add([PSCustomObject]@{
                Host     = $h
                State    = Get-HostSelectorStateText -IsLast $isLast
                Disabled = $false
                Value    = $h
            })
    }

    return $rows.ToArray()
}
