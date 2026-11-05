# ModuleLoad.Tests.ps1 - ShellPrompt 模块加载可靠性(故障注入)测试套件
<#
.SYNOPSIS
    ShellPrompt 模块加载链路的**故障注入**测试: 逐个注入加载失败, 断言模块
    **明确失败**而不是半初始化, 并断言失败后会话里没有残留。

.DESCRIPTION
    覆盖 9 条关键失败与恢复路径 (与本轮模块可靠性治理目标一一对应):
      1. 核心脚本不存在          -> 导入失败, 报错含缺失文件路径
      2. 核心脚本有语法错误      -> 导入失败, 报错含文件路径 + 语法错误详情
      3. 核心脚本加载期抛异常    -> 导入失败, 报错含文件路径 + 原始异常
      4. 必需依赖不存在          -> 明确导入失败, 无静默降级
      5. 必需依赖加载抛异常      -> 明确导入失败, 含依赖异常上下文
      6. 正常加载                -> 模块完整导入, 导出命令与别名完整
      7. 重复导入 / -Force 重载  -> 不产生重复事件订阅或副作用叠加
      8. Remove-Module 后再导入  -> 卸载干净, 重新导入后功能正常恢复
      9. 导入失败后的会话状态    -> 无半初始化残留(函数/别名/事件/Job/依赖)

    隔离设计 (为什么全部在子进程里跑):
      - Pester 宿主进程**已经加载了** ShellPrompt 模块, 在宿主里做"依赖缺失"
        或"导入失败无残留"的断言必然被宿主状态污染 —— 因此每个场景都在
        **独立的 pwsh 子进程**里执行, 进程内 PSModulePath 被重定向到沙箱目录。
      - 沙箱模块副本建在 `.agent_cache/module-load-tests/` 下, **绝不修改仓库里
        真实的模块文件**。仓库真实模块只在"正常加载"场景里被**只读**引用。

    断言强度:
      - 不止 `Should -Throw`: 还断言异常消息里**含目标脚本文件名 / 依赖名**与
        **具体原因**;
      - 正常导入后断言 `Get-Command -Module ShellPrompt` 的导出列表**完整且无重复**;
      - 失败导入后断言 `Get-EventSubscriber` / `Get-Job` / 全局导出函数 / 依赖模块
        **均无残留**。
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:moduleRoot = Join-Path $script:repoRoot 'ShellPrompt'
    $script:manifestPath = Join-Path $script:moduleRoot 'ShellPrompt.psd1'
    $script:sandboxRoot = Join-Path $script:repoRoot '.agent_cache/module-load-tests'

    # ---- 子进程探针脚本: 所有场景的实际执行体 ------------------------------
    # 探针负责: 隔离 PSModulePath -> 跑导入流程 -> 把结果写成 JSON。
    # 之所以写文件而不是 stdout: pwsh 的错误流与正常输出会混在 stdout 里,
    # 写文件才能拿到干净的结构化结果。
    $script:probeScriptPath = Join-Path $script:sandboxRoot 'child-probe.ps1'
    $script:probeTemplate = @'
param(
    [Parameter(Mandatory = $true)][string]$ManifestPath,
    [Parameter(Mandatory = $true)][string]$ResultPath,
    [Parameter(Mandatory = $true)][string]$SandboxHome,
    [Parameter(Mandatory = $true)][string]$Flow,
    [Parameter(Mandatory = $false)][string[]]$ModulePathRoots = @(),
    [Parameter(Mandatory = $false)][string]$RepairFrom = ''
)

$ErrorActionPreference = 'Continue'

# --- 进程隔离: PSModulePath 只保留沙箱目录 + pwsh 自带模块 ---
# 仓库真实的 Modules/ 目录**故意不加入**: 这样"必需依赖缺失"才是真的缺失,
# 而不是被宿主环境里的同名模块顶替。
$pathParts = @()
$pathParts += @($ModulePathRoots)
$pathParts += (Join-Path -Path $PSHOME -ChildPath 'Modules')
$env:PSModulePath = ($pathParts -join [IO.Path]::PathSeparator)

# --- 假 HOME: 让 Get-SshConfigHosts 能找到主机, 从而注册 SSH 参数补全器 ---
# 平台差异: Get-SshConfigHosts 里写死了 ".ssh\config"(Windows 风格),
# 在 Linux 上反斜杠不是路径分隔符, 因此**两个写法都建**一份, 各平台各取所需。
$null = New-Item -ItemType Directory -Path (Join-Path -Path $SandboxHome -ChildPath '.ssh') -Force
$sshBody = "Host testhost`n  HostName 127.0.0.1`n"
Set-Content -LiteralPath (Join-Path -Path $SandboxHome -ChildPath '.ssh/config') -Value $sshBody -Encoding UTF8
Set-Content -LiteralPath (Join-Path -Path $SandboxHome -ChildPath '.ssh\config') -Value $sshBody -Encoding UTF8
# 注意: $HOME 是只读常量, 改不了 —— 它必须由**进程启动时的环境变量**决定,
# 因此 HOME / USERPROFILE 由父进程通过 ProcessStartInfo.Environment 注入。

$report = [ordered]@{
    Flow         = $Flow
    Steps        = @()
    ErrorMessage = ''
    ErrorType    = ''
    InnerMessage = ''
}

function Write-Report {
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ResultPath -Encoding UTF8 -Force
}

function Get-SessionSnapshot {
    $module = Get-Module -Name 'ShellPrompt' -ErrorAction SilentlyContinue
    $exported = @(Get-Command -Module 'ShellPrompt' -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Name)
    $globalLeaks = @()
    foreach ($name in @('Show-UserScoopLogo', 'Start-TmuxSession', 'Copy-SshPublicKey',
            'Invoke-Reload', 'Update-Weather')) {
        $cmd = Get-Command -Name $name -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.ModuleName -ne 'ShellPrompt') { $globalLeaks += $name }
    }
    # 参数补全器数量: PowerShell 没有 Get-ArgumentCompleter, 用 TabExpansion2 反查
    $completerCount = -1
    try {
        $expansion = TabExpansion2 -inputScript 'Start-TmuxSession -HostName ' -cursorColumn 25
        $completerCount = @($expansion.CompletionMatches).Count
    } catch {
        $completerCount = -1
    }
    return [ordered]@{
        ModulePresent          = ($null -ne $module)
        ModuleCount            = @(Get-Module -Name 'ShellPrompt' -ErrorAction SilentlyContinue).Count
        ExportedCommands       = $exported
        EventSubscriberCount   = @(Get-EventSubscriber -ErrorAction SilentlyContinue).Count
        JobCount               = @(Get-Job -ErrorAction SilentlyContinue).Count
        GlobalLeaks            = $globalLeaks
        DependencyPresent      = [bool](Get-Module -Name 'PwshSpectreConsole' -ErrorAction SilentlyContinue)
        CompleterCount         = $completerCount
    }
}

function Invoke-ImportStep {
    param([string]$Name, [switch]$Force)
    $err = $null
    $ok = $true
    try {
        if ($Force) {
            Import-Module -Name $ManifestPath -Force -ErrorAction Stop -Verbose:$false
        } else {
            Import-Module -Name $ManifestPath -ErrorAction Stop -Verbose:$false
        }
    } catch {
        $ok = $false
        $err = $_
        $script:report.ErrorMessage = [string]$_.Exception.Message
        $script:report.ErrorType = [string]$_.Exception.GetType().FullName
        $script:report.InnerMessage = if ($null -ne $_.Exception.InnerException) {
            [string]$_.Exception.InnerException.Message
        } else { '' }
    }
    $report.Steps += [ordered]@{
        Name    = $Name
        Ok      = $ok
        Message = if ($null -ne $err) { [string]$err.Exception.Message } else { '' }
        State   = Get-SessionSnapshot
    }
    return $ok
}

switch ($Flow) {
    'Import' {
        $null = Invoke-ImportStep -Name 'import'
    }
    'ImportTwice' {
        $null = Invoke-ImportStep -Name 'import-1'
        $null = Invoke-ImportStep -Name 'import-2'
        $null = Invoke-ImportStep -Name 'import-force' -Force
    }
    'ImportRemoveReimport' {
        $null = Invoke-ImportStep -Name 'import-1'
        Remove-Module -Name 'ShellPrompt' -Force -ErrorAction SilentlyContinue
        $report.Steps += [ordered]@{
            Name = 'after-remove'; Ok = $true; Message = ''
            State = Get-SessionSnapshot
        }
        $null = Invoke-ImportStep -Name 'reimport'
    }
    'ImportFailRepairReimport' {
        $null = Invoke-ImportStep -Name 'import-broken'
        if (-not [string]::IsNullOrWhiteSpace($RepairFrom) -and (Test-Path -LiteralPath $RepairFrom)) {
            Copy-Item -LiteralPath $RepairFrom -Destination $ManifestPath.Replace('ShellPrompt.psd1', 'Private/Get-SshConfigHosts.ps1') -Force
        }
        $null = Invoke-ImportStep -Name 'import-repaired'
    }
    default {
        $report.ErrorMessage = "未知的 Flow: $Flow"
    }
}

Write-Report
exit 0
'@

    # ---- 辅助函数 ---------------------------------------------------------
    function script:Get-TestPwshPath {
        <#
        .SYNOPSIS
            定位 pwsh 可执行文件绝对路径(用于拉起子进程)。
        #>
        [CmdletBinding()]
        [OutputType([string])]
        param()

        $current = $null
        try { $current = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName } catch { $current = $null }
        if (-not [string]::IsNullOrWhiteSpace($current)) { return $current }
        $fromPath = Get-Command -Name 'pwsh' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($fromPath) { return [string]$fromPath.Source }
        $exeName = 'pwsh'
        if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.RuntimePlatform]::Windows)) {
            $exeName = 'pwsh.exe'
        }
        return (Join-Path -Path $PSHOME -ChildPath $exeName)
    }

    function script:New-ModuleSandbox {
        <#
        .SYNOPSIS
            在 .agent_cache/ 下构建模块副本沙箱(只复制 ShellPrompt/ 模块目录)。
        .DESCRIPTION
            刻意**不复制** Modules/ 与 data/: 依赖由子进程的 PSModulePath 提供,
            仓库真实文件全程只读, 不会被本测试改动。
        #>
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [Parameter(Mandatory = $true)][string]$Name
        )

        $sandbox = Join-Path $script:sandboxRoot $Name
        if (Test-Path -LiteralPath $sandbox) {
            Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
        $null = New-Item -ItemType Directory -Path $sandbox -Force
        Copy-Item -LiteralPath $script:moduleRoot -Destination $sandbox -Recurse -Force
        # 注意: 变量名不能叫 $home —— PowerShell 变量名大小写不敏感, $home 会撞上
        # 只读常量 $HOME, 赋值直接抛 SessionStateUnauthorizedAccessException。
        $sandboxHome = Join-Path $sandbox 'home'
        $null = New-Item -ItemType Directory -Path $sandboxHome -Force
        return $sandbox
    }

    function script:Invoke-SandboxProbe {
        <#
        .SYNOPSIS
            在独立子进程里跑一次探针, 返回解析后的结果对象。
        #>
        [CmdletBinding()]
        [OutputType([object])]
        param(
            [Parameter(Mandatory = $true)][string]$Sandbox,
            [Parameter(Mandatory = $true)][string]$Flow,
            [Parameter(Mandatory = $false)][string[]]$ModulePathRoots = @(),
            [Parameter(Mandatory = $false)][string]$RepairFrom = ''
        )

        $resultPath = Join-Path $Sandbox 'result.json'
        if (Test-Path -LiteralPath $resultPath) { Remove-Item -LiteralPath $resultPath -Force }

        # 注意: 变量名不能叫 $args —— $args 是 PowerShell 自动变量
        # (PSAvoidAssignmentToAutomaticVariable), 赋值会引入副作用。
        $probeArgs = @(
            '-NoProfile', '-NonInteractive', '-NoLogo',
            '-File', $script:probeScriptPath,
            '-ManifestPath', (Join-Path $Sandbox 'ShellPrompt/ShellPrompt.psd1'),
            '-ResultPath', $resultPath,
            '-SandboxHome', (Join-Path $Sandbox 'home'),
            '-Flow', $Flow
        )
        if ($ModulePathRoots.Count -gt 0) {
            $probeArgs += @('-ModulePathRoots') + $ModulePathRoots
        }
        if (-not [string]::IsNullOrWhiteSpace($RepairFrom)) {
            $probeArgs += @('-RepairFrom', $RepairFrom)
        }

        $pwsh = script:Get-TestPwshPath

        # 用 ProcessStartInfo 起子进程: HOME / USERPROFILE 必须在**进程启动前**
        # 通过环境变量注入 —— $HOME 是只读常量, 运行期改不了。
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $pwsh
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        foreach ($argument in $probeArgs) { [void]$startInfo.ArgumentList.Add($argument) }
        $sandboxHome = Join-Path $Sandbox 'home'
        $startInfo.Environment['HOME'] = $sandboxHome
        $startInfo.Environment['USERPROFILE'] = $sandboxHome
        $startInfo.Environment['XDG_CONFIG_HOME'] = (Join-Path -Path $sandboxHome -ChildPath '.config')

        $child = [System.Diagnostics.Process]::new()
        $child.StartInfo = $startInfo
        [void]$child.Start()
        $stdoutTask = $child.StandardOutput.ReadToEndAsync()
        $stderrTask = $child.StandardError.ReadToEndAsync()
        $child.WaitForExit()
        $null = $stdoutTask.GetAwaiter().GetResult()
        $childStderr = $stderrTask.GetAwaiter().GetResult()

        if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
            throw ("子进程探针没有产出结果文件 (Sandbox={0} Flow={1} ExitCode={2})`n{3}" -f
                $Sandbox, $Flow, $child.ExitCode, $childStderr)
        }
        $raw = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8
        return ($raw | ConvertFrom-Json)
    }

    function script:New-RepoSandbox {
        <#
        .SYNOPSIS
            构建一份"仓库副本"沙箱: profile + 模块 + data + 测试脚本。
        .DESCRIPTION
            用于让 Profile 冒烟检查跑在**被破坏过的**仓库副本上, 从而验证
            "冒烟检查能识别并拦截模块加载失败"这条能力本身。
            Modules/ 只复制 PwshSpectreConsole (硬依赖); Terminal.Gui 不需要 ——
            它在交互式 UI 真正被调用时才惰性加载, 不参与启动链路。
        #>
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [Parameter(Mandatory = $true)][string]$Name
        )

        $sandbox = Join-Path $script:sandboxRoot $Name
        if (Test-Path -LiteralPath $sandbox) {
            Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
        $null = New-Item -ItemType Directory -Path $sandbox -Force
        Copy-Item -LiteralPath $script:moduleRoot -Destination $sandbox -Recurse -Force
        Copy-Item -LiteralPath (Join-Path $script:repoRoot 'data') -Destination $sandbox -Recurse -Force
        Copy-Item -LiteralPath (Join-Path $script:repoRoot 'Microsoft.PowerShell_profile.ps1') -Destination $sandbox -Force
        # 硬依赖随副本一起带走, 让"健康对照组"与真实仓库等价
        $null = New-Item -ItemType Directory -Path (Join-Path $sandbox 'Modules') -Force
        Copy-Item -LiteralPath (Join-Path $script:repoRoot 'Modules/PwshSpectreConsole') `
            -Destination (Join-Path $sandbox 'Modules') -Recurse -Force
        return $sandbox
    }

    function script:Invoke-RepoSmoke {
        <#
        .SYNOPSIS
            在子进程里跑仓库副本的 Profile 冒烟检查, 返回退出码与合并输出。
        #>
        [CmdletBinding()]
        [OutputType([object])]
        param(
            [Parameter(Mandatory = $true)][string]$Sandbox
        )

        $smokeScript = Join-Path $Sandbox 'ShellPrompt/Tests/Invoke-ProfileSmoke.ps1'
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = (script:Get-TestPwshPath)
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        foreach ($argument in @('-NoProfile', '-NoLogo', '-File', $smokeScript)) {
            [void]$startInfo.ArgumentList.Add($argument)
        }
        $child = [System.Diagnostics.Process]::new()
        $child.StartInfo = $startInfo
        [void]$child.Start()
        $stdoutTask = $child.StandardOutput.ReadToEndAsync()
        $stderrTask = $child.StandardError.ReadToEndAsync()
        $child.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        return [pscustomobject]@{
            ExitCode = $child.ExitCode
            Output   = ($stdout + "`n" + $stderr)
        }
    }

    # ---- 前置准备 ---------------------------------------------------------
    $null = New-Item -ItemType Directory -Path $script:sandboxRoot -Force
    Set-Content -LiteralPath $script:probeScriptPath -Value $script:probeTemplate -Encoding UTF8 -Force

    # 沙箱用的依赖根: 指向**仓库真实**的 Modules/ 目录(只读引用)。
    # 子进程把它放进 PSModulePath, 于是沙箱模块能解析到 PwshSpectreConsole。
    $script:realModulesRoot = Join-Path $script:repoRoot 'Modules'
    # "依赖缺失"场景用的空模块根
    $script:emptyModulesRoot = Join-Path $script:sandboxRoot 'empty-modules'
    $null = New-Item -ItemType Directory -Path $script:emptyModulesRoot -Force
}

AfterAll {
    if ($null -ne $script:sandboxRoot -and (Test-Path -LiteralPath $script:sandboxRoot)) {
        Remove-Item -LiteralPath $script:sandboxRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Describe '核心脚本清单一致性 (防漂移)' {

    It 'CoreScripts.psd1 必须存在且可解析' {
        $inventoryPath = Join-Path $script:moduleRoot 'CoreScripts.psd1'
        Test-Path -LiteralPath $inventoryPath -PathType Leaf | Should -BeTrue
        { Import-PowerShellDataFile -LiteralPath $inventoryPath } | Should -Not -Throw
    }

    It '清单登记的脚本与 Private/Public 目录必须完全一致(不多不少)' {
        $inventory = Import-PowerShellDataFile -LiteralPath (Join-Path $script:moduleRoot 'CoreScripts.psd1')
        $declaredPrivate = @($inventory.Private) | Sort-Object
        $declaredPublic = @($inventory.Public) | Sort-Object

        $actualPrivate = @(Get-ChildItem -LiteralPath (Join-Path $script:moduleRoot 'Private') -Filter '*.ps1' -File |
            Select-Object -ExpandProperty Name) | Sort-Object
        $actualPublic = @(Get-ChildItem -LiteralPath (Join-Path $script:moduleRoot 'Public') -Filter '*.ps1' -File |
            Select-Object -ExpandProperty Name) | Sort-Object

        ($declaredPrivate -join ',') | Should -Be ($actualPrivate -join ',')
        ($declaredPublic -join ',') | Should -Be ($actualPublic -join ',')
    }

    It '清单里的每一个脚本都必须在磁盘上存在' {
        $inventory = Import-PowerShellDataFile -LiteralPath (Join-Path $script:moduleRoot 'CoreScripts.psd1')
        foreach ($name in @($inventory.Private)) {
            Test-Path -LiteralPath (Join-Path $script:moduleRoot "Private/$name") -PathType Leaf | Should -BeTrue -Because "清单登记的 $name 必须存在"
        }
        foreach ($name in @($inventory.Public)) {
            Test-Path -LiteralPath (Join-Path $script:moduleRoot "Public/$name") -PathType Leaf | Should -BeTrue -Because "清单登记的 $name 必须存在"
        }
    }
}

Describe '模块加载故障注入 (沙箱隔离 + 子进程)' {

    It '场景 1: 核心脚本不存在 -> 导入失败, 报错含缺失文件路径' {
        $sandbox = script:New-ModuleSandbox -Name 'missing-core'
        $victim = Join-Path $sandbox 'ShellPrompt/Private/Get-SshConfigHosts.ps1'
        Remove-Item -LiteralPath $victim -Force

        $result = script:Invoke-SandboxProbe -Sandbox $sandbox -Flow 'Import' -ModulePathRoots @($script:realModulesRoot)

        $step = $result.Steps | Where-Object { $_.Name -eq 'import' }
        $step.Ok | Should -BeFalse
        $step.Message | Should -Match ([regex]::Escape('Get-SshConfigHosts.ps1'))
        $step.Message | Should -Match '核心脚本缺失'
        $result.Steps[0].State.ModulePresent | Should -BeFalse
    }

    It '场景 2: 核心脚本有语法错误 -> 导入失败, 报错含文件路径与语法错误详情' {
        $sandbox = script:New-ModuleSandbox -Name 'syntax-error'
        $victim = Join-Path $sandbox 'ShellPrompt/Private/Get-SshConfigHosts.ps1'
        Set-Content -LiteralPath $victim -Value 'function Broken { if ( }' -Encoding UTF8

        $result = script:Invoke-SandboxProbe -Sandbox $sandbox -Flow 'Import' -ModulePathRoots @($script:realModulesRoot)

        $step = $result.Steps | Where-Object { $_.Name -eq 'import' }
        $step.Ok | Should -BeFalse
        $step.Message | Should -Match ([regex]::Escape('Get-SshConfigHosts.ps1'))
        $step.Message | Should -Match 'ParseException'
        # 语法错误详情必须能被看到(而不是只剩一个"加载失败")
        $step.Message | Should -Match 'Missing condition in if statement'
        $result.Steps[0].State.ModulePresent | Should -BeFalse
    }

    It '场景 3: 核心脚本加载期抛出运行时异常 -> 导入失败, 报错含文件路径与原始异常' {
        $sandbox = script:New-ModuleSandbox -Name 'loadtime-throw'
        $victim = Join-Path $sandbox 'ShellPrompt/Private/Get-SshConfigHosts.ps1'
        Set-Content -LiteralPath $victim -Value 'throw "BOOM-LOADTIME-CORE"' -Encoding UTF8

        $result = script:Invoke-SandboxProbe -Sandbox $sandbox -Flow 'Import' -ModulePathRoots @($script:realModulesRoot)

        $step = $result.Steps | Where-Object { $_.Name -eq 'import' }
        $step.Ok | Should -BeFalse
        $step.Message | Should -Match ([regex]::Escape('Get-SshConfigHosts.ps1'))
        $step.Message | Should -Match 'BOOM-LOADTIME-CORE'
        $result.Steps[0].State.ModulePresent | Should -BeFalse
    }

    It '场景 4: 必需依赖 PwshSpectreConsole 不存在 -> 明确导入失败, 无静默降级' {
        $sandbox = script:New-ModuleSandbox -Name 'missing-dependency'
        # PSModulePath 里**不放**仓库的 Modules/, 因此依赖真的缺失
        $result = script:Invoke-SandboxProbe -Sandbox $sandbox -Flow 'Import' -ModulePathRoots @($script:emptyModulesRoot)

        $step = $result.Steps | Where-Object { $_.Name -eq 'import' }
        $step.Ok | Should -BeFalse
        $step.Message | Should -Match 'PwshSpectreConsole'
        $step.Message | Should -Match '模块导入失败'
        $result.Steps[0].State.ModulePresent | Should -BeFalse
        $result.Steps[0].State.DependencyPresent | Should -BeFalse
    }

    It '场景 5: 必需依赖加载时抛出异常 -> 明确导入失败, 含依赖异常上下文' {
        $sandbox = script:New-ModuleSandbox -Name 'dependency-throws'
        # 造一个"加载即抛异常"的依赖模块, 放在沙箱的 Modules/ 下。
        # ShellPrompt.psm1 会把 <沙箱根>/Modules 注入 PSModulePath, 因此它优先生效。
        $depRoot = Join-Path $sandbox 'Modules/PwshSpectreConsole/9.9.9'
        $null = New-Item -ItemType Directory -Path $depRoot -Force
        Set-Content -LiteralPath (Join-Path $depRoot 'PwshSpectreConsole.psm1') `
            -Value 'throw "BOOM-DEPENDENCY-LOAD"' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $depRoot 'PwshSpectreConsole.psd1') -Value @"
@{
    RootModule        = 'PwshSpectreConsole.psm1'
    ModuleVersion     = '9.9.9'
    GUID              = 'deadbeef-0000-0000-0000-000000000001'
    Author            = 'test'
    Description       = 'fault injection stub'
    FunctionsToExport = @()
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
"@ -Encoding UTF8

        $result = script:Invoke-SandboxProbe -Sandbox $sandbox -Flow 'Import' -ModulePathRoots @($script:emptyModulesRoot)

        $step = $result.Steps | Where-Object { $_.Name -eq 'import' }
        $step.Ok | Should -BeFalse
        $step.Message | Should -Match 'PwshSpectreConsole'
        $step.Message | Should -Match 'BOOM-DEPENDENCY-LOAD'
        $result.Steps[0].State.ModulePresent | Should -BeFalse
    }

    It '场景 6: 正常加载 -> 模块完整导入, 导出命令与别名完整' {
        $sandbox = script:New-ModuleSandbox -Name 'healthy'
        $result = script:Invoke-SandboxProbe -Sandbox $sandbox -Flow 'Import' -ModulePathRoots @($script:realModulesRoot)

        $step = $result.Steps | Where-Object { $_.Name -eq 'import' }
        $step.Ok | Should -BeTrue -Because "正常导入不应失败: $($step.Message)"
        $state = $step.State
        $state.ModulePresent | Should -BeTrue
        $state.ExportedCommands.Count | Should -Be 5
        foreach ($name in @('Show-UserScoopLogo', 'Start-TmuxSession', 'Copy-SshPublicKey',
                'Invoke-Reload', 'Update-Weather')) {
            $state.ExportedCommands | Should -Contain $name
        }
        # 不应导出 Private 内部函数
        $state.ExportedCommands | Should -Not -Contain 'Get-CachedConfig'
        $state.ExportedCommands | Should -Not -Contain 'Get-SshConfigHosts'
        $state.EventSubscriberCount | Should -Be 0
        $state.JobCount | Should -Be 0
    }

    It '场景 7: 重复导入 / -Force 重新导入 -> 不产生重复事件订阅或副作用叠加' {
        $sandbox = script:New-ModuleSandbox -Name 'repeat-import'
        $result = script:Invoke-SandboxProbe -Sandbox $sandbox -Flow 'ImportTwice' -ModulePathRoots @($script:realModulesRoot)

        $steps = @($result.Steps | Where-Object { $_.Name -like 'import*' })
        $steps.Count | Should -Be 3
        foreach ($s in $steps) {
            $s.Ok | Should -BeTrue -Because "$($s.Name) 不应失败: $($s.Message)"
            $s.State.ExportedCommands.Count | Should -Be 5
            $s.State.ModuleCount | Should -Be 1
            $s.State.EventSubscriberCount | Should -Be 0
            $s.State.JobCount | Should -Be 0
        }
        # 参数补全器不得叠加注册(每次导入后都应恰好 1 个)
        $last = $steps[-1]
        if ($last.State.CompleterCount -ge 0) {
            $last.State.CompleterCount | Should -Be 1
        }
    }

    It '场景 8: Remove-Module 后重新导入 -> 卸载干净, 重新导入后功能正常恢复' {
        $sandbox = script:New-ModuleSandbox -Name 'remove-reimport'
        $result = script:Invoke-SandboxProbe -Sandbox $sandbox -Flow 'ImportRemoveReimport' -ModulePathRoots @($script:realModulesRoot)

        $import1 = $result.Steps | Where-Object { $_.Name -eq 'import-1' }
        $afterRemove = $result.Steps | Where-Object { $_.Name -eq 'after-remove' }
        $reimport = $result.Steps | Where-Object { $_.Name -eq 'reimport' }

        $import1.Ok | Should -BeTrue
        $reimport.Ok | Should -BeTrue -Because "卸载后重新导入不应失败: $($reimport.Message)"

        # 卸载必须干净: 模块不在了, 导出命令也不在
        $afterRemove.State.ModulePresent | Should -BeFalse
        $afterRemove.State.ExportedCommands.Count | Should -Be 0
        $afterRemove.State.EventSubscriberCount | Should -Be 0
        $afterRemove.State.JobCount | Should -Be 0
        if ($afterRemove.State.CompleterCount -ge 0) {
            $afterRemove.State.CompleterCount | Should -Be 0
        }

        # 重新导入后功能完整恢复
        $reimport.State.ModulePresent | Should -BeTrue
        $reimport.State.ExportedCommands.Count | Should -Be 5
    }

    It '场景 9: 导入失败后同一会话重新导入 -> 修复文件后恢复正常' {
        $sandbox = script:New-ModuleSandbox -Name 'repair-after-failure'
        $victim = Join-Path $sandbox 'ShellPrompt/Private/Get-SshConfigHosts.ps1'
        $pristine = Join-Path $sandbox 'Get-SshConfigHosts.pristine.ps1'
        Copy-Item -LiteralPath $victim -Destination $pristine -Force
        Set-Content -LiteralPath $victim -Value 'throw "BOOM-BEFORE-REPAIR"' -Encoding UTF8

        $result = script:Invoke-SandboxProbe -Sandbox $sandbox -Flow 'ImportFailRepairReimport' `
            -ModulePathRoots @($script:realModulesRoot) -RepairFrom $pristine

        $broken = $result.Steps | Where-Object { $_.Name -eq 'import-broken' }
        $repaired = $result.Steps | Where-Object { $_.Name -eq 'import-repaired' }

        $broken.Ok | Should -BeFalse
        $broken.Message | Should -Match 'BOOM-BEFORE-REPAIR'
        $repaired.Ok | Should -BeTrue -Because "修复后重新导入必须恢复: $($repaired.Message)"
        $repaired.State.ModulePresent | Should -BeTrue
        $repaired.State.ExportedCommands.Count | Should -Be 5
    }
}

Describe 'Profile 冒烟检查能识别并拦截模块加载失败' {

    It '核心脚本缺失时: 冒烟检查必须失败并报出缺失文件' {
        # 目的: 验证"冒烟检查能识别模块加载失败"这条能力本身 ——
        # 只在健康仓库上跑冒烟, 永远证明不了它能拦住失败。
        $sandbox = script:New-RepoSandbox -Name 'smoke-missing-core'
        Remove-Item -LiteralPath (Join-Path $sandbox 'ShellPrompt/Private/Get-SshConfigHosts.ps1') -Force

        $smoke = script:Invoke-RepoSmoke -Sandbox $sandbox

        $smoke.ExitCode | Should -Not -Be 0
        $smoke.Output | Should -Match 'Get-SshConfigHosts\.ps1'
        $smoke.Output | Should -Match '模块导入失败'
    }

    It '阶段 1 核心脚本损坏时: 冒烟检查必须失败并中止公开命令注册' {
        $sandbox = script:New-RepoSandbox -Name 'smoke-broken-stage1'
        # Initialize-Config.ps1 同时在阶段 1 清单与模块核心脚本清单里:
        # 破坏它 => 阶段 1 失败 => profile 必须中止注册 sss / ssh-copy-id
        Set-Content -LiteralPath (Join-Path $sandbox 'ShellPrompt/Private/Initialize-Config.ps1') `
            -Value 'throw "BOOM-STAGE1"' -Encoding UTF8

        $smoke = script:Invoke-RepoSmoke -Sandbox $sandbox

        $smoke.ExitCode | Should -Not -Be 0
        $smoke.Output | Should -Match 'BOOM-STAGE1'
        $smoke.Output | Should -Match 'Initialize-Config'
    }

    It '健康的仓库副本: 冒烟检查必须通过 (对照用例)' {
        $sandbox = script:New-RepoSandbox -Name 'smoke-healthy'
        $smoke = script:Invoke-RepoSmoke -Sandbox $sandbox

        $smoke.ExitCode | Should -Be 0
        $smoke.Output | Should -Match '结果: 全部通过'
    }
}

Describe 'Profile 在非交互宿主下不污染管道输出' {

    It '标准输出被重定向时: profile 不得打印欢迎语 banner' {
        # banner 走 Write-Host, 在被重定向的 stdout 里会污染调用方的管道结果。
        # 子进程用 ProcessStartInfo 重定向 stdout => IsOutputRedirected = $true,
        # 因此这条路径必须**看不到** banner。
        $sandbox = script:New-RepoSandbox -Name 'non-interactive'
        $wrapperDir = Join-Path $sandbox 'home/.config/powershell'
        $null = New-Item -ItemType Directory -Path $wrapperDir -Force
        $profileLiteral = (Join-Path $sandbox 'Microsoft.PowerShell_profile.ps1').Replace("'", "''")
        Set-Content -LiteralPath (Join-Path $wrapperDir 'Microsoft.PowerShell_profile.ps1') `
            -Value ". '$profileLiteral'" -Encoding UTF8

        $marker = Join-Path $sandbox 'marker.ps1'
        Set-Content -LiteralPath $marker -Value "Write-Output 'PIPELINE-MARKER'" -Encoding UTF8

        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = (script:Get-TestPwshPath)
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        # 注意: 这里**不能**加 -NoProfile —— 本用例要的就是"profile 在重定向的
        # stdout 下启动"这条真实链路。加了 -NoProfile 的话 profile 根本不加载,
        # 断言会变成永真, 测不到任何东西。
        foreach ($argument in @('-NoLogo', '-File', $marker)) {
            [void]$startInfo.ArgumentList.Add($argument)
        }
        $startInfo.Environment['HOME'] = (Join-Path $sandbox 'home')
        $startInfo.Environment['USERPROFILE'] = (Join-Path $sandbox 'home')
        $startInfo.Environment['XDG_CONFIG_HOME'] = (Join-Path $sandbox 'home/.config')

        $child = [System.Diagnostics.Process]::new()
        $child.StartInfo = $startInfo
        [void]$child.Start()
        $stdout = $child.StandardOutput.ReadToEndAsync().GetAwaiter().GetResult()
        $null = $child.StandardError.ReadToEndAsync().GetAwaiter().GetResult()
        $child.WaitForExit()

        # 业务输出必须在, 且 banner 必须不在
        $stdout | Should -Match 'PIPELINE-MARKER'
        $stdout | Should -Not -Match 'SHELL PROMPT'
    }
}

Describe '导入失败后的会话状态 (无半初始化残留)' {

    It 'Private 核心脚本加载失败后: 无残留导出函数 / 别名 / 事件订阅 / Job / 依赖模块' {
        $sandbox = script:New-ModuleSandbox -Name 'residue-check'
        $victim = Join-Path $sandbox 'ShellPrompt/Private/Get-SshConfigHosts.ps1'
        Set-Content -LiteralPath $victim -Value 'throw "BOOM-RESIDUE"' -Encoding UTF8

        $result = script:Invoke-SandboxProbe -Sandbox $sandbox -Flow 'Import' -ModulePathRoots @($script:realModulesRoot)

        $step = $result.Steps | Where-Object { $_.Name -eq 'import' }
        $step.Ok | Should -BeFalse
        $state = $step.State

        $state.ModulePresent | Should -BeFalse
        $state.ExportedCommands.Count | Should -Be 0
        $state.GlobalLeaks.Count | Should -Be 0
        $state.EventSubscriberCount | Should -Be 0
        $state.JobCount | Should -Be 0
        $state.DependencyPresent | Should -BeFalse
    }

    It 'Public 核心脚本加载失败后: 导入必须失败, 且导出面不得残缺' {
        # 这条专门盯"Public 脚本加载失败被吞掉、模块带着残缺导出面导入成功"的老毛病:
        # 旧实现里 Public 段是 Write-Warning 后继续, 结果模块导入成功但少一个
        # 公开命令 —— 对用户而言就是"命令时有时无"的假可用状态。
        $sandbox = script:New-ModuleSandbox -Name 'residue-public'
        $victim = Join-Path $sandbox 'ShellPrompt/Public/Start-TmuxSession.ps1'
        Set-Content -LiteralPath $victim -Value 'throw "BOOM-RESIDUE-PUBLIC"' -Encoding UTF8

        $result = script:Invoke-SandboxProbe -Sandbox $sandbox -Flow 'Import' -ModulePathRoots @($script:realModulesRoot)

        $step = $result.Steps | Where-Object { $_.Name -eq 'import' }
        $step.Ok | Should -BeFalse
        $step.Message | Should -Match ([regex]::Escape('Start-TmuxSession.ps1'))
        $step.Message | Should -Match 'BOOM-RESIDUE-PUBLIC'

        $state = $step.State
        $state.ModulePresent | Should -BeFalse
        $state.ExportedCommands.Count | Should -Be 0
        $state.GlobalLeaks.Count | Should -Be 0
        $state.EventSubscriberCount | Should -Be 0
        $state.JobCount | Should -Be 0
    }

    It '核心脚本缺失后: 导入必须失败, 且不得留下半初始化的导出面' {
        $sandbox = script:New-ModuleSandbox -Name 'residue-missing'
        Remove-Item -LiteralPath (Join-Path $sandbox 'ShellPrompt/Public/Start-TmuxSession.ps1') -Force

        $result = script:Invoke-SandboxProbe -Sandbox $sandbox -Flow 'Import' -ModulePathRoots @($script:realModulesRoot)

        $step = $result.Steps | Where-Object { $_.Name -eq 'import' }
        $step.Ok | Should -BeFalse
        $step.Message | Should -Match ([regex]::Escape('Start-TmuxSession.ps1'))

        $state = $step.State
        $state.ModulePresent | Should -BeFalse
        $state.ExportedCommands.Count | Should -Be 0
        $state.GlobalLeaks.Count | Should -Be 0
        $state.EventSubscriberCount | Should -Be 0
        $state.JobCount | Should -Be 0
    }
}
