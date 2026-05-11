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
        [string]$ColorCyan = "`e[38;2;0;255;209m",

        [Parameter(Mandatory = $false)]
        [string]$ColorGray = "`e[38;2;80;80;80m",

        [Parameter(Mandatory = $false)]
        [hashtable]$Keys = @{ Up = 38; Down = 40; Enter = 13; Esc = 27 },

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

        $currentDesc = ""

        # --- 1. 渲染常规菜单项 ---
        for ($i = 0; $i -lt $count; $i++)
        {
            if ($i -eq $idx)
            {
                $fgColor = 'Cyan'
                $marker  = "[>] "
            } else
            {
                $fgColor = 'White'
                $marker  = "    "
            }

            # 仅作为视觉对齐的装饰保留 [x]
            $num = $i + 1
            $prefix = "[$num]  "

            $displayText = ""
            $itemDesc = ""
            $item = $Options[$i]

            if ($item -is [string])
            {
                $displayText = "$item".Trim()
            } elseif ($item -is [hashtable])
            {
                $namePart = ""
                $descPart = ""
                $foundNameKey = ""

                foreach ($k in @('Name','Label','Title','Text'))
                {
                    if ($item.ContainsKey($k))
                    {
                        $namePart = "$($item[$k])"
                        $foundNameKey = $k
                        break
                    }
                }

                foreach ($k in @('Description','Status','Detail','Info','Remark','Note','Subtitle','Action','Command','Value'))
                {
                    if ($item.ContainsKey($k))
                    {
                        $descPart = "$($item[$k])"
                        break
                    }
                }

                if ([string]::IsNullOrEmpty($descPart) -and $item.Keys.Count -gt 1)
                {
                    $otherValues = @()
                    foreach ($k in $item.Keys)
                    {
                        if ($k -ne $foundNameKey)
                        {
                            $otherValues += "$($item[$k])"
                        }
                    }
                    $descPart = $otherValues -join " | "
                }

                $namePart = $namePart.Trim()
                $descPart = $descPart.Trim()
                $itemDesc = $descPart

                if ([string]::IsNullOrEmpty($namePart))
                {
                    $displayText = ($item.Values -join " | ").Trim()
                } else
                {
                    $displayText = $namePart
                }
            } else
            {
                $displayText = $item.ToString().Trim()
            }

            if ($i -eq $idx)
            { $currentDesc = $itemDesc 
            }

            Write-Host "  $marker$prefix$displayText" -ForegroundColor $fgColor
        }

        # --- 2. 渲染退出项 ---
        if ($idx -eq $count)
        {
            $exitFg = 'Cyan'
            $exitMk = "[>] "
        } else
        {
            $exitFg = 'DarkGray'
            $exitMk = "    "
        }

        Write-Host "  $exitMk[q]  $ExitLabel" -ForegroundColor $exitFg

        # --- 3. 底部动态状态栏 ---
        Write-Host ""
        Write-Host "  $($('─') * 50)"

        if (-not [string]::IsNullOrEmpty($currentDesc))
        {
            Write-Host "  💡 $currentDesc" -ForegroundColor Gray
            Write-Host "  $($('─') * 50)"
        } else
        {
            Write-Host "  💡 无备注信息" -ForegroundColor DarkGray
            Write-Host "  $($('─') * 50)"
        }

        # 已移除 1-9 select，回归最干净的提示语
        Write-Host "  ↑↓ move  ·  Enter confirm  ·  q quit" -ForegroundColor DarkGray
        Write-Host ""

        # --- 4. 按键交互 ---
        $key = $Host.UI.RawUI.ReadKey("NoEcho, IncludeKeyDown")
        $vK = $key.VirtualKeyCode

        if ($vK -eq $Keys.Up)
        { $idx = ($idx - 1 + ($count + 1)) % ($count + 1); continue
        }
        if ($vK -eq $Keys.Down)
        { $idx = ($idx + 1) % ($count + 1); continue
        }

        if ($vK -eq $Keys.Enter)
        {
            if ($idx -eq $count)
            { return $null 
            }
            return $Options[$idx]
        }

        if ($key.Character -eq 'q' -or $key.Character -eq 'Q')
        {
            return $null
        }
    }
}
