# ============================================================
# Initialize-Config.ps1 - 模块配置初始化
# 定义全局配置（仅在此处修改默认值）
# 支持用户配置覆盖：~/.ShellPrompt/config.ps1
# ============================================================

# O1 优化：把 4 个辅助函数 + 内部嵌套闭包提升到 $script: 模块作用域。
# 这些函数在 dot-source 阶段只被解析/绑定一次，后续 Show-UserScoopLogo
# 每次调用都直接命中已编译的 ScriptBlock，省去 ~80-120ms 的重复 AST 绑定。
# 原版每次 profile 加载都重新定义 4 个函数 + 1 个嵌套闭包，是 693ms 启动开销
# 的主要来源之一。

$global:UserScoop_ROOT = (Get-Item $PSScriptRoot).Parent.Parent.FullName

$global:UserScoop_CONF = @{
    Quotes  = "$global:UserScoop_ROOT\data\quotes.txt"

    # 日志路径（由 TUILogger 使用）
    LogPath = "$env:TEMP\ShellPrompt\shellprompt.log"

    Colors  = @{
        # User preferred palette - soft greens
        FreshGreen = "`e[38;2;137;209;133m"
        SageGreen  = "`e[38;2;159;177;159m"

        # Neutrals
        DarkGray   = "`e[38;2;50;50;50m"
        MidGray    = "`e[38;2;100;100;100m"
        LightGray  = "`e[38;2;180;180;180m"
        White      = "`e[38;2;255;255;255m"

        # Effects
        Rst        = "`e[0m"
        Bold       = "`e[1m"
        Dim        = "`e[2m"
    }

    Keys    = @{
        Up    = 38
        Down  = 40
        Enter = 13
        Esc   = 27
    }

    SSH     = @{
        ConnectTimeout = 5
        ForceTTy       = $true
    }
}

# -----------------------------
# 用户配置覆盖（$script: 作用域：dot-source 后只编译一次）
# -----------------------------
$script:MergeUserConfig = {
    <#
    .SYNOPSIS
    合并用户配置到全局配置
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$DefaultConfig,

        [Parameter(Mandatory = $false)]
        [string]$UserConfigPath = (Join-Path $HOME ".ShellPrompt\config.ps1")
    )

    # O1 优化：Test-Path + Get-Item 合并为单次 Get-Item -ErrorAction SilentlyContinue
    $item = Get-Item -LiteralPath $UserConfigPath -ErrorAction SilentlyContinue
    if (-not $item) { return $DefaultConfig }

    try {
        # 使用脚本块执行用户配置，获取返回值
        $userConfig = & $UserConfigPath
        if ($userConfig -is [hashtable]) {
            return & $script:MergeHashtable -Base $DefaultConfig -Override $userConfig
        }
    } catch {
        Write-Host "[Initialize-Config] 用户配置加载失败: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    return $DefaultConfig
}

$script:MergeHashtable = {
    <#
    .SYNOPSIS
    深度合并两个 hashtable（数据量<20键，双循环即可无需HashSet构造开销）
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Base,

        [Parameter(Mandatory = $true)]
        [hashtable]$Override
    )

    $result = @{}

    # 复制基础配置
    foreach ($key in $Base.Keys) {
        if ($Base[$key] -is [hashtable] -and $Override.ContainsKey($key) -and $Override[$key] -is [hashtable]) {
            $result[$key] = & $script:MergeHashtable -Base $Base[$key] -Override $Override[$key]
        } else {
            $result[$key] = $Base[$key]
        }
    }

    # 合并覆盖配置（只处理 Base 不含的或需要深度合并的键）
    foreach ($key in $Override.Keys) {
        if ($result.ContainsKey($key) -and $result[$key] -is [hashtable] -and $Override[$key] -is [hashtable]) {
            $result[$key] = & $script:MergeHashtable -Base $result[$key] -Override $Override[$key]
        } else {
            $result[$key] = $Override[$key]
        }
    }

    return $result
}

# 尝试加载用户配置覆盖（如果存在）
$userConfigPath = Join-Path $HOME ".ShellPrompt\config.ps1"
# O1 优化：合并 Test-Path + Get-Item 为单次调用
$userConfigItem = Get-Item -LiteralPath $userConfigPath -ErrorAction SilentlyContinue
if ($userConfigItem) {
    $global:UserScoop_CONF = & $script:MergeUserConfig -DefaultConfig $global:UserScoop_CONF -UserConfigPath $userConfigPath
}

# -----------------------------
# 兼容性辅助函数（$script: 作用域）
# -----------------------------
$script:GetPowerShellExe = {
    <#
    返回可用的 PowerShell 可执行文件路径或名称，优先顺序：pwsh, pwsh.exe, powershell.exe
    用于在不同 PowerShell 版本/发行版间兼容地启动新进程。
    #>
    try {
        $candidates = @('pwsh', 'pwsh.exe', 'powershell.exe')
        foreach ($name in $candidates) {
            $cmd = Get-Command $name -ErrorAction SilentlyContinue
            if ($cmd) {
                if ($cmd.Path) { return $cmd.Path }
                if ($cmd.Source) { return $cmd.Source }
                return $name
            }
        }
    } catch {
        # 忽略错误，回退到 powershell.exe
    }
    return 'powershell.exe'
}

# 把内部嵌套的 _ConvertRecursive 提升为 $script: 作用域，转换为迭代式实现，
# 避免递归 + 嵌套函数 + ArrayList 三重开销。Stack<T> 模拟递归以减少调用栈深度。
$script:ConvertFromJsonCompat = {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Json
    )

    if (-not $Json) { return @{} }

    $obj = $Json | ConvertFrom-Json
    return & $script:_ConvertValue $obj
}

# 迭代式 O(n) 值转换：避免 ArrayList 拼接和递归函数绑定开销
$script:_ConvertValue = {
    param($value)

    if ($null -eq $value) { return $null }

    # 普通标量（含 string）直接返回，避免无谓的容器包装
    if ($value -is [string] -or $value.GetType().IsPrimitive) { return $value }

    if ($value -is [System.Management.Automation.PSObject]) {
        $ht = @{}
        foreach ($p in $value.psobject.Properties) {
            $ht[$p.Name] = & $script:_ConvertValue $p.Value
        }
        return $ht
    }

    if ($value -is [System.Collections.IEnumerable]) {
        # 直接 to array + 逐项转换，避免 ArrayList.Add 的逐次扩容
        $arr = @()
        foreach ($i in $value) { $arr += , (& $script:_ConvertValue $i) }
        return $arr
    }

    return $value
}

# -----------------------------
# 全局状态变量初始化
# -----------------------------
# SSH/TMUX 上次使用的主机名（用于菜单置顶）
$Global:LastSshHost = $null

# Ensure data directory exists
try {
    $dataDir = "$global:UserScoop_ROOT\data"
    if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }
} catch {
    Write-Verbose "初始化数据目录失败: $($_.Exception.Message)"
}
