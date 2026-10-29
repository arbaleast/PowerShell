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

# Load configuration first; $script:ShellPromptRoot 守束避免重复 dot-source
if (-not (Get-Variable -Name 'ShellPromptRoot' -Scope Script -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\Private\Initialize-Config.ps1"
}

# ============================================================
# 加载 PwshSpectreConsole (v2.0 单轨硬依赖)
# - 全部 UI 渲染出口都在这里, 缺失即模块不可用, 因此不做静默降级
# - 必须在 Private 函数 dot-source 之前, 否则 dot-source 时 Get-Command 探测会失败
# - 失败时抛可定位的终止错误, 而不是伪装成"可选依赖"
# ============================================================
try {
    Import-Module -Name 'PwshSpectreConsole' -ErrorAction Stop
} catch {
    throw "[ShellPrompt] 必需的依赖模块 PwshSpectreConsole 加载失败: $($_.Exception.Message) " +
          "请确认仓库 Modules/PwshSpectreConsole/ 目录完整, 且当前为 PowerShell 7.6 及以上。"
}

# Load all module scripts (Private first, then Public; each in alphabetical order)
# This ensures Private functions are defined before Public functions that may call them.
Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" | Sort-Object Name | ForEach-Object {
    if ($_.Name -eq 'Initialize-Config.ps1') { return }
    try {
        . $_.FullName
    } catch {
        Write-Warning "[ShellPrompt] Failed to load $($_.Name): $($_.Exception.Message)"
    }
}

# 控制台 UI 主轨 (PSTui GridView) 可用性检测 —— 惰性执行
# - 加载期**不再**执行检测: 实测该检测是模块导入阶段的最大单一热点(约 500ms),
#   而它在 profile 启动阶段根本没有被使用(菜单要等用户主动触发)。
# - 检测结果改为惰性计算: 首次被真正需要时(Get-ConsoleUiState / Assert-ConsoleUiReady)
#   才现场跑一次, 结果缓存到 $script:ConsoleUiBackend, 后续复用。
# - 不静默失败: 真正要弹菜单时若主轨不可用, Assert-ConsoleUiReady 会抛出
#   带功能名与原因的可定位终止错误。
$script:ConsoleUiBackend = $null
Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" | Sort-Object Name | ForEach-Object {
    try {
        . $_.FullName
    } catch {
        Write-Warning "[ShellPrompt] Failed to load $($_.Name): $($_.Exception.Message)"
    }
}

# User config override
$userConfigPath = Join-Path $HOME ".ShellPrompt\config.ps1"
if (Test-Path $userConfigPath) {
    try {
        . $userConfigPath
    } catch {
        Write-Host "[ShellPrompt] User config failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# SSH Config auto-completion
$sshHosts = Get-SshConfigHosts
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

# 导出声明已完全通过 .psd1 的 FunctionsToExport 控制,
# 因此不再需要 .psm1 内的 Export-ModuleMember。

# 导出声明已完全通过 .psd1 的 FunctionsToExport 控制,
# 这里不再需要 Export-ModuleMember(GitHub #182 回归修复)
