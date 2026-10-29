# Invoke-Tests.ps1 - 固定测试入口
#
# 为什么需要这个入口:
#   本仓库测试套件已迁移到 Pester **v5+/v6 语法** (`Should -Be` / `Should -Invoke`),
#   与机器上常驻的 Pester 6.x 兼容。历史版本曾强制锁定 Pester 3.4.0 绝对路径,
#   导致新语法测试文件无法运行, 现已移除该锁定。
#   保留本入口的原因: 统一运行时版本守卫、统一输出汇总、支持以退出码反映结果 (CI 场景)。
#
# 用法 (pwsh 7.6+):
#   pwsh -NoProfile -File ./ShellPrompt/Tests/Invoke-Tests.ps1
#   pwsh -NoProfile -File ./ShellPrompt/Tests/Invoke-Tests.ps1 -Path 'ShellPrompt/Tests/Get-WttrWeather.Tests.ps1'
#   pwsh -NoProfile -File ./ShellPrompt/Tests/Invoke-Tests.ps1 -NoExit   (交互会话内调用时关闭 exit)

[CmdletBinding()]
[OutputType([void])]
param(
    # 要运行的测试文件; 省略则跑 Tests 目录全部 *.Tests.ps1
    [Parameter(Mandatory = $false)]
    [string[]]$Path,

    # 传给 Invoke-Pester 的额外参数 (splat)
    [Parameter(Mandatory = $false)]
    [hashtable]$PesterArgs,

    # 跑完后是否用退出码反映结果。
    # 默认开启(失败即非零退出) —— CI 与人工检查都需要它; 交互会话里用 `&` 调用本脚本时
    # 传 -NoExit, 否则 exit 会把当前会话一起结束。
    [Parameter(Mandatory = $false)]
    [switch]$NoExit
)

$ErrorActionPreference = 'Stop'

# ---- 1. 运行时版本守卫: 与 ShellPrompt.psd1 的 PowerShellVersion = 7.6 保持一致 ----
if ($PSVersionTable.PSVersion.Major -lt 7 -or
    ($PSVersionTable.PSVersion.Major -eq 7 -and $PSVersionTable.PSVersion.Minor -lt 6)) {
    throw "ShellPrompt v2.0 要求 PowerShell 7.6+, 当前为 $($PSVersionTable.PSVersion)。"
}

# ---- 2. 定位并加载 Pester 5+ (不再锁定 3.4.0) ----
# 优先使用已加载的 Pester; 否则从已安装模块中挑选版本号最高的一个
$loadedPester = Get-Module -Name Pester | Sort-Object Version -Descending | Select-Object -First 1
if ($loadedPester) {
    $pesterPath = $loadedPester.Path
}
else {
    $available = Get-Module -Name Pester -ListAvailable -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending |
        Where-Object { $_.Version.Major -ge 5 } |
        Select-Object -First 1
    if (-not $available) {
        throw "未找到 Pester 5+。请先安装: pwsh -c ""Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force"""
    }
    $pesterPath = $available.Path
}

Import-Module $pesterPath -Force -ErrorAction Stop
$pesterVersion = (Get-Module Pester | Sort-Object Version -Descending | Select-Object -First 1).Version.ToString()
if ($pesterVersion -notmatch '^[5-9]\.') {
    throw "Pester 版本校验失败: 实际 $pesterVersion (要求 5+)"
}
Write-Host "Pester 已加载: $pesterVersion" -ForegroundColor DarkGray

# ---- 3. 解析测试路径 ----
if (-not $Path) {
    $Path = @(Get-ChildItem -Path $PSScriptRoot -Filter '*.Tests.ps1' -File | Select-Object -ExpandProperty FullName)
}
Write-Host "待运行测试文件: $($Path.Count) 个" -ForegroundColor DarkGray

# ---- 4. 运行 (Pester v5+ 参数集: -Path / -PassThru / -Output) ----
$splat = @{ Path = $Path; PassThru = $true; Output = 'Normal' }
if ($PesterArgs) {
    foreach ($k in $PesterArgs.Keys) { $splat[$k] = $PesterArgs[$k] }
}

$result = Invoke-Pester @splat

# ---- 5. 汇总 ----
Write-Host ''
Write-Host ('=' * 60) -ForegroundColor DarkGray
Write-Host ("结果: 通过 {0} / 失败 {1} / 跳过 {2}" -f $result.PassedCount, $result.FailedCount, $result.SkippedCount) `
    -ForegroundColor $(if ($result.FailedCount -gt 0) { 'Red' } else { 'Green' })

if ($result.FailedCount -gt 0) {
    Write-Host '失败明细:' -ForegroundColor Red
    foreach ($t in $result.Failed) {
        Write-Host ("  - [{0}] {1}" -f $t.ExpandedPath, $t.Name) -ForegroundColor Red
        foreach ($m in @($t.ErrorRecord | Where-Object { $_ })) {
            Write-Host ("      {0}" -f ($m -split "`n" | Select-Object -First 3)) -ForegroundColor DarkRed
        }
    }
}
Write-Host ('=' * 60) -ForegroundColor DarkGray

if (-not $NoExit) {
    exit ([int]($result.FailedCount -gt 0))
}
