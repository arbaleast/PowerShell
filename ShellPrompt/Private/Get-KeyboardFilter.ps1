# Get-KeyboardFilter.ps1 - 通用键盘过滤工具
# 独立于菜单状态机, 可被任何需要"打字即搜"的场景复用
# (菜单场景已用 Invoke-MenuMachine 内置的 Get-VisibleMenuItems, 此文件提供更通用的工具)

function Test-FilterCharacter {
    <#
    .SYNOPSIS
        判断一个字符是否应被纳入过滤字符串(可打印 + 安全字符)

    .DESCRIPTION
        仅接受 [a-zA-Z0-9._-], 拒绝空格/控制字符/Unicode(避免拼音输入冲突, 与 Q1=A 对齐)。
        Send-MenuKey / 自定义输入框 / 第三方调用方均应使用此函数判定。

    .PARAMETER Character
        单个字符(可来自 [Console]::ReadKey().KeyChar 或 RawUI.ReadKey().Character)

    .EXAMPLE
        if (Test-FilterCharacter $key.Character) { $filter += $key.Character }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '')]    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Character
    )
    if ([string]::IsNullOrEmpty($Character)) { return $false }
    return ($Character -match '^[a-zA-Z0-9\.\-_]$')
}

function Get-FilteredItems {
    [CmdletBinding(SupportsShouldProcess=$true)]
    <#
    .SYNOPSIS
        根据过滤字符串在候选集合中筛选匹配项(大小写不敏感 + Contains 匹配)

    .DESCRIPTION
        纯函数, 不修改任何状态。
        候选项支持 PSCustomObject/hashtable/字符串数组, 取 .Label 或字符串本身。
        可选 AlwaysInclude 参数指定始终保留的项(如 EXIT 项)。

    .PARAMETER Items
        候选项集合

    .PARAMETER Filter
        过滤字符串(空时返回全部)

    .PARAMETER AlwaysInclude
        始终保留的项(如 EXIT 项), 不参与过滤

    .PARAMETER LabelProperty
        候选项的标签属性名(默认 'Label')

    .EXAMPLE
        $matched = Get-FilteredItems -Items $allItems -Filter "deb" -AlwaysInclude $exit
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$Items,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Filter = "",

        [Parameter(Mandatory = $false)]
        [object[]]$AlwaysInclude = @(),

        [Parameter(Mandatory = $false)]
        [string]$LabelProperty = "Label"
    )

    if ([string]::IsNullOrEmpty($Filter)) {
        return ,@($Items)
    }
    $f = $Filter.ToLowerInvariant()

    $matched = @()
    foreach ($item in $Items) {
        $label = if ($item -is [string]) { $item } elseif ($item.PSObject -and $item.PSObject.Properties[$LabelProperty]) { $item.$LabelProperty } else { "$item" }
        if ($label -and $label.ToString().ToLowerInvariant().Contains($f)) {
            $matched += $item
        }
    }
    foreach ($keep in $AlwaysInclude) {
        $matched += $keep
    }
    return ,$matched
}

function Update-FilterString {
    <#
    .SYNOPSIS
        根据当前按键更新过滤字符串(状态机无关的纯字符串操作)

    .DESCRIPTION
        输入: 当前 filter 字符串 + 按键对象, 输出: 新 filter 字符串。
        不修改任何外部状态, 便于测试。

    .PARAMETER Filter
        当前过滤字符串

    .PARAMETER Key
        ReadKey 返回的 KeyInfo/ConsoleKeyInfo 对象

    .OUTPUTS
        新过滤字符串(若按键不修改则返回原值)
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Filter,

        [Parameter(Mandatory = $true)]
        [object]$Key
    )
    $vK = $Key.VirtualKeyCode
    $char = $Key.Character

    # Backspace
    if ($vK -eq 8) {
        if ($Filter.Length -gt 0) { return $Filter.Substring(0, $Filter.Length - 1) }
        return $Filter
    }
    # Ctrl+U
    if ($vK -eq 17) { return "" }
    # 普通字符
    if (Test-FilterCharacter -Character $char) { return $Filter + $char }
    return $Filter
}
