#Requires -Version 7.0
<#
.SYNOPSIS
    Profile 启动冒烟检查: 在干净的子 pwsh 进程里加载仓库根的 Microsoft.PowerShell_profile.ps1。

.DESCRIPTION
    本脚本回答一个问题: "用户双击 pwsh 之后, profile 到底能不能正常起来?"
    它不复用父进程的任何状态, 而是**另起一个子 pwsh 进程**, 让那个子进程走
    **真实的 profile 加载链路**, 再把观察到的结果结构化回传给父进程判定。

    为什么必须另起进程:
      - 父进程(跑本脚本的 pwsh)通常带 -NoProfile 启动, 自身没有 profile 状态;
      - profile 里那些 $script: 变量、Stamp 计时戳、模块懒加载都是**进程级**状态,
        在同一个进程里 dot-source 无法还原真实启动语义;
      - 只有独立进程 + 独立 HOME 才能保证"干净环境"这个前提成立。

    子进程怎么走真实加载链路:
      - 在**临时 HOME** 下创建包装 profile, 路径取子进程自己的
        $PROFILE.CurrentUserAllHosts 与 $PROFILE.CurrentUserCurrentHost
        (Windows: %USERPROFILE%\Documents\PowerShell\profile.ps1 与
        ...\Documents\PowerShell\Microsoft.PowerShell_profile.ps1;
        Linux: $HOME/.config/powershell/ 下同名文件);
      - 包装 profile 只做一件事: dot-source 仓库根的 Microsoft.PowerShell_profile.ps1。
        dot-source 的是仓库里那个文件, 所以 profile 内部的
        $script:ActualRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
        仍然指向**仓库根**, ShellPrompt/ 子目录照常定位得到;
      - 子进程用 `pwsh -NoLogo -File <检查脚本>` 启动(**不加 -NoProfile**),
        profile 由 pwsh 自动加载, 加载完成后再跑检查脚本 —— 与真实启动顺序一致;
      - 临时 HOME 用完即删, 不污染真实用户的 profile 目录。

    检查项(任一失败即返回非零退出码):
      1. profile 加载 / 启动期自检通过(缺失命令、缺失文件均为空)          -> 退出码 1
      2. 加载过程中没有 [ShellPrompt] 前缀的警告/错误                    -> 退出码 2
      3. $global:_MARKS 存在且非空(需要 SHELLPROMPT_PROFILE_TRACE=1)     -> 退出码 3
      4. Ensure-ShellPrompt 之后 ShellPrompt 模块导入成功                -> 退出码 4

    退出码:
      0 = 全部通过; 1 = profile 加载/自检失败; 2 = [ShellPrompt] 警告;
      3 = _MARKS 缺失或为空; 4 = 模块导入失败。

    用法 (pwsh 7.6+):
      pwsh -NoProfile -File ./ShellPrompt/Tests/Invoke-ProfileSmoke.ps1
      pwsh -NoProfile -File ./ShellPrompt/Tests/Invoke-ProfileSmoke.ps1 -ProfilePath D:\repo\Microsoft.PowerShell_profile.ps1
      pwsh -NoProfile -File ./ShellPrompt/Tests/Invoke-ProfileSmoke.ps1 -KeepTemp   # 保留临时目录便于排查
#>
[CmdletBinding()]
param(
    # 被测 profile 路径; 默认取仓库根的 Microsoft.PowerShell_profile.ps1
    [string] $ProfilePath,

    # 保留临时工作目录(临时 HOME / 包装 profile / 日志), 便于排查
    [switch] $KeepTemp
)

$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------------
# 退出码表
# ---------------------------------------------------------------------------
$codeOk = 0
$codeProfile = 1
$codeWarning = 2
$codeMarks = 3
$codeModule = 4

# ---------------------------------------------------------------------------
# 辅助函数
# ---------------------------------------------------------------------------

function Get-SmokePwshPath {
    <#
    .SYNOPSIS
        定位 pwsh 可执行文件的绝对路径(用于拉起子进程)。
    .DESCRIPTION
        定位顺序:
          1. 当前进程自身的 MainModule.FileName —— 绝对路径, 不依赖 PATH,
             且保证子进程与父进程是同一份 pwsh(版本一致、globalization 开关一致);
          2. 当前进程的 Process.Path;
          3. PATH 里的 pwsh;
          4. $PSHOME 下的 pwsh[.exe]。
        本机验证环境里 pwsh 不在 PATH(只有 .agent_cache/pwsh760/pwsh),
        所以第 1 条是主力路径。
    .OUTPUTS
        [string] pwsh 可执行文件路径
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $current = $null
    try {
        $current = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    } catch {
        $current = $null
    }
    if ([string]::IsNullOrWhiteSpace($current)) {
        try {
            $current = (Get-Process -Id $PID -ErrorAction Stop).Path
        } catch {
            $current = $null
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($current)) { return $current }

    $fromPath = Get-Command -Name 'pwsh' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($fromPath) { return [string]$fromPath.Source }

    $exeName = 'pwsh'
    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
        $exeName = 'pwsh.exe'
    }
    return (Join-Path -Path $PSHOME -ChildPath $exeName)
}

function Invoke-SmokeChild {
    <#
    .SYNOPSIS
        以受控的环境变量拉起一个子进程, 捕获 stdout / stderr / 退出码。
    .DESCRIPTION
        用 ProcessStartInfo 直接起进程(不走 shell), 因此:
          - 参数用 ArgumentList 传, 不受引号/转义影响;
          - Environment 可以**只覆盖**需要的变量, 其余从父进程继承
            (例如容器里必需的 DOTNET_SYSTEM_GLOBALIZATION_INVARIANT);
          - WorkingDirectory 指定工作目录, 等价于 `pwsh -WorkingDirectory`。
        stdout / stderr 各自异步读取, 避免管道写满造成死锁。
    .OUTPUTS
        [pscustomobject] @{ ExitCode = int; StdOut = string; StdErr = string }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $FilePath,

        [Parameter(Mandatory = $true)]
        [string[]] $ArgumentList,

        [Parameter(Mandatory = $false)]
        [hashtable] $Environment,

        [Parameter(Mandatory = $false)]
        [string] $WorkingDirectory
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $startInfo.WorkingDirectory = $WorkingDirectory
    }
    foreach ($argument in $ArgumentList) {
        [void]$startInfo.ArgumentList.Add($argument)
    }
    if ($Environment) {
        foreach ($name in $Environment.Keys) {
            $startInfo.Environment[[string]$name] = [string]$Environment[$name]
        }
    }

    $child = [System.Diagnostics.Process]::new()
    $child.StartInfo = $startInfo
    [void]$child.Start()
    $stdoutTask = $child.StandardOutput.ReadToEndAsync()
    $stderrTask = $child.StandardError.ReadToEndAsync()
    $child.WaitForExit()

    return [pscustomobject]@{
        ExitCode = $child.ExitCode
        StdOut   = $stdoutTask.GetAwaiter().GetResult()
        StdErr   = $stderrTask.GetAwaiter().GetResult()
    }
}

function Write-SmokeCheck {
    <#
    .SYNOPSIS
        打印一条检查结果。
    .OUTPUTS
        无(仅写标准输出)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [bool] $Passed,

        [Parameter(Mandatory = $false)]
        [string] $Detail
    )

    $mark = 'FAIL'
    if ($Passed) { $mark = 'PASS' }
    $line = '[ProfileSmoke] [{0}] {1}' -f $mark, $Name
    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        $line = '{0} —— {1}' -f $line, $Detail
    }
    Write-Output $line
}

# ---------------------------------------------------------------------------
# 0) 解析路径
# ---------------------------------------------------------------------------
# 仓库根 = <repo>/ShellPrompt/Tests 的上两级
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

if ([string]::IsNullOrWhiteSpace($ProfilePath)) {
    $profileFull = Join-Path -Path $repoRoot -ChildPath 'Microsoft.PowerShell_profile.ps1'
} else {
    $profileFull = [System.IO.Path]::GetFullPath($ProfilePath)
}

Write-Output '[ProfileSmoke] ================================================'
Write-Output '[ProfileSmoke] profile 启动冒烟检查'
Write-Output ('[ProfileSmoke]   仓库根  : {0}' -f $repoRoot)
Write-Output ('[ProfileSmoke]   profile : {0}' -f $profileFull)

if (-not (Test-Path -LiteralPath $profileFull -PathType Leaf)) {
    Write-Error ('[ProfileSmoke] 找不到被测 profile 文件: {0}' -f $profileFull)
    exit $codeProfile
}

# ---------------------------------------------------------------------------
# 1) 准备临时工作区(临时 HOME / 包装 profile / 子进程脚本 / 日志)
# ---------------------------------------------------------------------------
$workspace = Join-Path -Path (Join-Path -Path $repoRoot -ChildPath '.agent_cache') -ChildPath ('profile-smoke/' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $workspace -Force -ErrorAction Stop | Out-Null
} catch {
    # .agent_cache 不可写时退回系统临时目录
    $workspace = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('profile-smoke-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $workspace -Force -ErrorAction Stop | Out-Null
}

$tempHome = Join-Path -Path $workspace -ChildPath 'home'
New-Item -ItemType Directory -Path $tempHome -Force -ErrorAction Stop | Out-Null

$resultPath = Join-Path -Path $workspace -ChildPath 'result.json'
$checkerPath = Join-Path -Path $workspace -ChildPath 'child-check.ps1'
$stdoutPath = Join-Path -Path $workspace -ChildPath 'child.stdout.log'
$stderrPath = Join-Path -Path $workspace -ChildPath 'child.stderr.log'

$pwshPath = Get-SmokePwshPath

# 子进程环境:
#   HOME / USERPROFILE -> 临时目录, 让 profile 目录落在临时位置(Windows 上 pwsh 的
#                         profile 目录基于 USERPROFILE\Documents\PowerShell)
#   XDG_CONFIG_HOME    -> Linux 上 pwsh 用它决定 profile 目录, 固定下来避免受宿主环境影响
#   SHELLPROMPT_PROFILE_TRACE=1 -> profile 里 Stamp 只有在这个开关打开时才写 $global:_MARKS
#   SHELLPROMPT_SMOKE_RESULT    -> 子进程把 JSON 结果写到这里
$childEnvironment = @{
    'HOME'                     = $tempHome
    'USERPROFILE'              = $tempHome
    'XDG_CONFIG_HOME'          = (Join-Path -Path $tempHome -ChildPath '.config')
    'SHELLPROMPT_PROFILE_TRACE' = '1'
    'SHELLPROMPT_SMOKE_RESULT' = $resultPath
}

Write-Output ('[ProfileSmoke]   子进程  : {0}' -f $pwshPath)
Write-Output ('[ProfileSmoke]   临时目录: {0}' -f $workspace)

$exitCode = $codeOk
$failureReason = [System.Collections.Generic.List[string]]::new()

try {
    # -----------------------------------------------------------------------
    # 2) 问子进程它自己的 profile 路径
    #    直接问最稳妥: 路径规则(Windows Documents\PowerShell / Linux ~/.config)
    #    由 pwsh 自己说了算, 脚本不硬编码。
    # -----------------------------------------------------------------------
    $probe = Invoke-SmokeChild -FilePath $pwshPath `
        -ArgumentList @('-NoLogo', '-NoProfile', '-Command', '$PROFILE.CurrentUserAllHosts; $PROFILE.CurrentUserCurrentHost') `
        -Environment $childEnvironment -WorkingDirectory $repoRoot

    $wrapperPathList = [System.Collections.Generic.List[string]]::new()
    foreach ($line in ($probe.StdOut -split '\r?\n')) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            $wrapperPathList.Add($line.Trim())
        }
    }
    if ($wrapperPathList.Count -eq 0) {
        Write-Error ('[ProfileSmoke] 无法确定子进程的 $PROFILE 路径。子进程 stderr: {0}' -f $probe.StdErr)
        exit $codeProfile
    }
    foreach ($wrapperPath in $wrapperPathList) {
        Write-Output ('[ProfileSmoke]   包装 profile: {0}' -f $wrapperPath)
    }

    # -----------------------------------------------------------------------
    # 3) 写包装 profile(极薄: 只 dot-source 仓库里的真 profile)
    # -----------------------------------------------------------------------
    # profile 路径里的单引号要转义, 否则拼进单引号字符串会破
    $profileLiteral = $profileFull.Replace("'", "''")

    $wrapperTemplate = @'
# ==============================================================================
# 临时包装 profile —— 由 ShellPrompt/Tests/Invoke-ProfileSmoke.ps1 生成, 请勿手工编辑
# ------------------------------------------------------------------------------
# 为什么需要它:
#   冒烟检查必须走**真实的 profile 加载链路**(pwsh 启动时自动加载
#   $PROFILE.CurrentUserAllHosts / $PROFILE.CurrentUserCurrentHost), 而不是手工
#   dot-source 一次了事 —— 否则"profile 在真实启动里会不会炸"这件事根本测不出来。
#   所以这里在临时 HOME 下放一个**极薄的包装 profile**: 只负责把仓库里真正的
#   Microsoft.PowerShell_profile.ps1 dot-source 进来。
#   关键点: dot-source 的是仓库里那个文件, 因此 profile 内部的
#   $script:ActualRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
#   仍然指向**仓库根**, ShellPrompt/ 子目录照常定位得到, 启动行为与真机一致。
#
# 3>&1 的作用: 把 warning 流并入输出流, 由 ForEach-Object 收集成 WarningRecord,
#   让检查脚本能精确区分"警告"和"普通输出"(banner 等)。
#   非警告输出原样放行, 不改变 profile 的正常启动行为。
#   (Write-Warning 在非交互宿主里本来就落到 stdout, 靠 3>&1 才能拿到原始告警对象。)
#
# 守卫的作用: AllHosts 与 CurrentHost 两个路径都会写同一个包装 profile,
#   pwsh 会把两个都加载一遍 —— 用 SmokeProfileLoaded 守卫保证仓库 profile
#   **只被 dot-source 一次**, 避免函数重复定义与 banner 重复输出。
# ==============================================================================
$smokeAlready = Get-Variable -Name 'SmokeProfileLoaded' -Scope Global -ErrorAction SilentlyContinue
if ($null -eq $smokeAlready) {
    Set-Variable -Name 'SmokeProfileLoaded' -Scope Global -Value $true
    $smokeWarning = [System.Collections.Generic.List[string]]::new()
    try {
        . '__PROFILE_PATH__' 3>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.WarningRecord]) {
                $smokeWarning.Add([string]$_.Message)
            } else {
                $_
            }
        }
    } catch {
        $smokeWarning.Add('PROFILE_DOT_SOURCE_FAILED: ' + [string]$_.Exception.Message)
    }
    Set-Variable -Name 'SmokeProfileWarning' -Scope Global -Value $smokeWarning.ToArray()
}
'@
    $wrapperContent = $wrapperTemplate.Replace('__PROFILE_PATH__', $profileLiteral)
    foreach ($wrapperPath in $wrapperPathList) {
        $wrapperDir = Split-Path -Parent $wrapperPath
        New-Item -ItemType Directory -Path $wrapperDir -Force -ErrorAction Stop | Out-Null
        Set-Content -LiteralPath $wrapperPath -Value $wrapperContent -Encoding UTF8 -Force
    }

    # -----------------------------------------------------------------------
    # 4) 写子进程检查脚本
    # -----------------------------------------------------------------------
    # 作用域说明(为什么这里能读到 profile 留下的变量):
    #   profile 是在 pwsh 的**全局作用域**里执行的, 所以 profile 里的
    #   $script:StartupMissingCommands / $script:StartupFailedFiles /
    #   $script:ActualRoot 实际上就是全局作用域的变量;
    #   本脚本用 -File 执行, 脚本作用域的父级就是全局作用域,
    #   因此 Get-Variable -Scope Global 能稳定取到它们。
    #   包装 profile 里收集到的告警也用 Set-Variable -Scope Global 传递, 同一机制。
    #
    # 集合处理注意: profile 的 _MARKS 是 List[object](元素是 pscustomobject),
    #   在本 pwsh 版本上 `@($list)` 会抛 "Argument types do not match",
    #   所以统一走 ICollection.Count / foreach, 不使用数组子表达式包列表。
    $checkerTemplate = @'
# ==============================================================================
# 子进程检查脚本 —— 由 ShellPrompt/Tests/Invoke-ProfileSmoke.ps1 生成, 请勿手工编辑
# ------------------------------------------------------------------------------
# 运行时机: pwsh -NoLogo -File <本脚本>。pwsh 先加载 profile, 再执行本脚本,
#   所以这里读到的是**真实启动之后**的状态, 也能调用 profile 定义的函数。
# 结果通过 JSON 文件回传给父进程(路径见环境变量 SHELLPROMPT_SMOKE_RESULT)。
# ==============================================================================
$ErrorActionPreference = 'Continue'

function Get-SmokeScopeValue {
    <#
    .SYNOPSIS
        读取指定名字的变量(全局作用域优先, 再回退当前作用域链)。
    .OUTPUTS
        [object] 变量值; 不存在时返回 $null
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    $inGlobal = Get-Variable -Name $Name -Scope Global -ErrorAction SilentlyContinue
    if ($null -ne $inGlobal) { return $inGlobal.Value }
    $inScope = Get-Variable -Name $Name -ErrorAction SilentlyContinue
    if ($null -ne $inScope) { return $inScope.Value }
    return $null
}

$resultPath = $env:SHELLPROMPT_SMOKE_RESULT

# --- 1) profile 到底加载了没有 ---
$profileCommand = Get-Command -Name 'Ensure-ShellPrompt' -ErrorAction SilentlyContinue
$profileLoaded = ($null -ne $profileCommand)
$actualRoot = Get-SmokeScopeValue -Name 'ActualRoot'

# --- 2) 启动期自检结果(profile 阶段 1 留下的两张清单) ---
$missingRaw = Get-SmokeScopeValue -Name 'StartupMissingCommands'
$failedRaw = Get-SmokeScopeValue -Name 'StartupFailedFiles'
$missingCommands = [System.Collections.Generic.List[string]]::new()
if ($null -ne $missingRaw) {
    foreach ($item in $missingRaw) { $missingCommands.Add([string]$item) }
}
$failedFiles = [System.Collections.Generic.List[string]]::new()
if ($null -ne $failedRaw) {
    foreach ($item in $failedRaw) { $failedFiles.Add([string]$item) }
}

# --- 3) 启动计时戳(必须 SHELLPROMPT_PROFILE_TRACE=1, 否则 profile 的 Stamp 不写) ---
$marksVariable = Get-Variable -Name '_MARKS' -Scope Global -ErrorAction SilentlyContinue
$markCount = 0
if ($null -ne $marksVariable -and $null -ne $marksVariable.Value) {
    $markValue = $marksVariable.Value
    if ($markValue -is [System.Collections.ICollection]) {
        $markCount = [int]$markValue.Count
    } else {
        $markCount = 1
    }
}

# --- 4) 包装 profile 收集到的 warning ---
$warningVariable = Get-Variable -Name 'SmokeProfileWarning' -Scope Global -ErrorAction SilentlyContinue
$warning = [System.Collections.Generic.List[string]]::new()
if ($null -ne $warningVariable -and $null -ne $warningVariable.Value) {
    foreach ($item in $warningVariable.Value) { $warning.Add([string]$item) }
}

# --- 5) Ensure-ShellPrompt -> ShellPrompt 模块导入 ---
# 2>&1 把 Ensure-ShellPrompt 内部的 Write-Error 收进这里, 避免污染 stderr,
# 也让"模块导入失败"的真实原因能原样带回父进程。
$importRecord = [System.Collections.Generic.List[string]]::new()
try {
    Ensure-ShellPrompt 2>&1 | ForEach-Object { $importRecord.Add([string]$_) }
} catch {
    $importRecord.Add([string]$_.Exception.Message)
}
$module = Get-Module -Name 'ShellPrompt' -ErrorAction SilentlyContinue
$moduleVersion = ''
if ($null -ne $module) { $moduleVersion = [string]$module.Version }

# --- 6) 本子进程自己的判定(退出码与父进程保持同一套优先级) ---
$shellPromptHit = $false
foreach ($item in $warning) {
    if ($item -match '\[ShellPrompt\]') { $shellPromptHit = $true }
}
$childExit = 0
if ((-not $profileLoaded) -or ($missingCommands.Count -gt 0) -or ($failedFiles.Count -gt 0)) {
    $childExit = 1
} elseif ($shellPromptHit) {
    $childExit = 2
} elseif ($markCount -le 0) {
    $childExit = 3
} elseif ($null -eq $module) {
    $childExit = 4
}

$result = [ordered]@{
    ProfileLoaded   = [bool]$profileLoaded
    ActualRoot      = [string]$actualRoot
    MissingCommands = $missingCommands.ToArray()
    FailedFiles     = $failedFiles.ToArray()
    MarkCount       = [int]$markCount
    Warning         = $warning.ToArray()
    ModuleImported  = ($null -ne $module)
    ModuleVersion   = $moduleVersion
    ImportRecord    = $importRecord.ToArray()
}

$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $resultPath -Encoding UTF8 -Force
exit $childExit
'@
    Set-Content -LiteralPath $checkerPath -Value $checkerTemplate -Encoding UTF8 -Force

    # -----------------------------------------------------------------------
    # 5) 跑子进程
    #    注意: **不加 -NoProfile** —— 必须让 pwsh 自己走 profile 加载链路。
    #    WorkingDirectory 指向仓库根, 等价于 `pwsh -WorkingDirectory <repoRoot>`。
    # -----------------------------------------------------------------------
    $child = Invoke-SmokeChild -FilePath $pwshPath `
        -ArgumentList @('-NoLogo', '-File', $checkerPath) `
        -Environment $childEnvironment -WorkingDirectory $repoRoot

    Set-Content -LiteralPath $stdoutPath -Value $child.StdOut -Encoding UTF8 -Force
    Set-Content -LiteralPath $stderrPath -Value $child.StdErr -Encoding UTF8 -Force

    Write-Output ('[ProfileSmoke]   子进程退出码: {0}' -f $child.ExitCode)

    # -----------------------------------------------------------------------
    # 6) 读回结果并判定
    # -----------------------------------------------------------------------
    $result = $null
    if (Test-Path -LiteralPath $resultPath -PathType Leaf) {
        try {
            $raw = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8
            $result = $raw | ConvertFrom-Json
        } catch {
            $result = $null
            $failureReason.Add(('子进程结果文件无法解析: {0}' -f $_.Exception.Message))
        }
    }

    if ($null -eq $result) {
        Write-SmokeCheck -Name 'profile 加载' -Passed $false -Detail '子进程没有产出结果文件'
        $failureReason.Add(('子进程未产出结果文件(退出码 {0})' -f $child.ExitCode))
        $exitCode = $codeProfile
    } else {
        # --- 检查 1: profile 加载 + 启动期自检 ---
        $selfCheckOk = $true
        $selfCheckDetail = '缺失命令 0 项, 缺失文件 0 项'
        if (-not $result.ProfileLoaded) {
            $selfCheckOk = $false
            $selfCheckDetail = 'profile 未成功加载(Ensure-ShellPrompt 不存在)'
            $failureReason.Add('profile 未成功加载')
        }
        $missingList = [System.Collections.Generic.List[string]]::new()
        if ($null -ne $result.MissingCommands) {
            foreach ($item in $result.MissingCommands) { $missingList.Add([string]$item) }
        }
        $failedList = [System.Collections.Generic.List[string]]::new()
        if ($null -ne $result.FailedFiles) {
            foreach ($item in $result.FailedFiles) { $failedList.Add([string]$item) }
        }
        if ($missingList.Count -gt 0 -or $failedList.Count -gt 0) {
            $selfCheckOk = $false
            $selfCheckDetail = ('缺失命令 {0} 项 [{1}], 缺失文件 {2} 项 [{3}]' -f `
                    $missingList.Count, ($missingList -join '; '), `
                    $failedList.Count, ($failedList -join '; '))
            $failureReason.Add(('启动期自检不通过: {0}' -f $selfCheckDetail))
        }
        Write-SmokeCheck -Name 'profile 加载 / 启动期自检' -Passed $selfCheckOk -Detail $selfCheckDetail

        # --- 检查 2: [ShellPrompt] 前缀的警告/错误 ---
        # 两条来源: 包装 profile 用 3>&1 抓到的原始告警; 以及子进程 stdout/stderr 兜底扫描。
        $shellPromptHit = [System.Collections.Generic.List[string]]::new()
        if ($null -ne $result.Warning) {
            foreach ($item in $result.Warning) {
                if ([string]$item -match '\[ShellPrompt\]') { $shellPromptHit.Add([string]$item) }
            }
        }
        foreach ($stream in @($child.StdOut, $child.StdErr)) {
            foreach ($line in ($stream -split '\r?\n')) {
                if ($line -match '\[ShellPrompt\]') { $shellPromptHit.Add($line.Trim()) }
            }
        }
        $warningOk = ($shellPromptHit.Count -eq 0)
        $warningDetail = '无 [ShellPrompt] 警告'
        if (-not $warningOk) {
            $warningDetail = ('命中 {0} 行: {1}' -f $shellPromptHit.Count, (($shellPromptHit | Select-Object -Unique) -join ' || '))
            $failureReason.Add(('出现 [ShellPrompt] 警告/错误: {0}' -f $warningDetail))
        }
        Write-SmokeCheck -Name '无 [ShellPrompt] 警告/错误' -Passed $warningOk -Detail $warningDetail

        # --- 检查 3: $global:_MARKS ---
        $marksOk = ([int]$result.MarkCount -gt 0)
        $marksDetail = ('$global:_MARKS 条目数 = {0}' -f $result.MarkCount)
        if (-not $marksOk) {
            $failureReason.Add('$global:_MARKS 缺失或为空(检查 SHELLPROMPT_PROFILE_TRACE 是否为 1)')
        }
        Write-SmokeCheck -Name '$global:_MARKS 非空' -Passed $marksOk -Detail $marksDetail

        # --- 检查 4: ShellPrompt 模块导入 ---
        $moduleOk = [bool]$result.ModuleImported
        $moduleDetail = ('模块版本 {0}' -f $result.ModuleVersion)
        if (-not $moduleOk) {
            $importList = [System.Collections.Generic.List[string]]::new()
            if ($null -ne $result.ImportRecord) {
                foreach ($item in $result.ImportRecord) { $importList.Add([string]$item) }
            }
            if ($importList.Count -gt 0) {
                $moduleDetail = ('导入失败: {0}' -f ($importList -join ' || '))
            } else {
                $moduleDetail = 'Ensure-ShellPrompt 执行后 Get-Module ShellPrompt 仍为空'
            }
            $failureReason.Add(('ShellPrompt 模块导入失败: {0}' -f $moduleDetail))
        }
        Write-SmokeCheck -Name 'ShellPrompt 模块导入' -Passed $moduleOk -Detail $moduleDetail

        # 退出码优先级: 1(加载/自检) > 2(警告) > 3(_MARKS) > 4(模块)
        if (-not $selfCheckOk) { $exitCode = $codeProfile }
        elseif (-not $warningOk) { $exitCode = $codeWarning }
        elseif (-not $marksOk) { $exitCode = $codeMarks }
        elseif (-not $moduleOk) { $exitCode = $codeModule }

        # 子进程自己也判了一遍, 父进程透传它的退出码(两者口径一致)
        if ($exitCode -eq $codeOk -and $child.ExitCode -ne $codeOk) {
            $exitCode = $child.ExitCode
        }
    }

    # -----------------------------------------------------------------------
    # 7) 失败时把子进程的原始输出全部打出来, 便于定位
    # -----------------------------------------------------------------------
    if ($exitCode -ne $codeOk) {
        Write-Output '[ProfileSmoke] ----------------------------------------------------'
        Write-Output '[ProfileSmoke] 失败原因:'
        foreach ($reason in $failureReason) {
            Write-Error ('[ProfileSmoke]   - {0}' -f $reason)
        }
        Write-Output '[ProfileSmoke] 子进程 stdout:'
        Write-Output $child.StdOut
        Write-Output '[ProfileSmoke] 子进程 stderr:'
        Write-Output $child.StdErr
    }
}
catch {
    $exitCode = $codeProfile
    Write-Error ('[ProfileSmoke] 冒烟检查自身异常: {0}' -f $_.Exception.Message)
}
finally {
    # 临时文件全部在 .agent_cache/ 或系统临时目录里, 用完即删; 仓库根不产生任何临时文件
    if ($KeepTemp) {
        Write-Output ('[ProfileSmoke] 已保留临时目录(-KeepTemp): {0}' -f $workspace)
    } else {
        try {
            Remove-Item -LiteralPath $workspace -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Warning ('[ProfileSmoke] 清理临时目录失败({0}): {1}' -f $workspace, $_.Exception.Message)
        }
    }
}

Write-Output '[ProfileSmoke] ----------------------------------------------------'
if ($exitCode -eq $codeOk) {
    Write-Output '[ProfileSmoke] 结果: 全部通过'
} else {
    Write-Output ('[ProfileSmoke] 结果: 失败 (退出码 {0})' -f $exitCode)
}

exit $exitCode
