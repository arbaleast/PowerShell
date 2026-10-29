# Format-GridViewStateText.ps1 - State 列文字的 24bit 真彩色染色助手
#
# 职责: 为 GridView State 列的危险/备选字面量染上 ANSI 真彩色,
#       Colors 域的 Danger / Warning 死代码由此接驳到 State 列文字色。
# 仅在 ColorKey ∈ {Danger, Warning} 时上色; 其它 key 走无色回退。
# 颜色码从 $script:Config.Colors 读取(已含 ESC, 与 Colors 域现有 ANSI 字符串同形态);
# 缺失时静默回退到纯文本, 绝不抛错。

function Format-GridViewStateText {
    <#
    .SYNOPSIS
        为 State 列文字加 ANSI 24bit 真彩色; Colors 域死代码接驳。

    .DESCRIPTION
        仅当 ColorKey ∈ {Danger, Warning} 时从 $script:Config.Colors 读取 SGR 串并
        包裹文本; 否则原样返回。颜色串缺失/为空时静默回退, 不抛错。
        颜色串若未以重置码 $script:Config.Colors.Rst 结尾, 会自动追加, 防止颜色泄露。

    .PARAMETER Text
        要染色的文字(通常为 '⚠ 危险' / '⚠ 备选')

    .PARAMETER ColorKey
        颜色键名(语义键), 仅识别 Danger / Warning(大小写不敏感)

    .OUTPUTS
        [string] 染色后文字(无色时与输入相同)

    .EXAMPLE
        Format-GridViewStateText -Text '⚠ 危险' -ColorKey 'Danger'
        # → "$Esc[38;2;220;90;90m⚠ 危险$Esc[0m"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string]$ColorKey
    )

    # 仅识别 Danger / Warning; 其它键一律回退到纯文本
    $keyLc = $ColorKey.ToLowerInvariant()
    if ($keyLc -notin @('danger', 'warning')) {
        return $Text
    }

    # 从配置层读取颜色码(已含 ESC, 与 Colors 域同形态)
    $code = $null
    try {
        if ($script:Config -and $script:Config.Colors) {
            $code = $script:Config.Colors[$ColorKey]
            if ($null -eq $code) { $code = $script:Config.Colors[$keyLc] }
        }
    } catch {
        $code = $null
    }
    if ([string]::IsNullOrEmpty("$code")) {
        return $Text
    }

    # 解析重置码 Rst(文本之后追加, 防颜色泄露到下一行)
    $rst = $null
    try {
        if ($script:Config -and $script:Config.Colors -and $script:Config.Colors.Rst) {
            $rst = [string]$script:Config.Colors.Rst
        }
    } catch {
        $rst = $null
    }
    if ([string]::IsNullOrEmpty($rst)) {
        $rst = "$([char]27)[0m"
    }

    # Colors.Danger 可能本来就以 Rst 收尾, 先剥掉以避免重复叠加重置码;
    # 最终形态统一为 配色码 + 文字 + 重置码, 与 Colors 域现有 ANSI 形态一致
    if ($rst -and "$code".EndsWith($rst)) {
        $code = "$code".Substring(0, "$code".Length - $rst.Length)
    }

    return "$code$Text$rst"
}
