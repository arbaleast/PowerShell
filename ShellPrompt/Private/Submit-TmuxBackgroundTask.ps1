# Submit-TmuxBackgroundTask.ps1 - 后台线程任务的提交端(异步数据获取的基础设施)
# 职责: 把一段"取数据"的脚本块丢到后台线程执行, 立即返回任务句柄。
#
# 为什么需要(2026-10-30 TUI 重构 · 异步非阻塞):
#   天气拉取(wttr.in, 单次 HTTP 超时 5s)与 SSH 探测(连接超时 5s + 10s 等待)是两次
#   **串行**的网络往返, 两者都发生在菜单渲染之前 —— 首屏被网络延迟直接卡住。
#   把它们放到后台线程后, 两者可以并行, 主线程只在需要结果的那一刻收割。
#
# 为什么用线程作业而不是普通作业:
#   Start-Job 会拉起**新进程**(PowerShell 7 起是 pwsh), 启动开销 300ms~1s,
#   还要重新加载模块上下文; Start-ThreadJob 只是新 runspace, 同进程, 启动开销 ~50ms。
#
# 关键约束(必须显式处理):
#   线程作业运行在**独立 runspace**, 拿不到模块作用域里的私有函数。
#   因此调用方必须用 -DependencyFile 列出需要 dot-source 的 Private 文件;
#   依赖缺失时本函数直接抛错, 由调用方退回同步路径(不静默降级成"空数据")。

function Submit-TmuxBackgroundTask {
    <#
    .SYNOPSIS
        在后台线程执行一段脚本块, 返回任务句柄。

    .DESCRIPTION
        用 Start-ThreadJob 提交任务:
          - -DependencyFile 里的文件会先在作业 runspace 内 dot-source,
            从而让作业能调用模块的私有函数(如 Get-TmuxSessions);
          - -Argument 以**单个**哈希表传给脚本块的第一个位置参数。

        依赖文件不存在时抛错(不静默忽略), 调用方据此退回同步路径。

    .PARAMETER ScriptBlock
        要在后台执行的脚本块, 第一个参数接收 -Argument 哈希表

    .PARAMETER DependencyFile
        需要在作业 runspace 内 dot-source 的 Private 文件名数组(相对 Private 目录)

    .PARAMETER Argument
        传给脚本块的参数哈希表

    .PARAMETER Name
        任务名(用于日志与诊断)

    .OUTPUTS
        任务句柄 PSCustomObject(.Task = 作业对象, .Name = 任务名); 提交失败时抛异常

    .EXAMPLE
        $task = Submit-TmuxBackgroundTask -ScriptBlock { param($a) Get-TmuxSessions -HostName $a.HostName } `
            -Argument @{ HostName = 'debian' } -DependencyFile @('Get-TmuxSessions.ps1')
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$DependencyFile = @(),

        [Parameter(Mandatory = $false)]
        [hashtable]$Argument = @{},

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Name = ''
    )

    $privateDir = $script:ShellPromptPrivateDir
    if ([string]::IsNullOrWhiteSpace($privateDir)) {
        throw '后台任务依赖解析失败: $script:ShellPromptPrivateDir 未初始化(模块未按预期加载)。'
    }

    # 依赖文件解析: 相对 Private 目录的文件名 -> 绝对路径; 缺失即抛错
    $initLines = [System.Collections.Generic.List[string]]::new()
    $initLines.Add('$ErrorActionPreference = ''Stop''') | Out-Null

    foreach ($depName in @($DependencyFile)) {
        $path = Join-Path -Path $privateDir -ChildPath $depName
        if (-not (Test-Path -Path $path)) {
            throw "后台任务依赖文件不存在: $depName ($path)"
        }
        # 单引号转义: 路径里的单引号会破坏 dot-source 语句
        $escaped = $path.Replace("'", "''")
        $initLines.Add((". '{0}'" -f $escaped)) | Out-Null
    }

    $initScript = [scriptblock]::Create(($initLines -join "`n"))

    $job = Start-ThreadJob -InitializationScript $initScript -ScriptBlock $ScriptBlock -ArgumentList $Argument

    # 句柄用 PSCustomObject 包一层: 作业对象的运行时类型随 ThreadJob 版本浮动,
    # 不适合写进 [OutputType]; 包一层后契约稳定(Task/Name 两个字段)。
    return [PSCustomObject]@{
        Task = $job
        Name = $Name
    }
}
