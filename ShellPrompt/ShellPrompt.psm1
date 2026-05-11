# ============================================================
# ShellPrompt.psm1 — 模块入口
# ============================================================

# 1. 首先加载配置（其他所有文件依赖它）
. "$PSScriptRoot\Private\Initialize-Config.ps1"

# 2. 加载所有私有函数
Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" | Where-Object { $_.Name -ne 'Initialize-Config.ps1' } | ForEach-Object {
    . $_.FullName
}

# 3. 加载所有公有函数
Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" | ForEach-Object {
    . $_.FullName
}

# 4. 加载别名（在函数加载完成后执行）
Set-Alias ll Get-ChildItem -ErrorAction SilentlyContinue
Set-Alias which where.exe -ErrorAction SilentlyContinue

# 5. 仅导出 Public 目录中的函数
$publicFunctions = (Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1").BaseName
Export-ModuleMember -Function $publicFunctions
