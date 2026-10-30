# New-WelcomeBanner.ps1 - 欢迎横幅构建器
# P2-2: 统一风格化的欢迎 banner, 与 TGUI 表格头部视觉一致
# 设计原则:
# 1. 纯函数 New-WelcomeBanner 返回行数组, 便于 Pester 测试
# 2. Show-UserScoopLogo (Public) 内部委托给 New-WelcomeBanner, 保持向后兼容
# 3. 语录缓存: $script:QuotesCache (mtime + 内容快照) 避免每次 profile 加载读盘
# 4. 调用方负责实际渲染: $lines | ForEach-Object { [Console]::WriteLine($_) }

function Get-RandomQuote {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([string])]
    <#
    .SYNOPSIS
        从语录文件读取并随机抽取一行(纯函数封装 + 缓存)

    .DESCRIPTION
        缓存基于文件 mtime: 文件未变化时复用上次的随机抽取结果, 避免每次
        profile 加载都读取并 -split 整个 quotes 文件。读取失败/文件不存在时
        返回 fallback 字符串。

    .PARAMETER QuotesPath
        语录文件完整路径; 为空时直接返回 fallback

    .PARAMETER Fallback
        当文件不存在或解析失败时返回的默认文本

    .OUTPUTS
        [string] 随机抽取的语录(已 Trim)
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$QuotesPath,

        [Parameter(Mandatory = $false)]
        [string]$Fallback = 'SYSTEM READY'
    )

    if (-not $QuotesPath) { return $Fallback }

    # 一次 Get-Item 替代 Test-Path + Get-Item
    $fileInfo = Get-Item $QuotesPath -ErrorAction SilentlyContinue
    if (-not $fileInfo) { return $Fallback }

    $mtime = $fileInfo.LastWriteTimeUtc.Ticks
    $cacheHit = $false
    if ($script:QuotesCache -and $script:QuotesCache.Path -eq $QuotesPath -and $script:QuotesCache.MTime -eq $mtime) {
        $lines = $script:QuotesCache.Lines
        $cacheHit = $true
    }
    if (-not $cacheHit) {
        $lines = (Get-Content $QuotesPath -Encoding UTF8 -Raw) -split "(?m)^%\r?\n"
        $script:QuotesCache = @{
            Path  = $QuotesPath
            MTime = $mtime
            Lines = $lines
        }
    }
    if ($lines -and $lines.Count -gt 0) {
        # 过滤空串/纯空白: Get-Random -InputObject 不接受空字符串
        $validLines = @($lines | Where-Object { $_ -and $_.Trim() })
        if ($validLines.Count -gt 0) {
            $picked = ($validLines | Get-Random).Trim()
            if ($picked) { return $picked }
        }
    }
    return $Fallback
}

function New-WelcomeBanner {
    <#
    .SYNOPSIS
        构造欢迎横幅(纯函数, 返回行数组, 不做 I/O)

    .DESCRIPTION
        风格与 TGUI 表格的 Header 区域保持一致:
          ╔══< user@host >══[ cwd ]══[ title ] [badge1] [badge2]
          ║
          ║  ~ quote
          ║  timestamp
          ║
          ║  ~
          ╚══════════════════════════════════════════════════

        不写控制台, 适合测试与单元渲染。

    .PARAMETER Title
        横幅主标题(默认 'SHELL PROMPT')

    .PARAMETER Subtitle
        横幅副标题/语录(默认 SYSTEM READY)

    .PARAMETER Badges
        右侧徽章数组(@{ Text="..."; Color="..."} 或纯字符串)

    .PARAMETER Width
        横幅宽度, 默认 60, 最小 40

    .PARAMETER UserName
        用户名(默认从 $env:USERNAME 读)

    .PARAMETER HostName
        主机名(默认从 $env:COMPUTERNAME 读)

    .PARAMETER Cwd
        当前目录的简短显示(默认 Split-Path -Leaf $PWD.Path)

    .PARAMETER Colors
        颜色覆盖表 @{ Primary, Accent, Muted, Border, Rst }

    .OUTPUTS
        [string[]] 横幅行数组(每行不含末尾换行)
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Title = 'SHELL PROMPT',

        [Parameter(Mandatory = $false)]
        [string]$Subtitle = 'SYSTEM READY',

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [array]$Badges = @(),

        [Parameter(Mandatory = $false)]
        [ValidateRange(40, 200)]
        [int]$Width = 60,

        [Parameter(Mandatory = $false)]
        [string]$UserName,

        [Parameter(Mandatory = $false)]
        [string]$HostName,

        [Parameter(Mandatory = $false)]
        [string]$Cwd,

        [Parameter(Mandatory = $false)]
        [hashtable]$Colors
    )

    # 颜色预解析: 统一走 Resolve-ColorTable(调用方覆盖 -> 预热缓存 -> 配置层默认值)
    $colorTable = Resolve-ColorTable -Name 'Primary', 'Accent', 'Muted', 'Rst', 'Border' -Colors $Colors
    $primary = $colorTable.Primary
    $accent  = $colorTable.Accent
    $muted   = $colorTable.Muted
    $border  = $colorTable.Border
    $rst     = $colorTable.Rst

    if (-not $UserName) { $UserName = if ($env:USERNAME) { $env:USERNAME } else { 'user' } }
    if (-not $HostName) { $HostName = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { 'local' } }
    if (-not $Cwd) {
        $Cwd = Split-Path -Leaf $PWD.Path
        if (-not $Cwd) { $Cwd = $PWD.Path }
    }

    # 徽章串: 拼接 " [text1] [text2] ..." 形式, 跟标题在同行显示
    $badgeStr = ''
    foreach ($b in $Badges) {
        $txt = if ($b -is [hashtable]) { $b.Text } else { "$b" }
        $col = if ($b -is [hashtable] -and $b.Color) { $b.Color } else { $accent }
        $badgeStr += " ${col}[$txt]${rst}"
    }

    $hLine = '=' * ($Width - 4)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    # 9 行布局(同原 Show-UserScoopLogo): 标题 / 空 / ~ / 引言 / 时间 / 空 / ~ / 分割 / 空
    $lines = @(
        ''
        "  $border--< $muted$UserName@$HostName$border >--[ $accent$Cwd$border ]--[ $primary$Title$border ]${rst}${badgeStr}"
        "  $border|${rst}"
        "  $border|${rst}  $border~${rst}"
        "  $border|${rst}  $primary$Subtitle${rst}"
        "  $border|${rst}  $muted$timestamp${rst}"
        "  $border|${rst}"
        "  $border|${rst}  $border~${rst}"
        "  $border+$hLine---${rst}"
        ''
    )
    return $lines
}
