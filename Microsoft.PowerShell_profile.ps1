$ProfileTimer = [System.Diagnostics.Stopwatch]::StartNew()

# 显式声明为 script 作用域，确保在后续调用的函数中安全访问
$script:ActualRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# ============================================================
# 阶段 1：仅加载配置和欢迎语（轻量级）
# ============================================================
. "$script:ActualRoot\ShellPrompt\Private\Initialize-Config.ps1"
. "$script:ActualRoot\ShellPrompt\Public\Show-UserScoopLogo.ps1"
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
        try {
            Import-Module $ModulePath -ErrorAction Stop -Verbose:$false
        } catch {
            # 暴露真实导入错误，避免上层 wrapper 误判为“模块未正确导入”
            Write-Error "[ShellPrompt] 模块导入失败 ($ModulePath): $($_.Exception.Message)"
            return
        }
    }
}

# 公开命令名 wrapper — 懒加载未触发时也能直接调用 Start-TmuxSession
# 关键:内部通过 Get-Command -Module 获取模块命令对象,避免与自身重名导致无限递归
function Start-TmuxSession {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments = $true)] [object[]] $Arguments)
    Ensure-ShellPrompt
    $cmd = Get-Command -Module ShellPrompt -Name Start-TmuxSession -ErrorAction SilentlyContinue
    if (-not $cmd) {
        Write-Error "ShellPrompt 模块未正确导入,无法调用 Start-TmuxSession"
        return
    }
    & $cmd @Arguments
}

# 短别名 — 历史兼容
Set-Alias -Name sss -Value Start-TmuxSession -Scope Global

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
# 重要：$script:OriginalPrompt 必须在 Invoke-DeferredInit 执行后抓取
# 因为 starship init 会覆盖 Function:prompt，提前抓取拿到的是 PowerShell
# 默认 prompt，主题不生效。所以这里先置空，在 global:prompt 内首次
# 调用时（Invoke-DeferredInit 之后）才取 Starship 覆盖后的真 prompt。
$script:OriginalPrompt = $null

function global:prompt {
    # 首次调用 prompt 时触发延迟初始化
    Invoke-DeferredInit
    # 首次调用时（在 Invoke-DeferredInit 之后）抓取被 Starship 覆盖的 prompt
    if ($null -eq $script:OriginalPrompt) {
        $script:OriginalPrompt = (Get-Item Function:prompt -ErrorAction SilentlyContinue).ScriptBlock
        if (-not $script:OriginalPrompt) { $script:OriginalPrompt = { "PS $PWD> " } }
    }
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
