# Start-TmuxSession.ps1 - 远程 tmux 会话管理器
# 流程(2026-10-30 TUI 重构): 主机选择 -> 后台并行取数(SSH 探测 + 天气预取)
#              -> 单一主视图(会话表格 / 失败占位面板) -> 单行动作条(单键分发)
#              -> 动作执行 -> 回到主视图
#
# 与重构前的差异(对应四个目标):
#   1. UI: 只有**一个**主视图。原来的"全局操作菜单"(第二个表格面板)已删除,
#      全局动作收敛为底部单行状态条(Show-TmuxActionBar), 键位写在窗口标题里。
#   2. 交互: 单字母键直达(a 附着 / n 新建 / r 刷新 / s SSH / x 删除 / q 退出)。
#   3. 状态: 成功不再弹 toast(原来的 "[OK] 正在重新获取会话列表 ..." 已删除);
#      探测失败时主视图渲染带错误码的占位面板, 并提示 r 重试 / s 直连。
#   4. 异步: SSH 探测与天气预取都在后台线程执行, 主线程只在需要结果时收割。

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

    交互契约(2026-10-30 TUI 重构):
      - 主视图只有一个: 有会话时列会话表格, 探测失败/无会话时列**带错误码的占位面板**;
      - 表格内: ↑↓ 选择, Enter 附着/恢复所选会话, ESC 进入底部单行动作条;
      - 动作条: 单字母键直达(a 附着 / n 新建 / r 刷新 / s SSH / x 删除 / q 退出), ESC 退出管理器;
      - 成功路径不再输出 toast, 只有失败才提示。

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
# 重构: 主机选择/主视图/动作条 三个 UI 全部委托给独立组件,
# 仅保留业务编排(取数/LastHost 记忆/子动作分发)
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

    # 2026-10-30 异步: 天气预取与随后的 SSH 探测在后台并行, 首屏不等网络。
    # 预取失败静默降级(标题区不显示天气), 不影响主流程。
    $null = Submit-WttrPrefetch

    # 当前主视图使用的状态对象; $null 表示"需要重新取数"。
    # 'Attach' 回到列表时复用它(不再多打一次 SSH), 其余动作执行后置空触发重取。
    $state = $null

    # 上一轮展示过的会话(用于跨轮保持行序稳定); 首轮为 $null, 表示"还没有基线"
    $previousSessions = $null

    # 备用屏幕生命周期 (2026-10-30 第三轮 TUI 修复):
    # 主循环整体搬进终端备用屏 (\e[?1049h), finally 中 \e[?1049l 恢复。
    # 无论正常退出还是异常/Ctrl-C, 原来的 Shell 现场(历史输出)都完整还原,
    # 不再出现"TMUX 残影叠加在 Shell 历史上"的画面割裂。
    Enter-TmuxAlternateScreen
    try {
        while ($true) {
        if ($null -eq $state) {
            # 取数: 后台线程执行 SSH 探测(失败自动退回同步路径)
            $raw = Invoke-TmuxSessionFetch -HostName $HostName
            $fetched = @()
            if ($null -ne $raw) { $fetched = @($raw.Sessions | Where-Object { $null -ne $_ }) }

            # 行序稳定(2026-10-29 审计): GridView 无预选行参数, 重新弹表后光标回到第一行;
            # 若各轮之间会话顺序变化, 同一行位置会指向别的会话 -> 误附着/误删除风险。
            # 按上一轮展示顺序重排: 幸存会话保持原相对位置, 新会话追加到末尾。
            $sessions = if ($null -ne $previousSessions) {
                Merge-TmuxSessionOrder -Previous $previousSessions -Refreshed $fetched
            } else {
                $fetched
            }
            $previousSessions = $sessions

            # 归一化成状态对象: 区分"确实没有会话"与"探测失败", 并给出错误码
            $state = Get-TmuxSessionState -SessionData $raw -Sessions $sessions
        }

        # ---------- 唯一主视图: 会话表格 / 失败占位面板 ----------
        $selected = Show-TmuxSessionDashboard -HostName $HostName -State $state
        if ($null -ne $selected) {
            # 选中会话 -> 立即附着/恢复(.Value 恒为纯会话名, 由列表层归一化)。
            # 暂停备用屏幕: tmux 是全屏程序, 必须拿到主讲干净的画面; detach
            # 键出主屏幕后, 再回到管理器备用屏重新绘制(2026-10-30 屏幕生命周期)。
            Exit-TmuxAlternateScreen
            Invoke-TmuxAttach -HostName $HostName -SessionName $selected.Value
            Enter-TmuxAlternateScreen
            # 附着会改变远端状态, 下一轮重新取数
            $state = $null
            continue
        }

        # ---------- 底部单行动作条(单键事件循环) ----------
        $hasSessions = $state.Status -eq 'Ok'
        $action = Show-TmuxActionBar -HasSessions $hasSessions -Context $state.Context
        if ($null -eq $action) {
            # ESC / 无输入: 退出管理器
            Write-Host " [OK] 已从 $HostName 断开连接" -ForegroundColor Cyan
            return
        }

        switch ($action.Value) {
            'Attach' {
                # 回到会话列表选择附着目标(复用当前状态, 不额外探测)
                continue
            }
            'New' {
                # 暂停管理器备用屏: 创建走交互输入 + 全屏 tmux, 需要主讲画面
                Exit-TmuxAlternateScreen
                New-TmuxSession -HostName $HostName
                Enter-TmuxAlternateScreen
                $state = $null
            }
            'Refresh' {
                # 静默刷新: 回到循环顶部重新取数, **不**输出成功 toast
                $state = $null
            }
            'Remove' {
                # 删除走 Remove-TmuxSession: 它内部重新列出目标会话并强制二次确认,
                # 是防误删的唯一屏障, 不在这里绕过。
                $removable = @($state.Sessions)
                if ($removable.Count -eq 0) {
                    Write-Warning '当前没有可删除的会话'
                    $state = $null
                    continue
                }
                Remove-TmuxSession -HostName $HostName -Sessions $removable
                $state = $null
            }
            'Ssh' {
                Write-Host " [SSH] 直接连接..." -ForegroundColor Green
                # 暂停管理器备用屏: SSH 直连是全屏交互会话, 拿主讲画面
                Exit-TmuxAlternateScreen
                # ssh 启动失败(未安装 OpenSSH 客户端 / ssh.exe 不在 PATH)时 Invoke-SshCommand 会抛异常;
                # 降级为警告并回到主循环, 而不是让整个 SSS 流程带异常中断。
                try {
                    $sshResult = Invoke-SshCommand -HostName $HostName -Interactive -PassThru
                } catch {
                    Write-Warning "无法执行 ssh: $($_.Exception.Message)"
                    Enter-TmuxAlternateScreen
                    $state = $null
                    continue
                }
                Enter-TmuxAlternateScreen
                if ($null -ne $sshResult -and $sshResult.ExitCode -ne 0) {
                    Write-Warning "SSH 连接未正常结束 (ssh 退出码: $($sshResult.ExitCode))"
                } else {
                    Write-Host "`n [OK] SSH 连接已关闭，回到管理菜单" -ForegroundColor Cyan
                }
                $state = $null
            }
            'Quit' {
                Write-Host " [OK] 已从 $HostName 断开连接" -ForegroundColor Cyan
                return
            }
            default {
                # 兜底: 动作条只返回登记过的动作, 未知取值一律不执行
                Write-Warning "未知的操作: $($action.Value), 已跳过。"
            }
        }
        } # while
    } finally {
        # 正常退出 / 异常 / Ctrl-C 都会执行到这里: 恢复进入前的主屏幕现场
        Exit-TmuxAlternateScreen
    }
}
