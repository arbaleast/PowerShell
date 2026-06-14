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

    # Starship
    if ($commands['starship']) {
        Invoke-Expression ((&starship init powershell) -join "`n")
    }

    # Fnm
    if ($commands['fnm']) {
        Invoke-Expression ((&fnm env --use-on-cd --shell powershell) -join "`n")
    }

    # PSReadLine
    if (Get-Module -ListAvailable -Name PSReadLine) {
        Import-Module PSReadLine -ErrorAction SilentlyContinue
        Set-PSReadLineOption -PredictionSource History
        Set-PSReadLineOption -EditMode Windows
        Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
        Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
        Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    }
}

# 通过包装 prompt 函数来触发延迟初始化
$script:OriginalPrompt = Get-Item Function:prompt -ErrorAction SilentlyContinue
if (-not $script:OriginalPrompt) { $script:OriginalPrompt = { "PS $PWD> " } }

function global:prompt {
    # 首次调用 prompt 时触发延迟初始化
    Invoke-DeferredInit
    # 调用原始 prompt
    & $script:OriginalPrompt
}

# ============================================================
# 阶段 3：Profile 加载计时
# ============================================================
$ProfileTimer.Stop()
Write-Host "PowerShell Profile Loaded: $($ProfileTimer.ElapsedMilliseconds)ms" -ForegroundColor DarkGray
