# ============================================================
# Invoke-ConsoleMenu.ps1 — 通用终端交互式菜单 UI 组件
# 纯渲染逻辑，无任何 tmux/SSH 业务知识
# ============================================================

function Invoke-ConsoleMenu
{
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

    while ($true)
    {
        Clear-Host

        Write-Host ""
        Write-Host "  ${ColorCyan}${Title}${ColorGray}"
        Write-Host "  $($('─') * 50)"

        for ($i = 0; $i -lt $count; $i++)
        {
            $fg = "White"
            $marker = "    "
            if ($i -eq $idx)
            {
                $fg = $ColorCyan
                $marker = "[>] "
            }
            Write-Host "$marker $($Options[$i])" -ForegroundColor $fg
        }

        $exitFg = if ($idx -eq $count)
        { $ColorCyan 
        } else
        { "White" 
        }
        $exitMarker = if ($idx -eq $count)
        { "[>] " 
        } else
        { "    " 
        }
        Write-Host "$exitMarker[q] $ExitLabel" -ForegroundColor $exitFg

        Write-Host ""
        Write-Host "  $($('─') * 50)"
        Write-Host "  ↑↓ move  ·  Enter select  ·  q quit" -ForegroundColor DarkGray
        Write-Host ""

        $key = $Host.UI.RawUI.ReadKey("NoEcho, IncludeKeyDown")
        $vK = $key.VirtualKeyCode

        if ($vK -eq $Keys.Up)
        {
            $idx = ($idx - 1 + ($count + 1)) % ($count + 1)
            continue
        }
        if ($vK -eq $Keys.Down)
        {
            $idx = ($idx + 1) % ($count + 1)
            continue
        }

        if ($vK -eq $Keys.Enter)
        {
            if ($idx -eq $count)
            {
                return $null
            }
            return $Options[$idx]
        }

        if ($key.Character -eq 'q' -or $key.Character -eq 'Q')
        {
            return $null
        }
    }
}
