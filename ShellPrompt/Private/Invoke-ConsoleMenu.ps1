# ============================================================
# Invoke-ConsoleMenu.ps1 — 通用终端交互式菜单 UI 组件
# 纯渲染逻辑，无任何 tmux/SSH 业务知识
# ============================================================

function Invoke-ConsoleMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Title,

        [Parameter(Mandatory = $true, Position = 1)]
        [array]$Options,

        [Parameter(Mandatory = $false)]
        [string]$ColorCyan = $global:UserScoop_CONF.Colors.Cyan,

        [Parameter(Mandatory = $false)]
        [string]$ColorGray = $global:UserScoop_CONF.Colors.Gray,

        [Parameter(Mandatory = $false)]
        [hashtable]$Keys = $global:UserScoop_CONF.Keys,

        [Parameter(Mandatory = $false)]
        [string]$ExitLabel = "EXIT"
    )

    $idx = 0
    $count = $Options.Count
    $reset = "`e[0m"   # 重置 ANSI SGR 状态

    $items = $Options | ForEach-Object {
        if ($_ -is [string]) {
            @{ Label = $_; Desc = "" }
        } else {
            @{ Label = $_.Label; Desc = $_.Desc }
        }
    }

    while ($true) {
        Clear-Host

        # 标题
        Write-Host ""
        Write-Host "  ${ColorCyan}${Title}${ColorGray}"
        Write-Host "  $($('─') * 50)"

        # 选项
        for ($i = 0; $i -lt $count; $i++) {
            if ($i -eq $idx) {
                Write-Host "  [>]  ${ColorCyan}$($items[$i].Label)${reset}"
            } else {
                Write-Host "  [ ]  $($items[$i].Label)"
            }
        }

        # 退出项
        if ($idx -eq $count) {
            Write-Host "  [q]  ${ColorCyan}${ExitLabel}${reset}"
        } else {
            Write-Host "  [q]  $ExitLabel"
        }

        # 动态描述
        Write-Host ""
        Write-Host "  $($('─') * 50)"
        if ($idx -lt $count) {
            $desc = $items[$idx].Desc
            if ($desc) {
                Write-Host "  ${ColorGray}$desc${reset}" -ForegroundColor DarkGray
            }
        } else {
            Write-Host "  ${ColorGray}return to local terminal${reset}" -ForegroundColor DarkGray
        }

        Write-Host ""
        Write-Host "  ↑↓ navigate  ·  Enter confirm  ·  q quit" -ForegroundColor DarkGray
        Write-Host ""

        # 按键
        $key = $Host.UI.RawUI.ReadKey("NoEcho, IncludeKeyDown")
        $vK = $key.VirtualKeyCode

        if ($vK -eq $Keys.Up)   { $idx = ($idx - 1 + ($count + 1)) % ($count + 1); continue }
        if ($vK -eq $Keys.Down) { $idx = ($idx + 1) % ($count + 1); continue }

        if ($vK -eq $Keys.Enter) {
            if ($idx -eq $count) { return $null }
            return $items[$idx]
        }

        if ($key.Character -eq 'q' -or $key.Character -eq 'Q') { return $null }
    }
}
