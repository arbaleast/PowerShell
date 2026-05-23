# ============================================================
# Initialize-Config.ps1 - 模块配置初始化
# 定义全局配置（仅在此处修改默认值）
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
        MintGreen  = "`e[38;2;137;209;133m"
        SoftGreen  = "`e[38;2;159;177;159m"
        
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

    Tmux          = @{
        DefaultSessionName = "main"
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

