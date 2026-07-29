# Invoke-ConsoleMenu.ps1 - 通用终端交互式菜单 UI 组件
# 全部使用 [Console]::Write + ANSI 转义,禁用 Write-Host 避免光标追踪不同步;
# 颜色统一走 Get-CachedConfig 预热缓存;循环中只更新变化的行。

function Write-MenuLine {
    param([int]$Line, [string]$Text)
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
        [string]$ColorPrimary,

        [Parameter(Mandatory = $false)]
        [string]$ColorAccent,

        [Parameter(Mandatory = $false)]
        [string]$ColorMuted,

        [Parameter(Mandatory = $false)]
        [hashtable]$Keys,

        [Parameter(Mandatory = $false)]
        [string]$ExitLabel = "EXIT"
    )

    # 默认值解析（走预热缓存快路径，0 命中回退到硬编码）
    if (-not $ColorPrimary) { $ColorPrimary = Get-CachedConfig -Section 'Colors' -Key 'FreshGreen' -Default "`e[38;2;137;209;133m" }
    if (-not $ColorAccent) { $ColorAccent = Get-CachedConfig -Section 'Colors' -Key 'SageGreen'  -Default "`e[38;2;159;177;159m" }
    if (-not $ColorMuted) { $ColorMuted = Get-CachedConfig -Section 'Colors' -Key 'MidGray'    -Default "`e[38;2;100;100;100m" }
    if (-not $Keys) {
        # 直接走 Get-CachedConfig;它内部会处理缓存未初始化的回退
        $Keys = @{
            Up    = Get-CachedConfig -Section 'Keys' -Key 'Up'    -Default 38
            Down  = Get-CachedConfig -Section 'Keys' -Key 'Down'  -Default 40
            Enter = Get-CachedConfig -Section 'Keys' -Key 'Enter' -Default 13
            Esc   = Get-CachedConfig -Section 'Keys' -Key 'Esc'   -Default 27
        }
    }

    $idx = 0
    $count = $Options.Count
    $exitIdx = $count
    $total = $count + 1
    $rst = Get-CachedConfig -Section 'Colors' -Key 'Rst' -Default "`e[0m"

    $items = $Options | ForEach-Object {
        if ($_ -is [string]) { @{ Label = $_; Desc = "" } } else { $_ }
    }

    # 布局:
    #   1: 空行 / 2-4: header (3 行)
    #   5..(5+count-1): 选项 / (5+count): EXIT
    #   描述行 = EXIT行 + 3 / 底边行 = 描述行 + 2
    $optionStartRow = 5
    $exitRow = $optionStartRow + $count
    $descRow = $exitRow + 3

    $exitKey = ($count + 1).ToString().PadLeft(2, '0')

    # 构建 SSH config Host → HostName 映射，用于在主机选择菜单中显示实际连接目标。
    # 使用户能直观看到菜单项 debian 实际解析为 debian.lan，避免将 SSH config 的
    # HostName 域名解析行为误判为模块问题。仅影响显示文本，不改变返回值。
    $sshHostNameMap = @{}
    $sshCfgPath = Join-Path $HOME ".ssh\config"
    $sshCfgLines = Get-Content $sshCfgPath -Encoding UTF8 -ErrorAction SilentlyContinue
    if ($sshCfgLines) {
        $curHost = $null
        foreach ($ln in $sshCfgLines) {
            if ($ln -match '^Host\s+(.+)$') {
                $curHost = ($matches[1] -split '\s+')[0]
                if ($curHost -match '[*?]') { $curHost = $null }
            } elseif ($ln -match '^\s+HostName\s+(.+)$' -and $curHost) {
                $sshHostNameMap[$curHost] = $matches[1].Trim()
            }
        }
    }

    # 真预分配: Generic.List<PSCustomObject> 一次性分配 count 槽位
    # 比 New-Object System.Collections.ArrayList($count) 省去内部扩容判断
    $optionLines = [System.Collections.Generic.List[PSCustomObject]]::new($count)
    for ($i = 0; $i -lt $count; $i++) {
        $key = ($i + 1).ToString().PadLeft(2, '0')
        $label = $items[$i].Label
        # 若 Host 别名在 SSH config 中定义了 HostName，在菜单项尾部追加 "→ <HostName>" 提示
        $displayLabel = if ($sshHostNameMap.ContainsKey($label)) { "$label → $($sshHostNameMap[$label])" } else { $label }
        $selectedLine = "  ${ColorPrimary}|${rst}  ${rst}>${rst} ${ColorPrimary}[${key}]${rst} ${ColorPrimary}${displayLabel}${rst}"
        $unselectedLine = "  ${ColorPrimary}|${rst}  ${ColorMuted} ${rst} ${ColorPrimary}[${key}]${rst} ${ColorMuted}${displayLabel}${rst}"
        $optionLines.Add([PSCustomObject]@{ Selected = $selectedLine; Unselected = $unselectedLine })
    }
    $exitSelected = "  ${ColorPrimary}|${rst}  ${ColorAccent}>${rst} ${ColorAccent}[${exitKey}]${rst} ${ColorAccent}${ExitLabel}${rst}"
    $exitUnselected = "  ${ColorPrimary}|${rst}  ${ColorMuted} ${rst} ${ColorAccent}[${exitKey}]${rst} ${ColorMuted}${ExitLabel}${rst}"

    [Console]::Clear()

    $hostname = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { "local" }
    $userName = if ($env:USERNAME) { $env:USERNAME } else { "user" }
    $cwd = Split-Path $PWD.Path -Leaf
    if (-not $cwd) { $cwd = $PWD.Path }
    $hLine = "-" * 40

    Write-MenuLine -Line 1 -Text ""
    Write-MenuLine -Line 2 -Text "  ${ColorPrimary}+--< ${ColorMuted}${userName}@${hostname}${ColorPrimary} >--[ ${ColorAccent}${cwd}${ColorPrimary} ]--[ ${ColorPrimary}${Title}${ColorPrimary} ]${rst}"
    Write-MenuLine -Line 3 -Text "  ${ColorPrimary}|${rst}"
    Write-MenuLine -Line 4 -Text "  ${ColorPrimary}|${rst}  ${ColorPrimary}+${rst}"

    for ($i = 0; $i -lt $count; $i++) {
        if ($i -eq $idx) {
            Write-MenuLine -Line ($optionStartRow + $i) -Text $optionLines[$i].Selected
        } else {
            Write-MenuLine -Line ($optionStartRow + $i) -Text $optionLines[$i].Unselected
        }
    }

    Write-MenuLine -Line $exitRow -Text $exitUnselected
    Write-MenuLine -Line ($exitRow + 1) -Text "  ${ColorPrimary}|${rst}"
    Write-MenuLine -Line ($exitRow + 2) -Text "  ${ColorPrimary}|${rst}  ${ColorPrimary}+${rst}"
    Write-MenuLine -Line $descRow -Text "  ${ColorPrimary}|${rst}  ${ColorMuted}-- $($items[$idx].Desc)${rst}"
    Write-MenuLine -Line ($descRow + 1) -Text "  ${ColorPrimary}|${rst}"
    Write-MenuLine -Line ($descRow + 2) -Text "  ${ColorPrimary}+${hLine}--${rst}"
    Write-MenuLine -Line ($descRow + 3) -Text ""
    Write-MenuLine -Line ($descRow + 4) -Text "  ${ColorMuted}up/down navigate + Enter confirm + Q quit${rst}"
    Write-MenuLine -Line ($descRow + 5) -Text ""

    # 预构建静态描述文本(只有 EXIT 选中时显示)
    $descExit = "  ${ColorPrimary}|${rst}  ${ColorMuted}-- return to local terminal${rst}"

    while ($true) {
        $oldIdx = $idx

        try {
            $key = $Host.UI.RawUI.ReadKey("NoEcho, IncludeKeyDown")
        } catch {
            [Console]::Clear()
            return $null
        }
        $vK = $key.VirtualKeyCode

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

        if ($oldIdx -ne $idx) {
            if ($oldIdx -eq $exitIdx) {
                Write-MenuLine -Line $exitRow -Text $exitUnselected
            } else {
                Write-MenuLine -Line ($optionStartRow + $oldIdx) -Text $optionLines[$oldIdx].Unselected
            }

            if ($idx -eq $exitIdx) {
                Write-MenuLine -Line $exitRow -Text $exitSelected
            } else {
                Write-MenuLine -Line ($optionStartRow + $idx) -Text $optionLines[$idx].Selected
            }

            # 直接命中预构描述或构建新描述
            if ($idx -lt $count -and $items[$idx].Desc) {
                $descText = "  ${ColorPrimary}|${rst}  ${ColorMuted}-- $($items[$idx].Desc)${rst}"
            } else {
                $descText = $descExit
            }
            Write-MenuLine -Line $descRow -Text $descText
        }
    }
}
