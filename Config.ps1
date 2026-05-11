# ============================================================
# UserScoop 配置 — 优化版 (去硬编码依赖)
# ============================================================

$global:UserScoop_ROOT = Split-Path -Parent $MyInvocation.MyCommand.Definition

$global:UserScoop_CONF = @{
    Quotes   = "$global:UserScoop_ROOT\quotes.txt"

    # 颜色和按键配置保持不变
    Colors   = @{
        Cyan = "`e[38;2;0;255;209m"
        Gray = "`e[38;2;80;80;80m"
        Rst  = "`e[0m"
    }
    Keys     = @{ Up = 38; Down = 40; Enter = 13; Esc = 27 }
    SSH      = @{ ConnectTimeout = 5; ForceTTy = $true }
    Tmux     = @{ DefaultSessionName = "main" }
}
