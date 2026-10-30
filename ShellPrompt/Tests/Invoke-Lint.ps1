# Invoke-Lint.ps1 - PSScriptAnalyzer Warning 增量门禁
#
# 目的:
#   1. 用仓库统一的静态分析配置扫描 ShellPrompt/ (递归, 含 Tests/), 不改任何规则开关。
#   2. Error 严重级别一律阻断。
#   3. Warning 采用"基线增量"策略: 只有"新增"的 Warning 才让门禁失败;
#      历史 Warning 保持原样 (本脚本不修复任何历史诊断的源码)。
#
# 指纹设计:
#   指纹 = RuleName + 仓库相对路径 + 规范化后的 Message
#   - 不含行号: 行号会随文件改动漂移, 参与比对会造成大量误报。
#   - 路径为仓库相对路径 (由 $PSScriptRoot/../.. 推出仓库根后相对化), 跨机器/跨 runner 稳定。
#   - Message 规范化: 折叠连续空白为单个空格, 并去掉首尾空白。
#   - 同一条消息在同一文件里可能出现多次 (例如 Reset-TerminalMode.ps1 里 5 条一模一样的
#     Empty catch), 因此基线每行额外记录"期望出现次数"。
#
# 退出码:
#   0 = 通过 (无 Error, 且无新增 Warning)
#   1 = 存在 Error 严重级别
#   2 = 存在新增 Warning (指纹不在基线内, 或出现次数超过基线期望)
#   3 = 基线文件缺失或无法解析 (-UpdateBaseline 时不算失败)
#   4 = 用法/配置错误 (扫描根、静态分析配置等参数不合法) —— 0~3 之外的补充码
#   优先级: 1 > 3 > 2 (Error 最严重; 基线不可用时无法做增量比对)
#
# -UpdateBaseline 是一次显式的"认可新增 Warning"动作: 基线缺失与新增 Warning 都不算失败,
# 但 Error 严重级别仍然无条件阻断。生成结果与人工维护的格式完全一致。
#
# 用法 (pwsh 7.6+):
#   pwsh -NoProfile -File ./ShellPrompt/Tests/Invoke-Lint.ps1
#   pwsh -NoProfile -File ./ShellPrompt/Tests/Invoke-Lint.ps1 -UpdateBaseline

[CmdletBinding()]
[OutputType([void])]
param(
    # 扫描根 (相对路径按仓库根目录解析)
    [Parameter(Mandatory = $false)]
    [string]$Path = './ShellPrompt',

    # 静态分析配置
    [Parameter(Mandatory = $false)]
    [string]$SettingsPath = './ShellPrompt/Settings.ScriptAnalyzer.psd1',

    # Warning 基线文件
    [Parameter(Mandatory = $false)]
    [string]$BaselinePath = (Join-Path $PSScriptRoot 'pssa-warning-baseline.txt'),

    # 人类可读报告输出路径 (默认 $repoRoot/.agent_cache/pssa.txt)
    [Parameter(Mandatory = $false)]
    [string]$ReportPath = (Join-Path (Join-Path $PSScriptRoot '../..') '.agent_cache/pssa.txt'),

    # 重新生成基线文件 (按指纹聚合、稳定排序)
    [Parameter(Mandatory = $false)]
    [switch]$UpdateBaseline,

    # 不写退出码 (在交互会话里用 `&` 调用本脚本时, 避免 exit 结束整个会话)
    [Parameter(Mandatory = $false)]
    [switch]$NoExit
)

$ErrorActionPreference = 'Stop'

# ---- 仓库根目录: 由脚本自身位置反推, 保证不同机器/不同 runner 上一致 ----
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))

# 基线文件头 (人工维护与 -UpdateBaseline 生成必须完全一致)
$baselineHeader = @(
    '# pssa-warning-baseline.txt - PSScriptAnalyzer Warning 增量门禁基线',
    '#',
    '# 本文件由 ShellPrompt/Tests/Invoke-Lint.ps1 的 -UpdateBaseline 生成, 也可人工维护。',
    '# 指纹 = RuleName + 仓库相对路径 + 规范化消息 (不含行号: 行号会随代码改动漂移)。',
    '# 每行格式:',
    '#   # <RuleName> | <仓库相对路径> | <规范化消息> | <期望出现次数>',
    '#',
    '# 语义:',
    '#   - 指纹不在本文件中 => 新增 Warning, 门禁失败 (退出码 2)',
    '#   - 当前出现次数 > 期望次数 => 新增 Warning, 门禁失败 (退出码 2)',
    '#   - 当前出现次数 < 期望次数 => 该 Warning 已被修复, 不失败, 可收紧基线',
    '#   - Error 严重级别始终阻断 (退出码 1), 与本基线无关'
)

function Get-LintFullPath {
    <#
    .SYNOPSIS
        把输入路径解析为绝对路径 (相对路径按仓库根目录解析)。

    .DESCRIPTION
        统一路径解析入口: 绝对路径原样规范化, 相对路径按仓库根目录展开,
        保证脚本在不同工作目录下行为一致。

    .PARAMETER InputPath
        待解析的路径。

    .EXAMPLE
        Get-LintFullPath -InputPath './ShellPrompt'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$InputPath
    )

    if ([string]::IsNullOrWhiteSpace($InputPath)) {
        throw '路径参数不能为空。'
    }

    if ([System.IO.Path]::IsPathRooted($InputPath)) {
        return [System.IO.Path]::GetFullPath($InputPath)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $InputPath))
}

function Get-LintRelativePath {
    <#
    .SYNOPSIS
        把绝对路径转换为仓库相对路径 (统一使用 "/" 分隔)。

    .DESCRIPTION
        基线指纹必须跨机器稳定, 因此不能记录绝对路径。
        本函数基于仓库根目录做相对化, 并把 Windows 的 "\" 换成 "/"。

    .PARAMETER FullPath
        待相对化的绝对路径。

    .EXAMPLE
        Get-LintRelativePath -FullPath '/repo/ShellPrompt/Private/Get-SshArgs.ps1'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$FullPath
    )

    if ([string]::IsNullOrWhiteSpace($FullPath)) {
        throw '无法解析诊断的脚本路径 (ScriptPath 为空)。'
    }

    $absolute = [System.IO.Path]::GetFullPath($FullPath)
    $relative = [System.IO.Path]::GetRelativePath($repoRoot, $absolute)
    return $relative.Replace('\', '/')
}

function ConvertTo-LintNormalizedMessage {
    <#
    .SYNOPSIS
        规范化 PSSA 诊断消息 (折叠连续空白, 去掉首尾空白)。

    .DESCRIPTION
        PSSA 的消息文本在版本间可能微调, 规范化可以吸收纯排版差异;
        指纹对不上时报告会打印实际消息, 便于人工判断。

    .PARAMETER Message
        原始诊断消息。

    .EXAMPLE
        ConvertTo-LintNormalizedMessage -Message "  a   b  "
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message
    )

    $collapsed = [regex]::Replace($Message, '\s+', ' ')
    return $collapsed.Trim()
}

function Get-LintFingerprint {
    <#
    .SYNOPSIS
        组装诊断指纹 (规则 + 仓库相对路径 + 规范化消息)。

    .DESCRIPTION
        指纹是基线比对的主键, 刻意不含行号, 以免文件改动造成误报。

    .PARAMETER RuleName
        PSSA 规则名。

    .PARAMETER RelativePath
        仓库相对路径。

    .PARAMETER Message
        规范化后的消息。

    .EXAMPLE
        Get-LintFingerprint -RuleName 'PSUseSingularNouns' -RelativePath 'ShellPrompt/a.ps1' -Message 'msg'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$RuleName,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message
    )

    return '{0}|{1}|{2}' -f $RuleName.Trim(), $RelativePath.Trim(), $Message.Trim()
}

function Get-LintEntry {
    <#
    .SYNOPSIS
        把一条 PSSA 诊断折算成基线条目 (指纹 + 期望出现次数)。

    .DESCRIPTION
        同一文件里同一条消息可能出现多次, 因此按指纹聚合出现次数。

    .PARAMETER Diagnostic
        Invoke-ScriptAnalyzer 返回的诊断记录。

    .EXAMPLE
        Get-LintEntry -Diagnostic $diagnostic
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Diagnostic
    )

    $relative = Get-LintRelativePath -FullPath $Diagnostic.ScriptPath
    $message = ConvertTo-LintNormalizedMessage -Message $Diagnostic.Message
    $fingerprint = Get-LintFingerprint -RuleName $Diagnostic.RuleName -RelativePath $relative -Message $message

    return [pscustomobject]@{
        RuleName   = $Diagnostic.RuleName
        Path       = $relative
        Message    = $message
        Fingerprint = $fingerprint
        Count      = 1
    }
}

function Read-LintBaseline {
    <#
    .SYNOPSIS
        读取并解析 Warning 基线文件。

    .DESCRIPTION
        基线条目格式为 "# <RuleName> | <路径> | <消息> | <期望次数>"。
        以 "#" 开头但不符合条目格式的行按注释处理; 不以 "#" 开头的非空行视为基线损坏。

    .PARAMETER LiteralPath
        基线文件的绝对路径。

    .EXAMPLE
        Read-LintBaseline -LiteralPath '/repo/ShellPrompt/Tests/pssa-warning-baseline.txt'
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath
    )

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        throw "基线文件不存在: $LiteralPath"
    }

    $entries = @{}
    $lines = @(Get-Content -LiteralPath $LiteralPath -Encoding utf8)
    $lineNumber = 0

    foreach ($line in $lines) {
        $lineNumber++
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0) {
            continue
        }

        if (-not $trimmed.StartsWith('#')) {
            throw "基线文件第 $lineNumber 行既不是注释也不是合法条目: $trimmed"
        }

        $body = $trimmed.Substring(1).Trim()
        $parts = $body.Split('|')
        if ($parts.Count -lt 4) {
            continue
        }

        $countText = $parts[$parts.Count - 1].Trim()
        if ($countText -notmatch '^[0-9]+$') {
            continue
        }

        $ruleName = $parts[0].Trim()
        $relativePath = $parts[1].Trim()
        $message = ($parts[2..($parts.Count - 2)] -join '|').Trim()

        if ($ruleName.Length -eq 0 -or $relativePath.Length -eq 0) {
            throw "基线文件第 $lineNumber 行缺少规则名或路径: $trimmed"
        }

        $fingerprint = Get-LintFingerprint -RuleName $ruleName -RelativePath $relativePath -Message $message
        if ($entries.ContainsKey($fingerprint)) {
            $entries[$fingerprint].Count = [int]$entries[$fingerprint].Count + [int]$countText
        }
        else {
            $entries[$fingerprint] = [pscustomobject]@{
                RuleName    = $ruleName
                Path        = $relativePath
                Message     = $message
                Fingerprint = $fingerprint
                Count       = [int]$countText
            }
        }
    }

    return $entries
}

function Test-LintEntryGreater {
    <#
    .SYNOPSIS
        按 (规则名, 路径, 消息) 做序号比较, 判定左项是否需要排在右项之后。

    .DESCRIPTION
        使用序号比较而不是区域设置比较, 保证基线文件在不同语言环境下排序一致。

    .PARAMETER Left
        左侧条目。

    .PARAMETER Right
        右侧条目。

    .EXAMPLE
        Test-LintEntryGreater -Left $a -Right $b
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Left,

        [Parameter(Mandatory = $true)]
        [object]$Right
    )

    $compared = [string]::CompareOrdinal($Left.RuleName, $Right.RuleName)
    if ($compared -ne 0) {
        return ($compared -gt 0)
    }

    $compared = [string]::CompareOrdinal($Left.Path, $Right.Path)
    if ($compared -ne 0) {
        return ($compared -gt 0)
    }

    return ([string]::CompareOrdinal($Left.Message, $Right.Message) -gt 0)
}

function Get-LintOrderedEntry {
    <#
    .SYNOPSIS
        对基线条目做稳定排序 (规则名, 路径, 消息)。

    .DESCRIPTION
        -UpdateBaseline 生成的文件需要稳定、可复现, 因此使用序号比较自行排序。

    .PARAMETER Item
        待排序的条目集合。

    .EXAMPLE
        Get-LintOrderedEntry -Item $entries
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Item
    )

    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $Item) {
        $list.Add($entry)
    }

    for ($i = 0; $i -lt $list.Count; $i++) {
        for ($j = $i + 1; $j -lt $list.Count; $j++) {
            if (Test-LintEntryGreater -Left $list[$i] -Right $list[$j]) {
                $swap = $list[$i]
                $list[$i] = $list[$j]
                $list[$j] = $swap
            }
        }
    }

    return $list.ToArray()
}

function Write-LintBaselineFile {
    <#
    .SYNOPSIS
        把聚合后的 Warning 条目写成基线文件。

    .DESCRIPTION
        输出格式与人工维护的基线完全一致: 固定文件头 + 每行一个条目,
        顺序为 (规则名, 路径, 消息) 序号排序。

    .PARAMETER LiteralPath
        基线文件的绝对路径。

    .PARAMETER EntryList
        待写入的条目集合。

    .EXAMPLE
        Write-LintBaselineFile -LiteralPath '/repo/pssa-warning-baseline.txt' -EntryList $entries
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$EntryList
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($headerLine in $baselineHeader) {
        $lines.Add($headerLine)
    }

    foreach ($entry in (Get-LintOrderedEntry -Item $EntryList)) {
        $lines.Add(('# {0} | {1} | {2} | {3}' -f $entry.RuleName, $entry.Path, $entry.Message, $entry.Count))
    }

    $parentDir = [System.IO.Path]::GetDirectoryName($LiteralPath)
    if ($parentDir -and -not (Test-Path -LiteralPath $parentDir -PathType Container)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    Set-Content -LiteralPath $LiteralPath -Value $lines -Encoding utf8
}

# ---- 1. 解析参数 ----
$scanPath = Get-LintFullPath -InputPath $Path
$settingsFullPath = Get-LintFullPath -InputPath $SettingsPath
$baselineFullPath = Get-LintFullPath -InputPath $BaselinePath
$reportFullPath = Get-LintFullPath -InputPath $ReportPath

if (-not (Test-Path -LiteralPath $scanPath -PathType Container)) {
    Write-Host ("扫描根不存在: {0}" -f $scanPath) -ForegroundColor Red
    exit 4
}

if (-not (Test-Path -LiteralPath $settingsFullPath -PathType Leaf)) {
    Write-Host ("静态分析配置不存在: {0}" -f $settingsFullPath) -ForegroundColor Red
    exit 4
}

# ---- 2. 运行 PSSA ----
Import-Module PSScriptAnalyzer -ErrorAction Stop
$pssaVersion = (Get-Module -Name PSScriptAnalyzer | Select-Object -First 1).Version.ToString()
$diagnostics = @(Invoke-ScriptAnalyzer -Path $scanPath -Recurse -Settings $settingsFullPath)

# 语法错误 (ParseError) 单独再扫一遍:
# 仓库配置 Settings.ScriptAnalyzer.psd1 的 Severity 只列了 Error/Warning/Information,
# PSSA 会因此把 ParseError 诊断整条丢掉 —— 语法错误会"静默通过"。
# 这里不改配置文件, 只在调用处额外要一次 ParseError, 让语法错误同样阻断门禁。
$parseDiagnostics = @(Invoke-ScriptAnalyzer -Path $scanPath -Recurse -Settings $settingsFullPath -Severity ParseError |
    Where-Object { $_.Severity -eq 'ParseError' })

$errorDiagnostics = @($diagnostics | Where-Object { $_.Severity -eq 'Error' })
$warningDiagnostics = @($diagnostics | Where-Object { $_.Severity -eq 'Warning' })
$informationDiagnostics = @($diagnostics | Where-Object { $_.Severity -eq 'Information' })

# Error 级阻断项 = 规则诊断里的 Error + 语法错误 (ParseError)
$blockingDiagnostics = @($errorDiagnostics) + @($parseDiagnostics)

# 按指纹聚合当前 Warning
$currentEntries = @{}
foreach ($diagnostic in $warningDiagnostics) {
    $entry = Get-LintEntry -Diagnostic $diagnostic
    if ($currentEntries.ContainsKey($entry.Fingerprint)) {
        $currentEntries[$entry.Fingerprint].Count = [int]$currentEntries[$entry.Fingerprint].Count + 1
    }
    else {
        $currentEntries[$entry.Fingerprint] = $entry
    }
}

# ---- 3. 读取基线 (缺失/损坏时按退出码 3 处理) ----
$baselineEntries = @{}
$baselineProblem = $null
try {
    $baselineEntries = Read-LintBaseline -LiteralPath $baselineFullPath
}
catch {
    $baselineProblem = $_.Exception.Message
}

# ---- 4. 比对 ----
$newWarnings = [System.Collections.Generic.List[object]]::new()
$tightenableWarnings = [System.Collections.Generic.List[object]]::new()
$matchedWarnings = [System.Collections.Generic.List[object]]::new()

if ($null -eq $baselineProblem) {
    foreach ($fingerprint in $currentEntries.Keys) {
        $current = $currentEntries[$fingerprint]
        if ($baselineEntries.ContainsKey($fingerprint)) {
            $expected = [int]$baselineEntries[$fingerprint].Count
            if ([int]$current.Count -gt $expected) {
                $newWarnings.Add([pscustomobject]@{
                    RuleName    = $current.RuleName
                    Path        = $current.Path
                    Message     = $current.Message
                    Expected    = $expected
                    Actual      = [int]$current.Count
                    Delta       = [int]$current.Count - $expected
                    Fingerprint = $fingerprint
                })
            }
            elseif ([int]$current.Count -lt $expected) {
                $tightenableWarnings.Add([pscustomobject]@{
                    RuleName    = $current.RuleName
                    Path        = $current.Path
                    Message     = $current.Message
                    Expected    = $expected
                    Actual      = [int]$current.Count
                    Delta       = [int]$current.Count - $expected
                    Fingerprint = $fingerprint
                })
            }
            else {
                $matchedWarnings.Add([pscustomobject]@{
                    RuleName    = $current.RuleName
                    Path        = $current.Path
                    Message     = $current.Message
                    Expected    = $expected
                    Actual      = [int]$current.Count
                    Delta       = 0
                    Fingerprint = $fingerprint
                })
            }
        }
        else {
            $newWarnings.Add([pscustomobject]@{
                RuleName    = $current.RuleName
                Path        = $current.Path
                Message     = $current.Message
                Expected    = 0
                Actual      = [int]$current.Count
                Delta       = [int]$current.Count
                Fingerprint = $fingerprint
            })
        }
    }

    # 基线里有、当前已经不再出现的条目 => Warning 已被修复, 可收紧基线
    foreach ($fingerprint in $baselineEntries.Keys) {
        if ($currentEntries.ContainsKey($fingerprint)) {
            continue
        }
        $baselineEntry = $baselineEntries[$fingerprint]
        $tightenableWarnings.Add([pscustomobject]@{
            RuleName    = $baselineEntry.RuleName
            Path        = $baselineEntry.Path
            Message     = $baselineEntry.Message
            Expected    = [int]$baselineEntry.Count
            Actual      = 0
            Delta       = -([int]$baselineEntry.Count)
            Fingerprint = $fingerprint
        })
    }
}

# ---- 5. 退出码 ----
# -UpdateBaseline 是一次显式的"认可新增 Warning"动作: 基线不可用与新增 Warning 都不算失败;
# 但 Error 严重级别仍然无条件阻断 (退出码 1)。
$exitCode = 0
if ($blockingDiagnostics.Count -gt 0) {
    $exitCode = 1
}
elseif (-not $UpdateBaseline) {
    if ($null -ne $baselineProblem) {
        $exitCode = 3
    }
    elseif ($newWarnings.Count -gt 0) {
        $exitCode = 2
    }
}

# ---- 6. 生成报告 ----
$report = [System.Collections.Generic.List[string]]::new()
$report.Add('PSScriptAnalyzer 增量门禁报告')
$report.Add(('=' * 72))
$report.Add(('生成时间   : {0}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))
$report.Add(('仓库根目录 : {0}' -f $repoRoot))
$report.Add(('扫描根     : {0}' -f (Get-LintRelativePath -FullPath $scanPath)))
$report.Add(('分析配置   : {0}' -f (Get-LintRelativePath -FullPath $settingsFullPath)))
$report.Add(('基线文件   : {0}' -f (Get-LintRelativePath -FullPath $baselineFullPath)))
$report.Add(('PSSA 版本  : {0}' -f $pssaVersion))
$report.Add(('运行模式   : {0}' -f $(if ($UpdateBaseline) { '更新基线 (-UpdateBaseline)' } else { '基线增量检查' })))
$report.Add(('诊断统计   : Error = {0} (含语法错误 {1}) / Warning = {2} (聚合后 {3} 条指纹) / Information = {4}' -f `
        $errorDiagnostics.Count, $parseDiagnostics.Count, $warningDiagnostics.Count, $currentEntries.Count, $informationDiagnostics.Count))
$report.Add(('-' * 72))

$report.Add('[Error] (严重级别, 一律阻断)')
if ($errorDiagnostics.Count -eq 0) {
    $report.Add('  (无)')
}
else {
    foreach ($diagnostic in $errorDiagnostics) {
        $report.Add(('  - {0} | {1} | L{2} | {3}' -f $diagnostic.RuleName, `
                (Get-LintRelativePath -FullPath $diagnostic.ScriptPath), $diagnostic.Line, $diagnostic.Message))
    }
}

$report.Add('')
if ($UpdateBaseline) {
    $report.Add('[新增 Warning] (不在基线内, 或出现次数超过基线期望 —— 本次将被写入新基线)')
}
else {
    $report.Add('[新增 Warning] (不在基线内, 或出现次数超过基线期望 —— 门禁失败)')
}
if ($null -ne $baselineProblem) {
    $report.Add('  (基线不可用, 无法比对)')
}
elseif ($newWarnings.Count -eq 0) {
    $report.Add('  (无)')
}
else {
    foreach ($item in $newWarnings) {
        $report.Add(('  - {0} | {1}' -f $item.RuleName, $item.Path))
        $report.Add(('      消息   : {0}' -f $item.Message))
        $report.Add(('      基线次数: {0} / 当前次数: {1} (超出 {2})' -f $item.Expected, $item.Actual, $item.Delta))
        $report.Add(('      指纹   : {0}' -f $item.Fingerprint))
    }
}

$report.Add('')
$report.Add('[可收紧基线] (当前出现次数少于基线期望 —— 不阻断, 建议用 -UpdateBaseline 收紧)')
if ($null -ne $baselineProblem) {
    $report.Add('  (基线不可用, 无法比对)')
}
elseif ($tightenableWarnings.Count -eq 0) {
    $report.Add('  (无)')
}
else {
    foreach ($item in $tightenableWarnings) {
        $report.Add(('  - {0} | {1}' -f $item.RuleName, $item.Path))
        $report.Add(('      消息   : {0}' -f $item.Message))
        $report.Add(('      基线次数: {0} / 当前次数: {1} (减少 {2})' -f $item.Expected, $item.Actual, (-$item.Delta)))
        $report.Add(('      指纹   : {0}' -f $item.Fingerprint))
    }
}

$report.Add('')
$report.Add('[基线一致] (与基线完全匹配)')
if ($null -ne $baselineProblem) {
    $report.Add('  (基线不可用, 无法比对)')
}
elseif ($matchedWarnings.Count -eq 0) {
    $report.Add('  (无)')
}
else {
    foreach ($item in $matchedWarnings) {
        $report.Add(('  - {0} | {1} | 基线 {1} 次 / 当前 {2} 次' -f $item.RuleName, $item.Path, $item.Actual))
        $report.Add(('      消息   : {0}' -f $item.Message))
    }
}

$report.Add('')
$report.Add(('-' * 72))
switch ($exitCode) {
    0 {
        if ($UpdateBaseline) {
            $report.Add('退出码: 0 —— 基线更新模式 (无 Error; 新增 Warning 将写入新基线)')
        }
        else {
            $report.Add('退出码: 0 —— 通过 (无 Error, 无新增 Warning)')
        }
    }
    1 { $report.Add('退出码: 1 —— 存在 Error 严重级别, 门禁阻断') }
    2 { $report.Add('退出码: 2 —— 存在新增 Warning, 门禁阻断') }
    3 { $report.Add(('退出码: 3 —— 基线不可用: {0}' -f $baselineProblem)) }
    default { $report.Add(('退出码: {0} —— 用法/配置错误' -f $exitCode)) }
}

$reportParent = [System.IO.Path]::GetDirectoryName($reportFullPath)
if ($reportParent -and -not (Test-Path -LiteralPath $reportParent -PathType Container)) {
    New-Item -ItemType Directory -Path $reportParent -Force | Out-Null
}
Set-Content -LiteralPath $reportFullPath -Value $report -Encoding utf8

# ---- 7. 控制台摘要 ----
Write-Host ''
Write-Host ('=' * 72) -ForegroundColor DarkGray
Write-Host ('PSSA 诊断: Error {0} / Warning {1} (聚合后 {2} 条指纹) / Information {3}' -f `
        $errorDiagnostics.Count, $warningDiagnostics.Count, $currentEntries.Count, $informationDiagnostics.Count) -ForegroundColor DarkGray
Write-Host ('报告: {0}' -f $reportFullPath) -ForegroundColor DarkGray

if ($errorDiagnostics.Count -gt 0) {
    Write-Host ''
    Write-Host ('Error ({0}) —— 一律阻断:' -f $errorDiagnostics.Count) -ForegroundColor Red
    foreach ($diagnostic in $errorDiagnostics) {
        Write-Host ('  - {0} | {1} | L{2}' -f $diagnostic.RuleName, `
                (Get-LintRelativePath -FullPath $diagnostic.ScriptPath), $diagnostic.Line) -ForegroundColor Red
        Write-Host ('      {0}' -f $diagnostic.Message) -ForegroundColor Red
    }
}

if ($null -ne $baselineProblem) {
    Write-Host ''
    Write-Host ('基线不可用: {0}' -f $baselineProblem) -ForegroundColor Red
    Write-Host '提示: 首次使用请执行 pwsh -NoProfile -File ./ShellPrompt/Tests/Invoke-Lint.ps1 -UpdateBaseline' -ForegroundColor Red
}

if ($newWarnings.Count -gt 0) {
    Write-Host ''
    if ($UpdateBaseline) {
        Write-Host ('新增 Warning ({0}) —— 将写入新基线:' -f $newWarnings.Count) -ForegroundColor Yellow
    }
    else {
        Write-Host ('新增 Warning ({0}) —— 门禁阻断:' -f $newWarnings.Count) -ForegroundColor Red
    }
    foreach ($item in $newWarnings) {
        Write-Host ('  - {0} | {1}' -f $item.RuleName, $item.Path) -ForegroundColor Red
        Write-Host ('      消息   : {0}' -f $item.Message) -ForegroundColor Red
        Write-Host ('      基线次数: {0} / 当前次数: {1} (超出 {2})' -f $item.Expected, $item.Actual, $item.Delta) -ForegroundColor Red
    }
}

if ($tightenableWarnings.Count -gt 0) {
    Write-Host ''
    Write-Host ('可收紧基线 ({0}) —— 不阻断, 建议执行 -UpdateBaseline 收紧:' -f $tightenableWarnings.Count) -ForegroundColor Yellow
    foreach ($item in $tightenableWarnings) {
        Write-Host ('  - {0} | {1}' -f $item.RuleName, $item.Path) -ForegroundColor Yellow
        Write-Host ('      消息   : {0}' -f $item.Message) -ForegroundColor Yellow
        Write-Host ('      基线次数: {0} / 当前次数: {1}' -f $item.Expected, $item.Actual) -ForegroundColor Yellow
    }
}

if ($exitCode -eq 0) {
    Write-Host ''
    if ($UpdateBaseline) {
        Write-Host '结果: 通过 —— 基线更新模式 (无 Error)' -ForegroundColor Green
    }
    else {
        Write-Host '结果: 通过 —— 无 Error, 无新增 Warning' -ForegroundColor Green
    }
}
else {
    Write-Host ''
    Write-Host ('结果: 失败 —— 退出码 {0}' -f $exitCode) -ForegroundColor Red
}
Write-Host ('=' * 72) -ForegroundColor DarkGray

# ---- 8. -UpdateBaseline: 重写基线 ----
if ($UpdateBaseline) {
    $allCurrent = @($currentEntries.Values)
    Write-LintBaselineFile -LiteralPath $baselineFullPath -EntryList $allCurrent
    Write-Host ''
    Write-Host ('基线已更新: {0} (共 {1} 条指纹)' -f $baselineFullPath, $allCurrent.Count) -ForegroundColor Green
    Write-Host '提示: 基线文件已按当前 PSSA 结果重写, 请人工确认后再提交。' -ForegroundColor Yellow
}

if (-not $NoExit) {
    exit $exitCode
}
