# Show-SshHostDashboard.ps1 - SSH 主机仪表盘的**分发器**(业务装配层)
#
# 职责划分(与 Show-HostSelector / Show-TmuxTuiDashboard 同一套分层):
#   - 本文件: 读数据(主机档案 + 本地活动历史) -> 调编排层 -> 归一返回值形状。
#     **不含任何渲染逻辑**, 也不含 SSH/tmux 业务。
#   - Invoke-SshHostDashboard: 事件循环 / 键盘 / 异步详情 / 缩放。
#
# 为什么需要它(而不是直接在 Show-HostSelector 里调编排层):
#   Show-HostSelector 是**既有公开契约**(返回含 .Value 的行对象), 而仪表盘
#   需要的是**结构化主机档案**(HostName/Port/User/Tags/Provider/Region …),
#   光有主机名数组不够。把"档案 + 活动历史"的装配收在这一层, 上层契约不变。

function Show-SshHostDashboard {
    <#
    .SYNOPSIS
        弹出 SSH 主机仪表盘, 返回选中的主机(或 $null)。

    .DESCRIPTION
        装配步骤:
          1. 主机档案(Get-SshHostProfile): 解析 ~/.ssh/config 的结构化档案;
          2. 本地活动历史(Get-SshHostActivity -All): 最后活跃 / 最近连接 / 按天统计
             —— 仪表盘 Activity 卡片的**真实**数据来源, 没有记录就显示"无记录";
          3. 调 Invoke-SshHostDashboard 跑交互循环。

        **不伪造任何数据**: 分类来自档案里的真实 Provider/本地标记, 标签来自
        档案里的真实 @tags 注释, 状态来自真实探测结果。

    .PARAMETER Hosts
        主机名白名单(来自 Get-SshConfigHosts); 为空表示用档案里的全部主机。

    .PARAMETER LastHost
        上次使用的主机名(列表置顶 + 标题带右半展示)。

    .PARAMETER Title
        标题带左半文本(调用方给出; 缺省 'ShellPrompt · SSH 主机')。

    .PARAMETER TitleSuffix
        标题后缀(如天气串), 由调用方拼好传入。

    .OUTPUTS
        PSCustomObject(.Value/.Host/.Disabled) 或 $null(用户取消 / 非交互环境)。
        .Value = 主机名(与 Show-HostSelector 的既有契约一致)。

    .EXAMPLE
        $picked = Show-SshHostDashboard -Hosts @('deb','web')
        if ($picked) { $picked.Value }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$Hosts = @(),

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$LastHost = '',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Title = '',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$TitleSuffix = ''
    )

    # ---- 主机档案(读 ~/.ssh/config; 读不到就是"没有主机", 不抛异常) ----
    $profiles = @(Get-SshHostProfile)

    # ---- 本地活动历史(读不到按空历史处理) ----
    $activity = @()
    try {
        $activity = @(Get-SshHostActivity -All)
    }
    catch {
        Write-Verbose "[Show-SshHostDashboard] 读取本地活动历史失败(按空历史处理): $($_.Exception.Message)"
    }

    $selected = Invoke-SshHostDashboard -Profiles $profiles -Activity $activity `
        -AllowedHosts $Hosts -LastHost $LastHost -Title $Title -TitleSuffix $TitleSuffix

    if ($null -eq $selected) { return $null }

    # 归一成既有契约形状: .Value = 主机名
    return [PSCustomObject]@{
        Value    = [string]$selected.HostName
        Host     = [string]$selected.HostName
        State    = ''
        Disabled = $false
        Profile  = $selected.Profile
    }
}
