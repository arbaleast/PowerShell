# ============================================================
# Get-TmuxSessions.ps1 — 通过 SSH 获取远程 tmux 会话列表
# ============================================================

$Global:LastSshHost = ""

function Get-TmuxSessions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $false)]
        [int]$ConnectTimeout = $global:UserScoop_CONF.SSH.ConnectTimeout
    )

    try {
        $output = ssh -o "ConnectTimeout=$ConnectTimeout" -o "StrictHostKeyChecking=no" $HostName "tmux ls 2>/dev/null" 2>$null | Out-String
    } catch {
        if ($Global:TUI_Logger) {
            $Global:TUI_Logger.Warning("SSH 获取 tmux 会话失败: $($_.Exception.Message)", @{ Host = $HostName })
        }
        return @{ Sessions = New-Object System.Collections.ArrayList; RawOutput = "" }
    }
    
    $sessionList = New-Object System.Collections.ArrayList
    foreach ($line in ($output -split "`n")) {
        if ($line -match '^[^:]+:') {
            $name = ($line -split ':')[0].Trim()
            $status = if ($line -match "attached") {
                "已挂载" 
            } else {
                "后台中" 
            }
            $sessionList.Add([PSCustomObject]@{ Name = $name; Status = $status }) | Out-Null
        }
    }

    return @{ Sessions = $sessionList; RawOutput = $output }
}

function Test-TmuxAvailable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $false)]
        [int]$ConnectTimeout = $global:UserScoop_CONF.SSH.ConnectTimeout
    )

    try {
        $result = ssh -o "ConnectTimeout=$ConnectTimeout" -o "StrictHostKeyChecking=no" $HostName "command -v tmux" 2>$null
        return $null -ne $result
    } catch {
        return $false
    }
}

# ============================================================
# 多终端复用器检测
# 支持 tmux、screen、byobu
# ============================================================
function Get-MultiplexerSessions {
    <#
    .SYNOPSIS
    获取本地多终端复用器会话（tmux/screen/byobu）
    
    .DESCRIPTION
    自动检测可用的终端复用器并获取其会话列表
    支持 tmux、screen、byobu 三种主流复用器
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$HostName = "localhost"
    )
    
    $result = @{
        Detected  = $null          # 检测到的复用器类型
        Available = $false        # 是否可用
        Sessions  = @()            # 会话列表
        RawOutput = ""            # 原始输出
    }
    
    # 优先级：tmux > byobu > screen
    $multiplexers = @('tmux', 'byobu', 'screen')
    
    foreach ($mux in $multiplexers) {
        $cmd = Get-Command $mux -ErrorAction SilentlyContinue
        if ($cmd) {
            $result.Detected = $mux
            $result.Available = $true
            
            # 根据复用器类型获取会话
            $sessions = switch ($mux) {
                'tmux' {
                    & tmux list-sessions 2>$null | ForEach-Object {
                        if ($_ -match '^([^:]+)') {
                            [PSCustomObject]@{
                                Name   = $matches[1]
                                Status = if ($_ -match "attached") { "已挂载" } else { "后台中" }
                            }
                        }
                    }
                }
                'screen' {
                    & screen -ls 2>$null | ForEach-Object {
                        if ($_ -match '^\s*(\d+)\s*\(([^)]+)\)') {
                            [PSCustomObject]@{
                                Name   = $matches[1]
                                Status = if ($matches[2] -match "Attached") { "已挂载" } else { "后台中" }
                            }
                        }
                    }
                }
                'byobu' {
                    # byobu 使用 tmux 或 screen 作为后端
                    $backend = & byobu-launcher-import tmux 2>$null
                    if ($backend -eq "tmux") {
                        & tmux list-sessions 2>$null | ForEach-Object {
                            if ($_ -match '^([^:]+)') {
                                [PSCustomObject]@{
                                    Name   = $matches[1]
                                    Status = if ($_ -match "attached") { "已挂载" } else { "后台中" }
                                }
                            }
                        }
                    }
                }
            }
            
            if ($sessions) {
                $result.Sessions = @($sessions)
            }
            break
        }
    }
    
    return $result
}

function Test-MultiplexerAvailable {
    <#
    .SYNOPSIS
    检测本地是否有可用的终端复用器
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$Type = $null  # 可指定 tmux/screen/byobu
    )
    
    if ($Type) {
        return $null -ne (Get-Command $Type -ErrorAction SilentlyContinue)
    }
    
    return (Test-Path (Get-Command tmux -ErrorAction SilentlyContinue).Source) -or
    (Test-Path (Get-Command screen -ErrorAction SilentlyContinue).Source) -or
    (Test-Path (Get-Command byobu -ErrorAction SilentlyContinue).Source)
}
