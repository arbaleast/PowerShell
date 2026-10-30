# Get-HostSelectorRow.ps1 - SSH 主机选择器的表格行构造(纯函数, 无 UI 依赖)
# 职责: 把主机列表转换为主机选择器的行对象(LastHost 置顶 + State 标注)。
# 调用方: Show-HostSelector(公开入口)。

function Get-HostSelectorRow {
    <#
    .SYNOPSIS
        构造 SSH 主机选择器的表格行。

    .DESCRIPTION
        State 文字承载"上次使用/普通"语义; LastHost 置顶,
        便于用户快速回到上次使用的主机。

    .PARAMETER Hosts
        主机名数组(来自 Get-SshConfigHosts)

    .PARAMETER LastHost
        上次使用的主机名(用于置顶 + State 标注), 为空时不做特殊处理

    .OUTPUTS
        PSCustomObject 数组(Host/State/Disabled/Value)

    .EXAMPLE
        $rows = Get-HostSelectorRow -Hosts $hosts -LastHost 'debian'
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
        $rows.Add([PSCustomObject]@{
                Host     = $h
                State    = Get-HostSelectorStateText -IsLast $isLast
                Disabled = $false
                Value    = $h
            })
    }

    return $rows.ToArray()
}
