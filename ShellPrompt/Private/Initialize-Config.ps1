# ============================================================
# Initialize-Config.ps1 - 模块配置初始化
# 定义全局配置（仅在此处修改默认值）
# 支持用户配置覆盖：~/.ShellPrompt/config.ps1
# ============================================================

$global:UserScoop_ROOT = (Get-Item $PSScriptRoot).Parent.Parent.FullName

$global:UserScoop_CONF = @{
    Quotes        = "$global:UserScoop_ROOT\data\quotes.txt"
    
    # 日志路径（由 TUILogger 使用）
    LogPath       = "$env:TEMP\ShellPrompt\shellprompt.log"

    Colors        = @{
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

    Keys          = @{
        Up    = 38
        Down  = 40
        Enter = 13
        Esc   = 27
    }

    SSH           = @{
        ConnectTimeout = 5
        ForceTTy       = $true
    }

    WaterReminder = @{
        Enabled         = $true
        IntervalMin     = 60           # 基础间隔(分钟)
        DayGoalMl       = 2000         # 每日目标(ml)
        QuietHoursStart = 22           # 夜间休眠开始(22:00)
        QuietHoursEnd   = 7            # 夜间休眠结束(07:00)
        WeatherEnabled  = $true        # 是否启用天气感知
        HistoryPath     = "$global:UserScoop_ROOT\data\water-history.json"
        LogPath         = "$global:UserScoop_ROOT\data\water-reminder.log"
    }
}

# -----------------------------
# 用户配置覆盖
# -----------------------------
function Merge-UserConfig {
    <#
    .SYNOPSIS
    合并用户配置到全局配置
    
    .DESCRIPTION
    从 ~/.ShellPrompt/config.ps1 加载用户配置
    用户配置使用 $global:UserScoop_CONF 变量来覆盖默认值
    支持 hashtable 深度合并
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$DefaultConfig,
        
        [Parameter(Mandatory = $false)]
        [string]$UserConfigPath = (Join-Path $HOME ".ShellPrompt\config.ps1")
    )
    
    if (-not (Test-Path $UserConfigPath)) {
        return $DefaultConfig
    }
    
    try {
        # 使用脚本块执行用户配置，获取返回值
        # 用户配置脚本应该返回要合并的 hashtable
        $userConfig = & $UserConfigPath
        if ($userConfig -is [hashtable]) {
            return Merge-Hashtable -Base $DefaultConfig -Override $userConfig
        }
    } catch {
        Write-Host "[Initialize-Config] 用户配置加载失败: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    return $DefaultConfig
}

function Merge-Hashtable {
    <#
    .SYNOPSIS
    深度合并两个 hashtable
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
            $result[$key] = Merge-Hashtable -Base $Base[$key] -Override $Override[$key]
        } else {
            $result[$key] = $Base[$key]
        }
    }
    
    # 合并覆盖配置
    foreach ($key in $Override.Keys) {
        if ($result.ContainsKey($key) -and $result[$key] -is [hashtable] -and $Override[$key] -is [hashtable]) {
            $result[$key] = Merge-Hashtable -Base $result[$key] -Override $Override[$key]
        } else {
            $result[$key] = $Override[$key]
        }
    }
    
    return $result
}

# 尝试加载用户配置覆盖（如果存在）
$userConfigPath = Join-Path $HOME ".ShellPrompt\config.ps1"
if (Test-Path $userConfigPath) {
    $global:UserScoop_CONF = Merge-UserConfig -DefaultConfig $global:UserScoop_CONF -UserConfigPath $userConfigPath
}

# -----------------------------
# 兼容性辅助函数
# -----------------------------
function Get-PowerShellExe {
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

function ConvertFromJsonCompat {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Json
    )

    function _ConvertRecursive {
        param($value)
        if ($null -eq $value) { return $null }

        if ($value -is [System.Management.Automation.PSObject]) {
            $ht = @{}
            foreach ($p in $value.psobject.Properties) {
                $ht[$p.Name] = _ConvertRecursive $p.Value
            }
            return $ht
        } elseif ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
            # 使用 ArrayList 避免数组拼接的 O(n²) 性能问题
            $arr = New-Object System.Collections.ArrayList
            foreach ($i in $value) { [void]$arr.Add((_ConvertRecursive $i)) }
            return $arr
        } else {
            return $value
        }
    }

    if (-not $Json) { return @{} }

    $obj = $Json | ConvertFrom-Json
    return _ConvertRecursive $obj
}

# -----------------------------
# 全局状态变量初始化
# -----------------------------
# SSH/TMUX 上次使用的主机名（用于菜单置顶）
$Global:LastSshHost = $null

# Ensure data and log directories exist and provide a default empty history file
try {
    $wr = $global:UserScoop_CONF.WaterReminder
    if ($wr) {
        $historyDir = Split-Path $wr.HistoryPath -Parent
        if (-not (Test-Path $historyDir)) { New-Item -ItemType Directory -Path $historyDir -Force | Out-Null }

        $logDir = Split-Path $wr.LogPath -Parent
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

        if (-not (Test-Path $wr.HistoryPath)) {
            '{}' | Out-File -FilePath $wr.HistoryPath -Encoding UTF8 -Force
        }
    }
} catch {
    # 不要阻塞模块加载：只记录到主机日志
    Write-Verbose "初始化数据目录失败: $($_.Exception.Message)"
}

