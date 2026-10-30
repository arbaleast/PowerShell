# Start-TmuxSession.ps1 - 远程 tmux 会话管理器
# 流程(方案 A): 主机选择 -> tmux 检测 -> 真实会话列表(主界面, Enter=附着/恢复)
#              -> ESC 全局操作菜单(创建/删除/直连 SSH/刷新) -> SSH 连接

$script:TmuxSessionPrefix = "tmux-"

<#
.SYNOPSIS
    生成随机 tmux 会话名称

.DESCRIPTION
    生成以 "tmux-" 为前缀的 6 位随机数字会话名。

.EXAMPLE
    New-RandomSessionName
#>

function New-RandomSessionName {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([string])]
    param()

    # "New" 属于会改变系统状态的动词, 按 PSScriptAnalyzer 规则需支持 ShouldProcess
    if (-not $PSCmdlet.ShouldProcess('tmux session name', 'Generate random tmux session name')) {
        return ''
    }
    return "$script:TmuxSessionPrefix$(Get-Random -Minimum 100000 -Maximum 999999)"
}

<#
.SYNOPSIS
    远程 tmux 会话交互式管理器

.DESCRIPTION
    通过交互式菜单管理远程主机上的 tmux 会话，支持主机选择、tmux 可用性探测、
    会话附着/创建/删除、直接 SSH 登录等操作。
    方案 A (2026-10-29): 主界面以真实 tmux 会话列表为中心 --
    Enter 选中会话即附着/恢复; ESC 进入轻量全局操作菜单(删除/创建/直连 SSH/刷新);
    空状态和探测失败时不弹空表格, 直接给出明确提示并进入全局操作菜单。
    各操作分支已抽取到独立的 Private 函数:
    Invoke-TmuxAttach(附着执行) / New-TmuxSession(创建) / Remove-TmuxSession(删除)。

.PARAMETER HostName
    远程主机名（来自 ~/.ssh/config）。未指定时弹出交互式主机选择菜单。

.EXAMPLE
    Start-TmuxSession

    弹出交互式菜单选择主机并管理远程 tmux 会话。

.EXAMPLE
    Start-TmuxSession -HostName myserver

    直接连接指定主机的 tmux 管理器。
#>
# 重构: 主机选择/动作选择/会话选择 三个 UI 全部委托给新组件,
# 仅保留业务编排(SSH 探测/LastHost 记忆/子动作分发)
function Start-TmuxSession {

    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$HostName
    )
    if ($PSCmdlet.ShouldProcess($HostName, 'Start tmux session manager')) { } else { return  }

    # 内部验证：使用 Test-SshHostName 统一校验规则
    if ($HostName -and -not (Test-SshHostName -HostName $HostName)) {
        throw "主机名 [$HostName] 包含非法字符，仅允许字母、数字、点、短横线和下划线"
    }

    # P2-6: 入口处显示欢迎 banner, 使用与 Show-UserScoopLogo 一致的样式
    Write-TmuxWelcomeBanner

    # 主机选择: 委托 Show-HostSelector(实时过滤 + LastHost 徽章)
    if (-not $HostName) {
        # P2-4: 包裹 spinner 保持 UX 一致性(缓存命中会一闪而过, 未命中会有动画)
        $hosts = Invoke-WithProgress -Message "加载主机列表" -ScriptBlock { Get-SshConfigHosts }
        $selected = Show-HostSelector -Hosts $hosts -LastHost $script:Config.SSH.LastHost
        if ($null -eq $selected) { return }
        $HostName = $selected.Value
    }

    $script:Config.SSH.LastHost = $HostName

    Write-Host "`n [SSH] 目标主机: $HostName" -ForegroundColor Cyan

    # P2-4: SSH 探测是真正耗时的步骤(网络慢时 5-30s), spinner 是必须的
    $availInfo = Invoke-WithProgress -Message "检测远程 tmux (可能几秒)" -ScriptBlock { Get-TmuxAvailability -HostName $HostName }

    # fix(sss): 探测失败不再直接 fall through 到 ssh, 改成警告后仍进管理器。
    # 方案 A (2026-10-29): tmux 管理器主界面 = 真实会话列表(Show-TmuxSessionList):
    #   - Enter 选中会话 -> 立即附着/恢复(Invoke-TmuxAttach);
    #   - ESC 从会话列表进入轻量全局操作菜单(Show-SessionManager: 删除/创建/直连/刷新);
    #   - 无会话 / 探测失败时不弹空表格, 直接进入全局操作菜单并给出明确提示。
    # 不使用按键以外的自定义交互(PSTui Out-ConsoleGridView 不支持操作栏/快捷键)。
    Write-TmuxAvailabilityNotice -HostName $HostName -AvailabilityInfo $availInfo

    Write-Host " [提示] Enter=附着/恢复所选会话, ESC=全局操作(创建/删除/直连 SSH/刷新)" -ForegroundColor DarkGray

    # 上一轮展示过的会话(用于跨轮保持行序稳定); 首轮为 $null, 表示"还没有基线"
    $previousSessions = $null

    while ($true) {
        # 每次菜单循环重新探测远端 tmux 会话状态,确保菜单始终显示最新数据(Q6=A)
        # P2-5: 同样走 spinner 包裹, 使 SSH 刷具有统一 UX
        # -Force: 强制跳过 Get-TmuxSessions 内部的 30s TTL 缓存, 保证"刷新"立即生效。
        $sessionData = Invoke-WithProgress -Message "获取远程 tmux 会话" -ScriptBlock { Get-TmuxSessions -HostName $HostName -Force }
        # 行序稳定(2026-10-29 审计): GridView 无预选行参数, 重新弹表后光标回到第一行;
        # 若各轮之间会话顺序变化, 同一行位置会指向别的会话 -> 误附着/误删风险。
        # 按上一轮展示顺序重排: 幸存会话保持原相对位置, 新会话追加到末尾。
        $sessions = if ($null -ne $previousSessions) {
            Merge-TmuxSessionOrder -Previous $previousSessions -Refreshed $sessionData.Sessions
        } else {
            @($sessionData.Sessions)
        }
        $previousSessions = $sessions
        # 计数口径与会话列表层共用 Get-TmuxSessionSummary, 保证标题"附 X / 分 Y"一致
        $summary = Get-TmuxSessionSummary -Sessions $sessions
        $action = $null

        if ($sessions.Count -gt 0) {
            # ---------- 主界面: 真实会话列表(每行 = 一个 tmux 会话) ----------
            # 不传 -SessionRefresher: 刷新属于全局操作, 收敛到 ESC 后的全局操作菜单,
            # 会话表格只展示真实会话行, 不混入"刷新/创建"等伪数据行。
            $selected = Show-TmuxSessionList -HostName $HostName -Sessions $sessions `
                -Title "TMUX 管理器" -ExitLabel "返回" -ShowStateBadge

            if ($null -ne $selected) {
                # 选中会话 -> 立即附着/恢复(.Value 恒为纯会话名, 由列表层归一化)
                Invoke-TmuxAttach -HostName $HostName -SessionName $selected.Value
                continue
            }

            # ---------- ESC: 轻量全局操作菜单(不再包含"附着"项) ----------
            $action = Show-SessionManager -HostName $HostName -TmuxVersion $sessionData.Version `
                -SessionCount $sessions.Count -AttachedCount $summary.Attached -DetachedCount $summary.Detached `
                -HasSessions $true
        }
        else {
            # ---------- 空状态 / 数据获取失败: 不弹空表格, 给出可理解反馈 ----------
            # Get-TmuxSessions 现在同时返回探测结果(Available/ExitCode/NetworkError/TimedOut),
            # 这里用"本次拉取自带的探测结果"区分"确实没有会话"与"根本没拿到数据",
            # 不再依赖入口处那次可能被 30s TTL 缓存命中的旧探测($availInfo), 不伪装成空列表。
            if ($sessionData.Available) {
                Write-Warning "远程主机 $HostName 当前没有 tmux 会话"
            }
            elseif ($sessionData.TimedOut) {
                # SSH 等待超时(被 Kill)与"远端命令失败"是两回事, 分开提示便于排查
                Write-Warning "连接 $HostName 超时, 未能获取 tmux 会话列表 (可在全局菜单用 Ssh 直连排查)"
            }
            else {
                Write-Warning "未能获取 $HostName 的 tmux 会话列表 (tmux 检测失败, 详见上方提示)"
            }

            # 无会话时无附着/删除动作, 只剩 创建新 tmux / 直接 SSH / 刷新
            $action = Show-SessionManager -HostName $HostName -TmuxVersion $sessionData.Version `
                -SessionCount 0 -HasSessions $false
        }

        if ($null -eq $action) {
            Write-Host " [OK] 已从 $HostName 断开连接" -ForegroundColor Cyan
            return
        }

        # 委托子函数执行具体动作; 动作完成后回到循环顶部重新拉会话(会话列表为主界面)
        switch ($action.Value) {
            "New"     { New-TmuxSession -HostName $HostName }
            "Remove"  { Remove-TmuxSession -HostName $HostName -Sessions $sessions }
            "Ssh"     {
                Write-Host " [SSH] 直接连接..." -ForegroundColor Green
                # ssh 启动失败(未安装 OpenSSH 客户端 / ssh.exe 不在 PATH)时 Invoke-SshCommand 会抛异常;
                # 降级为警告并回到主循环, 而不是让整个 SSS 流程带异常中断。
                try {
                    $sshResult = Invoke-SshCommand -HostName $HostName -Interactive -PassThru
                } catch {
                    Write-Warning "无法执行 ssh: $($_.Exception.Message)"
                    continue
                }
                if ($null -ne $sshResult -and $sshResult.ExitCode -ne 0) {
                    Write-Warning "SSH 连接未正常结束 (ssh 退出码: $($sshResult.ExitCode))"
                } else {
                    Write-Host "`n [OK] SSH 连接已关闭，回到管理菜单" -ForegroundColor Cyan
                }
            }
            "Refresh" {
                # P2-5: Refresh 在菜单内部被选后, 会跳出菜单 -> while 顶部重新探测
                # 所以不需要在 Refresh 分支重复探测; 原代码是 P1-4 前的遗留, 现仅输出提示
                Write-Host " [OK] 正在重新获取会话列表 ..." -ForegroundColor DarkGray
            }
            default   {
                # 兜底: 全局操作菜单理论上只返回 New/Remove/Ssh/Refresh, 未知取值一律不执行
                Write-Warning "未知的操作: $($action.Value), 已跳过。"
            }
        }
    }
}
