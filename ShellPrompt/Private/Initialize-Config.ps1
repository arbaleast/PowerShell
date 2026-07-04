# Initialize-Config.ps1 - 模块配置初始化 & 配置访问助手
# 单一配置源: $script:Config 按域划分(Colors/Keys/Paths/SSH),
# 读取统一走 Get-CachedConfig;热路径键值预热到 $script:_ColorCache
# 以减少菜单/Logo 渲染中的 4 段三层回退。

# 1. 模块根路径（脚本级，不暴露为全局变量）
$script:ShellPromptRoot = (Get-Item $PSScriptRoot).Parent.Parent.FullName

# 2. 单一来源：模块级配置对象（按域划分：Colors / Keys / SSH / Paths）
$script:Config = [ordered]@{
    Paths  = [ordered]@{
        Quotes  = Join-Path $script:ShellPromptRoot 'data\quotes.txt'
        LogPath = Join-Path $env:TEMP 'ShellPrompt\shellprompt.log'
    }
    Colors = [ordered]@{
        FreshGreen = "`e[38;2;137;209;133m"
        SageGreen  = "`e[38;2;159;177;159m"
        DarkGray   = "`e[38;2;50;50;50m"
        MidGray    = "`e[38;2;100;100;100m"
        LightGray  = "`e[38;2;180;180;180m"
        White      = "`e[38;2;255;255;255m"
        Rst        = "`e[0m"
        Bold       = "`e[1m"
        Dim        = "`e[2m"
    }
    Keys   = [ordered]@{
        Up    = 38
        Down  = 40
        Enter = 13
        Esc   = 27
    }
    SSH    = [ordered]@{
        ConnectTimeout = 5
        ForceTTy       = $true
    }
}

# 3. 上次使用的 SSH 主机（用于菜单置顶，保持全局以便 profile/外部脚本可见）
$Global:LastSshHost = $null

# 4. 确保数据目录存在
try {
    $dataDir = Join-Path $script:ShellPromptRoot 'data'
    if (-not (Test-Path $dataDir)) {
        New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    }
} catch {
    Write-Verbose "初始化数据目录失败: $($_.Exception.Message)"
}

# 5. 预热热路径值到 $script 作用域,菜单/Logo 渲染时直接命中快路径,
#    避免在每次菜单绘制时重复执行回退查询 (Invoke-ConsoleMenu 每次红绘约 5-10 次)。
#    注: 仅缓存"非空字符串"键值;若用户配置在运行时被修改,请清除此缓存。
$script:_ColorCache = @{
    'Colors|FreshGreen' = $script:Config.Colors.FreshGreen
    'Colors|SageGreen'  = $script:Config.Colors.SageGreen
    'Colors|MidGray'    = $script:Config.Colors.MidGray
    'Colors|Rst'        = $script:Config.Colors.Rst
    'Keys|Up'           = $script:Config.Keys.Up
    'Keys|Down'         = $script:Config.Keys.Down
    'Keys|Enter'        = $script:Config.Keys.Enter
    'Keys|Esc'          = $script:Config.Keys.Esc
    'Paths|Quotes'      = $script:Config.Paths.Quotes
}

# 6. 统一配置读取入口: 优先命中 $script:_ColorCache 预热键,
#    冷路径直接回退到 $script:Config。
function Get-CachedConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Paths', 'Colors', 'Keys', 'SSH')]
        [string]$Section,

        [Parameter(Mandatory = $true)]
        [string]$Key,

        [Parameter(Mandatory = $false)]
        [object]$Default
    )
    $cacheKey = "${Section}|${Key}"
    if ($script:_ColorCache.ContainsKey($cacheKey)) {
        $cached = $script:_ColorCache[$cacheKey]
        if ($null -ne $cached -and "$cached" -ne '') { return $cached }
    }
    # 冷路径: 直接走 $script:Config,未命中则返回传入的 $Default
    if ($script:Config -and $script:Config[$Section] -and $null -ne $script:Config[$Section][$Key]) {
        return $script:Config[$Section][$Key]
    }
    return $Default
}
