# Invoke-Tests.ps1 - 固定测试入口
#
# 为什么需要这个入口:
#   本仓库测试套件已迁移到 Pester **v5+/v6 语法** (`Should -Be` / `Should -Invoke`),
#   与机器上常驻的 Pester 6.x 兼容。历史版本曾强制锁定 Pester 3.4.0 绝对路径,
#   导致新语法测试文件无法运行, 现已移除该锁定。
#   保留本入口的原因: 统一运行时版本守卫、统一输出汇总、支持以退出码反映结果 (CI 场景)。
#
# 质量门禁 (CI 质量下限):
#   只判"有没有 Fail"不够 —— 测试被整份删除或被大面积掏空之后, 套件照样全绿。
#   因此本入口额外把**测试规模**纳入门禁:
#     -MinPassed    : 通过用例数下限; 低于门槛 => 非零退出。
#     -MinTestFiles : 测试文件数下限 (Tests 目录下 *.Tests.ps1); 低于门槛 => 非零退出。
#   两个门槛默认 0 = 不启用, 由 CI 显式传参 —— CI workflow 里写的数字是**受审基线**,
#   改动会在 diff 里暴露。降低门槛等同于降低质量标准, 必须在 PR 里说明理由;
#   门槛参数只影响规模判定, 永远**不能**用来掩盖真实失败 (Fail 独立判定, 恒为非零退出)。
#
# 用法 (pwsh 7.6+):
#   pwsh -NoProfile -File ./ShellPrompt/Tests/Invoke-Tests.ps1
#   pwsh -NoProfile -File ./ShellPrompt/Tests/Invoke-Tests.ps1 -Path 'ShellPrompt/Tests/Get-WttrWeather.Tests.ps1'
#   pwsh -NoProfile -File ./ShellPrompt/Tests/Invoke-Tests.ps1 -NoExit   (交互会话内调用时关闭 exit)
#   pwsh -NoProfile -File ./ShellPrompt/Tests/Invoke-Tests.ps1 -MinPassed 300 -MinTestFiles 15
#
# 退出码:
#   0 = 全部通过 (无 Fail, 且达到门槛)
#   1 = 存在测试失败 (FailedCount > 0) —— 永远阻断, 不受门槛参数影响
#   2 = 门槛未达标 (通过用例数 < -MinPassed, 或测试文件数 < -MinTestFiles)

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
    [switch]$NoExit,

    # 通过用例数下限 (质量门禁)。0 = 不启用。
    # 实际 PassedCount 低于门槛 => 退出码 2 (非零), CI 阻断。
    # CI 在 workflow 里显式传值; 该数字是受审基线, 降低它 = 降低质量标准。
    [Parameter(Mandatory = $false)]
    [int]$MinPassed = 0,

    # 测试文件数下限 (质量门禁)。0 = 不启用。
    # 统计 Tests 目录下 *.Tests.ps1 的**现存数量**, 因此整份测试文件被删除时
    # 也会掉到门槛以下 => 退出码 2 (非零), CI 阻断。
    [Parameter(Mandatory = $false)]
    [int]$MinTestFiles = 0
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
# 全量清单始终现算: 即使本次只跑 -Path 指定的子集, 也要知道仓库里现在还剩多少
# 测试文件 —— "整份测试文件被删除"必须能被 -MinTestFiles 门禁发现。
$allTestFiles = @(Get-ChildItem -Path $PSScriptRoot -Filter '*.Tests.ps1' -File | Select-Object -ExpandProperty FullName)
if (-not $Path) {
    $Path = $allTestFiles
}
Write-Host "待运行测试文件: $($Path.Count) 个 (Tests 目录现存 $($allTestFiles.Count) 个)" -ForegroundColor DarkGray

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

# ---- 6. 质量门禁判定 ----
# 规模判定与失败判定**相互独立**:
#   - 存在 Fail            => 退出码 1 (永远阻断, 门槛参数不能掩盖)
#   - 规模低于门槛         => 退出码 2 (阻断)
# 门槛只做"下限"检查, 不做上限检查 —— 新增测试只会让结果更宽松, 不会导致 CI 失败。
$gateFailures = [System.Collections.Generic.List[string]]::new()

if ($MinPassed -gt 0 -and $result.PassedCount -lt $MinPassed) {
    $gateFailures.Add(("通过用例数 {0} 低于门槛 {1}" -f $result.PassedCount, $MinPassed))
}
if ($MinTestFiles -gt 0 -and $allTestFiles.Count -lt $MinTestFiles) {
    $gateFailures.Add(("测试文件数 {0} 低于门槛 {1}" -f $allTestFiles.Count, $MinTestFiles))
}

Write-Host ("[门禁] 测试文件数: {0} / 门槛 {1}" -f $allTestFiles.Count, $(if ($MinTestFiles -gt 0) { $MinTestFiles } else { '未启用' })) `
    -ForegroundColor $(if ($MinTestFiles -gt 0 -and $allTestFiles.Count -lt $MinTestFiles) { 'Red' } else { 'DarkGray' })
Write-Host ("[门禁] 通过用例数: {0} / 门槛 {1}" -f $result.PassedCount, $(if ($MinPassed -gt 0) { $MinPassed } else { '未启用' })) `
    -ForegroundColor $(if ($MinPassed -gt 0 -and $result.PassedCount -lt $MinPassed) { 'Red' } else { 'DarkGray' })

if ($gateFailures.Count -gt 0) {
    Write-Host '门禁未达标:' -ForegroundColor Red
    foreach ($g in $gateFailures) {
        Write-Host ("  - {0}" -f $g) -ForegroundColor Red
    }
}

if (-not $NoExit) {
    # 优先级: 测试失败 (1) > 门禁未达标 (2) > 通过 (0)
    if ($result.FailedCount -gt 0) { exit 1 }
    if ($gateFailures.Count -gt 0) { exit 2 }
    exit 0
}
