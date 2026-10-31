# Get-TguiTextWidth.ps1 - 终端显示宽度测量(纯函数, 无副作用)
#
# 背景 (2026-10-31 sss 仪表盘 UI 升级):
#   底部快捷键栏需要按**可用列宽**决定显示哪些项, 否则窄终端里
#   StatusBar 会在右侧硬截断(真机 40x10 取证: "s SSH" 被截成 "s SS",
#   x/q/Esc 三项完全不可见)。要做到"按宽度取舍而不是按截断",
#   必须先能算出每项在终端里占多少列。
#
# 口径与 Terminal.Gui 使用的 Wcwidth 保持一致:
#   - 东亚全角/宽字符(CJK 统一表注音、假名、全角形式、扩展 A/B 等)占 2 列;
#   - 组合记号/变体选择符占 0 列;
#   - 其余占 1 列;
#   - 代理对(增补平面, 如 emoji)按**一个**宽字符计 2 列, 不拆成两个代理项。
#
# 契约: 纯函数, 不触碰控制台/终端/网络 —— 可直接对任意字符串断言。

function Get-TguiTextWidth {
    <#
    .SYNOPSIS
        测量文本在终端里的显示宽度(列数)。

    .DESCRIPTION
        返回文本占用的终端列数: 东亚全角/宽字符计 2, 零宽字符计 0, 其余计 1。
        用于"按宽度取舍"的布局预算估算(底部快捷键栏、标题带分区)。

    .PARAMETER Text
        待测量的文本(可含中文/全角标点/emoji)。

    .OUTPUTS
        [int] 显示宽度(列数); 空串返回 0。

    .EXAMPLE
        Get-TguiTextWidth -Text '附着'   # => 4
        Get-TguiTextWidth -Text 'Attached' # => 8
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text
    )

    if ([string]::IsNullOrEmpty($Text)) { return 0 }

    # 宽字符区段(Wcwidth 口径: 全角 + 宽表意文字 + emoji 区段)
    $wideRanges = @(
        @(0x1100, 0x115F),   # 谚文字母
        @(0x2E80, 0x303E),   # CJK 部首 / 康熙部首 / CJK 符号与标点
        @(0x3041, 0x33FF),   # 平假名 / 片假名 / 注音 / 兼容符号
        @(0x3400, 0x4DBF),   # CJK 扩展 A
        @(0x4E00, 0x9FFF),   # CJK 统一表意文字
        @(0xA000, 0xA4CF),   # 彝文
        @(0xAC00, 0xD7A3),   # 谚文音节
        @(0xF900, 0xFAFF),   # CJK 兼容表意文字
        @(0xFE30, 0xFE4F),   # CJK 兼容形式
        @(0xFF00, 0xFF60),   # 全角形式
        @(0xFFE0, 0xFFE6),   # 全角符号
        @(0x1F300, 0x1F64F), # emoji 表情与图形
        @(0x1F900, 0x1F9FF), # 补充符号与图形
        @(0x20000, 0x2FFFD), # CJK 扩展 B~F
        @(0x30000, 0x3FFFD)  # CJK 扩展 G+
    )
    # 零宽区段(组合记号 / 变体选择符 / 零宽连接符)
    $zeroRanges = @(
        @(0x0300, 0x036F),   # 组合变音符号
        @(0x200B, 0x200F),   # 零宽空格/方向标记
        @(0x20D0, 0x20FF),   # 组合记号
        @(0xFE00, 0xFE0F)    # 变体选择符
    )

    $width = 0
    $index = 0
    $length = $Text.Length
    while ($index -lt $length) {
        $code = [int][char]$Text[$index]
        # 代理对: 高代理 + 低代理 => 合成一个码位
        if ($code -ge 0xD800 -and $code -le 0xDBFF -and ($index + 1) -lt $length) {
            $low = [int][char]$Text[$index + 1]
            if ($low -ge 0xDC00 -and $low -le 0xDFFF) {
                $code = 0x10000 + (($code - 0xD800) * 0x400) + ($low - 0xDC00)
                $index += 2
            } else {
                $index++
            }
        } else {
            $index++
        }

        $cellWidth = 1
        foreach ($range in $zeroRanges) {
            if ($code -ge $range[0] -and $code -le $range[1]) { $cellWidth = 0; break }
        }
        if ($cellWidth -eq 1) {
            foreach ($range in $wideRanges) {
                if ($code -ge $range[0] -and $code -le $range[1]) { $cellWidth = 2; break }
            }
        }
        $width += $cellWidth
    }

    return $width
}
