# Invoke-TmuxTuiAction.ps1 - TGUI 仪表盘的**业务动作分发**(单一事实来源)
#
# 背景 (2026-10-30 TGUI 迁移 · 阶段 B):
#   Show-TmuxTuiDashboard 是"TG 生命周期层"(Init/Run/Shutdown + 事件循环),
#   本函数是"业务分发层" —— 把界面动作值(Attach/New/Refresh/Ssh/Remove)
#   翻译成既有业务函数的调用。拆开的原因:
#     1. 业务分发必须能被 Pester 独立覆盖(不启 TG 事件循环);
#     2. Goal 六-4 要求"验证 new/delete/refresh/attach 的分发";
#     3. Goal 三-5 要求"危险操作必须保留现有二次确认逻辑" —— 删除统一走
#        Invoke-TmuxSessionDeletion(确认屏障在那个函数里, 不可绕过)。
#
# 契约: 不碰终端、不进事件循环; 只调用既有业务函数并回报结果。

function Invoke-TmuxTuiAction {
    <#
    .SYNOPSIS
        把 TGUI 仪表盘的动作值分发给既有业务函数(阶段 B)。

    .DESCRIPTION
        动作与既有业务函数的对应(与 Get-TmuxActionDefinition 的键位表一致):
          Attach  -> Invoke-TmuxAttach(附着所选会话); 无选中会话时**不执行**
          New     -> New-TmuxSession(新建会话)
          Refresh -> 只刷新(不调用任何业务函数)
          Remove  -> Invoke-TmuxSessionDeletion(删除所选会话, 内含二次确认屏障)
          Ssh     -> Invoke-SshCommand -Interactive(直连 SSH)
          Quit    -> 不执行任何业务函数(由编排层退出)

        返回 PSCustomObject:
          .Action           实际执行的动作值(未识别时为空串)
          .Executed        是否真的调用了业务函数
          .PreviousSelected 下一轮应保留的选中会话名(动作会改变会话状态时保留)
          .NeedsRefresh    是否需要重新取数(刷新数据源)

    .PARAMETER Action
        动作值(Attach/New/Refresh/Ssh/Remove/Quit)。

    .PARAMETER HostName
        当前 SSH 主机名。

    .PARAMETER SelectedSession
        仪表盘当前选中的会话名(Attach/Remove 用)。

    .PARAMETER State
        当前状态对象(兼容旧路径; 仪表盘路径直接用选中行, 不再弹嵌套列表)。

    .OUTPUTS
        [PSCustomObject] Action/Executed/PreviousSelected/NeedsRefresh

    .EXAMPLE
        Invoke-TmuxTuiAction -Action 'Refresh' -HostName 'deb'
    #>
    # $State 是旧路径兼容契约参数(仪表盘路径直接用选中行), 保留以稳定公开调用形态。
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'State', Justification = '旧路径兼容契约参数, 参见 .PARAMETER State')]
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$HostName,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$SelectedSession = '',

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$State = $null
    )

    if (-not $PSCmdlet.ShouldProcess("$HostName/$Action", 'Invoke tmux action')) {
        return [PSCustomObject]@{
            Action = $Action; Executed = $false; PreviousSelected = $SelectedSession; NeedsRefresh = $false
        }
    }

    $executed = $false
    $previousSelected = $SelectedSession

    switch ($Action) {
        'Attach' {
            if ($SelectedSession) {
                Invoke-TmuxAttach -HostName $HostName -SessionName $SelectedSession
                $executed = $true
            }
        }
        'New' {
            New-TmuxSession -HostName $HostName
            $executed = $true
        }
        'Refresh' {
            # 纯刷新: 不调业务函数, 只让编排层重新取数
            $executed = $true
        }
        'Remove' {
            if ($SelectedSession) {
                # 删除走仪表盘当前选中行, **不再弹嵌套 PSTui 列表**;
                # 二次确认屏障(Read-SpectreConfirm)在共享删除函数里, 不可绕过。
                Invoke-TmuxSessionDeletion -HostName $HostName -SessionName $SelectedSession
                $executed = $true
            }
        }
        'Ssh' {
            try {
                Invoke-SshCommand -HostName $HostName -Interactive -PassThru | Out-Null
                $executed = $true
            } catch {
                Write-Warning "无法执行 ssh: $($_.Exception.Message)"
            }
        }
        'Quit' {
            # 退出由编排层处理, 这里不调业务函数
            $executed = $true
        }
        default {
            Write-Warning "未知的操作: $Action, 已跳过。"
        }
    }

    return [PSCustomObject]@{
        Action           = $Action
        Executed        = $executed
        PreviousSelected = $previousSelected
        NeedsRefresh    = $true
    }
}
