# Get-SshHostProfile.ps1 - ~/.ssh/config 的**结构化主机档案**解析(数据层)
#
# 为什么需要它:
#   既有的 Get-SshConfigHosts 只返回 Host 别名数组(给 Tab 补全用), 不带
#   HostName / Port / User / IdentityFile, 也没有任何"云服务商 / 区域 / 标签 /
#   分组"信息。sss 新仪表盘的左侧列表要显示状态与标签、右侧 Connection /
#   Infrastructure 卡片要显示连接参数与云主机信息 —— 这些都需要**一个主机
#   一个档案**, 于是把解析能力单列成这条数据层。
#
# 数据来源(不伪造):
#   - 连接字段全部来自 ssh config 里**真实存在的指令**;
#   - Provider / Region / Tags 只能来自人写在 Host 块前的元数据注释
#     (`# @provider AWS` / `# @region us-east-1` / `# @tags prod,web` /
#      `# @group prod`)。没写就留空 —— UI 层按"空"显示"无数据",
#     **绝不用主机名去猜云厂商**。
#
# 解析边界(与 OpenSSH 的差异, 有意为之并在此登记):
#   - `Match` 及其后续属性不属于上一个 Host 块, 按块边界丢弃;
#   - `Include` 按"插入点"展开(会先结束当前 Host 块), 相对路径按**主配置
#     所在目录**解析 —— 生产环境主配置就在 ~/.ssh, 等价于"按 ~/.ssh 解析",
#     同时让测试可以用临时目录隔离, 不必改动 $HOME;
#   - Include 递归限深 5 层、总文件数 32, 且按完整路径去重, 防自引用死循环;
#   - 通配符(`*` / `?`)与非法别名(以 '-' 开头等)不产生档案条目 ——
#     别名最终会进 ssh 命令行, 这里与 Get-SshConfigHosts / Test-SshHostName
#     的白名单保持同一口径。
#
# 缓存: 按"主配置完整路径 + 主配置 mtime + 所有参与解析(含 Include)文件的
#   mtime"做 $script: 级缓存。文件一旦变动就重解析; 测试用 -NoCache 或
#   不同 -ConfigPath 隔离, 不会串味。

function Get-SshHostProfile {
    <#
    .SYNOPSIS
        解析 ssh config, 返回结构化的主机档案数组。

    .DESCRIPTION
        每个 Host 块产出一条档案(Name = 该块第一个合法别名, Aliases = 全部合法别名)。
        同一别名在多个 Host 块里重复出现时**首见为准**, 后续块只补空字段(与 ssh
        自身"第一次取到的值生效"的合并语义一致)。

        文件缺失或读取失败时返回空数组, 不抛异常(与 Get-SshConfigHosts 同口径):
        这里只是界面数据源, 读不到就显示"没有主机", 不该把整个 TUI 拖崩。

    .PARAMETER ConfigPath
        主配置文件路径。缺省为 `$HOME/.ssh/config`。

    .PARAMETER NoCache
        跳过 mtime 缓存强制重解析(测试与"手工改完配置要立刻看到"的场景用)。

    .PARAMETER MaxDepth
        Include 递归深度上限(默认 5)。

    .PARAMETER MaxFiles
        参与解析的文件数上限(默认 32), 防止 Include 通配符吞掉大目录。

    .OUTPUTS
        PSCustomObject 数组: Name / Aliases / HostName / Port / User / IdentityFile /
        ProxyJump / Provider / Region / Tags / Group / IsLocal / Source

    .EXAMPLE
        $profiles = Get-SshHostProfile
        $profiles | Where-Object IsLocal
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath = '',

        [Parameter(Mandatory = $false)]
        [switch]$NoCache,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 32)]
        [int]$MaxDepth = 5,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 512)]
        [int]$MaxFiles = 32
    )

    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        $ConfigPath = Join-Path $HOME '.ssh/config'
    }
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        return @()
    }

    $mainItem = Get-Item -LiteralPath $ConfigPath -ErrorAction SilentlyContinue
    if ($null -eq $mainItem) {
        return @()
    }
    $mainPath = $mainItem.FullName

    # ---- 缓存命中(主配置 + 每个参与文件都未变动) ----
    if (-not $NoCache -and $null -ne $script:SshHostProfileCache) {
        $cache = $script:SshHostProfileCache
        if ($cache.MainPath -ceq $mainPath) {
            $unchanged = $true
            foreach ($file in $cache.Files) {
                $item = Get-Item -LiteralPath $file -ErrorAction SilentlyContinue
                if ($null -eq $item -or $item.LastWriteTimeUtc -ne $cache.Mtimes[$file]) {
                    $unchanged = $false
                    break
                }
            }
            if ($unchanged) {
                return $cache.Profiles
            }
        }
    }

    # ---- 解析(文件顺序 = ssh 的读取顺序: 主配置 -> 各 Include 在插入点展开) ----
    $blocks = [System.Collections.Generic.List[object]]::new()
    $files = [System.Collections.Generic.List[string]]::new()
    $visited = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    # Include 相对路径的基准目录 = 主配置所在目录(生产即 ~/.ssh)
    $baseDirectory = [System.IO.Path]::GetDirectoryName($mainPath)

    Read-SshHostConfigBlock -Path $mainPath -GroupDefault '' -Depth 0 -MaxDepth $MaxDepth `
        -MaxFiles $MaxFiles -Blocks $blocks -Files $files -Visited $visited -BaseDirectory $baseDirectory

    # ---- 归一(补缺省值 / 判本地 / 同名合并) ----
    $profiles = [System.Collections.Generic.List[object]]::new()
    $byName = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($block in $blocks) {
        if ([string]::IsNullOrWhiteSpace($block.Name)) { continue }

        $hostName = $block.HostName
        if ([string]::IsNullOrWhiteSpace($hostName)) { $hostName = $block.Name }
        $port = 22
        if ($block.Port -ge 1 -and $block.Port -le 65535) { $port = [int]$block.Port }

        $isLocal = $false
        foreach ($localName in @('localhost', '127.0.0.1', '::1')) {
            if ($hostName -eq $localName) { $isLocal = $true; break }
        }

        $entry = [PSCustomObject]@{
            Name         = [string]$block.Name
            Aliases      = @($block.Aliases)
            HostName     = [string]$hostName
            Port         = $port
            User         = [string]$block.User
            IdentityFile = [string]$block.IdentityFile
            ProxyJump    = [string]$block.ProxyJump
            Provider     = [string]$block.Provider
            Region       = [string]$block.Region
            Tags         = @($block.Tags)
            Group        = [string]$block.Group
            IsLocal      = $isLocal
            Source       = [string]$block.Source
        }

        $key = [string]$block.Name
        if ($byName.ContainsKey($key)) {
            # 同名块: 首见为准, 后续只补空字段(标签取并集)
            $existing = $profiles[$byName[$key]]
            if ([string]::IsNullOrWhiteSpace($existing.HostName) -and $hostName) { $existing.HostName = [string]$hostName }
            if ([string]::IsNullOrWhiteSpace($existing.User) -and $block.User) { $existing.User = [string]$block.User }
            if ([string]::IsNullOrWhiteSpace($existing.IdentityFile) -and $block.IdentityFile) { $existing.IdentityFile = [string]$block.IdentityFile }
            if ([string]::IsNullOrWhiteSpace($existing.ProxyJump) -and $block.ProxyJump) { $existing.ProxyJump = [string]$block.ProxyJump }
            if ([string]::IsNullOrWhiteSpace($existing.Provider) -and $block.Provider) { $existing.Provider = [string]$block.Provider }
            if ([string]::IsNullOrWhiteSpace($existing.Region) -and $block.Region) { $existing.Region = [string]$block.Region }
            if ([string]::IsNullOrWhiteSpace($existing.Group) -and $block.Group) { $existing.Group = [string]$block.Group }
            if (@($block.Tags).Count -gt 0) {
                $merged = [System.Collections.Generic.List[string]]::new()
                foreach ($tag in @($existing.Tags) + @($block.Tags)) {
                    if ([string]::IsNullOrWhiteSpace($tag)) { continue }
                    if ($merged.Contains($tag)) { continue }
                    $merged.Add([string]$tag)
                }
                $existing.Tags = $merged.ToArray()
            }
            continue
        }

        $byName[$key] = $profiles.Count
        $profiles.Add($entry)
    }

    $result = $profiles.ToArray()

    # ---- 写缓存(只缓存成功解析的结果; mtime 快照与参数无关的文件集合一一对应) ----
    $mtimes = @{}
    foreach ($file in $files) {
        $item = Get-Item -LiteralPath $file -ErrorAction SilentlyContinue
        if ($null -ne $item) { $mtimes[$file] = $item.LastWriteTimeUtc }
    }
    $script:SshHostProfileCache = [PSCustomObject]@{
        MainPath = $mainPath
        Files    = @($files.ToArray())
        Mtimes   = $mtimes
        Profiles = $result
    }

    return $result
}

function Read-SshHostConfigBlock {
    <#
    .SYNOPSIS
        解析单个 ssh config 文件(含递归 Include)并按源码顺序收集 Host 块。

    .DESCRIPTION
        内部实现, 不对外导出。职责刻意切得很薄:
          - 只做"文本 -> 草稿块"的机械转换, 不补缺省值(归一在 Get-SshHostProfile 末尾);
          - Include 在插入点递归, 被包含文件的块 Group 缺省取文件名(不含扩展名) ——
            这是"主机分组"唯一不需要人额外标注的真实来源。

    .PARAMETER Path
        待解析文件的完整路径。

    .PARAMETER GroupDefault
        本文件内块未写 `@group` 时的缺省分组(主配置为空串, Include 文件为文件名)。

    .PARAMETER Depth
        当前递归深度。

    .PARAMETER MaxDepth
        递归深度上限。

    .PARAMETER MaxFiles
        参与解析的文件数上限。

    .PARAMETER Blocks
        收集器(由调用方创建, 保证顺序)。

    .PARAMETER Files
        实际参与解析的文件收集器(供缓存做 mtime 快照)。

    .PARAMETER Visited
        已访问文件集合(完整路径, 大小写不敏感)。

    .PARAMETER BaseDirectory
        Include 相对路径的基准目录。

    .OUTPUTS
        [void] —— 结果通过 Blocks / Files 收集器回传。
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$GroupDefault = '',

        [Parameter(Mandatory = $false)]
        [int]$Depth = 0,

        [Parameter(Mandatory = $false)]
        [int]$MaxDepth = 5,

        [Parameter(Mandatory = $false)]
        [int]$MaxFiles = 32,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Blocks,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Files,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]]$Visited,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$BaseDirectory = ''
    )

    if ($Depth -gt $MaxDepth) { return }
    if ($Files.Count -ge $MaxFiles) { return }

    # 读不到的文件直接跳过; 目录由 Resolve-SshIncludeTarget 展开, 这里只收文件
    $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($null -eq $item -or $item.PSIsContainer) { return }
    $fullPath = $item.FullName
    if (-not $Visited.Add($fullPath)) { return }
    $Files.Add($fullPath)

    $lines = @(Get-Content -LiteralPath $fullPath -Encoding UTF8 -ErrorAction SilentlyContinue)
    if ($null -eq $lines) { $lines = @() }

    $current = $null
    # 待消费的元数据注释: 只在紧邻的 Host 行被消费时生效
    $pending = @{ Provider = ''; Region = ''; Tags = @(); Group = '' }

    foreach ($line in $lines) {
        $text = ([string]$line).Trim()
        if ($text.Length -eq 0) { continue }

        if ($text.StartsWith('#')) {
            if ($text -match '^#\s*@(?<key>provider|region|tags|group)\s*(?<val>.*)$') {
                $metaKey = $matches['key'].ToLowerInvariant()
                $metaValue = ([string]$matches['val']).Trim()
                switch ($metaKey) {
                    'provider' { if ($metaValue) { $pending.Provider = $metaValue } }
                    'region' { if ($metaValue) { $pending.Region = $metaValue } }
                    'group' { if ($metaValue) { $pending.Group = $metaValue; } }
                    'tags' {
                        if ($metaValue) {
                            $pending.Tags = @($metaValue -split ',' | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
                        }
                    }
                }
            }
            continue
        }

        # 行内注释: 只剥离"空白 + #"起的尾部(引号内的 # 不处理, 与 ssh 的常见写法一致)
        $text = ($text -replace '\s+#.*$', '').Trim()
        if ($text.Length -eq 0) { continue }

        if ($text -notmatch '^(?<key>[A-Za-z]+)\s*(?<sep>=|\s)\s*(?<val>.*)$') { continue }
        $keyword = $matches['key'].ToLowerInvariant()
        $value = ([string]$matches['val']).Trim()

        switch ($keyword) {
            'host' {
                # 上一个块到此结束 —— 必须先落盘再开新块, 否则前一整块会静默丢失
                if ($null -ne $current) { [void]$Blocks.Add($current) }
                $current = ConvertTo-SshHostConfigDraft -Patterns $value -Source $fullPath -Pending $pending -GroupDefault $GroupDefault
                $pending = @{ Provider = ''; Region = ''; Tags = @(); Group = '' }
            }
            'match' {
                # Match 之后的属性不属于任何 Host 块 —— 按块边界丢弃
                if ($null -ne $current) { [void]$Blocks.Add($current) }
                $current = $null
                $pending = @{ Provider = ''; Region = ''; Tags = @(); Group = '' }
            }
            'include' {
                # 插入点展开: Include 先结束当前块(见文件头的解析边界登记)
                if ($null -ne $current) { [void]$Blocks.Add($current) }
                $current = $null
                Resolve-SshIncludeTarget -Value $value -BaseDirectory $BaseDirectory |
                    ForEach-Object {
                        Read-SshHostConfigBlock -Path $_ -Depth ($Depth + 1) -MaxDepth $MaxDepth `
                            -MaxFiles $MaxFiles -Blocks $Blocks -Files $Files -Visited $Visited `
                            -BaseDirectory $BaseDirectory `
                            -GroupDefault ([System.IO.Path]::GetFileNameWithoutExtension($_))
                    }
            }
            default {
                if ($null -eq $current) { continue }
                switch ($keyword) {
                    'hostname' { if ([string]::IsNullOrWhiteSpace($current.HostName)) { $current.HostName = $value } }
                    'port' {
                        if ($current.Port -eq 0) {
                            $portValue = 0
                            if ([int]::TryParse($value, [ref]$portValue) -and $portValue -ge 1 -and $portValue -le 65535) {
                                $current.Port = $portValue
                            }
                        }
                    }
                    'user' { if ([string]::IsNullOrWhiteSpace($current.User)) { $current.User = $value } }
                    'identityfile' { if ([string]::IsNullOrWhiteSpace($current.IdentityFile)) { $current.IdentityFile = $value } }
                    'proxyjump' { if ([string]::IsNullOrWhiteSpace($current.ProxyJump)) { $current.ProxyJump = $value } }
                }
            }
        }
    }

    if ($null -ne $current) { [void]$Blocks.Add($current) }
}

function ConvertTo-SshHostConfigDraft {
    <#
    .SYNOPSIS
        由 Host 行的模式串创建一个草稿块(过滤通配符与非法别名)。

    .DESCRIPTION
        内部实现。别名会经主机选择直接进入 ssh 参数, 因此这里复用
        Test-SshHostName 的白名单: 通配符(* ?)、否定模式(!)与以 '-' 开头的
        注入形态一律不产生条目 —— 与 Get-SshConfigHosts 的过滤口径一致。

    .PARAMETER Patterns
        Host 行后面的完整模式串(可能含多个以空白分隔的模式)。

    .PARAMETER Source
        该块所在文件完整路径。

    .PARAMETER Pending
        紧邻的元数据注释集合。

    .PARAMETER GroupDefault
        未写 `@group` 时的缺省分组(Include 文件名)。

    .OUTPUTS
        草稿 PSCustomObject(Name/Aliases/HostName/Port/User/IdentityFile/ProxyJump/
        Provider/Region/Tags/Group/Source)
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Patterns = '',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Source = '',

        [Parameter(Mandatory = $true)]
        [hashtable]$Pending,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$GroupDefault = ''
    )

    $aliases = [System.Collections.Generic.List[string]]::new()
    foreach ($pattern in ($Patterns -split '\s+')) {
        if ([string]::IsNullOrWhiteSpace($pattern)) { continue }
        if ($pattern -match '[*?]') { continue }
        if (-not (Test-SshHostName -HostName $pattern)) { continue }
        if (-not $aliases.Contains($pattern)) { $aliases.Add($pattern) }
    }

    $aliasesArray = $aliases.ToArray()
    $name = ''
    if ($aliasesArray.Count -gt 0) { $name = $aliasesArray[0] }

    $group = [string]$Pending.Group
    if (-not [string]::IsNullOrWhiteSpace($GroupDefault)) {
        # 主配置里没写 @group 就留空; Include 文件缺省用文件名当分组
        if ([string]::IsNullOrWhiteSpace($group)) { $group = $GroupDefault }
    }

    return [PSCustomObject]@{
        Name         = $name
        Aliases      = $aliasesArray
        HostName     = ''
        Port         = 0
        User         = ''
        IdentityFile = ''
        ProxyJump    = ''
        Provider     = [string]$Pending.Provider
        Region       = [string]$Pending.Region
        Tags         = @($Pending.Tags)
        Group        = $group
        Source       = $Source
    }
}

function Resolve-SshIncludeTarget {
    <#
    .SYNOPSIS
        把 Include 指令的值展开成待解析的文件路径列表。

    .DESCRIPTION
        内部实现。支持:
          - 多个以空白分隔的模式;
          - `~` 展开;
          - 相对路径按 BaseDirectory(生产即 ~/.ssh)解析;
          - 通配符 `*`/`?`(用 Get-ChildItem 展开);
          - 目录(展开为目录下的全部文件)。

        不存在的路径静默跳过 —— Include 指向不存在的文件在 ssh 里同样不算错误。

    .PARAMETER Value
        Include 指令的原始值。

    .PARAMETER BaseDirectory
        相对路径的基准目录。

    .OUTPUTS
        [string[]] 已存在的文件完整路径
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Value = '',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$BaseDirectory = ''
    )

    $targets = [System.Collections.Generic.List[string]]::new()
    foreach ($rawPattern in ($Value -split '\s+')) {
        if ([string]::IsNullOrWhiteSpace($rawPattern)) { continue }

        $pattern = $rawPattern
        if ($pattern.StartsWith('~')) {
            $pattern = $HOME + $pattern.Substring(1)
        }
        elseif (-not [System.IO.Path]::IsPathRooted($pattern) -and -not [string]::IsNullOrWhiteSpace($BaseDirectory)) {
            $pattern = Join-Path $BaseDirectory $pattern
        }

        if ($pattern -match '[*?]') {
            $directory = [System.IO.Path]::GetDirectoryName($pattern)
            $leaf = [System.IO.Path]::GetFileName($pattern)
            if ([string]::IsNullOrWhiteSpace($directory) -or -not (Test-Path -LiteralPath $directory -PathType Container)) { continue }
            foreach ($file in @(Get-ChildItem -LiteralPath $directory -Filter $leaf -File -ErrorAction SilentlyContinue)) {
                if (-not $targets.Contains($file.FullName)) { $targets.Add($file.FullName) }
            }
            continue
        }

        if (Test-Path -LiteralPath $pattern -PathType Container) {
            foreach ($file in @(Get-ChildItem -LiteralPath $pattern -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
                if (-not $targets.Contains($file.FullName)) { $targets.Add($file.FullName) }
            }
            continue
        }

        if (Test-Path -LiteralPath $pattern -PathType Leaf) {
            $resolved = (Resolve-Path -LiteralPath $pattern).Path
            if (-not $targets.Contains($resolved)) { $targets.Add($resolved) }
        }
    }

    return $targets.ToArray()
}

function Get-SshHostCategoryList {
    <#
    .SYNOPSIS
        由真实主机档案推导顶部分类栏的分类名列表。

    .DESCRIPTION
        规则(分类**全部来自数据**, 不写死示例主机):
          1. 恒以 'All' 开头;
          2. 其后是实际出现过的 Provider(首次出现顺序, 大小写不敏感去重);
          3. 存在本地主机时追加 'Local'(若没有同名 Provider);
          4. 存在"无 Provider 且非本地"的主机时追加 'Other'(若没有同名 Provider)。

        没有任何主机时只有 'All' —— 空态由 UI 层表达, 不伪造分类。

    .PARAMETER Profiles
        Get-SshHostProfile 的产物(允许空集合)。

    .OUTPUTS
        [string[]] 分类名数组
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [object[]]$Profiles = @()
    )

    $categories = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $categories.Add('All')
    [void]$seen.Add('All')

    $hasLocal = $false
    $hasOther = $false

    foreach ($hostProfile in @($Profiles)) {
        if ($null -eq $hostProfile) { continue }
        $provider = ''
        try { $provider = [string]$hostProfile.Provider } catch { $provider = '' }
        if (-not [string]::IsNullOrWhiteSpace($provider)) {
            if ($seen.Add($provider)) { $categories.Add($provider) }
        }
        elseif (-not $hostProfile.IsLocal) {
            $hasOther = $true
        }
        if ($hostProfile.IsLocal) { $hasLocal = $true }
    }

    if ($hasLocal -and $seen.Add('Local')) { $categories.Add('Local') }
    if ($hasOther -and $seen.Add('Other')) { $categories.Add('Other') }

    return $categories.ToArray()
}

function Select-SshHostByCategory {
    <#
    .SYNOPSIS
        按分类名过滤主机档案(纯函数)。

    .DESCRIPTION
        分类语义与 Get-SshHostCategoryList 严格对应:
          'All'   -> 全部;
          'Local' -> IsLocal 为真的主机;
          'Other' -> 无 Provider 且非本地的主机;
          其它    -> Provider 等于该分类的主机(大小写不敏感)。

        纯函数: 不读文件、不发网络请求 —— UI 层切分类时可以随时重算。

    .PARAMETER Profiles
        Get-SshHostProfile 的产物。

    .PARAMETER Category
        分类名(缺省 'All')。

    .OUTPUTS
        PSCustomObject 数组(保持输入顺序)
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [object[]]$Profiles = @(),

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Category = 'All'
    )

    $selected = [System.Collections.Generic.List[object]]::new()
    $wanted = [string]$Category
    if ([string]::IsNullOrWhiteSpace($wanted)) { $wanted = 'All' }

    foreach ($hostProfile in @($Profiles)) {
        if ($null -eq $hostProfile) { continue }
        $provider = ''
        try { $provider = [string]$hostProfile.Provider } catch { $provider = '' }
        $isLocal = $false
        try { $isLocal = [bool]$hostProfile.IsLocal } catch { $isLocal = $false }

        $match = $false
        if ($wanted -eq 'All') { $match = $true }
        elseif ($wanted -eq 'Local') { $match = $isLocal }
        elseif ($wanted -eq 'Other') { $match = (-not $isLocal) -and [string]::IsNullOrWhiteSpace($provider) }
        else { $match = ($provider -eq $wanted) }

        if ($match) { $selected.Add($hostProfile) }
    }

    return $selected.ToArray()
}
