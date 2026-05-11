function Invoke-ConsoleMenu
{
    <#
    .SYNOPSIS
        通用的终端交互式菜单组件。
    .DESCRIPTION
        渲染一个上下可导航的终端菜单，返回用户选中的项（对象），或 "MENU_BACK"（退出）。
        业务逻辑与 UI 渲染完全分离。
    .PARAMETER Title
        菜单标题，显示在顶部。
    .PARAMETER Options
        菜单选项数组，每项为对象（字符串或 hashtable）。
    .PARAMETER ColorCyan
        高亮前景色，默认取自 $global:UserScoop_CONF.Colors.Cyan。
    .PARAMETER ColorGray
        次要文字颜色，默认取自 $global:UserScoop_CONF.Colors.Gray。
    .PARAMETER Keys
        按键码 hashtable（Up/Down/Enter/Esc），默认取自 $global:UserScoop_CONF.Keys。
    .PARAMETER ExitLabel
        退出项文字，默认 "EXIT"。
    .EXAMPLE
        $choice = Invoke-ConsoleMenu -Title "操作选择" -Options @("开始", "暂停", "停止")
        if ($choice -eq "停止") { ... }
    #>
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

        # 标题区
        Write-Host ""
        Write-Host "  ${ColorCyan}${Title}${ColorGray}"
        Write-Host "  $($('─') * 50)"

        # 选项列表
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

        # 退出项（固定在最后）
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

        # 底部装饰
        Write-Host ""
        Write-Host "  $($('─') * 50)"
        Write-Host "  ↑↓ move  ·  Enter select  ·  q quit" -ForegroundColor DarkGray
        Write-Host ""

        # 按键读取
        $key = $Host.UI.RawUI.ReadKey("NoEcho, IncludeKeyDown")
        $vK = $key.VirtualKeyCode

        # 导航
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

        # 确认
        if ($vK -eq $Keys.Enter)
        {
            if ($idx -eq $count)
            {
                return "MENU_BACK"
            }
            return $Options[$idx]
        }

        # 退出
        if ($key.Character -eq 'q' -or $key.Character -eq 'Q')
        {
            return "MENU_BACK"
        }
    }
}
