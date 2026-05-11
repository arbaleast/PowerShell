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

        for ($i = 0; $i -lt $Options.Count; $i++)
        {
            # 1. 初始化默认状态 (未选中)
            $fgColor = [System.ConsoleColor]::White
            $marker = "    "

            # 2. 判断是否选中
            if ($i -eq $idx)
            {
                $fgColor = [System.ConsoleColor]::Cyan
                $marker = "[>] "
            }

            # 3. 智能解析选项名称 (兼容字符串数组和对象数组)
            $displayText = ""
            if ($Options[$i] -is [string])
            {
                $displayText = $Options[$i]
            } elseif ($null -ne $Options[$i].Name)
            {
                # 处理对象数组 (比如 Get-TmuxSessions 返回的带有 Name 和 Status 的对象)
                $displayText = "$($Options[$i].Name) $($Options[$i].Status)"
            } else
            {
                # 最后的兜底
                $displayText = $Options[$i].ToString()
            }

            # 4. 打印菜单项 (附加一点缩进让整体更好看)
            Write-Host "  $marker $displayText" -ForegroundColor $fgColor
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
