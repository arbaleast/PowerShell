# Get-GridViewColumnPlan.ps1 - GridView 表格的列裁剪计划
# 职责: 计算可见列/键列/隐藏列, 并产出用于渲染的裁剪行。
# 抽出来的原因: 列裁剪逻辑与弹窗调用耦合较深, 独立成函数后 Invoke-GridViewPrompt
# 只负责"弹窗 + 归一化 + 恢复隐藏字段", 便于单独验证。

function Get-GridViewColumnPlan {
    <#
    .SYNOPSIS
        计算 GridView 表格的列裁剪计划。

    .DESCRIPTION
        跨模块解耦点: 用户可见表格不能泄漏内部字段(Disabled/Value/Status),
        而弹窗返回后又要能把这些字段恢复回选中对象。本函数负责:
          1. 选定唯一键列(优先 Name/Label/Host/Action/Session/No, 兜底用索引列);
          2. 计算可见列(键列 + 非隐藏、非下划线开头的属性);
          3. 产出裁剪后的行对象供 Out-ConsoleGridView 渲染。

    .PARAMETER Rows
        原始行数据(PSCustomObject 数组)

    .PARAMETER HiddenColumns
        哈希表: 键 = 隐藏列名, 值 = 默认恢复值

    .OUTPUTS
        PSCustomObject(.KeyColumn/.HiddenKeys/.VisibleColumns/.TrimmedRows)

    .EXAMPLE
        $plan = Get-GridViewColumnPlan -Rows $rows -HiddenColumns @{ Value = '' }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '')]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Rows,
        [Parameter(Mandatory = $false)][hashtable]$HiddenColumns
    )

    # 优先用 Name/Label/Host/Action/Session/No 等自然唯一键
    $keyColumn = $null
    foreach ($col in @('Name', 'Label', 'Host', 'Action', 'Session', 'No')) {
        if ($Rows[0].PSObject.Properties[$col]) {
            $keyColumn = $col
            break
        }
    }
    if (-not $keyColumn) {
        # 兜底: 用索引号作为行标识
        for ($i = 0; $i -lt $Rows.Count; $i++) {
            $Rows[$i] | Add-Member -NotePropertyName '_RowIdx' -NotePropertyValue $i -Force
        }
        $keyColumn = '_RowIdx'
    }

    # 提取可见列名(排除隐藏列的键)
    $hiddenKeys = if ($HiddenColumns -and $HiddenColumns.Keys) { $HiddenColumns.Keys } else { @() }
    $visibleColumns = @($keyColumn)
    foreach ($prop in $Rows[0].PSObject.Properties) {
        if ($prop.Name -notin $hiddenKeys -and $prop.Name -ne $keyColumn -and $prop.Name -notmatch '^_') {
            $visibleColumns += $prop.Name
        }
    }

    return [PSCustomObject]@{
        KeyColumn      = $keyColumn
        HiddenKeys     = @($hiddenKeys)
        VisibleColumns = $visibleColumns
        TrimmedRows    = @($Rows | Select-Object -Property $visibleColumns)
    }
}
