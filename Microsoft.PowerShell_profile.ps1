$ProfileTimer = [System.Diagnostics.Stopwatch]::StartNew()

# 显式声明为 script 作用域，确保在后续调用的函数中安全访问
$script:ActualRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# ============================================================
# 阶段 1：仅加载配置和欢迎语（轻量级）
# ============================================================
. "$script:ActualRoot\ShellPrompt\Private\Initialize-Config.ps1"
. "$script:ActualRoot\ShellPrompt\Public\Initialize-Environment.ps1"
Show-UserScoopLogo

# ============================================================
# 别名 — 保证在 ShellPrompt 模块懒加载前即可使用
# ============================================================
Set-Alias ll Get-ChildItem -ErrorAction SilentlyContinue
Set-Alias which where.exe -ErrorAction SilentlyContinue

# ============================================================
# ShellPrompt 懒加载
# ============================================================
function Ensure-ShellPrompt {
    if (-not (Get-Module ShellPrompt)) {
        $ModulePath = Join-Path $script:ActualRoot "ShellPrompt\ShellPrompt.psd1"
        Import-Module $ModulePath -ErrorAction SilentlyContinue
    }
}

function sss {
    Ensure-ShellPrompt
    Start-TmuxSession @args
}

# ============================================================
# 阶段 2：延迟初始化（首次提示前执行）
# — Starship / Fnm / PSReadLine 这些工具初始化需要 100~400ms
# — 推迟到首次用户交互前，大幅缩短 profile 加载感知时间
# ============================================================
$script:DeferredInitDone = $false

function Invoke-DeferredInit {
    if ($script:DeferredInitDone) { return }
    $script:DeferredInitDone = $true

    # 一次 Get-Command 查找所有工具（减少进程查找开销）
    $commands = @{}
    Get-Command -Name starship, fnm -ErrorAction SilentlyContinue | ForEach-Object { $commands[$_.Name] = $_ }

    # Starship — 失败也不能影响 prompt 主链
    if ($commands['starship']) {
        try { Invoke-Expression ((&starship init powershell) -join "`n") } catch { }
    }

    # Fnm — 失败也不能影响 prompt 主链
    if ($commands['fnm']) {
        try { Invoke-Expression ((&fnm env --use-on-cd --shell powershell) -join "`n") } catch { }
    }

    # PSReadLine — 每个 set 命令独立 try-catch
    # 原因：PSReadLine 版本不同参数可能不同（-PredictionSource 是 2.2+ 才有的）
    # 如果任何 set 失败，绝不能阻断 prompt 链
    if (Get-Module -ListAvailable -Name PSReadLine) {
        try {
            Import-Module PSReadLine -ErrorAction SilentlyContinue
            try { Set-PSReadLineOption -PredictionSource History -ErrorAction Stop } catch { }
            try { Set-PSReadLineOption -EditMode Windows -ErrorAction Stop } catch { }
            try { Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete -ErrorAction Stop } catch { }
            try { Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward -ErrorAction Stop } catch { }
            try { Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward -ErrorAction Stop } catch { }
        } catch { }
    }
}

# 通过包装 prompt 函数来触发延迟初始化
# 重要：Get-Item Function:prompt 返回的是 FunctionInfo 对象（不是 ScriptBlock）
# 显式取 .ScriptBlock 避免类型歧义
$script:OriginalPrompt = (Get-Item Function:prompt -ErrorAction SilentlyContinue).ScriptBlock
if (-not $script:OriginalPrompt) { $script:OriginalPrompt = { "PS $PWD> " } }

function global:prompt {
    # 首次调用 prompt 时触发延迟初始化
    Invoke-DeferredInit
    # 调用原始 prompt — 兜底防止 prompt 链断裂
    try {
        return & $script:OriginalPrompt
    } catch {
        return "PS> "
    }
}


# ============================================================
# 阶段 3：Profile 加载计时
# ============================================================
$ProfileTimer.Stop()
Write-Host "PowerShell Profile Loaded: $($ProfileTimer.ElapsedMilliseconds)ms" -ForegroundColor DarkGray
