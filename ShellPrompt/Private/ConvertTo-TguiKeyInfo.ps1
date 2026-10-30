# ConvertTo-TguiKeyInfo.ps1 - Terminal.Gui 键对象 -> 仓库键事件形状的**桥接**(纯函数)
#
# 背景 (2026-10-30 TGUI 迁移 · 阶段 B):
#   仓库既有的键位契约是 ConsoleKey 风格: @{ Key = 'Escape'; KeyChar = [char]27 }
#   (见 Resolve-TmuxTuiKeyAction 的输入契约与现有单测)。
#   Terminal.Gui 2.4.10 的键对象不是这个形状 —— 反射实测:
#     - 键码枚举在 Terminal.Gui.Drivers.KeyCode, **只有 'Esc', 没有 'Escape'**;
#     - `Key.ToString()` 对字母返回**小写**('n'), `Key.KeyCode.ToString()` 返回**大写**('N');
#     - `Key.WithCtrl/WithShift/WithAlt` 是属性不是方法。
#   直接把 TG 的键丢给既有映射函数会静默失配(单字母键全部落空), 因此这里做一层
#   **显式翻译**: Esc -> Escape, 字母 -> 大写 Key + 小写 KeyChar, 其余原样透传。
#
# 契约: 纯函数, 不触碰控制台/TG 运行时 —— 只读入参对象的 .KeyCode 属性。

function ConvertTo-TguiKeyInfo {
    <#
    .SYNOPSIS
        把 Terminal.Gui 的键对象翻译成仓库键事件形状(Key/KeyChar)。

    .DESCRIPTION
        输入: 任何带 .KeyCode 属性的对象(Terminal.Gui.Input.Key 实例, 或测试桩
        PSCustomObject{ KeyCode = 'N' })。
        输出 PSCustomObject:
          .Key     - ConsoleKey 风格的名字: 'Escape' / 'Enter' / 'N' / 'CursorUp' ...
          .KeyChar - 对应字符: Esc -> [char]27, Enter -> [char]13,
                     字母 -> 小写字母, 其余 -> [char]0

        字母键的 KeyChar 取**小写**: Resolve-TmuxTuiKeyAction 会把 KeyChar 小写后
        与 Get-TmuxActionDefinition 的键位表比对, 大写会全部失配。

    .PARAMETER Key
        Terminal.Gui 键对象(或同形状桩对象)。

    .OUTPUTS
        [PSCustomObject] .Key / .KeyChar; 输入为 $null 时返回 $null。

    .EXAMPLE
        $info = ConvertTo-TguiKeyInfo -Key ([PSCustomObject]@{ KeyCode = 'Esc' })
        $info.Key | Should -BeExactly 'Escape'
    #>
    # 纯函数, 不改系统状态 —— ConvertTo- 动词按 PSSA 规则需显式豁免 ShouldProcess
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Key
    )

    if ($null -eq $Key) { return $null }

    # KeyCode 在 TG 里是 Terminal.Gui.Drivers.KeyCode 枚举; 用 [string] 取其名字。
    # 字符串桩(测试)同样适用 —— [string]'Esc' == 'Esc'。
    $code = [string]$Key.KeyCode
    if ([string]::IsNullOrEmpty($code)) { $code = [string]$Key }

    switch ($code) {
        'Esc' {
            return [PSCustomObject]@{ Key = 'Escape'; KeyChar = [char]27 }
        }
        'Enter' {
            return [PSCustomObject]@{ Key = 'Enter'; KeyChar = [char]13 }
        }
        default {
            # 单个 A-Z 字母: 键名大写, 字符小写
            if ($code.Length -eq 1 -and $code -cmatch '[A-Z]') {
                return [PSCustomObject]@{
                    Key     = $code
                    KeyChar = [char]([int][char]$code + 32)
                }
            }
            return [PSCustomObject]@{ Key = $code; KeyChar = [char]0 }
        }
    }
}
