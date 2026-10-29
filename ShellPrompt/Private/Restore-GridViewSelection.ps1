# Restore-GridViewSelection.ps1 - GridView 选中结果的归一化与隐藏字段恢复
# 职责: 把 Out-ConsoleGridView 返回的选中结果统一成单个对象, 并把渲染时裁剪掉的
#       内部字段(Disabled/Value/Status)恢复回该对象。
# 抽出来的原因: 该逻辑与"弹窗调用"耦合无关, 独立后 Invoke-GridViewPrompt 只负责弹窗。

function Restore-GridViewSelection {
    <#
    .SYNOPSIS
        归一化 GridView 选中结果并恢复被隐藏的内部字段。

    .DESCRIPTION
        跨模块解耦点: Out-ConsoleGridView 的返回可能是单对象, 也可能是单元素集合;
        而渲染前的列裁剪会把 Disabled/Value/Status 等内部字段移除。本函数统一这两种
        形态, 并按键列(KeyColumn)找回原始行, 把隐藏字段拷贝回选中对象; 原行不存在的
        字段使用 HiddenColumns 中配置的默认值。

    .PARAMETER Selected
        Out-ConsoleGridView 返回的原始选中结果

    .PARAMETER Rows
        渲染前的完整行数据(用于找回原始行)

    .PARAMETER KeyColumn
        唯一键列名(与 Get-GridViewColumnPlan 保持一致)

    .PARAMETER HiddenKeys
        需要恢复的隐藏字段名数组

    .PARAMETER HiddenColumns
        哈希表: 键 = 隐藏列名, 值 = 原行缺失该列时使用的默认值

    .OUTPUTS
        归一化后的选中对象(含恢复的隐藏字段), 或 $null

    .EXAMPLE
        $sel = Restore-GridViewSelection -Selected $raw -Rows $rows -KeyColumn 'Session' -HiddenKeys @('Value')
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)][object]$Selected,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Rows,
        [Parameter(Mandatory = $true)][string]$KeyColumn,
        [Parameter(Mandatory = $false)][AllowEmptyCollection()][string[]]$HiddenKeys = @(),
        [Parameter(Mandatory = $false)][hashtable]$HiddenColumns
    )

    # 归一化: 兼容单对象 / 单元素集合两种返回形态
    if ($Selected -is [System.Collections.IEnumerable] -and $Selected -isnot [string]) {
        $first = $null
        foreach ($item in $Selected) {
            $first = $item
            break
        }
        if ($null -eq $first) {
            return $null
        }
        $Selected = $first
    }

    # 用键列找到原始行, 并将隐藏字段拷贝到返回对象
    $keyVal = $Selected.$KeyColumn
    $originalRow = $Rows | Where-Object { $_."$KeyColumn" -eq $keyVal } | Select-Object -First 1
    if ($originalRow) {
        foreach ($hk in $HiddenKeys) {
            if ($originalRow.PSObject.Properties[$hk]) {
                $Selected | Add-Member -NotePropertyName $hk -NotePropertyValue $originalRow.$hk -Force
            } elseif ($HiddenColumns) {
                # 列在原行中不存在, 使用传入的默认值
                $Selected | Add-Member -NotePropertyName $hk -NotePropertyValue $HiddenColumns[$hk] -Force
            }
        }
    }

    return $Selected
}
