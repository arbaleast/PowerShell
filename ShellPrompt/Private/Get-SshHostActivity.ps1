# Get-SshHostActivity.ps1 - SSH 主机**本地连接活动**读数(数据层)
#
# 为什么需要它:
#   仪表盘左侧列表要显示"最后活跃", 右侧 Activity 卡片要显示"最近连接记录 +
#   按天活动统计"。这些数据 ssh 本身不提供 —— 唯一**真实**的来源是 ShellPrompt
#   自己记录的本机连接历史。于是这里维护一个版本化的本地 JSON(写入见
#   Add-SshHostActivity.ps1), 只如实回放已经发生过的连接, 没有记录就是"无数据",
#   绝不用随机数或主机名去填充卡片。
#
# 存储位置: `$HOME/.ShellPrompt/host-activity.json`(可用 -StorePath 覆盖, 测试隔离用)。
# 容错口径: 文件缺失 / 空文件 / JSON 损坏 / 字段缺失 一律当"空历史"处理, 不抛异常 ——
#   界面数据源不该因为一个坏掉的记录文件就打不开。
#
# 本文件同时承载三个内部助手(读文档 / 写文档 / 视图投影), 供 Add-SshHostActivity 复用:
#   - Read-SshHostActivityDocument   : 宽容读取(损坏降级为空历史)
#   - Write-SshHostActivityDocument  : 先写临时文件再替换(避免半截 JSON)
#   - ConvertTo-SshHostActivityView  : 把存储条目投影成 UI 直接消费的视图对象

function ConvertTo-SshActivityStampString {
    <#
    .SYNOPSIS
        把活动记录里的时间值统一成 ISO 8601 UTC 字符串。

    .DESCRIPTION
        内部实现。**这是本文件最容易被踩的一处**: PowerShell 7.5+ 的
        ConvertFrom-Json 默认会把形如 `2026-10-31T08:00:00Z` 的字符串
        自动反序列化成 [datetime]。之后若再用 `[string]` 强转, 得到的是
        **当前区域格式**(如 `10/31/2026 08:00:00`)而不是 ISO —— 排序列序与
        回放会一起漂掉(实测: 第二次写入把历史时间戳改写成区域格式, 且
        LastSeen 排序失效)。

        因此在读取的唯一咽喉处做归一: datetime / datetimeoffset 一律转成
        不变的 ISO 串, 字符串原样返回。写入端因此永远拿到可直接字典序排序
        的时间戳。

    .PARAMETER Value
        原始值(可能来自 JSON 反序列化, 也可能是手写字符串)。

    .OUTPUTS
        [string] ISO 8601 UTC 字符串; 空值返回空串。
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) { return '' }
    if ($Value -is [datetime]) {
        return ([datetime]$Value).ToUniversalTime().ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [datetimeoffset]) {
        return ([datetimeoffset]$Value).UtcDateTime.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    return [string]$Value
}

function Get-SshHostActivityStorePath {
    <#
    .SYNOPSIS
        解析活动记录文件路径(缺省 ~/.ShellPrompt/host-activity.json)。

    .DESCRIPTION
        内部实现。把"路径解析"收成一处, 读写两个函数共用同一个口径, 测试
        只需换 -StorePath 即可完全隔离, 不必改写 $HOME。

    .PARAMETER StorePath
        显式指定的记录文件路径; 为空时用缺省位置。

    .OUTPUTS
        [string] 记录文件完整路径
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$StorePath = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($StorePath)) {
        return [System.IO.Path]::GetFullPath($StorePath)
    }
    return (Join-Path (Join-Path $HOME '.ShellPrompt') 'host-activity.json')
}

function Read-SshHostActivityDocument {
    <#
    .SYNOPSIS
        宽容读取活动记录文档。

    .DESCRIPTION
        内部实现。返回 @{ Version = 1; Hosts = @{ <host> = @{ LastSeenUtc; Count; Recent } } }。
        任何读取/解析故障都降级为空文档 —— 调用方(读视图 / 追加记录)因此永远拿到
        一个可用结构, 不需要各自写 try/catch。

    .PARAMETER LiteralPath
        记录文件完整路径。

    .OUTPUTS
        [hashtable] 文档(Version / Hosts)
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath
    )

    $document = @{ Version = 1; Hosts = @{} }
    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) { return $document }

    try {
        $raw = Get-Content -LiteralPath $LiteralPath -Raw -Encoding UTF8 -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return $document }

        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $parsed) { return $document }
        if ($null -eq $parsed.PSObject.Properties['Hosts']) { return $document }
        if ($null -eq $parsed.Hosts) { return $document }

        foreach ($property in $parsed.Hosts.PSObject.Properties) {
            $hostName = [string]$property.Name
            if ([string]::IsNullOrWhiteSpace($hostName)) { continue }

            $lastSeen = ''
            $count = 0
            $recent = [System.Collections.Generic.List[string]]::new()
            $entry = $property.Value
            if ($null -ne $entry) {
                if ($null -ne $entry.PSObject.Properties['LastSeenUtc']) {
                    $lastSeen = ConvertTo-SshActivityStampString -Value $entry.LastSeenUtc
                }
                if ($null -ne $entry.PSObject.Properties['Count'] -and $null -ne $entry.Count) {
                    $parsedCount = 0
                    if ([int]::TryParse([string]$entry.Count, [ref]$parsedCount) -and $parsedCount -ge 0) {
                        $count = $parsedCount
                    }
                }
                if ($null -ne $entry.PSObject.Properties['Recent'] -and $null -ne $entry.Recent) {
                    foreach ($stamp in @($entry.Recent)) {
                        $text = ConvertTo-SshActivityStampString -Value $stamp
                        if (-not [string]::IsNullOrWhiteSpace($text)) { $recent.Add($text) }
                    }
                }
            }

            $document.Hosts[$hostName] = @{
                LastSeenUtc = $lastSeen
                Count       = $count
                Recent      = $recent.ToArray()
            }
        }
    } catch {
        # 损坏的 JSON 当作空历史(界面数据源不能因为坏文件打不开)
        Write-Verbose "[Get-SshHostActivity] 活动记录读取失败, 按空历史处理: $($_.Exception.Message)"
        return @{ Version = 1; Hosts = @{} }
    }

    return $document
}

function Write-SshHostActivityDocument {
    <#
    .SYNOPSIS
        原子写出活动记录文档(先写临时文件, 再替换目标)。

    .DESCRIPTION
        内部实现。直接覆盖写有"写到一半进程被杀 -> 留下半截 JSON"的风险,
        这里先写 `<path>.tmp` 再 Move-Item -Force 替换, 最坏情况是丢掉本次更新,
        而不是把历史记录整份写坏。

    .PARAMETER LiteralPath
        记录文件完整路径。

    .PARAMETER Document
        Read-SshHostActivityDocument 产出的文档结构。

    .OUTPUTS
        [void]
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath,

        [Parameter(Mandatory = $true)]
        [hashtable]$Document
    )

    $parent = [System.IO.Path]::GetDirectoryName($LiteralPath)
    try {
        if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
            New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
        }

        $json = $Document | ConvertTo-Json -Depth 6
        $tempPath = $LiteralPath + '.tmp'
        Set-Content -LiteralPath $tempPath -Value $json -Encoding utf8 -ErrorAction Stop
        Move-Item -LiteralPath $tempPath -Destination $LiteralPath -Force -ErrorAction Stop
    }
    catch {
        # 写失败必须**终止并给出可定位的原因**: 静默继续会让调用方以为
        # "活动已记录", 界面上却永远没有数据(而且原始的 3 条非终止错误
        # 会在调用栈里刷屏)。调用方(Start-TmuxSession)按"辅助信息写失败
        # 不阻断主流程"的策略降级处理。
        throw "写入活动记录失败($LiteralPath): $($_.Exception.Message)"
    }
}

function ConvertTo-SshHostActivityView {
    <#
    .SYNOPSIS
        把存储条目投影成界面直接消费的活动视图对象。

    .DESCRIPTION
        内部实现。字段:
          Host       - 主机名
          LastSeen   - 最后活跃(本地时区; 无记录为 $null)
          Count      - 累计连接次数
          Recent     - 最近连接时间(本地时区, 升序, 最多 20)
          DayBuckets - 长度 7 的数组: 从 6 天前到"今天"的每日连接次数
          HasData    - 是否有真实记录(UI 据此显示"无数据"而不是空图)

        时间解析用 RoundtripKind: 存储里是 UTC ISO 串, 回放时转本地时区;
        坏的时间串直接跳过, 不参与分桶。

    .PARAMETER HostName
        主机名。

    .PARAMETER Entry
        存储条目(LastSeenUtc / Count / Recent); $null 表示无记录。

    .PARAMETER Today
        分桶基准日(本地时区 0 点), 缺省取当前日期; 测试可注入固定日期。

    .OUTPUTS
        PSCustomObject(Host/LastSeen/Count/Recent/DayBuckets/HasData)
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [hashtable]$Entry,

        [Parameter(Mandatory = $false)]
        [datetime]$Today = (Get-Date).Date
    )

    $recentLocal = [System.Collections.Generic.List[datetime]]::new()
    $count = 0
    $lastSeen = $null

    if ($null -ne $Entry) {
        $entryCount = $Entry['Count']
        if ($null -ne $entryCount) {
            $parsedCount = 0
            if ([int]::TryParse([string]$entryCount, [ref]$parsedCount) -and $parsedCount -ge 0) { $count = $parsedCount }
        }

        $lastSeenText = [string]$Entry['LastSeenUtc']
        if (-not [string]::IsNullOrWhiteSpace($lastSeenText)) {
            $parsedLastSeen = [datetime]::MinValue
            if ([datetime]::TryParse($lastSeenText, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsedLastSeen)) {
                $lastSeen = $parsedLastSeen.ToLocalTime()
            }
        }

        foreach ($stamp in @($Entry['Recent'])) {
            $text = [string]$stamp
            if ([string]::IsNullOrWhiteSpace($text)) { continue }
            $parsed = [datetime]::MinValue
            if ([datetime]::TryParse($text, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)) {
                $recentLocal.Add($parsed.ToLocalTime())
            }
        }
        $recentLocal.Sort()
    }

    # 分桶: 索引 6 = 今天, 索引 0 = 6 天前。只统计 Recent 里的真实记录。
    $dayBuckets = [int[]]::new(7)
    foreach ($moment in $recentLocal) {
        $deltaDays = [int]($Today.Date - $moment.Date).TotalDays
        if ($deltaDays -ge 0 -and $deltaDays -le 6) {
            $dayBuckets[6 - $deltaDays] = $dayBuckets[6 - $deltaDays] + 1
        }
    }

    return [PSCustomObject]@{
        Host       = $HostName
        LastSeen   = $lastSeen
        Count      = $count
        Recent     = $recentLocal.ToArray()
        DayBuckets = $dayBuckets
        HasData    = (($count -gt 0) -or ($recentLocal.Count -gt 0))
    }
}

function Get-SshHostActivity {
    <#
    .SYNOPSIS
        读取主机的本地连接活动(最后活跃 / 最近记录 / 按天统计)。

    .DESCRIPTION
        只回放真实记录过的连接:
          - 无记录时 HasData=$false、LastSeen=$null、DayBuckets 全 0;
          - -All(或 -HostName 为空 / '*')返回全部主机的活动视图, 按最后活跃倒序;
          - 记录文件损坏按空历史处理, 不抛异常。

    .PARAMETER HostName
        主机名(与 ssh config 的别名/HostName 同一口径, 大小写不敏感)。

    .PARAMETER All
        列出全部主机的活动记录。

    .PARAMETER StorePath
        记录文件路径覆盖(测试隔离用), 缺省 ~/.ShellPrompt/host-activity.json。

    .OUTPUTS
        PSCustomObject(Host/LastSeen/Count/Recent/DayBuckets/HasData);
        -All 时为该对象的数组。

    .EXAMPLE
        $activity = Get-SshHostActivity -HostName 'deb'
        if ($activity.HasData) { $activity.LastSeen }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$HostName = '',

        [Parameter(Mandatory = $false)]
        [switch]$All,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$StorePath = ''
    )

    $resolvedPath = Get-SshHostActivityStorePath -StorePath $StorePath
    $document = Read-SshHostActivityDocument -LiteralPath $resolvedPath

    $listAll = $All.IsPresent -or [string]::IsNullOrWhiteSpace($HostName) -or $HostName -eq '*'
    if ($listAll) {
        $views = [System.Collections.Generic.List[object]]::new()
        foreach ($key in @($document.Hosts.Keys)) {
            $views.Add((ConvertTo-SshHostActivityView -HostName ([string]$key) -Entry $document.Hosts[$key]))
        }
        # 有记录的排前面, 同组内按最后活跃倒序; 无记录(坏字段)排最后
        return @($views | Sort-Object -Property @{ Expression = { if ($null -eq $_.LastSeen) { [datetime]::MinValue } else { $_.LastSeen } }; Descending = $true })
    }

    $entry = $null
    if ($document.Hosts.ContainsKey($HostName)) {
        $entry = $document.Hosts[$HostName]
    }
    return (ConvertTo-SshHostActivityView -HostName $HostName -Entry $entry)
}
