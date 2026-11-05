# ShellPrompt.psm1 - Module Entry Point

# ============================================================
# 仓库自带 PSModule 注入 (v2.0 单轨 Spectre)
# 仓库根目录下的 Modules/ 包含 PwshSpectreConsole 等本地依赖模块,
# 默认 PSModulePath 不会包含此目录, 所以需在 Import-Module 之前注入。
# 硬依赖: ShellPrompt.psd1 已声明 PowerShellVersion='7.6', 低版本会在导入阶段
# 就被 PowerShell 拒绝, 因此本文件不再做版本分支。
# ============================================================
$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$repoModulesDir = Join-Path -Path $repoRoot -ChildPath 'Modules'
if ((Test-Path -Path $repoModulesDir) -and `
    (-not ($env:PSModulePath -split [IO.Path]::PathSeparator -match ([regex]::Escape($repoModulesDir))))) {
    $env:PSModulePath = $repoModulesDir + [IO.Path]::PathSeparator + $env:PSModulePath
}

# Private 目录绝对路径: 后台线程任务(Submit-TmuxBackgroundTask)需要按文件名定位
# 待 dot-source 的模块内文件 —— 线程作业是独立 runspace, 拿不到模块作用域。
$script:ShellPromptPrivateDir = Join-Path -Path $PSScriptRoot -ChildPath 'Private'

# ============================================================
# 加载失败诊断助手 (模块私有, 不导出)
# ============================================================
# 为什么需要: 模块加载失败必须**立即终止导入**, 且错误信息必须能定位到
# "哪个脚本、什么原因"。PowerShell 默认的 dot-source 失败信息要么不含脚本路径
# (运行时 throw), 要么只含路径不含堆栈上下文 (解析错误), 因此这里统一拼接。
function ConvertTo-ShellPromptLoadException {
    <#
    .SYNOPSIS
        构造带完整定位上下文的模块加载失败异常(不抛, 只返回对象)。

    .DESCRIPTION
        返回的异常 Message 固定包含四段信息:
          - 失败阶段(哪一步: 配置初始化 / Private / Public / 依赖 / 补全注册)
          - 失败脚本的**绝对路径**
          - 原始异常的类型与消息(含内部异常)
          - 堆栈上下文(PowerShell 脚本堆栈, 缺失时退回 .NET 堆栈)
        同时把原始异常挂成 InnerException, 便于调用方程序化检查。

    .OUTPUTS
        [System.InvalidOperationException]
    #>
    [CmdletBinding()]
    [OutputType([System.Exception])]
    param(
        # 失败阶段描述
        [Parameter(Mandatory = $true)]
        [string]$Stage,

        # 失败脚本绝对路径(缺失/加载失败时必填)
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$ScriptPath,

        # 原始异常
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [System.Exception]$Exception,

        # PowerShell 脚本堆栈(来自 ErrorRecord.ScriptStackTrace)
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$ScriptStackTrace
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("[ShellPrompt] 模块导入失败: $Stage")
    if (-not [string]::IsNullOrWhiteSpace($ScriptPath)) {
        $lines.Add("  失败脚本: $ScriptPath")
    }
    if ($null -ne $Exception) {
        $lines.Add("  异常类型: $($Exception.GetType().FullName)")
        $lines.Add("  原始异常: $($Exception.Message)")
        $inner = $Exception.InnerException
        if ($null -ne $inner) {
            $lines.Add("  内部异常: $($inner.GetType().FullName): $($inner.Message)")
        }
    }
    $stack = $ScriptStackTrace
    if ([string]::IsNullOrWhiteSpace($stack) -and $null -ne $Exception) {
        $stack = $Exception.StackTrace
    }
    if (-not [string]::IsNullOrWhiteSpace($stack)) {
        $lines.Add("  堆栈: $stack")
    }

    $message = $lines -join [Environment]::NewLine
    if ($null -ne $Exception) {
        return [System.InvalidOperationException]::new($message, $Exception)
    }
    return [System.InvalidOperationException]::new($message)
}

function Get-ShellPromptScriptFile {
    <#
    .SYNOPSIS
        列出目录下的 *.ps1 脚本, 按文件名 **Ordinal** 升序返回绝对路径。

    .DESCRIPTION
        排序用 [System.StringComparer]::Ordinal 而不是 Sort-Object:
        - Sort-Object 默认按**当前区域文化**比较, 不同语言环境下顺序可能不同;
        - Ordinal 比较是纯二进制序, 与区域设置、文件系统枚举顺序都无关,
          因此"加载顺序确定"是**可复现**的, 不依赖文件系统的返回顺序。

    .OUTPUTS
        [string[]] 绝对路径数组
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Directory
    )

    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        throw "[ShellPrompt] 模块脚本目录不存在: $Directory"
    }

    $paths = [System.IO.Directory]::GetFiles($Directory, '*.ps1')
    [Array]::Sort($paths, [System.StringComparer]::Ordinal)
    return $paths
}

# ============================================================
# 核心脚本加载 (Private -> Public)
# ------------------------------------------------------------
# 加载契约 (2026-11 模块可靠性治理):
#   1. Private/ 与 Public/ 下的脚本**全部是核心脚本**。本模块当前不存在
#      "装了也能用、缺了也能用"的可选功能分支, 因此不做人为分类 ——
#      任一核心脚本缺失 / 语法错误 / 加载期抛异常, 都必须**立即终止模块导入**,
#      不允许"Write-Warning 后继续"的半初始化状态。
#   2. 顺序: Private 全量 -> Public 全量, 每段内按文件名 Ordinal 升序。
#      顺序确定性的依据: Private/Public 内**没有任何脚本在顶层调用其它脚本里
#      的函数**(已用 AST 全量核对: 顶层语句只有 $script: 变量初始化),
#      因此字典序不会产生前向引用; 唯一有顶层副作用的
#      Private/Initialize-Config.ps1 被单独优先加载。
#   3. 失败即终止: 错误信息包含**失败脚本绝对路径**与**原始异常**
#      (类型/消息/内部异常/堆栈), 并把原始异常挂为 InnerException。
#   4. 无残留: 模块加载期不写 $global: 变量、不订阅引擎事件、不启动后台 Job
#      (已核对), 因此加载失败时不会在会话里留下非托管资源; 模块作用域的
#      $script: 状态随模块一起丢弃, Register-ArgumentCompleter 注册的补全器
#      也随模块作用域在 Remove-Module 时自动注销。
# ============================================================

# --- 步骤 0: 核心脚本清单校验 (缺失检测) ---
# 为什么需要清单: 目录驱动的加载**看不到"少了文件"** —— 少一个 Private 脚本时,
# 加载循环照常跑完, 只是那个脚本定义的函数不存在, 错误要等到用户第一次调用
# 公开命令时才暴露(实测: 曾出现"模块导入成功但导出命令缺一个"的假可用状态)。
# 清单是**参照集**: 清单里的每一项都必须在磁盘上存在, 缺失即导入失败, 报错含
# 该文件的绝对路径。清单与目录的一致性由 ModuleLoad.Tests.ps1 断言兜底。
$coreInventoryPath = Join-Path -Path $PSScriptRoot -ChildPath 'CoreScripts.psd1'
if (-not (Test-Path -LiteralPath $coreInventoryPath -PathType Leaf)) {
    throw (ConvertTo-ShellPromptLoadException `
        -Stage '核心脚本清单缺失' `
        -ScriptPath $coreInventoryPath `
        -Exception ([System.IO.FileNotFoundException]::new("找不到核心脚本清单: $coreInventoryPath")))
}
try {
    $coreInventory = Import-PowerShellDataFile -LiteralPath $coreInventoryPath
} catch {
    throw (ConvertTo-ShellPromptLoadException `
        -Stage '核心脚本清单解析失败' `
        -ScriptPath $coreInventoryPath `
        -Exception $_.Exception `
        -ScriptStackTrace $_.ScriptStackTrace)
}

# --- 步骤 1: 核心脚本清单逐项存在性校验 (缺失即导入失败) ---
# 报错含**缺失文件的绝对路径**, 便于直接定位。
# 放在所有加载动作之前: 缺文件时**一个脚本都不加载**, 不产生半初始化状态。
$coreMissing = [System.Collections.Generic.List[string]]::new()
foreach ($coreSection in @(
        @{ Key = 'Private'; Directory = $script:ShellPromptPrivateDir },
        @{ Key = 'Public'; Directory = (Join-Path -Path $PSScriptRoot -ChildPath 'Public') })) {
    $declared = @()
    if ($coreInventory.ContainsKey($coreSection.Key)) {
        $declared = @($coreInventory[$coreSection.Key])
    }
    foreach ($coreName in $declared) {
        $corePath = Join-Path -Path $coreSection.Directory -ChildPath $coreName
        if (-not (Test-Path -LiteralPath $corePath -PathType Leaf)) {
            $coreMissing.Add($corePath)
        }
    }
}
if ($coreMissing.Count -gt 0) {
    $missingText = ($coreMissing -join [Environment]::NewLine)
    throw (ConvertTo-ShellPromptLoadException `
        -Stage ("核心脚本缺失 ({0} 个)" -f $coreMissing.Count) `
        -ScriptPath ($coreMissing -join '; ') `
        -Exception ([System.IO.FileNotFoundException]::new("以下核心脚本在磁盘上不存在:`n$missingText")))
}

# --- 步骤 2: Private/Initialize-Config.ps1 (最先加载, 单独处理) ---
# 单独处理的原因: 它建立 $script:Config / $script:ColorCache 等全局配置基座,
# 且被 profile 阶段 1 独立 dot-source, 必须在其它脚本之前就绪。
$initConfigPath = Join-Path -Path $script:ShellPromptPrivateDir -ChildPath 'Initialize-Config.ps1'
if (-not (Test-Path -LiteralPath $initConfigPath -PathType Leaf)) {
    throw (ConvertTo-ShellPromptLoadException `
        -Stage '核心脚本缺失 (配置初始化)' `
        -ScriptPath $initConfigPath `
        -Exception ([System.IO.FileNotFoundException]::new("找不到核心脚本: $initConfigPath")))
}
try {
    . $initConfigPath
} catch {
    throw (ConvertTo-ShellPromptLoadException `
        -Stage '核心脚本加载失败 (配置初始化)' `
        -ScriptPath $initConfigPath `
        -Exception $_.Exception `
        -ScriptStackTrace $_.ScriptStackTrace)
}

# --- 步骤 3: 加载 PwshSpectreConsole (v2.0 单轨硬依赖) ---
# - 全部 UI 渲染出口都在这里, 缺失即模块不可用, 因此不做静默降级
# - 必须在 Private 函数 dot-source 之前, 否则 dot-source 时 Get-Command 探测会失败
# - 失败时抛可定位的终止错误, 而不是伪装成"可选依赖"
try {
    Import-Module -Name 'PwshSpectreConsole' -ErrorAction Stop
} catch {
    throw (ConvertTo-ShellPromptLoadException `
        -Stage '必需依赖模块 PwshSpectreConsole 加载失败' `
        -ScriptPath (Join-Path -Path $repoModulesDir -ChildPath 'PwshSpectreConsole') `
        -Exception $_.Exception `
        -ScriptStackTrace $_.ScriptStackTrace)
}

# --- 步骤 4: Private 全量 (排除已单独加载的 Initialize-Config.ps1) ---
foreach ($privatePath in (Get-ShellPromptScriptFile -Directory $script:ShellPromptPrivateDir)) {
    $privateName = [System.IO.Path]::GetFileName($privatePath)
    if ($privateName -eq 'Initialize-Config.ps1') { continue }
    try {
        . $privatePath
    } catch {
        throw (ConvertTo-ShellPromptLoadException `
            -Stage '核心脚本加载失败 (Private)' `
            -ScriptPath $privatePath `
            -Exception $_.Exception `
            -ScriptStackTrace $_.ScriptStackTrace)
    }
}

# 交互式 UI 主轨 (Terminal.Gui v2 独立 ALC) 可用性检测 —— 惰性执行
# - 加载期**不再**执行检测: 实测该检测是模块导入阶段的最大单一热点(约 500ms),
#   而它在 profile 启动阶段根本没有被使用(菜单要等用户主动触发)。
# - 检测结果改为惰性计算: 首次被真正需要时(Get-ConsoleUiState / Assert-ConsoleUiReady)
#   才现场跑一次, 结果缓存到 $script:ConsoleUiBackend, 后续复用。
# - 不静默失败: 真正要弹菜单时若主轨不可用, Assert-ConsoleUiReady 会抛出
#   带功能名与原因的可定位终止错误。
$script:ConsoleUiBackend = $null

# --- 步骤 5: Public 全量 ---
foreach ($publicPath in (Get-ShellPromptScriptFile -Directory (Join-Path -Path $PSScriptRoot -ChildPath 'Public'))) {
    try {
        . $publicPath
    } catch {
        throw (ConvertTo-ShellPromptLoadException `
            -Stage '核心脚本加载失败 (Public)' `
            -ScriptPath $publicPath `
            -Exception $_.Exception `
            -ScriptStackTrace $_.ScriptStackTrace)
    }
}

# User config override 已移入 Private/Initialize-Config.ps1(步骤 6)。
# 移入的原因: 预热缓存 $script:ColorCache 必须在用户配置**之后**生成, 否则
# Get-CachedConfig 优先命中预热快照, config.ps1 里的覆盖会被静默忽略。
# 放在 Initialize-Config.ps1 里还顺带让 profile 启动期的欢迎语用上同一份配置。

# --- 步骤 6: SSH Config auto-completion ---
# 补全器注册在**模块作用域**, Remove-Module 时由 PowerShell 自动注销,
# 因此不需要额外的 OnRemove 清理逻辑。
try {
    $sshHosts = @(Get-SshConfigHosts)
    if ($sshHosts.Count -gt 0) {
        Register-ArgumentCompleter -CommandName 'Start-TmuxSession' -ParameterName 'HostName' -ScriptBlock {
            # $commandAst / $cursorPosition 由 PowerShell 补全基础架构提供，
            # 用于在多 token 命令行中精确定位当前补全位置。
            param($wordToComplete, $commandAst, $cursorPosition)
            $hosts = Get-SshConfigHosts
            $hosts | Where-Object { $_ -like "*$wordToComplete*" } | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
            # 静默引用 AST 与位置参数，避免 PSReviewUnusedParameter 误报（运行时由 PowerShell 注入）。
            $null = $commandAst, $cursorPosition
        }
    }
} catch {
    throw (ConvertTo-ShellPromptLoadException `
        -Stage 'SSH 主机补全注册失败' `
        -Exception $_.Exception `
        -ScriptStackTrace $_.ScriptStackTrace)
}

# 导出声明已完全通过 .psd1 的 FunctionsToExport 控制,
# 因此不再需要 .psm1 内的 Export-ModuleMember(GitHub #182 回归修复)。


