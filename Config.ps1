# 路径初始化
$global:HERMES_ROOT = $env:HERMES_ROOT
if (-not $global:HERMES_ROOT) { $global:HERMES_ROOT = "D:\Env" }

$global:HERMES_APPS = $env:HERMES_APPS
if (-not $global:HERMES_APPS) { $global:HERMES_APPS = "$global:HERMES_ROOT\UserScoop\apps" }

$global:HERMES_CONF = @{
    Quotes   = "$global:HERMES_ROOT\quotes.txt"
    Starship = "$global:HERMES_APPS\starship\current\starship.exe"
    Fnm      = "$global:HERMES_APPS\fnm\current\fnm.exe"
    Colors   = @{
        Cyan = "`e[38;2;0;255;209m"
        Gray = "`e[38;2;80;80;80m"
        Rst  = "`e[0m"
    }
    Keys     = @{ Up = 38; Down = 40; Enter = 13; Esc = 27 }
}
    