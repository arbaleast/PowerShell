# Get-TmuxRefreshedSession.ps1 - 用户触发的会话列表刷新
# 职责: 执行刷新脚本块并把结果归一化为会话数组(过滤 $null, 保证调用方可直接 .Count);
#       附带刷新前后行序稳定的合并函数 Merge-TmuxSessionOrder(见文件末尾)。
# 注意: 刷新脚本块抛出的异常原样向上传播, "失败后保留原列表"的恢复策略
#       由列表层 Show-TmuxSessionList 决定(本函数没有"原列表"这个上下文)。

function Get-TmuxRefreshedSession {
    <#
    .SYNOPSIS
        执行刷新脚本块, 返回归一化后的会话数组。

    .DESCRIPTION
        刷新语义完全由用户触发(菜单中的"⟳ 刷新会话列表"项), 不引入定时器或后台轮询。
        归一化规则: 过滤掉 $null 元素并包装成数组, 避免调用方拿到 @($null) 这类
        "看起来有一个元素"的结果, 也避免空结果被 PowerShell 展开成 $null。

    .PARAMETER SessionRefresher
        刷新脚本块, 返回新的会话数组(Get-TmuxSessions 的 .Sessions)

    .OUTPUTS
        会话数组(可能为空数组)

    .EXAMPLE
        $sessions = Get-TmuxRefreshedSession -SessionRefresher $refresher
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$SessionRefresher
    )

    $refreshed = & $SessionRefresher
    if (-not $refreshed) {
        return , @()
    }
    return , @($refreshed | Where-Object { $null -ne $_ })
}

function Merge-TmuxSessionOrder {
    <#
    .SYNOPSIS
        把刷新后的会话列表按上一次展示的顺序重排, 保证"行位置 ↔ 会话"稳定。

    .DESCRIPTION
        背景(2026-10-29 审计): PSTui Out-ConsoleGridView 没有"预选行/初始选中行"参数,
        刷新后重新弹窗时光标固定回到第一行。若刷新结果的顺序与上一次展示不同,
        同一行位置会指向另一个会话, 用户肌肉记忆式的 Enter 可能附着/删除错误目标。
        合并规则:
          - 仍在列表中的会话按上一次展示的相对顺序排列(精确按 Name 匹配, 区分大小写);
          - 上一次展示过、但已消失的会话直接丢弃(由调用方负责警告);
          - 刷新结果里的新会话按其原始顺序追加到末尾。
        注意: 本函数只稳定"行 ↔ 会话"的映射, 不会也不能恢复光标位置
        (GridView 能力边界, 光标刷新后仍回到第一行)。

    .PARAMETER Previous
        上一次展示的会话数组(元素含 Name)

    .PARAMETER Refreshed
        刷新获取到的会话数组(元素含 Name, 已由调用方过滤 $null)

    .OUTPUTS
        重排后的会话数组(object[], 可能为空数组)

    .EXAMPLE
        $current = Merge-TmuxSessionOrder -Previous $old -Refreshed $new
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [object[]]$Previous,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [object[]]$Refreshed
    )

    # 剩余候选: 用 List 承载以便"取走"已匹配元素, 空结果时 .Count 依然可靠
    $remaining = [System.Collections.Generic.List[object]]::new()
    foreach ($s in $Refreshed) {
        if ($null -ne $s) { $remaining.Add($s) }
    }

    $ordered = [System.Collections.Generic.List[object]]::new()
    foreach ($prev in $Previous) {
        if ($null -eq $prev) { continue }
        $prevName = [string]$prev.Name
        $hit = $null
        foreach ($candidate in $remaining) {
            # -ceq 精确匹配: 会话名是身份标识, 不做大小写折叠
            if ([string]$candidate.Name -ceq $prevName) { $hit = $candidate; break }
        }
        if ($null -ne $hit) {
            $ordered.Add($hit)
            [void]$remaining.Remove($hit)
        }
    }

    # 新会话(上一次列表里没有的)按刷新结果顺序追加到末尾
    foreach ($s in $remaining) { $ordered.Add($s) }

    return , $ordered.ToArray()
}
