# Resolve-TmuxActionKey.ps1 - 单键 -> 动作值 的映射(纯函数)
# 职责: 把用户按下的一个键(通常是单字母)解析成动作值, 供事件循环分发。
# 契约:
#   - 只认 Get-TmuxActionDefinition 里登记的键位; 其余一律返回空串(未命中)。
#   - 无会话时不解析"附着/删除"(与工具条隐藏保持一致, 避免界面与行为不一致)。
#   - 纯函数: 不读配置、不读会话、不产生副作用 —— 因此可以被 Pester 独立覆盖。

function Resolve-TmuxActionKey {
    <#
    .SYNOPSIS
        把单键解析为 tmux 管理器动作值。

    .DESCRIPTION
        输入一个按键(单字母, 大小写不敏感), 输出对应动作值:
            a -> Attach   n -> New   r -> Refresh   s -> Ssh   x -> Remove   q -> Quit
        未登记的键返回空串; 无会话时"附着/删除"同样返回空串。

    .PARAMETER Key
        按下的键(单字母)。允许空串 —— 返回空串。

    .PARAMETER HasSessions
        当前是否存在 tmux 会话。为 $false 时不解析依赖会话的动作。

    .PARAMETER Context
        渲染上下文: Normal(默认) / Error。只影响文案, 不影响键位解析结果。

    .OUTPUTS
        [string] 动作值(Attach/New/Refresh/Ssh/Remove/Quit); 未命中时为空串

    .EXAMPLE
        Resolve-TmuxActionKey -Key 'n' -HasSessions $true
        # -> New
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Key = '',

        [Parameter(Mandatory = $false)]
        [bool]$HasSessions = $false,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Normal', 'Error')]
        [string]$Context = 'Normal'
    )

    if ([string]::IsNullOrWhiteSpace($Key)) { return '' }

    $normalized = $Key.Trim().ToLowerInvariant()
    $definitions = @(Get-TmuxActionDefinition -HasSessions $HasSessions -Context $Context)

    foreach ($definition in $definitions) {
        if ($definition.Key -eq $normalized) {
            return [string]$definition.Value
        }
    }

    return ''
}
