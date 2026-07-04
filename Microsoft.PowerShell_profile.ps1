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

# ssh-copy-id wrapper — 懒加载未触发时也能直接调用,避免模块作用域别名在
# 调用方 shell 不可见的问题（Set-ProfileAliases.ps1 注册的是模块作用域别名,
# 只在模块内可见,Set-Alias -Scope Global 才是真正的全局别名）
function Copy-SshPublicKey {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments = $true)] [object[]] $Arguments)
    Ensure-ShellPrompt
    $cmd = Get-Command -Module ShellPrompt -Name Copy-SshPublicKey -ErrorAction SilentlyContinue
    if (-not $cmd) {
        Write-Error "ShellPrompt 模块未正确导入,无法调用 Copy-SshPublicKey"
        return
    }
    & $cmd @Arguments
}
Set-Alias -Name ssh-copy-id -Value Copy-SshPublicKey -Scope Global -Force

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
    # 关键:Windows 下 scoop shim 的 .exe 扩展名必须包含在键名中,
    # 否则 hashtable 查不到(Application 命令的 Name 字段是 starship.exe 而非 starship)
    $commands = @{}
    Get-Command -Name starship, fnm -ErrorAction SilentlyContinue | ForEach-Object { $commands[$_.Name] = $_ }

    # Starship — 失败也不能影响 prompt 主链
    # 关键修复:不能使用 Invoke-Expression 执行 init 字符串。
    # 原因:starship init 输出的是 $null = New-Module starship { ... function global:prompt ... Export-ModuleMember ... }
    # 用 Invoke-Expression 执行时,New-Module 创建的动态模块只在临时 ScriptBlock 作用域中存活,
    # 表达式执行完毕后模块随作用域被 GC,里面的 function global:prompt 定义也跟着丢失,主题不显示。
    # 必须 dot-source 一个临时脚本文件,让 New-Module 注册到全局模块表中持久存在。
    if ($commands['starship.exe']) {
        try {
            $initStr = (& starship init powershell --print-full-init) -join "`n"
            if ($initStr) {
                $tmp = [System.IO.Path]::GetTempFileName() + ".ps1"
                [System.IO.File]::WriteAllText($tmp, $initStr, [System.Text.Encoding]::UTF8)
                . $tmp
                Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            }
        } catch { }
    }

    # Fnm — 失败也不能影响 prompt 主链
    if ($commands['fnm.exe']) {
        try { Invoke-Expression ((& fnm env --use-on-cd --shell powershell) -join "`n") } catch { }
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

# 关键重构:profile 加载时直接执行延迟初始化(不通过 prompt 函数)
# 原因:仓库内 profile 走 dot-source 被薄壳加载时,如果延迟初始化只放在
# function global:prompt 包装器内,存在两个严重问题:
# 1. profile 跑完就退出 script scope,包装器内的 $script:OriginalPrompt
#    在薄壳 caller scope 里永远为 null,走到 else 分支捕获默认 prompt。
# 2. 真正调 prompt 时,Invoke-DeferredInit 也不一定被触发(若用户用
#    pwsh -Command 等不会触发 prompt 的方式),starship 永远不初始化。
# 修复:在 profile 末尾直接调用 Invoke-DeferredInit,starship 会覆盖
# Function:prompt;然后在 profile 自身 scope 内抓取覆盖后的真 prompt,
# 存为 $global:OriginalPrompt 供薄壳 scope 直接访问。
Invoke-DeferredInit

# 抓取 starship 覆盖后的真 prompt(此时 Function:prompt 已经是 starship 的)
$currentPrompt = Get-Item Function:prompt -ErrorAction SilentlyContinue
if ($currentPrompt) {
    $global:OriginalPrompt = $currentPrompt.ScriptBlock
} else {
    $global:OriginalPrompt = { "PS $PWD> " }
}

# 简单包装器:直接调用真 prompt,不再做延迟初始化(已经在 profile 加载时完成)
function global:prompt {
    try {
        return & $global:OriginalPrompt
    } catch {
        return "PS> "
    }
}


# ============================================================
# 阶段 3：Profile 加载计时
# ============================================================
$ProfileTimer.Stop()
Write-Host "PowerShell Profile Loaded: $($ProfileTimer.ElapsedMilliseconds)ms" -ForegroundColor DarkGray
