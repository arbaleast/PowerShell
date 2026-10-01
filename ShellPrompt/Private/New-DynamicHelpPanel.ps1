# New-DynamicHelpPanel.ps1 - 动态帮助面板
# 根据当前选中项的 Action 标签返回对应的快捷键提示字符串
# P1-3 使用场景: Show-SessionManager 中, 选中"附着"显示 [↵ 附着 R 重命名 Del 删除],
# 选中"删除"显示 [↵ 删除 ↑↓ 选择 双重确认] 等


function New-DynamicHelpPanel {
    <#
    .SYNOPSIS
        根据上下文构造动态帮助提示字符串

    .DESCRIPTION
        接收一组 HelpEntry(键+说明)数组, 返回拼接后的 ANSI 字符串。
        每条目格式: @{ Keys = "Enter"; Action = "附着" }, 多个条目以 │ 分隔。

    .PARAMETER Entries
        帮助条目数组(每个为 hashtable 或 PSCustomObject, 至少含 Keys + Action)

    .PARAMETER Colors
        颜色覆盖表(主色/弱化色/重置)

    .EXAMPLE
        $help = New-DynamicHelpPanel -Entries @(
            @{ Keys = "↵"; Action = "附着" }
            @{ Keys = "Del"; Action = "删除" }
            @{ Keys = "R"; Action = "刷新" }
        )
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    [OutputType([string])]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '')]    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$Entries,

        [Parameter(Mandatory = $false)]
        [hashtable]$Colors
    )

    if (-not $Entries -or $Entries.Count -eq 0) { return "" }

    $primary = if ($Colors -and $Colors.Primary) { $Colors.Primary } else { Get-CachedConfig -Section 'Colors' -Key 'FreshGreen' -Default "`e[38;2;137;209;133m" }
    $accent  = if ($Colors -and $Colors.Accent)  { $Colors.Accent  } else { Get-CachedConfig -Section 'Colors' -Key 'SageGreen'  -Default "`e[38;2;159;177;159m" }
    $muted   = if ($Colors -and $Colors.Muted)   { $Colors.Muted   } else { Get-CachedConfig -Section 'Colors' -Key 'MidGray'    -Default "`e[38;2;100;100;100m" }
    $rst     = if ($Colors -and $Colors.Rst)     { $Colors.Rst     } else { Get-CachedConfig -Section 'Colors' -Key 'Rst' -Default "`e[0m" }

    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($e in $Entries) {
        # 使用 [''] 索引避免 hashtable.Keys 属性冲突(返回 KeyCollection 枚举器)
        $keys = if ($e -is [System.Collections.IDictionary]) { $e['Keys'] } else { $e.Keys }
        $action = if ($e -is [System.Collections.IDictionary]) { $e['Action'] } else { $e.Action }
        if ([string]::IsNullOrEmpty($keys) -or [string]::IsNullOrEmpty($action)) { continue }
        $parts.Add("${primary}[$keys]${rst} ${muted}$action${rst}") | Out-Null
    }

    return $parts -join "  ${muted}│${rst}  "
}

function Get-SessionActionHelp {
    <#
    .SYNOPSIS
        根据当前选中的会话动作返回对应的帮助条目

    .DESCRIPTION
        Q2=A 决策: 快捷键硬编码, 但根据选中动作动态切换内容。
        - "附着/恢复" 时: Enter 附着 / Del 删除(选中项) / R 刷新
        - "删除" 时: Enter 删除(需二次确认) / ↑↓ 选择
        - "刷新" 时: Enter 刷新
        - "新建"/"直连" 时: Enter 执行

    .PARAMETER ActionLabel
        当前选中项的 Label 文字

    .OUTPUTS
        HelpEntry 数组, 供 New-DynamicHelpPanel 使用
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ActionLabel
    )

    $common = @(
        @{ Keys = "Esc"; Action = "退出" },
        @{ Keys = "Q"; Action = "退出" }
    )

    switch ($ActionLabel) {
        "附着/恢复 tmux 会话" {
            return ,(@(
                @{ Keys = "Enter"; Action = "选择会话并附着" },
                @{ Keys = "R"; Action = "刷新会话列表" }
            ) + $common)
        }
        "删除 tmux 会话" {
            return ,(@(
                @{ Keys = "Enter"; Action = "选择并删除(需二次确认)" },
                @{ Keys = "R"; Action = "刷新会话列表" }
            ) + $common)
        }
        "刷新会话列表" {
            return ,(@(
                @{ Keys = "Enter"; Action = "立即刷新" }
            ) + $common)
        }
        default {
            return ,(@(
                @{ Keys = "Enter"; Action = "执行" }
            ) + $common)
        }
    }
}
