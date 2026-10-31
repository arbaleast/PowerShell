# Test-TguiQuitKey.ps1 - TGUI 事件参数(Key)是否为"退出键"的纯判定(Esc / Ctrl+C)
#
# 背景 (2026-10-31 真机 Ctrl+C 修复):
#   Ctrl+C 的 Key.KeyCode 在 2.4.10 的 ToString() 是 **'C, CtrlMask'** 形态
#   (真机取证 Diag-TguiKeys: "VIEW KeyDown: C, CtrlMask") —— 整串与 'C'
#   等值比较永远失败, 这是 91b4280 首版兜底真机无效的根因。
#   Esc 恰好无修饰后缀, 所以 Esc 判断首版即生效。
#
# 判定 = Esc 原样, 或 Ctrl+C:
#   - 优先 Key.IsCtrl 属性(p72 探针: Key 有 get_IsCtrl);
#   - KeyCode 文本带 'CtrlMask' 后缀时也按 Ctrl 处理(双保险, 防形态漂移);
#   - 基键取 ',' 前第一段 Trim 后等于 'C'/'c'。

function Test-TguiQuitKey {
    <#
    .SYNOPSIS
        判断 TGUI KeyDown 事件参数($args[1] 的 Key)是否为 Esc / Ctrl+C。

    .DESCRIPTION
        纯函数, 不触碰 ALC 外的任何状态; 异常一律返回 $false(非退出键)。

    .PARAMETER Key
        TG KeyDown 事件的 Key 参数(跨 ALC 实例, 动态属性访问)。

    .OUTPUTS
        [bool]

    .EXAMPLE
        $win.add_KeyDown({ if (Test-TguiQuitKey -Key $args[1]) { ... } })
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Key
    )

    if ($null -eq $Key) { return $false }
    try {
        $kcText = [string]$Key.KeyCode
        if ($kcText -eq 'Esc') { return $true }

        $isCtrl = $false
        try { $isCtrl = [bool]$Key.IsCtrl } catch { $isCtrl = $false }
        if (-not $isCtrl -and $kcText -match 'CtrlMask') { $isCtrl = $true }
        if (-not $isCtrl) { return $false }

        $baseKey = ($kcText -split ',')[0].Trim()
        return ($baseKey -in @('C', 'c'))
    } catch {
        return $false
    }
}
