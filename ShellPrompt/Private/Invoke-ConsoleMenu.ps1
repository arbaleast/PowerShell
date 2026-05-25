# ============================================================
# Invoke-ConsoleMenu.ps1 - 通用终端交互式菜单 UI 组件
# 硬核黑客风格 - 结构化信息, 路径/分支标签
# 全部使用 [Console]::Write + ANSI 转义，禁止混合 Write-Host
# 避免 Write-Host 与 Console API 光标追踪不同步导致的偏移
# ============================================================

# 重写指定行（ANSI 定位 + \e[2K 清整行 + 写内容）
function Write-MenuLine {
    param([int]$Line, [string]$Text)
    # $Line 是 1-based ANSI 行号
    # \e[${Line};1H = 定位到行 $Line, 列 1
    # \e[2K         = 清空整行
    [Console]::Write("`e[${Line};1H`e[2K${Text}")
}

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

    # 仅在调试模式下写入调试日志，避免无条件文件 I/O
    if ($script:IsDebugMode) {
        "DEBUG: Invoke-ConsoleMenu called, Title='$Title', Options.Count=$($Options.Count)" | Out-File -FilePath "$env:TEMP\menu-debug.txt" -Encoding utf8
    }

    $idx = 0
    $count = $Options.Count
    $exitIdx = $count
    $total = $count + 1
    $rst = "`e[0m"

    $items = $Options | ForEach-Object {
        if ($_ -is [string]) {
            @{ Label = $_; Desc = "" }
        } else {
            # 透传 PSCustomObject 的所有属性（包括 RawName 等调用方自定义字段）
            $_
        }
    }

    # 所有行列号使用 1-based ANSI 行号
    # 行1: 空行
    # 行2: header line 1  (+--< ... >--)
    # 行3: header line 2  (|)
    # 行4: header line 3  (|  +)
    # 行5..(5+count-1): N 个选项行
    # 行(5+count): EXIT行
    # 行(5+count+1): 分隔线 (|)
    # 行(5+count+2): 分隔线 (|  +)
    # 行(5+count+3): 描述行
    # 行(5+count+4): footer (|)
    # 行(5+count+5): footer (+---)
    # 行(5+count+6): 空行
    # 行(5+count+7): 导航提示行
    # 行(5+count+8): 空行
    $optionStartRow = 5
    $exitRow = $optionStartRow + $count
    $descRow = $exitRow + 3

    $exitKey = ($count + 1).ToString().PadLeft(2, '0')

    # 构建选项行文本缓存
    $optionLines = New-Object System.Collections.ArrayList ($count)
    for ($i = 0; $i -lt $count; $i++) {
        $key = ($i + 1).ToString().PadLeft(2, '0')
        $selectedLine = "  ${ColorPrimary}|${rst}  ${ColorHighlight}>${rst} ${ColorPrimary}[${key}]${rst} ${ColorPrimary}$($items[$i].Label)${rst}"
        $unselectedLine = "  ${ColorPrimary}|${rst}  ${ColorMuted} ${rst} ${ColorPrimary}[${key}]${rst} ${ColorMuted}$($items[$i].Label)${rst}"
        [void]$optionLines.Add([PSCustomObject]@{ Selected = $selectedLine; Unselected = $unselectedLine })
    }
    $exitSelected = "  ${ColorPrimary}|${rst}  ${ColorAccent}>${rst} ${ColorAccent}[${exitKey}]${rst} ${ColorAccent}${ExitLabel}${rst}"
    $exitUnselected = "  ${ColorPrimary}|${rst}  ${ColorMuted} ${rst} ${ColorAccent}[${exitKey}]${rst} ${ColorMuted}${ExitLabel}${rst}"

    # ============================================================
    # 首次渲染：全部使用 [Console]::Write + ANSI 转义
    # 不用 Write-Host，避免光标追踪不一致
    # ============================================================
    [Console]::Write("`e[2J`e[H`e[0m")

    if ($Global:TUI_PerfState -and (Test-Path variable:Global:TUI_PerfState)) {
        $Global:TUI_PerfState.ReportFrame()
    }

    $hostname = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { "local" }
    $userName = if ($env:USERNAME) { $env:USERNAME } else { "user" }
    # 获取当前目录名（兼容 Windows \ 和 Unix / 路径）
    $cwd = Split-Path $PWD.Path -Leaf
    if (-not $cwd) { $cwd = $PWD.Path }
    $hLine = "-" * 40

    # 行1: 空行
    Write-MenuLine -Line 1 -Text ""
    # 行2: header line 1
    Write-MenuLine -Line 2 -Text "  ${ColorPrimary}+--< ${ColorMuted}${userName}@${hostname}${ColorPrimary} >--[ ${ColorAccent}${cwd}${ColorPrimary} ]--[ ${ColorPrimary}${Title}${ColorPrimary} ]${rst}"
    # 行3: header line 2
    Write-MenuLine -Line 3 -Text "  ${ColorPrimary}|${rst}"
    # 行4: header line 3
    Write-MenuLine -Line 4 -Text "  ${ColorPrimary}|${rst}  ${ColorPrimary}+${rst}"

    # 行5..(5+count-1): 选项行
    for ($i = 0; $i -lt $count; $i++) {
        if ($i -eq $idx) {
            Write-MenuLine -Line ($optionStartRow + $i) -Text $optionLines[$i].Selected
        } else {
            Write-MenuLine -Line ($optionStartRow + $i) -Text $optionLines[$i].Unselected
        }
    }

    # 行(5+count): EXIT行
    Write-MenuLine -Line $exitRow -Text $exitUnselected

    # 行(5+count+1): 分隔线
    Write-MenuLine -Line ($exitRow + 1) -Text "  ${ColorPrimary}|${rst}"
    # 行(5+count+2): 分隔线
    Write-MenuLine -Line ($exitRow + 2) -Text "  ${ColorPrimary}|${rst}  ${ColorPrimary}+${rst}"
    # 行(5+count+3): 描述行
    Write-MenuLine -Line $descRow -Text "  ${ColorPrimary}|${rst}  ${ColorMuted}-- $($items[$idx].Desc)${rst}"
    # 行(5+count+4): footer
    Write-MenuLine -Line ($descRow + 1) -Text "  ${ColorPrimary}|${rst}"
    # 行(5+count+5): footer
    Write-MenuLine -Line ($descRow + 2) -Text "  ${ColorPrimary}+${hLine}--${rst}"
    # 行(5+count+6): 空行
    Write-MenuLine -Line ($descRow + 3) -Text ""
    # 行(5+count+7): 导航提示行
    Write-MenuLine -Line ($descRow + 4) -Text "  ${ColorMuted}up/down navigate + Enter confirm + Q quit${rst}"
    # 行(5+count+8): 空行
    Write-MenuLine -Line ($descRow + 5) -Text ""

    # 导航循环
    while ($true) {
        $oldIdx = $idx

        try {
            $key = $Host.UI.RawUI.ReadKey("NoEcho, IncludeKeyDown")
        } catch {
            if ($script:IsDebugMode) {
                "DEBUG: ReadKey exception: $($_.Exception.Message)" | Out-File -FilePath "$env:TEMP\menu-debug.txt" -Append -Encoding utf8
            }
            [Console]::Write("`e[2J`e[H`e[0m")
            Clear-Host
            return $null
        }
        $vK = $key.VirtualKeyCode

        if ($Global:TUI_PerfState -and (Test-Path variable:Global:TUI_PerfState)) {
            $Global:TUI_PerfState.ReportKeyPress()
        }

        if ($vK -eq $Keys.Up) {
            $idx = ($idx - 1 + $total) % $total
        } elseif ($vK -eq $Keys.Down) {
            $idx = ($idx + 1) % $total
        } elseif ($vK -eq $Keys.Enter) {
            if ($script:IsDebugMode) {
                "DEBUG: Enter pressed, idx=$idx, exitIdx=$exitIdx" | Out-File -FilePath "$env:TEMP\menu-debug.txt" -Append -Encoding utf8
            }
            if ($idx -eq $exitIdx) {
                return $null
            }
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
            $descText = "  ${ColorPrimary}|${rst}  ${ColorMuted}-- return to local terminal${rst}"
            if ($idx -lt $count -and $items[$idx].Desc) {
                $descText = "  ${ColorPrimary}|${rst}  ${ColorMuted}-- $($items[$idx].Desc)${rst}"
            }
            Write-MenuLine -Line $descRow -Text $descText
        }
    }
}