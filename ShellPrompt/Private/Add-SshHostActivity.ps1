# Add-SshHostActivity.ps1 - 记录一次 SSH 主机连接活动(数据层写入端)
#
# 为什么需要它:
#   仪表盘的"最后活跃 / 最近连接记录 / 按天活动"只能来自 ShellPrompt 自己记录
#   的真实连接历史。本函数就是这份历史的唯一写入点 —— 在用户确实连上某台主机
#   之后被调用一次, 不做任何推测性写入。
#
# 记录口径:
#   - 一台主机只保留最近 20 条时间戳(升序), 累计次数 Count 单独计;
#   - 记录文件最多 200 台主机, 超出时按"最后活跃最旧"淘汰 —— 这是本机历史,
#     不是审计日志, 不该无限膨胀;
#   - 写入走 Read-SshHostActivityDocument / Write-SshHostActivityDocument
#     (后者先写临时文件再替换), 避免半截 JSON 毁掉整份历史。
#
# 时间口径: 参数名是 TimeUtc。Local 会被转成 UTC; Unspecified 按 UTC 解释;
#   落盘恒为 ISO 8601 UTC('o' 格式), 读取端再转回本地时区 —— 跨时区不会漂。

function Add-SshHostActivity {
    <#
    .SYNOPSIS
        记录一次主机连接活动(累加次数 + 追加时间戳)。

    .DESCRIPTION
        写入 `~/.ShellPrompt/host-activity.json`(可用 -StorePath 覆盖)。
        -PassThru 时返回写入后该主机的活动视图(与 Get-SshHostActivity 同形)。

        支持 ShouldProcess: 这是会改本地文件的写操作。

    .PARAMETER HostName
        主机名(ssh config 里的别名或 HostName, 大小写不敏感)。

    .PARAMETER TimeUtc
        本次连接的时间; 缺省当前 UTC 时间。Local 会转 UTC, Unspecified 按 UTC 解释。

    .PARAMETER PassThru
        返回写入后的主机活动视图。

    .PARAMETER StorePath
        记录文件路径覆盖(测试隔离用)。

    .OUTPUTS
        -PassThru 时返回 PSCustomObject(Host/LastSeen/Count/Recent/DayBuckets/HasData);
        否则无输出。

    .EXAMPLE
        Add-SshHostActivity -HostName 'deb'
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$HostName,

        [Parameter(Mandatory = $false)]
        [datetime]$TimeUtc = [datetime]::UtcNow,

        [Parameter(Mandatory = $false)]
        [switch]$PassThru,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$StorePath = ''
    )

    $resolvedPath = Get-SshHostActivityStorePath -StorePath $StorePath
    if (-not $PSCmdlet.ShouldProcess($HostName, '记录 SSH 主机连接活动')) { return }

    # 统一到 UTC: 落盘时间戳与排序都依赖它, 不在这里做归一就会出现"本地时间串
    # 与 UTC 串混排", Recent 的升序也就不可信了。
    $utcTime = $TimeUtc
    switch ($TimeUtc.Kind) {
        'Local' { $utcTime = $TimeUtc.ToUniversalTime() }
        'Utc' { $utcTime = $TimeUtc }
        default { $utcTime = [datetime]::SpecifyKind($TimeUtc, [System.DateTimeKind]::Utc) }
    }
    $stamp = $utcTime.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)

    $document = Read-SshHostActivityDocument -LiteralPath $resolvedPath

    $existing = $null
    if ($document.Hosts.ContainsKey($HostName)) { $existing = $document.Hosts[$HostName] }

    $count = 0
    $recent = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $existing) {
        $parsedCount = 0
        if ([int]::TryParse([string]$existing['Count'], [ref]$parsedCount) -and $parsedCount -ge 0) {
            $count = $parsedCount
        }
        foreach ($recorded in @($existing['Recent'])) {
            $text = [string]$recorded
            if (-not [string]::IsNullOrWhiteSpace($text)) { $recent.Add($text) }
        }
    }

    $recent.Add($stamp)
    # ISO 8601 UTC 串的字典序 == 时间序, 所以这里排序不必逐条解析
    $ordered = @($recent | Sort-Object)
    if ($ordered.Count -gt 20) {
        $ordered = @($ordered[($ordered.Count - 20)..($ordered.Count - 1)])
    }

    # LastSeen 取 Recent 的最大值, 而不是"本次写入的时间" ——
    # 补录一条更早的记录(如导入历史)时, 最后活跃不应被改成那个更早的时刻。
    $lastSeenStamp = $ordered[$ordered.Count - 1]
    $document.Hosts[$HostName] = @{
        LastSeenUtc = $lastSeenStamp
        Count       = $count + 1
        Recent      = $ordered
    }

    # 淘汰: 主机数上限 200, 丢最后活跃最旧的那些
    if ($document.Hosts.Count -gt 200) {
        $candidates = @(
            foreach ($key in @($document.Hosts.Keys)) {
                [PSCustomObject]@{
                    Key      = [string]$key
                    LastSeen = [string]$document.Hosts[$key]['LastSeenUtc']
                }
            }
        )
        $removeCount = $document.Hosts.Count - 200
        $oldestFirst = @($candidates | Sort-Object -Property LastSeen)
        for ($i = 0; $i -lt $removeCount -and $i -lt $oldestFirst.Count; $i++) {
            [void]$document.Hosts.Remove($oldestFirst[$i].Key)
        }
    }

    Write-SshHostActivityDocument -LiteralPath $resolvedPath -Document $document

    if ($PassThru) {
        return (Get-SshHostActivity -HostName $HostName -StorePath $resolvedPath)
    }
}
