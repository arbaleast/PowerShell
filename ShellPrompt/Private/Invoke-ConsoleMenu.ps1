# ============================================================
# Invoke-ConsoleMenu.ps1 - 通用终端交互式菜单 UI 组件
# 硬核黑客风格 - 结构化信息, 路径/分支标签
# 优化：方向键导航时只重绘变化的行，避免闪烁和残留
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

    # 计算各区域的行号（1-based ANSI）
    # 清屏后：
    #   行1: Write-Host ""  (空行)
    #   行2: header line 1
    #   行3: header line 2
    #   行4: header line 3
    #   行5..(5+count-1): 选项行
    #   行(5+count): EXIT行
    #   行(5+count+1): 分隔线 |
    #   行(5+count+2): 分隔线 |
    #   行(5+count+3): 描述行
    #   行(5+count+4): footer |
    #   行(5+count+5): footer +
    $headerEndRow = 4
    $optionStartRow = 5
    $exitRow = $optionStartRow + $count
    $descRow = $exitRow + 3

    # 提前计算 exitKey（供后续缓存行使用）
    $exitKey = ($count + 1).ToString().PadLeft(2, '0')

    # 构建选项行文本（缓存，避免重复构建）
    # 使用强类型 ArrayList 避免数组拼接的 O(n²) 性能问题
    $optionLines = New-Object System.Collections.ArrayList ($count)
    for ($i = 0; $i -lt $count; $i++) {
        $key = ($i + 1).ToString().PadLeft(2, '0')
        # 两种状态：选中/未选中
        $selectedLine = "  ${ColorPrimary}|${rst}  ${ColorHighlight}>${rst} ${ColorPrimary}[${key}]${rst} ${ColorPrimary}$($items[$i].Label)${rst}"
        $unselectedLine = "  ${ColorPrimary}|${rst}  ${ColorMuted} ${rst} ${ColorPrimary}[${key}]${rst} ${ColorMuted}$($items[$i].Label)${rst}"
        [void]$optionLines.Add([PSCustomObject]@{ Selected = $selectedLine; Unselected = $unselectedLine })
    }
    $exitSelected = "  ${ColorPrimary}|${rst}  ${ColorAccent}>${rst} ${ColorAccent}[${exitKey}]${rst} ${ColorAccent}${ExitLabel}${rst}"
    $exitUnselected = "  ${ColorPrimary}|${rst}  ${ColorMuted} ${rst} ${ColorAccent}[${exitKey}]${rst} ${ColorMuted}${ExitLabel}${rst}"

    # 重写指定行的函数（定位到行首，清行，写内容）
    function Write-MenuLine {
        param([int]$Line, [string]$Text)
        [Console]::Write("`e[${Line};1H`e[K${Text}")
    }

    # 首次渲染：完整输出菜单
    [Console]::Write("`e[2J`e[H`e[0m")

    if ($Global:TUI_PerfState) {
        $Global:TUI_PerfState.ReportFrame()
    }

    $hostname = $env:COMPUTERNAME ?? "local"
    $userName = $env:USERNAME ?? "user"
    $cwd = $PWD.Path.Split('\')[-1]
    $hLine = "-" * 40

    # Header
    Write-Host ""
    Write-Host "  ${ColorPrimary}+--< ${ColorMuted}${userName}@${hostname}${ColorPrimary} >--[ ${ColorAccent}${cwd}${ColorPrimary} ]--[ ${ColorPrimary}${Title}${ColorPrimary} ]${rst}"
    Write-Host "  ${ColorPrimary}|${rst}"
    Write-Host "  ${ColorPrimary}|${rst}  ${ColorPrimary}+${rst}"

    # Options
    for ($i = 0; $i -lt $count; $i++) {
        if ($i -eq $idx) {
            Write-Host $optionLines[$i].Selected
        } else {
            Write-Host $optionLines[$i].Unselected
        }
    }

    # Exit（首次渲染，使用缓存的行文本）
    if ($idx -eq $exitIdx) {
        Write-Host $exitSelected
    } else {
        Write-Host $exitUnselected
    }

    # Description area
    Write-Host "  ${ColorPrimary}|${rst}"
    Write-Host "  ${ColorPrimary}|${rst}  ${ColorPrimary}+${rst}"

    if ($idx -lt $count -and $items[$idx].Desc) {
        Write-Host "  ${ColorPrimary}|${rst}  ${ColorMuted}-- $($items[$idx].Desc)${rst}"
    } elseif ($idx -eq $exitIdx) {
        Write-Host "  ${ColorPrimary}|${rst}  ${ColorMuted}-- return to local terminal${rst}"
    }

    # Footer
    Write-Host "  ${ColorPrimary}|${rst}"
    Write-Host "  ${ColorPrimary}+${hLine}--${rst}"
    Write-Host ""
    Write-Host "  ${ColorMuted}up/down navigate + Enter confirm + Q quit${rst}" -ForegroundColor DarkGray
    Write-Host ""

    # 导航循环
    while ($true) {
        $oldIdx = $idx

        $key = $Host.UI.RawUI.ReadKey("NoEcho, IncludeKeyDown")
        $vK = $key.VirtualKeyCode

        if ($Global:TUI_PerfState) {
            $Global:TUI_PerfState.ReportKeyPress()
        }

        if ($vK -eq $Keys.Up) {
            $idx = ($idx - 1 + $total) % $total
        } elseif ($vK -eq $Keys.Down) {
            $idx = ($idx + 1) % $total
        } elseif ($vK -eq $Keys.Enter) {
            if ($idx -eq $exitIdx) { return $null }
            return $items[$idx]
        } elseif ($key.Character -eq 'q' -or $key.Character -eq 'Q') {
            return $null
        }

        # 只重绘变化的行
        if ($oldIdx -ne $idx) {
            # 恢复旧行为未选中状态
            if ($oldIdx -eq $exitIdx) {
                Write-MenuLine -Line $exitRow -Text $exitUnselected
            } else {
                Write-MenuLine -Line ($optionStartRow + $oldIdx) -Text $optionLines[$oldIdx].Unselected
            }

            # 设置新行为选中状态
            if ($idx -eq $exitIdx) {
                Write-MenuLine -Line $exitRow -Text $exitSelected
            } else {
                Write-MenuLine -Line ($optionStartRow + $idx) -Text $optionLines[$idx].Selected
            }

            # 更新描述行
            $descText = ""
            if ($idx -lt $count -and $items[$idx].Desc) {
                $descText = "  ${ColorPrimary}|${rst}  ${ColorMuted}-- $($items[$idx].Desc)${rst}"
            } elseif ($idx -eq $exitIdx) {
                $descText = "  ${ColorPrimary}|${rst}  ${ColorMuted}-- return to local terminal${rst}"
            }
            Write-MenuLine -Line $descRow -Text $descText
        }
    }
}
