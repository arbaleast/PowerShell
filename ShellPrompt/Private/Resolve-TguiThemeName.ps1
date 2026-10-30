# Resolve-TguiThemeName.ps1 - UI.Theme.Name 配置值的规范化(纯函数)
#
# 背景 (2026-10-30 PSTui 移除):
#   原 Resolve-TgThemeName 位于既已删除的 Set-TgColorScheme.ps1(PSTui 默认
#   加载上下文轨)。ALC 原生的 Set-TguiTheme 仍需要同一份方案名规范化,
#   因此本函数迁入 TGUI 轨并更名 —— 行为与原实现逐字等价。

function Resolve-TguiThemeName {
    <#
    .SYNOPSIS
        把配置里的 UI.Theme.Name 规范化成方案名列表。

    .DESCRIPTION
        真终端颜色指纹探针实测(TG 2.4.10.0): 表格主体取自 Scheme 'Base',
        底部状态栏取自 Scheme 'Menu'。只覆写其中一个必然"看起来没生效",
        因此配置形态必须支持多 Scheme。

        **必须兼容两种旧/新形态**:
          - [string[]]@('Base','Menu') —— 当前默认形态;
          - 裸字符串 'Menu'            —— 用户既有配置文件里的形态。
        裸字符串经过 @() 包裹天然成为单元素数组, 此处再做逗号切分与去空白,
        任何形态都不会抛异常。空值 / 全空白时回退到 'Base'。

    .PARAMETER Name
        配置里的原始值, 允许为 $null / 单字符串 / 字符串数组

    .OUTPUTS
        [string[]] 已去重、去空白的方案名数组

    .EXAMPLE
        Resolve-TguiThemeName -Name 'Menu'
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Name
    )

    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($item in @($Name)) {
        if ($null -eq $item) { continue }
        # 兼容 'Base,Menu' 这种被写成单个逗号分隔字符串的形态
        foreach ($piece in ([string]$item -split ',')) {
            $trimmed = $piece.Trim()
            if ($trimmed -and -not $names.Contains($trimmed)) {
                $names.Add($trimmed)
            }
        }
    }
    if ($names.Count -eq 0) {
        $names.Add('Base')
    }
    return $names.ToArray()
}
