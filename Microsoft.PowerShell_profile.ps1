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
# 维护约定(消除"新增依赖忘记加一行 dot-source"的隐患):
#   1) $script:StartupBannerEntries 只登记"入口文件";
#   2) 入口文件调用到的其它 ShellPrompt 内部函数, 由下面的依赖解析器依据
#      "函数名 -> 定义文件"静态索引自动补齐 —— 新增内部依赖**不需要**再手工
#      加一行 dot-source(此前 Resolve-ColorTable 漏加载即为该隐患的根因);
#   3) 任何无法满足的依赖都会在自检块中以 Write-Warning 明确报出, 绝不静默失败。
$script:StartupBannerDir = Join-Path $script:ActualRoot 'ShellPrompt'
$script:StartupBannerEntries = @(
    'Private\Initialize-Config.ps1'
    'Private\New-WelcomeBanner.ps1'
    'Private\Initialize-FnmEnvironment.ps1'
    'Public\Show-UserScoopLogo.ps1'
)

# --- 1) 扫描 Private/Public 目录清单 (缓存失效判定的依据) ---
# 只做文件系统层面的枚举, 不读文件内容。目录枚举走 [System.IO.Directory]::EnumerateFiles,
# 避开 Get-ChildItem 的 cmdlet 开销(启动期敏感路径)。
# 记录每个文件的 (LastWriteTimeUtc ticks, Length), 以及每个目录的文件名列表,
# 用于判定"参与索引的文件集合"是否发生变化(新增/删除/修改)。
$script:StartupScanFiles = [ordered]@{}   # 相对路径 -> @{ M = mtime ticks; L = 长度 }
$script:StartupScanDirs = [ordered]@{}    # 目录名 -> @(文件名, 有序)
foreach ($startupDir in @('Private', 'Public')) {
    $startupDirPath = Join-Path $script:StartupBannerDir $startupDir
    if (-not (Test-Path -LiteralPath $startupDirPath -PathType Container)) { continue }
    $names = [System.Collections.Generic.List[string]]::new()
    try {
        $fullNames = @([System.IO.Directory]::EnumerateFiles($startupDirPath, '*.ps1'))
    } catch {
        continue
    }
    foreach ($full in $fullNames) {
        $fileInfo = $null
        try { $fileInfo = [System.IO.FileInfo]::new($full) } catch { continue }
        $rel = Join-Path $startupDir $fileInfo.Name
        $script:StartupScanFiles[$rel] = [PSCustomObject]@{
            M = $fileInfo.LastWriteTimeUtc.Ticks
            L = $fileInfo.Length
        }
        $names.Add($fileInfo.Name) | Out-Null
    }
    $namesSorted = @($names | Sort-Object)
    $script:StartupScanDirs[$startupDir] = $namesSorted
}

# --- 1b) 依赖闭包结果缓存 ---
# 目的: "函数名 -> 文件"索引 + AST 解析(约 130ms)在每次启动都要重做, 而结果只在
# 相关文件变化时才会变。这里把有序加载清单缓存到用户缓存目录的 JSON, 下次启动
# 校验所有参与索引文件的 (mtime, 长度) 未变则直接命中缓存, 跳过索引与 AST 解析。
#
# 缓存路径: %LOCALAPPDATA%\ShellPrompt\startup-graph.json
# 失效判定: 任一 Private/Public 下 *.ps1 文件的 mtime 或长度变化, 或文件被新增/删除
# 容错:     缓存损坏 / JSON 解析失败 / 并发写冲突 -> 静默回退到全量重建, 不报错不中断
$script:StartupCachePath = Join-Path $env:LOCALAPPDATA 'ShellPrompt\startup-graph.json'

function Test-StartupCacheHit {
    <#
    .SYNOPSIS
        校验启动图缓存是否仍然有效 (与当前磁盘状态逐文件比对)
    .OUTPUTS
        [bool] 是否命中
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)] $Cache,
        [Parameter(Mandatory = $true)] $ScanFiles,
        [Parameter(Mandatory = $true)] $ScanDirs
    )

    # 目录清单必须完全一致(覆盖新增/删除文件)
    $cacheDirs = $Cache.dirs
    if ($null -eq $cacheDirs) { return $false }
    foreach ($dirName in $ScanDirs.Keys) {
        $cached = @($cacheDirs.$dirName)
        $current = @($ScanDirs[$dirName])
        if ($cached.Count -ne $current.Count) { return $false }
        for ($i = 0; $i -lt $current.Count; $i++) {
            if ($cached[$i] -ne $current[$i]) { return $false }
        }
    }
    foreach ($dirName in $cacheDirs.PSObject.Properties.Name) {
        if (-not $ScanDirs.Contains($dirName)) { return $false }
    }

    # 文件集合 + (mtime, 长度) 必须完全一致
    $cacheFiles = $Cache.files
    if ($null -eq $cacheFiles) { return $false }
    $cacheFileNames = @($cacheFiles.PSObject.Properties.Name)
    if ($cacheFileNames.Count -ne $ScanFiles.Count) { return $false }
    foreach ($rel in $ScanFiles.Keys) {
        $entry = $cacheFiles.$rel
        if ($null -eq $entry) { return $false }
        if ([long]$entry.M -ne [long]$ScanFiles[$rel].M) { return $false }
        if ([long]$entry.L -ne [long]$ScanFiles[$rel].L) { return $false }
    }

    # 加载清单必须存在
    if ($null -eq $Cache.order) { return $false }
    return $true
}

function Save-StartupCache {
    <#
    .SYNOPSIS
        原子写入启动图缓存; 失败时静默忽略(不影响启动)
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)] [string]$Path,
        [Parameter(Mandatory = $true)] $ScanFiles,
        [Parameter(Mandatory = $true)] $ScanDirs,
        [Parameter(Mandatory = $true)] [string[]]$Order
    )

    try {
        $dir = Split-Path -Parent $Path
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
            [System.IO.Directory]::CreateDirectory($dir) | Out-Null
        }
        $payload = [PSCustomObject]@{
            version = 1
            files   = $ScanFiles
            dirs    = $ScanDirs
            order   = @($Order)
        }
        $json = $payload | ConvertTo-Json -Depth 6 -Compress
        # 原子写: 先写临时文件再 Move 覆盖, 避免并发启动读到半截 JSON
        $tmp = "$Path.$PID.tmp"
        [System.IO.File]::WriteAllText($tmp, $json, [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::Copy($tmp, $Path, $true)
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    } catch {
        # 缓存不可写(权限/只读目录)不应影响启动
    }
}

$script:StartupCacheHit = $false
$script:StartupOrder = $null

# 尝试命中缓存
try {
    if (Test-Path -LiteralPath $script:StartupCachePath -PathType Leaf) {
        $raw = [System.IO.File]::ReadAllText($script:StartupCachePath)
        $cache = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($cache.version -eq 1 -and (Test-StartupCacheHit -Cache $cache -ScanFiles $script:StartupScanFiles -ScanDirs $script:StartupScanDirs)) {
            $script:StartupOrder = [System.Collections.Generic.List[string]]::new()
            foreach ($rel in @($cache.order)) { $script:StartupOrder.Add($rel) | Out-Null }
            $script:StartupCacheHit = $true
        }
    }
} catch {
    # 缓存损坏 / JSON 解析失败 -> 静默回退到全量重建
    $script:StartupCacheHit = $false
    $script:StartupOrder = $null
}

# --- 2) 收集入口文件的依赖闭包 (仅在缓存未命中时执行) ---
# 依赖识别用 PowerShell AST 精确提取"真实命令调用"(CommandAst),
# 这样注释里提到的函数名不会造成误判, 也不会把 tmux/SSH/GridView 等
# 与欢迎语无关的重脚本拖进启动路径 —— 保留阶段 1 的"轻量级"语义。
$script:StartupFailedFiles = [System.Collections.Generic.List[string]]::new()

if (-not $script:StartupCacheHit) {
    # 2a) 建立"函数名 -> 定义文件"静态索引
    # 正则只扫函数定义行(不解析调用点), 索引覆盖 Private + Public。
    # 读文件走 [System.IO.File]::ReadAllText 直读, 避免 Get-Content 的 cmdlet 开销。
    $script:StartupFunctionIndex = @{}
    $script:StartupFunctionPattern = '(?m)^[ \t]*function[ \t]+([A-Za-z][\w-]*)'
    foreach ($startupDir in @('Private', 'Public')) {
        $startupDirPath = Join-Path $script:StartupBannerDir $startupDir
        if (-not (Test-Path -LiteralPath $startupDirPath -PathType Container)) { continue }
        $fileNames = @($script:StartupScanDirs[$startupDir])
        foreach ($fileName in $fileNames) {
            $full = Join-Path $startupDirPath $fileName
            $rel = Join-Path $startupDir $fileName
            try {
                $text = [System.IO.File]::ReadAllText($full)
            } catch {
                continue
            }
            foreach ($m in [regex]::Matches($text, $script:StartupFunctionPattern)) {
                $script:StartupFunctionIndex[$m.Groups[1].Value] = $rel
            }
        }
    }

    # 2b) 依赖闭包 + 拓扑排序
    $script:StartupFileDeps = @{}   # 相对路径 -> 该文件依赖的 ShellPrompt 内部文件列表
    $script:StartupLoadedFiles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $startupPending = [System.Collections.Generic.Queue[string]]::new()
    foreach ($entry in $script:StartupBannerEntries) { $startupPending.Enqueue($entry) }

    while ($startupPending.Count -gt 0) {
        $rel = $startupPending.Dequeue()
        if (-not $script:StartupLoadedFiles.Add($rel)) { continue }
        $full = Join-Path $script:StartupBannerDir $rel
        if (-not (Test-Path -LiteralPath $full)) {
            $script:StartupFailedFiles.Add($rel)
            continue
        }

        # AST 提取本文件中的命令调用, 命中索引的定义文件记为该文件的依赖
        $deps = [System.Collections.Generic.List[string]]::new()
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($full, [ref]$null, [ref]$parseErrors)
        if ($ast) {
            $commands = $ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst]
                }, $true)
            foreach ($cmd in $commands) {
                $name = $cmd.GetCommandName()
                if (-not $name) { continue }
                $def = $script:StartupFunctionIndex[$name]
                if (-not $def) { continue }   # 非 ShellPrompt 内部函数(如 Get-Content), 忽略
                if (-not $deps.Contains($def)) { $deps.Add($def) }
                if (-not $script:StartupLoadedFiles.Contains($def)) { $startupPending.Enqueue($def) }
            }
        }
        $script:StartupFileDeps[$rel] = $deps
    }

    # 按依赖顺序(被依赖者在前)加载, 保证顶层语句执行时依赖已就绪
    # 注意: dot-source 必须留在 profile 顶层执行 —— 放进函数体内时, 被定义的函数
    # 会随函数作用域一起销毁, 反而拿不到函数。
    $script:StartupOrder = [System.Collections.Generic.List[string]]::new()
    $script:StartupVisited = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    function Resolve-StartupLoadOrder {
        param([string]$Rel)
        if (-not $script:StartupVisited.Add($Rel)) { return }
        $deps = $script:StartupFileDeps[$Rel]
        if ($deps) {
            foreach ($d in $deps) { Resolve-StartupLoadOrder -Rel $d }
        }
        $script:StartupOrder.Add($Rel)
    }
    foreach ($entry in $script:StartupBannerEntries) { Resolve-StartupLoadOrder -Rel $entry }
    Remove-Item -LiteralPath 'Function:Resolve-StartupLoadOrder' -ErrorAction SilentlyContinue

    # 2c) 写回缓存 (失败静默)
    Save-StartupCache -Path $script:StartupCachePath -ScanFiles $script:StartupScanFiles -ScanDirs $script:StartupScanDirs -Order $script:StartupOrder.ToArray()
}

# --- 3) 按依赖顺序(被依赖者在前)加载, 保证顶层语句执行时依赖已就绪 ---
# 注意: dot-source 必须留在 profile 顶层执行 —— 放进函数体内时, 被定义的函数
# 会随函数作用域一起销毁, 反而拿不到函数。
foreach ($rel in $script:StartupOrder) {
    $full = Join-Path $script:StartupBannerDir $rel
    if (-not (Test-Path -LiteralPath $full)) { continue }
    try {
        . $full
    } catch {
        $script:StartupFailedFiles.Add($rel)
        Write-Warning "[ShellPrompt] 欢迎语依赖脚本加载失败 ($rel): $($_.Exception.Message)"
    }
}
# 清理仅用于排序的临时辅助函数, 避免污染全局作用域
Remove-Item -LiteralPath 'Function:Resolve-StartupLoadOrder' -ErrorAction SilentlyContinue
Remove-Item -LiteralPath 'Function:Test-StartupCacheHit' -ErrorAction SilentlyContinue
Remove-Item -LiteralPath 'Function:Save-StartupCache' -ErrorAction SilentlyContinue
Stamp('P1_after_dot_source')

# --- 4) 自检: 启动期 dot-source 依赖的命令必须全部可见 ---
# 注: Initialize-FnmEnvironment / Invoke-DeferredInit 在此之前已
# 通过阶段 1 依赖闭包加载(Initialize-FnmEnvironment)或定义于 profile 阶段 2 同步路径
# (Invoke-DeferredInit), 此处校验面向启动期 dot-source 后的命令可见性 (欢迎语链路 + fnm 链路)。
$script:StartupRequiredCommands = @(
    'Get-CachedConfig'
    'Resolve-ColorTable'
    'Get-RandomQuote'
    'New-WelcomeBanner'
    'Show-UserScoopLogo'
    'Initialize-FnmEnvironment'
)
$script:StartupMissingCommands = @(
    $script:StartupRequiredCommands |
        Where-Object { -not (Get-Command -Name $_ -CommandType Function -ErrorAction SilentlyContinue) }
)
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
    # (添加 Private\Initialize-FnmEnvironment.ps1 到 $script:StartupBannerEntries,
    #  依赖闭包会自动解析并加载)。缓存命中则零子进程; 缓存失效则跑一次 fnm env
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
