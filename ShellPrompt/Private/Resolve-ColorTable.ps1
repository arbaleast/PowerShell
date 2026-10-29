# Resolve-ColorTable.ps1 - 统一的颜色语义解析助手
# 把分散在多个渲染文件里的"取一个 Colors 键 + 默认值"模式收敛到一处:
#   1) 调用方显式覆盖优先(非空值生效);
#   2) 其次走配置层(Get-CachedConfig: 预热缓存 -> $script:Config -> 默认值);
#   3) 默认值取自配置层 $script:Config.Colors, 本文件不硬编码任何 ANSI 字面量。
# 语义键与配置键的映射集中在 $script:ColorSemanticMap, 新增语义只需要改这一处。

# 颜色语义键 -> 配置层 Colors 键
$script:ColorSemanticMap = @{
    Primary    = 'FreshGreen'
    Accent     = 'SageGreen'
    Muted      = 'MidGray'
    Danger     = 'Danger'
    Warning    = 'Warning'
    SelectedBg = 'SelectedBg'
    Cyan       = 'Cyan'
    Dark       = 'DarkGray'
    Rst        = 'Rst'
}

function Resolve-ColorTable {
    <#
    .SYNOPSIS
        解析一组颜色语义键, 返回"语义键 -> ANSI 串"的哈希表。

    .DESCRIPTION
        统一菜单/横幅/徽章等渲染点的颜色预解析:
        - 调用方覆盖(Colors 哈希表)中的非空值优先;
        - 否则走配置层 Get-CachedConfig(命中预热缓存时零额外开销);
        - 再否则回退到 $script:Config.Colors 中的配置值(本文件不内置 ANSI 字面量)。
        'Border' 语义键默认跟随已解析的 'Primary'(与各渲染点历史行为一致)。

    .PARAMETER Name
        需要的语义键名数组, 可选值:
        Primary / Accent / Muted / Danger / Warning / SelectedBg / Cyan / Dark / Rst / Border

    .PARAMETER Colors
        调用方颜色覆盖表(语义键 -> ANSI 串), 可为空

    .OUTPUTS
        哈希表: 语义键 -> ANSI 串

    .EXAMPLE
        $t = Resolve-ColorTable -Name 'Primary', 'Accent', 'Rst'
        $t.Primary
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Name,

        [Parameter(Mandatory = $false)]
        [hashtable]$Colors
    )

    $table = @{}
    foreach ($n in $Name) {
        # Border 依赖 Primary, 放到第二轮处理
        if ($n -eq 'Border') { continue }
        # 1) 调用方覆盖优先
        if ($Colors -and $Colors.ContainsKey($n) -and $Colors[$n]) {
            $table[$n] = $Colors[$n]
            continue
        }
        # 2) 配置层取值(预热缓存 -> $script:Config -> 默认值)
        $cfgKey = $script:ColorSemanticMap[$n]
        if (-not $cfgKey) {
            $table[$n] = ''
            continue
        }
        $table[$n] = Get-CachedConfig -Section 'Colors' -Key $cfgKey -Default $script:Config.Colors[$cfgKey]
    }

    # 3) Border 语义键: 调用方覆盖 > Primary(已按同样优先级解析)
    if ($Name -contains 'Border') {
        if ($Colors -and $Colors.ContainsKey('Border') -and $Colors['Border']) {
            $table['Border'] = $Colors['Border']
        } elseif ($table.ContainsKey('Primary')) {
            $table['Border'] = $table['Primary']
        } else {
            $cfgKey = $script:ColorSemanticMap['Primary']
            $table['Border'] = Get-CachedConfig -Section 'Colors' -Key $cfgKey -Default $script:Config.Colors[$cfgKey]
        }
    }

    return $table
}
