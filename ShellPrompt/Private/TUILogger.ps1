# ============================================================
# TUILogger.ps1 - TUI 日志系统
# 遵循 ratatui/lazygit 日志设计模式
# ============================================================

# 日志级别枚举
enum TUILogLevel {
    Trace = 0
    Debug = 1
    Info = 2
    Warning = 3
    Error = 4
}

# 日志条目结构
class TUILogEntry {
    [DateTime]$Time
    [TUILogLevel]$Level
    [string]$Message
    [hashtable]$Fields
    [string]$Source

    [string] ToString() {
        $levelStr = $this.Level.ToString().ToUpper().PadRight(7)
        $fieldStr = ""
        
        if ($this.Fields -and $this.Fields.Count -gt 0) {
            $fieldStr = " | " + ($this.Fields.GetEnumerator() | ForEach-Object { 
                    "$($_.Key)=$($_.Value)" 
                }) -join " "
        }
        
        $sourceStr = ""
        if ($this.Source) {
            $sourceStr = " [$($this.Source)]"
        }
        
        $timeStr = $this.Time.ToString('HH:mm:ss.fff')
        return "[$timeStr] $levelStr$sourceStr $($this.Message)$fieldStr"
    }
}

# TUI 日志记录器
class TUILogger {
    [TUILogLevel]$MinLevel
    [System.IO.StreamWriter]$FileWriter
    [bool]$EnableConsole
    [bool]$EnableFile
    [string]$LogFilePath
    [int]$MaxFileSizeMb = 10
    [int]$MaxBackupFiles = 3
    
    TUILogger() {
        $this.MinLevel = [TUILogLevel]::Warning
        $this.EnableConsole = $true
        $this.EnableFile = $false
    }
    
    TUILogger([TUILogLevel]$level, [string]$logFile) {
        $this.MinLevel = $level
        $this.EnableConsole = $true
        
        if ($logFile) {
            $this.LogFilePath = $logFile
            $this.EnableFile = $this.InitFileWriter($logFile)
        }
    }
    
    [bool] InitFileWriter([string]$logFile) {
        try {
            $logDir = Split-Path $logFile -Parent
            if (-not (Test-Path $logDir)) {
                New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            }
            
            $this.FileWriter = [System.IO.StreamWriter]::new($logFile, $true)
            $this.FileWriter.AutoFlush = $true
            return $true
        } catch {
            Write-Host "[TUILogger] 初始化日志文件失败: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }
    
    [void] Log([TUILogLevel]$level, [string]$message) {
        $this.Log($level, $message, $null, $null)
    }
    
    [void] Log([TUILogLevel]$level, [string]$message, [string]$source) {
        $this.Log($level, $message, $null, $source)
    }
    
    [void] Log([TUILogLevel]$level, [string]$message, [hashtable]$fields, [string]$source) {
        if ($level -lt $this.MinLevel) { return }
        
        $entry = [TUILogEntry]@{
            Time    = [DateTime]::UtcNow
            Level   = $level
            Message = $message
            Fields  = $fields
            Source  = $source
        }
        
        $output = $entry.ToString()
        
        # 控制台输出（带颜色）
        if ($this.EnableConsole) {
            $color = switch ($level) {
                ([TUILogLevel]::Error) { "Red" }
                ([TUILogLevel]::Warning) { "Yellow" }
                ([TUILogLevel]::Debug) { "Cyan" }
                ([TUILogLevel]::Trace) { "DarkGray" }
                default { "White" }
            }
            Write-Host $output -ForegroundColor $color
        }
        
        # 文件输出
        if ($this.EnableFile -and $this.FileWriter) {
            # 检查文件大小，执行滚动
            $this.RotateIfNeeded()
            $this.FileWriter.WriteLine($output)
        }
    }
    
    [void] RotateIfNeeded() {
        if (-not $this.LogFilePath -or -not (Test-Path $this.LogFilePath)) { return }
        
        try {
            $fileInfo = Get-Item $this.LogFilePath -ErrorAction SilentlyContinue
            if ($fileInfo -and $fileInfo.Length -gt ($this.MaxFileSizeMb * 1MB)) {
                $this.FileWriter.Close()
                
                # 滚动备份文件
                for ($i = $this.MaxBackupFiles; $i -gt 1; $i--) {
                    $oldFile = "$($this.LogFilePath).$($i - 1)"
                    $newFile = "$($this.LogFilePath).$i"
                    if (Test-Path $oldFile) {
                        Move-Item -Path $oldFile -Destination $newFile -Force
                    }
                }
                
                # 当前日志文件变成 .1
                Move-Item -Path $this.LogFilePath -Destination "$($this.LogFilePath).1" -Force
                
                # 重新打开
                $this.FileWriter = [System.IO.StreamWriter]::new($this.LogFilePath, $true)
                $this.FileWriter.AutoFlush = $true
            }
        } catch {
            # 忽略滚动错误
        }
    }
    
    # 便捷方法
    [void] Trace([string]$message) {
        $this.Log([TUILogLevel]::Trace, $message, $null, $this.GetCaller())
    }
    
    [void] Debug([string]$message) {
        $this.Log([TUILogLevel]::Debug, $message, $null, $this.GetCaller())
    }
    
    [void] Info([string]$message) {
        $this.Log([TUILogLevel]::Info, $message, $null, $this.GetCaller())
    }
    
    [void] Warning([string]$message) {
        $this.Log([TUILogLevel]::Warning, $message, $null, $this.GetCaller())
    }
    
    [void] Error([string]$message) {
        $this.Log([TUILogLevel]::Error, $message, $null, $this.GetCaller())
    }
    
    [void] Error([string]$message, [hashtable]$fields) {
        $this.Log([TUILogLevel]::Error, $message, $fields, $this.GetCaller())
    }
    
    # 获取调用者信息
    hidden [string] GetCaller() {
        $caller = (Get-PSCallStack)[2]
        if ($caller) {
            $fileName = Split-Path $caller.ScriptName -Leaf
            return "$fileName`:$($caller.ScriptLineNumber)"
        }
        return $null
    }
    
    [void] Dispose() {
        if ($this.FileWriter) {
            $this.FileWriter.Close()
            $this.FileWriter.Dispose()
        }
    }
}

# 全局日志记录器实例
$Global:TUI_Logger = $null

# 初始化全局日志记录器
function Initialize-TUILogger {
    <#
    .SYNOPSIS
    初始化 TUI 日志记录器
    
    .DESCRIPTION
    根据 DEBUG 环境变量和配置初始化日志系统
    #>
    
    # 读取配置中的日志路径
    $logPath = $null
    if ($global:UserScoop_CONF -and $global:UserScoop_CONF.LogPath) {
        $logPath = $global:UserScoop_CONF.LogPath
    } else {
        # 默认路径
        $logDir = Join-Path $env:TEMP "ShellPrompt"
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        $logPath = Join-Path $logDir "shellprompt.log"
    }
    
    # 确定日志级别
    $logLevel = [TUILogLevel]::Warning
    
    if ($env:DEBUG -eq "1" -or $env:DEBUG -eq "true") {
        $logLevel = [TUILogLevel]::Debug
    }
    if ($env:DEBUG_TRACE -eq "1") {
        $logLevel = [TUILogLevel]::Trace
    }
    
    # 创建日志记录器
    $Global:TUI_Logger = [TUILogger]::new($logLevel, $logPath)
    
    # 如果启用了调试，输出一条启动日志
    if ($logLevel -ge [TUILogLevel]::Debug) {
        $Global:TUI_Logger.Info("TUI Logger initialized. Debug mode: $($env:DEBUG), LogLevel: $logLevel, LogFile: $logPath")
    }
    
    return $Global:TUI_Logger
}

# 便捷访问函数
function Write-TUILog {
    <#
    .SYNOPSIS
    写入 TUI 日志的便捷函数
    #>
    param(
        [Parameter(Mandatory = $true)]
        [TUILogLevel]$Level,
        
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [hashtable]$Fields = $null,
        
        [string]$Source = $null
    )
    
    if ($Global:TUI_Logger) {
        $Global:TUI_Logger.Log($Level, $Message, $Fields, $Source)
    }
}

# 调试模式检查
function Test-TUIDebugMode {
    <#
    .SYNOPSIS
    检查是否处于调试模式
    #>
    return ($env:DEBUG -eq "1" -or $env:DEBUG -eq "true")
}

# 便捷访问函数