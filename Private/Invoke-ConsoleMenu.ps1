function Invoke-ConsoleMenu
{
    <#
    .SYNOPSIS
        通用的终端交互式菜单组件。
    .DESCRIPTION
        渲染一个上下可导航的终端菜单，返回用户选中的项（字符串）或 $null（退出）。
        业务逻辑与 UI 渲染完全分离。
    .PARAMETER Title
        菜单标题，显示在顶部。
    .PARAMETER Options
        菜单选项数组，每项为一个字符串。
    .PARAMETER Color
        高亮颜色，默认 Cyan。
    .PARAMETER ExitLabel
        退出选项的标签，默认 "EXIT"。
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
        [string]$Color = "Cyan",

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
        Write-Host "  $Title" -ForegroundColor $Color
        Write-Host "  $('─' * 50)" -ForegroundColor DarkGray

        # 选项列表
        for ($i = 0; $i -lt $count; $i++)
        {
            $fg = "White"
            $marker = "    "
            if ($i -eq $idx)
            {
                $fg = $Color
                $marker = "[>] "
            }
            Write-Host "$marker $($Options[$i])" -ForegroundColor $fg
        }

        # 退出项（固定在最后）
        $exitFg = if ($idx -eq $count)
        { $Color 
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
        Write-Host "  $('─' * 50)" -ForegroundColor DarkGray
        Write-Host "  ↑↓ move  ·  Enter select  ·  q quit" -ForegroundColor DarkGray
        Write-Host ""

        # 按键读取
        $key = $Host.UI.RawUI.ReadKey("NoEcho, IncludeKeyDown")
        $vK = $key.VirtualKeyCode

        # 导航
        if ($vK -eq 38)
        {
            $idx = ($idx - 1 + ($count + 1)) % ($count + 1)
            continue
        }
        if ($vK -eq 40)
        {
            $idx = ($idx + 1) % ($count + 1)
            continue
        }

        # 确认
        if ($vK -eq 13)
        {
            if ($idx -eq $count)
            {
                return $null
            }
            return $Options[$idx]
        }

        # 退出
        if ($key.Character -eq 'q' -or $key.Character -eq 'Q')
        {
            return $null
        }
    }
}
