$ProfileTimer = [System.Diagnostics.Stopwatch]::StartNew()

# 显式声明为 script 作用域，确保在后续调用的函数中安全访问
$script:ActualRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
# 始终定义 Stamp 函数(零开销), 但仅当 trace env 设置时才真正写时间戳
function global:Stamp {
    param([Parameter(Position=0)] [string]$Label)
    if (-not $env:SHELLPROMPT_PROFILE_TRACE) { return }
    if (-not $global:_MARKS) { $global:_MARKS = New-Object System.Collections.Generic.List[object] }
    [void]$global:_MARKS.Add([pscustomobject]@{ L = $Label; T = [int]([System.Diagnostics.Stopwatch]::GetTimestamp() * 1000.0 / [System.Diagnostics.Stopwatch]::Frequency) })
}
Stamp('P0_root')

# ============================================================
# 阶段 1：仅加载配置和欢迎语（轻量级）
# ============================================================
# 设计意图: 欢迎语必须在 ShellPrompt 模块(重)加载之前渲染出来, 因此这里
# 只加载欢迎语链路真正需要的脚本, 不把 tmux/SSH/GridView 等重依赖提前拉进来。
# 该"轻量级"是有意为之, 不是历史遗留。
#
# 维护约定:
#   1) $script:StartupLoadOrder 登记"启动期需要的文件", 顺序 = 加载顺序,
#      被依赖者在前。这里只登记文件, 不做自动依赖推导。
#   2) 新增启动期依赖时, 必须把被依赖的文件一并加进本清单。
#      漏加不会静默失败: 下面的自检会用 AST 取出这些文件里**真实调用**的命令名
#      (注释与字符串里的函数名不算), 逐个检查在当前会话里能否解析, 解析不到就
#      明确报出"哪个文件调用了哪个没加载的命令"。
#   3) 自检不通过只告警、不阻断启动。
#
# 2026-10-29 精简: 原先这里有一套"函数名 -> 定义文件"静态索引 + AST 依赖闭包 +
# 拓扑排序 + %LOCALAPPDATA%\ShellPrompt\startup-graph.json 缓存(约 250 行)。
# 逐文件核对后, 实际依赖闭包只有 5 个文件(见下方清单), 显式有序清单足够表达:
#   收益: 启动期不再扫描 Private/Public 全目录、不再读写用户目录下的 JSON;
#         profile 从 434 行降到约 260 行, 启动链路一眼看得懂。
#   代价: 依赖关系从"自动推导"变成"手工维护", 由上面的 AST 自检兜底。
$script:StartupBannerDir = Join-Path $script:ActualRoot 'ShellPrompt'
$script:StartupLoadOrder = @(
    # Get-CachedConfig 的定义处
    'Private\Initialize-Config.ps1'
    # 依赖 Get-CachedConfig
    'Private\Resolve-ColorTable.ps1'
    # 依赖 Resolve-ColorTable
    'Private\New-WelcomeBanner.ps1'
    # 自包含(fnm 环境初始化)
    'Private\Initialize-FnmEnvironment.ps1'
    # 依赖 Get-CachedConfig / Get-RandomQuote / New-WelcomeBanner
    'Public\Show-UserScoopLogo.ps1'
)

# --- 1) 按清单顺序 dot-source ---
# 注意: dot-source 必须留在 profile 顶层执行 —— 放进函数体内时, 被定义的函数
# 会随函数作用域一起销毁, 反而拿不到函数。
$script:StartupFailedFiles = [System.Collections.Generic.List[string]]::new()
foreach ($rel in $script:StartupLoadOrder) {
    $full = Join-Path $script:StartupBannerDir $rel
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        $script:StartupFailedFiles.Add($rel)
        continue
    }
    try {
        . $full
    } catch {
        $script:StartupFailedFiles.Add($rel)
        Write-Warning "[ShellPrompt] 欢迎语依赖脚本加载失败 ($rel): $($_.Exception.Message)"
    }
}
Stamp('P1_after_dot_source')

# --- 2) 自检: 启动期脚本里调用到的命令必须全部可见 ---
# 目的: 捕捉"新增了启动期依赖, 却忘记把定义文件加进 $script:StartupLoadOrder"。
# 判定方式: AST 取出这 5 个文件里真实调用的命令名(注释/字符串里的不算),
#           逐个检查当前会话里能否解析; 解析不到且该名字确实是 ShellPrompt
#           内部函数(Private/Public 里有定义) -> 报出来源文件, 由维护者补进清单。
# 两处细节:
#   1) 用调用运算符(&)调用的命令一律跳过 —— 那是"用到时才需要"的外部工具
#      (如 & fnm env), fnm 没装也不该在启动期报警。
#   2) 只有真的发现解析不到的命令时, 才去扫 Private/Public 建函数索引, 把
#      "解析不到"收敛成"确实是内部函数漏加载"; 正常启动路径不做这次全目录扫描。
$script:StartupMissingCommands = [System.Collections.Generic.List[string]]::new()
$startupUnresolved = [System.Collections.Generic.List[string]]::new()
foreach ($rel in $script:StartupLoadOrder) {
    $full = Join-Path $script:StartupBannerDir $rel
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($full, [ref]$null, [ref]$parseErrors)
    if (-not $ast) { continue }
    $commands = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst]
        }, $true)
    foreach ($cmd in $commands) {
        $name = $cmd.GetCommandName()
        if (-not $name) { continue }
        if ($cmd.InvocationOperator -eq [System.Management.Automation.Language.CommandInvocationOperator]::Ampersand) { continue }
        if (Get-Command -Name $name -ErrorAction SilentlyContinue) { continue }
        $startupUnresolved.Add("$rel|$name")
    }
}

if ($startupUnresolved.Count -gt 0) {
    $startupInternalIndex = @{}
    foreach ($startupDir in @('Private', 'Public')) {
        $dirPath = Join-Path $script:StartupBannerDir $startupDir
        if (-not (Test-Path -LiteralPath $dirPath -PathType Container)) { continue }
        try {
            $startupFiles = @([System.IO.Directory]::EnumerateFiles($dirPath, '*.ps1'))
        } catch {
            continue
        }
        foreach ($file in $startupFiles) {
            try { $text = [System.IO.File]::ReadAllText($file) } catch { continue }
            foreach ($m in [regex]::Matches($text, '(?m)^[ \t]*function[ \t]+([A-Za-z][\w-]*)')) {
                $startupInternalIndex[$m.Groups[1].Value] = $file
            }
        }
    }
    foreach ($entry in $startupUnresolved) {
        $parts = $entry -split '\|', 2
        if ($startupInternalIndex.ContainsKey($parts[1])) {
            $script:StartupMissingCommands.Add("$($parts[0]) -> $($parts[1])")
        }
    }
}

if ($script:StartupMissingCommands.Count -gt 0 -or $script:StartupFailedFiles.Count -gt 0) {
    Write-Warning (
        "[ShellPrompt] 欢迎语依赖加载不完整 —— 缺失命令: {0}; 缺失文件: {1}" -f
        ($script:StartupMissingCommands -join ', '),
        ($script:StartupFailedFiles -join ', ')
    )
} else {
    Show-UserScoopLogo
}

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
# 阶段 2：延迟初始化
# — Starship / Fnm / PSReadLine 这些工具初始化需要 100~400ms
# — Starship 走 profile 阶段 2 同步路径: Invoke-Expression (starship init powershell --print-full-init)
#   由 starship 自我替换 Function:prompt, 完成 prompt 接管
# — Fnm 走缓存路径(Initialize-FnmEnvironment),首次或 fnm 可执行文件变化时
#   才跑一次 fnm env 子进程,后续启动直接读缓存重算 PATH。
# ============================================================
$script:DeferredInitDone = $false

function Invoke-DeferredInit {
    <#
    .SYNOPSIS
        启动期延迟初始化: fnm (缓存路径) + Starship (同步 starship init) + PSReadLine.
    #>
    if ($script:DeferredInitDone) { return }
    $script:DeferredInitDone = $true

    # Fnm — 走缓存路径: Initialize-FnmEnvironment 已由阶段 1 dot-source 注入
    # (它在 $script:StartupLoadOrder 清单里)。缓存命中则零子进程; 缓存失效则跑一次 fnm env
    #  并写回缓存, 后续启动复用。失败时该函数内部已自动回退到子进程保底路径。
    if (Get-Command -Name 'Initialize-FnmEnvironment' -ErrorAction SilentlyContinue) {
        try { Initialize-FnmEnvironment -ErrorAction SilentlyContinue | Out-Null } catch { }
    } else {
        # 兜底: 走传统子进程路径, 保证 node 一定可用
        try { Invoke-Expression ((& fnm env --use-on-cd --shell powershell) -join "`n") } catch { }
    }

    # Starship — 同步路径: starship init 会自我替换 Function:prompt,
    # 完成 prompt 接管; 失败时静默跳过, 保留默认 PS> prompt.
    # 关键:直接 `Invoke-Expression (& starship init --print-full-init)` 在 PS 7.6+ 会抛
    # "Cannot convert 'System.Object[]' to 'System.String'" — `& cmd` 返回的是行数组,
    # Invoke-Expression 只接受单字符串,整个脚本从未执行,Function:prompt 未被替换,
    # 用户看到 PS 默认 `> ` prompt。修复:先 join 成单字符串再 Invoke-Expression。
    $starship = Get-Command -Name 'starship' -ErrorAction SilentlyContinue
    if ($starship) {
        try {
            $starshipInit = & $starship init powershell --print-full-init
            Invoke-Expression ($starshipInit -join "`n")
        } catch {
            Write-Verbose "[profile] starship init 失败: $($_.Exception.Message)"
        }
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

# 阶段 2 同步部分: fnm(走缓存) + starship(同步 init) + PSReadLine。
Invoke-DeferredInit
Stamp('P2_after_deferred')

# ============================================================
# 阶段 3：Profile 加载计时（保留计时器用于诊断，不重复输出）
# ============================================================
$ProfileTimer.Stop()
# 宿主（powershell.exe / pwsh.exe / VS Code PS 扩展）已输出各自的
# "Loading personal and system profiles took Xms"，我们不再重复输出。
