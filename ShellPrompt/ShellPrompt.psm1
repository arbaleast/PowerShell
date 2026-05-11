# ============================================================
# ShellPrompt.psm1 — 模块入口（修复版）
# ============================================================

# 1. 加载配置
$configPath = Join-Path $PSScriptRoot "Private\Initialize-Config.ps1"
if (Test-Path $configPath)
{ . $configPath 
}

# 2. 加载所有私有函数 (排除配置文件)
Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" |
    Where-Object { $_.Name -ne 'Initialize-Config.ps1' } |
    ForEach-Object { . $_.FullName }

# 3. 加载所有公有函数
Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" |
    ForEach-Object { . $_.FullName }

# 4. 定义别名 (确保在函数加载之后)
# 注意：reload 必须指向 Public 目录下的函数名 Invoke-Reload
Set-Alias ll Get-ChildItem -Description "Quick list"
Set-Alias which where.exe -Description "Find command path"
Set-Alias reload Invoke-Reload -Description "Reload profile"

# 5. 导出成员
$publicFunctions = (Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1").BaseName
# 关键：必须同时指定 -Function 和 -Alias 才能全部导出
Export-ModuleMember -Function $publicFunctions -Alias *
