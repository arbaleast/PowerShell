# ============================================================
# Invoke-ConsoleMenu.ps1 - 通用终端交互式菜单 UI 组件
# 硬核黑客风格 - 结构化信息, 路径/分支标签
# ============================================================

function Invoke-ConsoleMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Title,

        [Parameter(Mandatory = $true, Position = 1)]
        [array]$Options,

        [Parameter(Mandatory = $false)]
        [string]$ColorPrimary = $global:UserScoop_CONF.Colors.FreshGreen,

        [Parameter(Mandatory = $false)]
        [string]$ColorAccent = $global:UserScoop_CONF.Colors.SageGreen,

        [Parameter(Mandatory = $false)]
        [string]$ColorMuted = $global:UserScoop_CONF.Colors.MidGray,

        [Parameter(Mandatory = $false)]
        [string]$ColorHighlight = $global:UserScoop_CONF.Colors.MintGreen,

        [Parameter(Mandatory = $false)]
        [hashtable]$Keys = $global:UserScoop_CONF.Keys,

        [Parameter(Mandatory = $false)]
        [string]$ExitLabel = "EXIT"
    )

    $idx = 0
    $count = $Options.Count
    $exitIdx = $count
    $total = $count + 1
    $rst = "`e[0m"

    $items = $Options | ForEach-Object {
        if ($_ -is [string]) {
            @{ Label = $_; Desc = "" }
        } else {
            @{ Label = $_.Label; Desc = $_.Desc }
        }
    }

    while ($true) {
        Clear-Host

        # Get system info for labels
        $hostname = $env:COMPUTERNAME ?? "local"
        $userName = $env:USERNAME ?? "user"
        $cwd = $PWD.Path.Split('\')[-1]
        $hLine = "━" * 45

        # ══════════════════════════════════════════════════════
        # Hardcore header with labels
        # ══════════════════════════════════════════════════════
        Write-Host ""
        Write-Host "  ${ColorPrimary}┌──〈 ${ColorMuted}${userName}@${hostname}${ColorPrimary} 〉━━[ ${ColorAccent}${cwd}${ColorPrimary} ]━━[ ${ColorPrimary}${Title}${ColorPrimary} ]${rst}"
        Write-Host "  ${ColorPrimary}┃${rst}"
        Write-Host "  ${ColorPrimary}│${rst}  ${ColorPrimary}┄${rst}"

        # ══════════════════════════════════════════════════════
        # Options list with key indicators
        # ══════════════════════════════════════════════════════
        for ($i = 0; $i -lt $count; $i++) {
            $key = ($i + 1).ToString().PadLeft(2, '0')
            $prefix = if ($i -eq $idx) { "${ColorHighlight}▸" } else { "${ColorMuted} " }
            $labelColor = if ($i -eq $idx) { $ColorPrimary } else { $ColorMuted }
            
            Write-Host "  ${ColorPrimary}│${rst}  ${prefix}${rst} ${ColorPrimary}[${key}]${rst} ${labelColor}$($items[$i].Label)${rst}"
        }

        # Exit
        $exitKey = ($count + 1).ToString().PadLeft(2, '0')
        $exitPrefix = if ($idx -eq $exitIdx) { "${ColorAccent}▸" } else { "${ColorMuted} " }
        $exitColor = if ($idx -eq $exitIdx) { $ColorAccent } else { $ColorMuted }
        Write-Host "  ${ColorPrimary}│${rst}  ${exitPrefix}${rst} ${ColorAccent}[${exitKey}]${rst} ${exitColor}${ExitLabel}${rst}"

        # ══════════════════════════════════════════════════════
        # Description at bottom
        # ══════════════════════════════════════════════════════
        Write-Host "  ${ColorPrimary}┃${rst}"
        Write-Host "  ${ColorPrimary}│${rst}  ${ColorPrimary}┄${rst}"

        if ($idx -lt $count -and $items[$idx].Desc) {
            Write-Host "  ${ColorPrimary}│${rst}  ${ColorMuted}$($items[$idx].Desc)${rst}"
        } elseif ($idx -eq $exitIdx) {
            Write-Host "  ${ColorPrimary}│${rst}  ${ColorMuted}return to local terminal${rst}"
        }

        # Footer
        Write-Host "  ${ColorPrimary}┃${rst}"
        Write-Host "  ${ColorPrimary}└${hLine}━━━ ○${rst}"

        # Hint
        Write-Host ""
        Write-Host "  ${ColorMuted}↑↓ navigate · Enter confirm · Q quit${rst}" -ForegroundColor DarkGray
        Write-Host ""

        # Key handling
        $key = $Host.UI.RawUI.ReadKey("NoEcho, IncludeKeyDown")
        $vK = $key.VirtualKeyCode

        if ($vK -eq $Keys.Up) {
            $idx = ($idx - 1 + $total) % $total
            continue
        }
        if ($vK -eq $Keys.Down) {
            $idx = ($idx + 1) % $total
            continue
        }

        if ($vK -eq $Keys.Enter) {
            if ($idx -eq $exitIdx) { return $null }
            return $items[$idx]
        }

        if ($key.Character -eq 'q' -or $key.Character -eq 'Q') { return $null }
    }
}
