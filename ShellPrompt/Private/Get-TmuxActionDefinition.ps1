# Get-TmuxActionDefinition.ps1 - tmux 管理器的全局动作定义(键位 -> 动作)
# 职责: 动作集合的**单一事实来源**, 同时驱动两处渲染/分发:
#   - Format-TmuxToolbarText : 渲染单行工具条/状态栏文案([n]新建  [r]刷新 ...);
#   - Resolve-TmuxActionKey   : 把用户按下的单字母键映射成动作值。
#
# 背景(2026-10-30 TUI 重构): 原"全局操作菜单"是**第二个表格面板**, 与会话列表上下重复
#   渲染, 屏幕信息密度过高; 且只能靠方向键 + Enter 触发, 高频操作路径长。
#   现降级为"单行状态栏 + 单键直达", 本文件即那套键位契约的落点。
#
# 不变量:
#   - 键位与动作值的映射是**数据**, 不是散落在 if/else 里的分支; 新增动作只改本文件。
#   - Context 只影响**文案**(刷新/重试、SSH/直连), 键位本身不变 —— 用户肌肉记忆不因状态切换而失效。
#   - RequiresSessions 标记依赖"当前存在会话"的动作(附着/删除), 无会话时不暴露, 避免死键。

function Get-TmuxActionDefinition {
    <#
    .SYNOPSIS
        返回 tmux 管理器的动作定义集合(键位 / 文案 / 动作值)。

    .DESCRIPTION
        动作集合是"工具条文案"与"单键事件循环"的唯一事实来源:
          - Format-TmuxToolbarText 用它渲染 `[n]新建  [r]刷新  [s]SSH ...` 单行文本;
          - Resolve-TmuxActionKey 用它把按下的单字母键映射成动作值。

        上下文(Context)只切换文案, 不切换键位:
          - Normal: 正常态(r=刷新, s=SSH)
          - Error : 降级态(r=重试, s=直连)

        键位表:
            a -> Attach  附着(需要存在会话)
            n -> New     新建
            r -> Refresh 刷新 / 重试
            s -> Ssh     SSH / 直连
            x -> Remove  删除(需要存在会话, 高危, 二次确认在 Remove-TmuxSession 内)
            q -> Quit    退出管理器

    .PARAMETER HasSessions
        当前是否存在 tmux 会话。为 $false 时不暴露"附着/删除"两个动作。

    .PARAMETER Context
        渲染上下文: Normal(默认) / Error(失败降级态)

    .OUTPUTS
        PSCustomObject 数组(.Key/.Label/.Value/.RequiresSessions)

    .EXAMPLE
        Get-TmuxActionDefinition -HasSessions $true -Context 'Normal'
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [bool]$HasSessions = $false,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Normal', 'Error')]
        [string]$Context = 'Normal'
    )

    # 键位 -> 动作的固定表; Label 按上下文二选一(键位与动作值恒定)
    $table = @(
        [PSCustomObject]@{ Key = 'a'; Value = 'Attach';  Normal = '附着'; Error = '附着'; RequiresSessions = $true }
        [PSCustomObject]@{ Key = 'n'; Value = 'New';     Normal = '新建'; Error = '新建'; RequiresSessions = $false }
        [PSCustomObject]@{ Key = 'r'; Value = 'Refresh'; Normal = '刷新'; Error = '重试'; RequiresSessions = $false }
        [PSCustomObject]@{ Key = 's'; Value = 'Ssh';     Normal = 'SSH';  Error = '直连'; RequiresSessions = $false }
        [PSCustomObject]@{ Key = 'x'; Value = 'Remove';  Normal = '删除'; Error = '删除'; RequiresSessions = $true }
        [PSCustomObject]@{ Key = 'q'; Value = 'Quit';    Normal = '退出'; Error = '退出'; RequiresSessions = $false }
    )

    $result = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($item in $table) {
        # 无会话时不暴露依赖会话的动作(附着/删除), 避免出现点了没反应的死键
        if ($item.RequiresSessions -and -not $HasSessions) { continue }
        $label = if ($Context -eq 'Error') { $item.Error } else { $item.Normal }
        $result.Add([PSCustomObject]@{
                Key              = $item.Key
                Label            = $label
                Value            = $item.Value
                RequiresSessions = $item.RequiresSessions
            })
    }

    return $result.ToArray()
}
