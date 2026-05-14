# ============================================================
# Initialize-Config.ps1 - 模块配置初始化
# 定义全局配置（仅在此处修改默认值）
# ============================================================

$global:UserScoop_ROOT = (Get-Item $PSScriptRoot).Parent.Parent.FullName

$global:UserScoop_CONF = @{
    Quotes = "$global:UserScoop_ROOT\quotes.txt"

    Colors = @{
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

    Keys   = @{
        Up    = 38
        Down  = 40
        Enter = 13
        Esc   = 27
    }

    SSH    = @{
        ConnectTimeout = 5
        ForceTTy       = $true
    }

    Tmux   = @{
        DefaultSessionName = "main"
    }
}
