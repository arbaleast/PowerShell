# ============================================================
# ShellPrompt.psm1 — PowerShell 模块入口
# ============================================================

# 加载私有函数（不对外暴露）
Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" | ForEach-Object {
    . $_.FullName
}

# 加载公有函数
Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" | ForEach-Object {
    . $_.FullName
}

# 仅导出 Public 目录中的函数
$publicFunctions = (Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1").BaseName
Export-ModuleMember -Function $publicFunctions
