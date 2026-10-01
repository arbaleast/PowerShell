# New-AnsiLayout.ps1 - ANSI 终端布局构建器
# 三区布局基元: Header(标题/状态徽章) / Main(可滚动列表) / Footer(快捷键)
# 所有渲染走 [Console]::Write + ANSI 转义, 避免 Write-Host 光标追踪不同步;
# 颜色统一走 Get-CachedConfig 预热缓存。

function Write-AnsiLine {
    [CmdletBinding(SupportsShouldProcess=$true)]
    [OutputType([void])]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '')]
param(
        [int]$Line,
        [string]$Text
    )
    # 定位到指定行首, 清除整行, 输出文本
    [Console]::Write("`e[${Line};1H`e[2K${Text}")
}

function New-AnsiLayout {
    <#
    .SYNOPSIS
        构造 ANSI 终端三区布局(Header / Main / Footer)

    .DESCRIPTION
        返回一个 PSCustomObject, 持有 Header、Main、Footer 三个字符串数组,
        以及 Clear() / Redraw() 方法用于控制台渲染。
        不直接负责键盘事件分发(交给 Show-* 调用方)。

    .PARAMETER Title
        标题文字, 显示在 Header 区域起始位置

    .PARAMETER Width
        终端宽度(字符数), 默认取 [Console]::WindowWidth, 最小 60

    .PARAMETER Colors
        颜色覆盖表(主色/强调色/弱化色/边框色), 未指定时取 Get-CachedConfig 默认值

    .PARAMETER HeaderBadges
        Header 区域右侧的徽章数组(每个元素为 @{ Text="..."; Color="..." } 或纯字符串)

    .EXAMPLE
        $layout = New-AnsiLayout -Title "主机选择" -HeaderBadges @("3 主机", "● ready")
        $layout.Header | ForEach-Object { Write-AnsiLine -Line ($i++) -Text $_ }
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Title = "",

        [Parameter(Mandatory = $false)]
        [ValidateRange(40, 300)]
        [int]$Width = 0,

        [Parameter(Mandatory = $false)]
        [hashtable]$Colors,

        [Parameter(Mandatory = $false)]
        [array]$HeaderBadges = @()
    )

    # 颜色预解析: 走缓存, 热路径无分支
    $primary = if ($Colors -and $Colors.Primary) { $Colors.Primary } else { Get-CachedConfig -Section 'Colors' -Key 'FreshGreen' -Default "`e[38;2;137;209;133m" }
    $accent  = if ($Colors -and $Colors.Accent)  { $Colors.Accent  } else { Get-CachedConfig -Section 'Colors' -Key 'SageGreen'  -Default "`e[38;2;159;177;159m" }
    $muted   = if ($Colors -and $Colors.Muted)   { $Colors.Muted   } else { Get-CachedConfig -Section 'Colors' -Key 'MidGray'    -Default "`e[38;2;100;100;100m" }
    $border  = if ($Colors -and $Colors.Border)  { $Colors.Border  } else { $primary }
    $rst     = if ($Colors -and $Colors.Rst)     { $Colors.Rst     } else { Get-CachedConfig -Section 'Colors' -Key 'Rst' -Default "`e[0m" }

    # 宽度: 取窗口宽度, 但不小于 60(避免徽章换行)
    if ($Width -le 0) {
        $Width = [Math]::Max(60, [Console]::WindowWidth)
    }
    $hLine = "-" * ($Width - 4)

    # Header 区域: 第 1-4 行(标题行 / 空行 / 装饰行 / 分隔线)
    $hostname = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { "local" }
    $userName = if ($env:USERNAME) { $env:USERNAME } else { "user" }
    $cwd = Split-Path -Leaf $PWD.Path
    if (-not $cwd) { $cwd = $PWD.Path }

    # 徽章串: 拼接 " [text1] [text2] ..." 形式, 跟标题在同行显示
    $badgeStr = ""
    foreach ($b in $HeaderBadges) {
        $txt = if ($b -is [hashtable]) { $b.Text } else { "$b" }
        $col = if ($b -is [hashtable] -and $b.Color) { $b.Color } else { $accent }
        $badgeStr += " ${col}[$txt]${rst}"
    }

    $header = [System.Collections.Generic.List[string]]::new()
    $header.Add("")
    $header.Add("  ${primary}+--< ${muted}${userName}@${hostname}${primary} >--[ ${accent}${cwd}${primary} ]--[ ${primary}${Title}${primary} ]${rst}${badgeStr}")
    $header.Add("  ${primary}|${rst}")
    $header.Add("  ${primary}+${hLine}--${rst}")

    # Footer 区域: 默认 2 行(快捷键提示 / 装饰), 留空由调用方填充
    $footer = [System.Collections.Generic.List[string]]::new()
    $footer.Add("  ${primary}+${hLine}--${rst}")
    $footer.Add("")

    return [PSCustomObject]@{
        Title     = $Title
        Width     = $Width
        Primary   = $primary
        Accent    = $accent
        Muted     = $muted
        Border    = $border
        Rst       = $rst
        HLine     = $hLine
        Header    = $header
        Main      = [System.Collections.Generic.List[string]]::new()
        Footer    = $footer
        HeaderRowCount = $header.Count
    }
}

function Add-MainLine {
    [CmdletBinding(SupportsShouldProcess=$true)]
    <#
    .SYNOPSIS
        向布局的 Main 区域追加一行

    .PARAMETER Layout
        New-AnsiLayout 返回的布局对象

    .PARAMETER Text
        追加的完整 ANSI 字符串(已含颜色转义)
    #>
    [CmdletBinding()]
    [OutputType([void])]
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Layout,

        [Parameter(Mandatory = $true)]
        [string]$Text
    )
    $Layout.Main.Add($Text) | Out-Null
}

function Set-FooterLine {
    <#
    .SYNOPSIS
        设置 Footer 区域指定索引处的文本

    .PARAMETER Layout
        New-AnsiLayout 返回的布局对象

    .PARAMETER Index
        Footer 行索引(0-based)

    .PARAMETER Text
        设置的完整 ANSI 字符串
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Layout,

        [Parameter(Mandatory = $true)]
        [int]$Index,

        [Parameter(Mandatory = $true)]
        [string]$Text
    )
    if ($Index -ge 0 -and $Index -lt $Layout.Footer.Count) {
        $Layout.Footer[$Index] = $Text
    }
}

function Show-AnsiLayout {
    <#
    .SYNOPSIS
        将布局完整渲染到控制台(清屏 + 逐行输出)

    .PARAMETER Layout
        New-AnsiLayout 返回的布局对象

    .PARAMETER StartRow
        起始输出行号(默认 1, 整屏清空重绘时用)
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Layout,

        [Parameter(Mandatory = $false)]
        [int]$StartRow = 1
    )
    if ($StartRow -eq 1) { [Console]::Clear() }
    $row = $StartRow
    foreach ($line in $Layout.Header) {
        Write-AnsiLine -Line $row -Text $line
        $row++
    }
    foreach ($line in $Layout.Main) {
        Write-AnsiLine -Line $row -Text $line
        $row++
    }
    foreach ($line in $Layout.Footer) {
        Write-AnsiLine -Line $row -Text $line
        $row++
    }
}
