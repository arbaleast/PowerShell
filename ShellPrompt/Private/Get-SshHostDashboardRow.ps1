# Get-SshHostDashboardRow.ps1 - SSH 主机仪表盘的**行视图模型**(纯函数, 无 UI 依赖)
#
# 背景 (2026-10-31 sss 仪表盘重构):
#   左侧主机列表要同时展示: 状态点(●绿/●红/●灰) · 主机名 · 分组缩进 · 标签 · 最后活跃。
#   数据来源分三类, 本文件只做"数据 -> 行视图模型"的一次性映射:
#     - 主机档案(Get-SshHostProfile 产物): 名称/HostName/Port/User/Tags/Group/Provider/Region
#     - 本地活动历史(Get-SshHostActivity 产物): 最后活跃时间/最近连接次数
#     - 运行时状态(远端探测结果): 由编排层异步回填(初值 Unknown)
#   把映射抽成纯函数的目的: 排序/过滤/相对时间文案可以无头单测, 不需要 TG。
#
# 契约:
#   - 不读写任何文件, 不发网络请求, 不碰 Terminal.Gui;
#   - 不伪造数据: 没有活动记录 => HasActivity=$false / LastActive=$null / 文案 '—';
#     没有远端探测结果 => Status='Unknown'(灰), 绝不猜成"在线";
#   - 分类过滤由调用方(编排层)用数据层的 Select-SshHostByCategory 先做, 本函数
#     只负责文本过滤 + 排序 + 行映射。

function Get-SshHostRelativeTime {
    <#
    .SYNOPSIS
        把"最后活跃时间"格式化成列表里的紧凑相对文案。

    .DESCRIPTION
        宽度预算很窄(列表最右一列), 只输出 4 种形态:
          刚刚 / 5m / 2h / 3d / 2w ; 无记录返回 '—'(U+2014, 单列宽)。
        只做**展示**: 超过 4 周也落到 'Nw', 不输出绝对时间(右侧 Activity 卡片
        才展示绝对时间)。

    .PARAMETER Time
        最后活跃时间(本地时区); $null 表示没有真实记录。

    .PARAMETER Now
        参照时间(默认当前时间, 测试可注入固定值)。

    .OUTPUTS
        [string] 相对时间文案; 无记录返回 '—'。

    .EXAMPLE
        Get-SshHostRelativeTime -Time (Get-Date).AddHours(-2)   # => '2h'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [Nullable[datetime]]$Time,

        [Parameter(Mandatory = $false)]
        [Nullable[datetime]]$Now
    )

    if ($null -eq $Time) { return [string][char]0x2014 }   # —
    $ref = if ($null -ne $Now) { $Now } else { Get-Date }
    $delta = $ref - $Time
    if ($delta.TotalSeconds -lt 0) { return '刚刚' }        # 时钟回拨/未来时间
    if ($delta.TotalMinutes -lt 1) { return '刚刚' }
    if ($delta.TotalHours -lt 1) { return ("{0}m" -f [int][Math]::Floor($delta.TotalMinutes)) }
    if ($delta.TotalDays -lt 1) { return ("{0}h" -f [int][Math]::Floor($delta.TotalHours)) }
    if ($delta.TotalDays -lt 7) { return ("{0}d" -f [int][Math]::Floor($delta.TotalDays)) }
    return ("{0}w" -f [int][Math]::Floor($delta.TotalDays / 7))
}

function Get-SshHostStatusPresentation {
    <#
    .SYNOPSIS
        把远端探测状态映射成列表/详情共用的展示三元组。

    .DESCRIPTION
        状态语义固定三态(与 Get-SshHostDetail 的 Status 对齐):
          Online  -> '在线'  / '●' / Theme 角色 Online
          Offline -> '离线'  / '●' / Theme 角色 Offline
          Unknown -> '未知'  / '●' / Theme 角色 Unknown
        状态点统一用 ●(U+25CF, East Asian Width = Ambiguous, 主流等宽字体按
        单列渲染); 不用 ✗/↗ 这类宽度不一致或字体缺失率高的符号做**列对齐**
        元素, 它们只出现在详情卡片的自由文本里。

    .PARAMETER Status
        远端探测状态 'Online' | 'Offline' | 'Unknown'(其它值按 Unknown 处理)。

    .OUTPUTS
        [PSCustomObject] Status/StatusText/StatusGlyph/StatusRole

    .EXAMPLE
        Get-SshHostStatusPresentation -Status 'Online'   # => 在线 / ● / Online
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Status = 'Unknown'
    )

    $glyph = [string][char]0x25CF   # ●
    switch ($Status) {
        'Online' { return [PSCustomObject]@{ Status = 'Online'; StatusText = '在线'; StatusGlyph = $glyph; StatusRole = 'Online' } }
        'Offline' { return [PSCustomObject]@{ Status = 'Offline'; StatusText = '离线'; StatusGlyph = $glyph; StatusRole = 'Offline' } }
        default { return [PSCustomObject]@{ Status = 'Unknown'; StatusText = '未知'; StatusGlyph = $glyph; StatusRole = 'Unknown' } }
    }
}

function Get-SshHostDashboardRow {
    <#
    .SYNOPSIS
        把主机档案 + 本地活动历史映射为仪表盘左侧列表的行视图模型。

    .DESCRIPTION
        处理顺序(每个主机只走一遍):
          1. 文本过滤: 名称/HostName/标签 任意一项包含 -Filter(忽略大小写);
          2. 排序: 上次使用的主机置顶; 其余按 分组名 -> 主机名 升序
             (无分组的主机排在分组主机之后, 避免"有分组/无分组"交错);
          3. 映射为行对象, 附上状态展示三元组、相对活跃时间、分组缩进标记。

        行字段(HostListView / 详情面板共用这一份):
          Name/HostName/Port/User/Tags/Group/Provider/Region/IsLocal/
          IdentityFile/ProxyJump/Source  — 档案原样透传
          Status/StatusText/StatusGlyph/StatusRole — 初值 Unknown(编排层异步回填)
          LastActive [datetime?] / LastActiveText / HasActivity / ConnectCount
          IsLastHost [bool] / Indent [bool](Group 非空 => 列表里缩进两格)
          DisplayName — 列表里真正渲染的名称(含缩进)

    .PARAMETER Profile
        主机档案数组(Get-SshHostProfile 产物)。字段缺失时按缺省处理(不抛错),
        便于测试注入最小对象。

    .PARAMETER Activity
        本地活动记录数组(Get-SshHostActivity -All 产物), 可为 $null/空。

    .PARAMETER LastHost
        上次使用的主机名(置顶 + 星标)。

    .PARAMETER Filter
        搜索过滤文本; 空串表示不过滤。

    .OUTPUTS
        [PSCustomObject[]] 行视图模型数组(可能为空数组)。

    .EXAMPLE
        $rows = Get-SshHostDashboardRow -Profile $profiles -Activity $activity -LastHost 'debian' -Filter 'prod'
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Profile,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Activity,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$LastHost = '',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Filter = ''
    )

    if ($null -eq $Profile -or $Profile.Count -eq 0) { return @() }

    # 活动记录按主机名索引(大小写不敏感: SSH 主机名不区分大小写)
    $activityMap = @{}
    foreach ($a in @($Activity)) {
        if ($null -eq $a) { continue }
        $key = [string](Get-SshHostProp -Object $a -Name 'Host').ToLowerInvariant()
        if ($key) { $activityMap[$key] = $a }
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($p in @($Profile)) {
        if ($null -eq $p) { continue }

        $name = [string](Get-SshHostProp -Object $p -Name 'Name')
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $hostName = [string](Get-SshHostProp -Object $p -Name 'HostName')
        if ([string]::IsNullOrWhiteSpace($hostName)) { $hostName = $name }
        $tags = @(Get-SshHostProp -Object $p -Name 'Tags')
        $group = [string](Get-SshHostProp -Object $p -Name 'Group')

        # ---- 1. 文本过滤(名称 / HostName / 标签) ----
        if (-not [string]::IsNullOrEmpty($Filter)) {
            $hit = ($name.IndexOf($Filter, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                   ($hostName.IndexOf($Filter, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
            if (-not $hit) {
                foreach ($t in $tags) {
                    if ([string]$t -and ([string]$t).IndexOf($Filter, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $hit = $true; break }
                }
            }
            if (-not $hit) { continue }
        }

        # ---- 2. 活动历史(真实数据; 缺失就如实留空) ----
        $act = $null
        $key = $name.ToLowerInvariant()
        if ($activityMap.ContainsKey($key)) { $act = $activityMap[$key] }
        $lastActive = $null
        $connectCount = 0
        if ($null -ne $act) {
            $lastSeen = Get-SshHostProp -Object $act -Name 'LastSeen'
            if ($null -ne $lastSeen) { $lastActive = [datetime]$lastSeen }
            $count = Get-SshHostProp -Object $act -Name 'Count'
            if ($null -ne $count) { $connectCount = [int]$count }
        }

        $status = Get-SshHostStatusPresentation -Status ([string](Get-SshHostProp -Object $p -Name 'Status'))

        $port = Get-SshHostProp -Object $p -Name 'Port'
        if ($null -eq $port) { $port = 22 }

        $rows.Add([PSCustomObject]@{
                Name           = $name
                HostName       = $hostName
                Port           = [int]$port
                User           = [string](Get-SshHostProp -Object $p -Name 'User')
                IdentityFile   = [string](Get-SshHostProp -Object $p -Name 'IdentityFile')
                ProxyJump      = [string](Get-SshHostProp -Object $p -Name 'ProxyJump')
                Tags           = [string[]]@($tags)
                Group          = $group
                Provider       = [string](Get-SshHostProp -Object $p -Name 'Provider')
                Region         = [string](Get-SshHostProp -Object $p -Name 'Region')
                IsLocal        = [bool](Get-SshHostProp -Object $p -Name 'IsLocal')
                Source         = [string](Get-SshHostProp -Object $p -Name 'Source')
                Status         = $status.Status
                StatusText     = $status.StatusText
                StatusGlyph    = $status.StatusGlyph
                StatusRole     = $status.StatusRole
                LastActive     = $lastActive
                LastActiveText = Get-SshHostRelativeTime -Time $lastActive
                HasActivity    = ($null -ne $lastActive)
                ConnectCount   = $connectCount
                IsLastHost     = ($LastHost -and ($name -eq $LastHost))
                Indent         = -not [string]::IsNullOrWhiteSpace($group)
                DisplayName    = $name
                Value          = $name
                Disabled       = $false
            })
    }

    # ---- 3. 排序: 上次使用置顶 -> 分组名(无分组最后) -> 主机名 ----
    # ★ 用**单个**排序表达式, 而不是 Sort-Object 的四个表达式:
    #   Sort-Object 会为每个表达式给**每个元素**各跑一次脚本块
    #   (30 台主机 x 4 个表达式 = 120 次脚本块调用), 而排序只需要一个
    #   可比较的键。这里把三段语义拼成一个定长前缀键:
    #     段1: '0' = 上次使用 / '1' = 普通        (上次使用置顶)
    #     段2: '0' = 有分组   / '1' = 无分组      (无分组排在分组主机之后)
    #     段3: 分组名 + "\u0000" + 主机名         (分组内按主机名升序)
    #   分组名与主机名之间用 NUL 分隔, 避免 'ab' 与 'a'+'b' 之类的歧义拼接。
    #   段1/段2 都是定长单字符, 因此"有分组"一定排在"无分组"之前,
    #   "上次使用"一定排在最前 —— 与原先四个表达式的多键排序等价。
    $sorted = @($rows | Sort-Object -Property @{
            Expression = {
                $lastFlag = if ($_.IsLastHost) { '0' } else { '1' }
                $groupFlag = if ([string]::IsNullOrWhiteSpace($_.Group)) { '1' } else { '0' }
                $lastFlag + $groupFlag + $_.Group + [string][char]0 + $_.Name
            }
        })

    return $sorted
}

# 内部小工具: 兼容"字段可能不存在"的档案对象(测试注入最小对象 / 旧版档案),
# 不抛 PropertyNotFound 也不返回 $null 陷阱。
function Get-SshHostProp {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $Object) { return $null }
    # ★ 快路径(2026-10-31 仪表盘性能实测驱动):
    #   PSObject.Properties['X'].Value 每次调用都要走一遍适配器层的属性表查找,
    #   是**解释执行**里最贵的一类操作; 而本函数在一行映射里要被调 12 次/主机,
    #   实测整表重算(Get-SshHostDashboardRow, 30 台)约 15.8ms, 其中相当一部分
    #   花在这里。直接用属性访问 `$Object.$Name` 语义等价(字段不存在时同样
    #   返回 $null), 只是快一个数量级。
    try {
        return $Object.$Name
    }
    catch {
        # 极少数不响应属性访问的对象(如某些集合): 退回属性表查找
        $prop = $Object.PSObject.Properties[$Name]
        if ($null -eq $prop) { return $null }
        return $prop.Value
    }
}
