# Initialize-FnmEnvironment.ps1 - fnm 环境初始化(缓存加速)
#
# 设计目标: 把 `fnm env --use-on-cd --shell powershell` 子进程(~60~130ms)从
# 启动关键路径上移走, 同时**不丢失** fnm 提供的任何能力:
#   - FNM_MULTISHELL_PATH / FNM_DIR / FNM_VERSION_FILE_STRATEGY 等环境变量
#   - Set-FnmOnLoad / Set-LocationWithFnm 函数
#   - `cd` 别名(进入含 .nvmrc / .node-version / package.json 的目录时自动切换 node 版本)
#
# 实现: 首次(或 fnm 可执行文件变化 / 已安装 node 版本列表变化后)跑一次 fnm env,
# 把其中**与 PATH 无关**的部分缓存到 %LOCALAPPDATA%\ShellPrompt\fnm-env.json;
# 之后启动只读缓存 + 本地重算 PATH。
#
# 为什么 PATH 不能直接缓存:
#   fnm env 输出的是 `$env:PATH = "..."` —— 一份**完整 PATH 快照**。直接缓存并回放
#   会把用户启动后对 PATH 的任何修改(临时 prepend、工具自注入)全部覆盖掉, 属于
#   静默破坏用户环境的行为, 绝对不能做。
#   因此缓存只保留 fnm 自己的注入规则, PATH 在运行时基于**当前** $env:PATH 重算。
#
# 缓存失效判定: fnm 可执行文件的 (LastWriteTimeUtc.Ticks, Length) + 已安装 node 版本列表
#   - fnm 升级后 fnm 可执行文件必然变化, 触发失配重建
#   - `fnm install` / `fnm uninstall` 后 node 版本列表变化, 触发失配重建
#   - 不需要额外 `fnm --version` 子进程(那会抵消优化收益)
#
# 保底: 若无法确定 aliases 目录(例如 fnm 换了目录布局), 直接回退到执行
# `fnm env` 子进程, 保证 node/npm 一定可用 —— 正确性优先于速度。

function Initialize-FnmEnvironment {
    <#
    .SYNOPSIS
        初始化 fnm 管理的 node 环境(优先走缓存, 避免启动期子进程)

    .DESCRIPTION
        读取 %LOCALAPPDATA%\ShellPrompt\fnm-env.json 缓存中的 fnm 环境定义并本地重算
        PATH 注入; 缓存缺失或失效时重新生成(仅此一次会调用 fnm 子进程)。

    .OUTPUTS
        [bool] 是否成功完成初始化
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingEmptyCatchBlock', '', Justification = '缓存读取/写入失败时静默回退到子进程保底路径, 正确性优先于可见告警')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = '启动期 profile 同步路径调用, 不应交互式确认')]
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $fnmCmd = Get-Command -Name 'fnm.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $fnmCmd) { return $false }

    $fnmExe = $fnmCmd.Source
    $exeInfo = Get-Item -LiteralPath $fnmExe -ErrorAction SilentlyContinue
    if (-not $exeInfo) { return $false }

    # 缓存键基础部分: fnm 可执行文件指纹 + 目标 shell
    $baseKey = "fnm|$($exeInfo.LastWriteTimeUtc.Ticks)|$($exeInfo.Length)|powershell"

    $cacheKey = $baseKey
    $cacheDir = Join-Path $env:LOCALAPPDATA 'ShellPrompt'
    $cachePath = Join-Path $cacheDir 'fnm-env.json'

    # 命中校验环节: 拼接已持久化的 NodeVersions 形成 key', 实现"用户 install/uninstall 后
    # 自动失效"语义。注意: 启动期**不**主动跑 fnm ls(那会增加子进程开销);
    # 这里读上一轮缓存时已经持久化的 NodeVersions, 命中即复用、未命中即重建。
    try {
        if (Test-Path -LiteralPath $cachePath -PathType Leaf) {
            $raw = [System.IO.File]::ReadAllText($cachePath)
            $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
            if ($parsed.NodeVersions) { $cacheKey = "$baseKey|ns=$($parsed.NodeVersions)" }
        }
    } catch {
        # 缓存结构损坏 -> 落入下方全量重建分支
    }

    $cache = $null
    try {
        if (Test-Path -LiteralPath $cachePath -PathType Leaf) {
            $raw = [System.IO.File]::ReadAllText($cachePath)
            $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
            if ($parsed.Key -eq $cacheKey) { $cache = $parsed }
        }
    } catch {
        # 缓存损坏 -> 重建 (在本函数末尾走 New-FnmEnvironmentCache)
    }

    if (-not $cache) {
        $cache = New-FnmEnvironmentCache -CacheKey $cacheKey
        if (-not $cache) { return $false }
        try {
            if (-not (Test-Path -LiteralPath $cacheDir -PathType Container)) {
                [System.IO.Directory]::CreateDirectory($cacheDir) | Out-Null
            }
            # 原子写: 先写临时文件再覆盖, 避免并发启动读到半截 JSON
            $tmp = "$cachePath.$PID.tmp"
            [System.IO.File]::WriteAllText($tmp, ($cache | ConvertTo-Json -Depth 4 -Compress), [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::Copy($tmp, $cachePath, $true)
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        } catch {
            # 缓存不可写不影响本次启动 —— 内存中的 $cache 仍然可用
        }
    }

    return (Set-FnmEnvironmentFromCache -Cache $cache)
}

function New-FnmEnvironmentCache {
    <#
    .SYNOPSIS
        调用一次 `fnm env` 子进程, 抽取可缓存部分并组装缓存对象

    .OUTPUTS
        [PSCustomObject] 缓存对象(失败时为 $null)
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingEmptyCatchBlock', '', Justification = 'fnm 子进程失败时静默返回 $null, 让上层回退到完整 fnm env 子进程路径')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = '纯子进程读取 + JSON 组装, 无外部可观察状态变更')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '', Justification = 'Invoke-Expression 是 fnm env --shell powershell 输出格式的必要消费方式, 不存在等价方案')]
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CacheKey
    )

    $raw = $null
    try {
        $raw = (& fnm env --use-on-cd --shell powershell) -join "`n"
    } catch {
        return $null
    }
    if (-not $raw) { return $null }

    $envLines = [System.Collections.Generic.List[string]]::new()
    $aliasDir = $null

    foreach ($line in ($raw -split "`r?`n")) {
        if (-not $line.Trim()) { continue }

        # PATH 行单独处理: 只从中提取 fnm 的 aliases 目录, 绝不缓存整份 PATH 快照
        if ($line -match '^\s*\$env:PATH\s*=') {
            $value = ($line -replace '^\s*\$env:PATH\s*=\s*', '').Trim().Trim('"')
            foreach ($entry in ($value -split ';')) {
                if ($entry -match 'fnm[\\/]aliases') { $aliasDir = $entry }
            }
            continue
        }

        # FNM_MULTISHELL_PATH 是**每个会话唯一**的目录, 由运行时生成, 不缓存
        if ($line -match '^\s*\$env:FNM_MULTISHELL_PATH\s*=') { continue }

        $envLines.Add($line) | Out-Null
    }

    # 已安装 node 版本列表作为缓存键一部分。fnm ls 文本形态跨版本较稳定;
    # 解析失败时回退到空字符串(此时仅 fnm 可执行文件变化触发失效)。
    $nodeVersions = @()
    try {
        $nodeVersions = @((& fnm ls) -join "`n" | Select-String -Pattern '^\s*\*\s*v(\d+\.\d+\.\d+)\s*$' -ErrorAction SilentlyContinue |
            ForEach-Object { ($_.Matches[0].Groups[1].Value) })
    } catch { }
    if ($nodeVersions.Count -eq 0) {
        try {
            $nodeVersions = @((& fnm ls) -join "`n" | Select-String -Pattern 'v(\d+\.\d+\.\d+)' -AllMatches -ErrorAction SilentlyContinue |
                ForEach-Object { $_.Matches[0].Groups[1].Value } | Sort-Object -Unique)
        } catch { }
    }
    $nodeVersionsJoined = ($nodeVersions | Sort-Object) -join ','

    return [PSCustomObject]@{
        # 写入磁盘的 Key 字段 = 基础键 + 当前 node 版本指纹: 这样下次启动时
        # Initialize-FnmEnvironment 用同一规则构造 cacheKey, 双方口径一致;
        # 用户 install/uninstall 后 node 列表变化 -> 失配 -> 自动重建。
        Key          = "$CacheKey|ns=$nodeVersionsJoined"
        Env          = ($envLines -join "`n")
        AliasDir     = $aliasDir
        NodeVersions = $nodeVersionsJoined
    }
}

function Set-FnmEnvironmentFromCache {
    <#
    .SYNOPSIS
        应用缓存: 设置 FNM_* 环境变量、函数与别名, 并基于当前 PATH 重算 fnm 注入

    .OUTPUTS
        [bool] 是否成功应用
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingEmptyCatchBlock', '', Justification = 'fnm env 回放失败时静默回退保底路径, 正确性优先于可见告警')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '', Justification = 'Invoke-Expression 是回放缓存中 fnm env --shell powershell 输出的必要方式, 不存在等价方案')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = '启动期 profile 同步路径调用, 不应交互式确认')]
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        $Cache
    )

    # 每个会话独立的 multishell 目录(命名规则与 fnm 一致: <pid>_<unix-ms>)
    $multishell = Join-Path $env:LOCALAPPDATA (
        "fnm_multishells\{0}_{1}" -f $PID, [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
    $env:FNM_MULTISHELL_PATH = $multishell

    # 先回放 FNM_* 变量 / 函数 / 别名定义(FNM_DIR 在其中, 供后续解析 aliases 目录)
    if ($Cache.Env) {
        try {
            Invoke-Expression $Cache.Env
        } catch {
            # 回放失败 -> 走保底路径
            return (Set-FnmEnvironmentByFallback)
        }
    }

    # 解析 aliases 目录: 优先用缓存记录, 其次用 $env:FNM_DIR 推导
    $aliasDir = $Cache.AliasDir
    if (-not $aliasDir -or -not (Test-Path -LiteralPath $aliasDir -PathType Container)) {
        if ($env:FNM_DIR) {
            $candidate = Join-Path $env:FNM_DIR 'aliases\default'
            if (Test-Path -LiteralPath $candidate -PathType Container) { $aliasDir = $candidate }
        }
    }
    if (-not $aliasDir -or -not (Test-Path -LiteralPath $aliasDir -PathType Container)) {
        # 无法确定 -> 保底执行子进程, 保证 node 一定可用
        return (Set-FnmEnvironmentByFallback)
    }

    # 基于**当前** PATH 重算: 去掉历史 fnm 注入, 再前置新的 multishell 目录
    $kept = @(
        $env:PATH -split ';' | Where-Object {
            $_ -and $_ -notmatch 'fnm[\\/]multishells' -and $_ -notmatch 'fnm[\\/]aliases'
        }
    )
    $env:PATH = (@($multishell) + $kept + @($aliasDir)) -join ';'

    return $true
}

function Set-FnmEnvironmentByFallback {
    <#
    .SYNOPSIS
        保底路径: 直接执行 `fnm env` 子进程(正确性优先)

    .OUTPUTS
        [bool] 是否成功
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingEmptyCatchBlock', '', Justification = 'fnm 子进程失败时静默返回 $false, 由 profile 自身决定是否启动回退')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '', Justification = 'Invoke-Expression 是 fnm env --shell powershell 输出格式的必要消费方式, 不存在等价方案')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = '启动期 profile 同步路径调用, 不应交互式确认')]
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $raw = (& fnm env --use-on-cd --shell powershell) -join "`n"
        if ($raw) {
            Invoke-Expression $raw
            return $true
        }
    } catch {
        # 忽略: 保持现状, 不影响 shell 启动
    }
    return $false
}
