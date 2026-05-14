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
Set-Alias water Start-WaterReminder -ErrorAction SilentlyContinue

# 5. 显式导出所有公有函数
$publicFunctions = @(
    'Initialize-Environment'
    'Show-UserScoopLogo'
    'Start-TmuxSession'
    'Start-WaterReminder'
    'Get-WaterReminderHistory'
    'reload'
)

Export-ModuleMember -Function $publicFunctions
