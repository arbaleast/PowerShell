function ConvertTo-SshEscapedString {
    <#
    .SYNOPSIS
        转义字符串中的单引号以安全嵌入 SSH 远程命令

    .DESCRIPTION
        SSH 远程命令通过 `sh -c '...'` 执行, 字符串中的单引号必须转换为 `'\''` 序列。
        本函数执行该转义。调用方需自行决定是否需要外围单引号包裹。

    .PARAMETER Value
        待转义的原始字符串

    .EXAMPLE
        ConvertTo-SshEscapedString -Value "it's a test" → "it'\''s a test"
    #>
    [CmdletBinding()]
    [OutputType([string])]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '')]    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Value
    )
    return $Value -replace "'", "'\''"
}
