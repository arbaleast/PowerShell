# ============================================================
# ShellPrompt.psm1 — 模块入口
# ============================================================

# 1. 加载配置
. "$PSScriptRoot\Private\Initialize-Config.ps1"

# 2. 加载所有私有函数（排除配置）
Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" |
    Where-Object { $_.Name -ne 'Initialize-Config.ps1' } |
    ForEach-Object { . $_.FullName }

# 3. 加载所有公有函数
Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" |
    ForEach-Object { . $_.FullName }

# 4. 别名
Set-Alias ll Get-ChildItem -ErrorAction SilentlyContinue
Set-Alias which where.exe -ErrorAction SilentlyContinue

# 5. 导出 — 从所有 Public/*.ps1 内容中提取函数名
$publicFunctions = Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" | ForEach-Object {
    $content = Get-Content $_.FullName -Raw
    [regex]::Matches($content, '(?m)^function\s+(\w+)') | ForEach-Object { $_.Groups[1].Value }
}

Export-ModuleMember -Function $publicFunctions
