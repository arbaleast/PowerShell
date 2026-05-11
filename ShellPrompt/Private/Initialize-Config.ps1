# ============================================================
# Initialize-Config.ps1 — 模块配置初始化
# 定义全局配置（仅在此处修改默认值）
# ============================================================

$global:UserScoop_ROOT = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Definition)

$global:UserScoop_CONF = @{
    Quotes   = "$global:UserScoop_ROOT\quotes.txt"

    Colors   = @{
        Cyan = "`e[38;2;0;255;209m"
        Gray = "`e[38;2;80;80;80m"
        Rst  = "`e[0m"
    }

    Keys     = @{
        Up    = 38
        Down  = 40
        Enter = 13
        Esc   = 27
    }

    SSH      = @{
        ConnectTimeout = 5
        ForceTTy       = $true
    }

    Tmux     = @{
        DefaultSessionName = "main"
    }
}
