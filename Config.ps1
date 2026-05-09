# ============================================================
# UserScoop 配置 — PowerShell 环境路径与参数
# ============================================================
# 功能说明：
#   此文件集中管理 UserScoop PowerShell 配置的所有路径和参数。
#   支持两种配置优先级：
#     1. 环境变量（优先，用于容器/CI 环境）
#     2. 本地默认值（兜底，用于本地开发环境）
#
# 目录结构约定：
#   $UserScoop_ROOT/
#   ├── quotes.txt          # 启动语录文件（见下）
#   └── UserScoop/
#       └── apps/          # 工具集（Starship、Fnm 等）
#           ├── starship/current/starship.exe
#           └── fnm/current/fnm.exe
#
# 语录文件格式（quotes.txt）：
#   每条语录以 % 分隔，文件末尾换行。
#   示例：
#     第一条语录
#     %
#     第二条语录
#     %
# ============================================================

# ---------- 路径配置 ----------

# 根目录：UserScoop 配置的顶层目录
#   - 环境变量：UserScoop_ROOT
#   - 默认值  ：D:\Env（本地开发默认值）
#   - 用途    ：存放 quotes.txt 语录文件
$global:UserScoop_ROOT = $env:UserScoop_ROOT
if (-not $global:UserScoop_ROOT)
{ $global:UserScoop_ROOT = "D:\Env" 
}

# 应用目录：工具集根路径
#   - 环境变量：UserScoop_APPS
#   - 默认值  ：$UserScoop_ROOT\UserScoop\apps
#   - 用途    ：存放 Starship、Fnm 等工具的版本目录
$global:UserScoop_APPS = $env:UserScoop_APPS
if (-not $global:UserScoop_APPS)
{ $global:UserScoop_APPS = "$global:UserScoop_ROOT\UserScoop\apps" 
}

# ---------- 运行时配置 ----------

$global:UserScoop_CONF = @{
    # 语录文件路径：启动时随机显示一条语录
    Quotes   = "$global:UserScoop_ROOT\quotes.txt"

    # Starship 提示符路径
    Starship = "$global:UserScoop_APPS\starship\current\starship.exe"

    # Fnm（Fast Node Manager）路径
    Fnm      = "$global:UserScoop_APPS\fnm\current\fnm.exe"

    # 终端颜色方案（RGB 24-bit 色）
    Colors   = @{
        Cyan = "`e[38;2;0;255;209m"   # 主色调：青色
        Gray = "`e[38;2;80;80;80m"    # 次要文字：灰色
        Rst  = "`e[0m"                 # 重置格式
    }

    # 键盘虚拟键码（用于交互式菜单）
    Keys     = @{
        Up    = 38   # ↑
        Down  = 40   # ↓
        Enter = 13   # 回车
        Esc   = 27   # ESC
    }

    # SSH 配置
    SSH      = @{
        ConnectTimeout = 5      # SSH 连接超时（秒）
        ForceTTy       = $true  # 强制分配伪终端（用于 tmux 交互）
    }

    # Tmux 配置
    Tmux     = @{
        DefaultSessionName = "main"  # 默认会话名称
    }
}
