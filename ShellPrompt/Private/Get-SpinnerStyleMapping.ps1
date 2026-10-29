# Get-SpinnerStyleMapping.ps1 - ShellPrompt 样式名 -> Spectre.Console spinner 名
# 职责: 把 ShellPrompt 的 5 个样式名翻译成 Spectre.Console `Spinner.Known` 的成员名,
#       供 Invoke-WithProgress 传给 Invoke-SpectreCommandWithStatus -Spinner。
#
# 约束(不能凭印象写名字):
#   Invoke-SpectreCommandWithStatus 的 -Spinner 带
#   [ValidateSet([SpectreConsoleSpinner])], 候选集来自运行时的
#   `[Spectre.Console.Spinner+Known] | Get-Member -Static -MemberType Properties`
#   (见 Modules/PwshSpectreConsole/2.6.3/PwshSpectreConsole.psm1 的 SpectreConsoleSpinner
#   验证器)。映射到不存在的成员名会在**参数绑定阶段**直接抛
#   "Value 'xxx' is invalid. Try one of: ..."。
#
# 2026-10-29 修正: Blocks 原映射到 'Block1'。Spectre.Console 的 Spinner.Known
#   成员名里既没有 'Block1' 也没有 'Blocks'(实际成员是 Material / Material2...)，
#   因此 Invoke-WithProgress -Style 'Blocks' 会直接参数绑定失败。
#   改为映射到视觉等价的 'Material'(同样是竖条高度波浪动画)。

function Get-SpinnerStyleMapping {
    <#
    .SYNOPSIS
        将 ShellPrompt spinner 样式名映射到 Spectre.Spinner.Known 枚举字符串

    .DESCRIPTION
        映射规则:
          Dots    → Dots6     (用户原始诉求即"6 个点的加载动画")
          Braille → Dots3     (盲文点阵最接近的 Spectre 内置样式)
          Ascii   → Ascii     (直接对应)
          Blocks  → Material  (竖条高度波浪动画; Spectre 无 Block/Blocks 成员名)
          Arrows  → Arrow     (直接对应)
          其它     → Dots6     (安全回退)

        本函数是纯函数, 便于 Pester 单元测试覆盖所有分支。
        Invoke-WithProgress 用本函数把 ShellPrompt 样式名翻译成 Spectre 的 Spinner 名称。

    .PARAMETER Style
        ShellPrompt spinner 样式名 (Braille/Ascii/Blocks/Dots/Arrows)

    .OUTPUTS
        [string] Spectre.Spinner.Known 枚举名称 (例如 'Dots3', 'Ascii', 'Material')
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Style = 'Braille'
    )

    $map = @{
        'Dots'    = 'Dots6'
        'Braille' = 'Dots3'
        'Ascii'   = 'Ascii'
        'Blocks'  = 'Material'
        'Arrows'  = 'Arrow'
    }
    if ($map.ContainsKey($Style)) { return $map[$Style] }
    return 'Dots6'
}
