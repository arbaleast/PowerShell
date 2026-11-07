# Enter-TmuxAlternateScreen.ps1 - tmux 管理器主循环的终端备用屏幕(Alternate Screen)开关
#
# 背景 (2026-10-30 第三轮 TUI 修复):
#   tmux 管理器在真实终端截图时暴露"画面割裂": 退出 TUI 或 tmux detach 后,
#   TUI 残影与 Shell 历史(如 SSH 欢迎界面)相互叠加。根因是主循环直接在
#   **当前屏幕缓冲**上反复渲染 —— 内联表格、HUD 提示、tmux 全屏画面全部
#   写进同一段滚动历史, 退出时没有任何恢复动作。
#
# 修复语义 (严格管理备用屏幕生命周期):
#   - Enter-TmuxAlternateScreen: 主循环开始前写 \e[?1049h 切到备用屏幕
#     + \e[2J\e[H 硬清屏归位(第五轮修复: 每次进入/恢复都从左上角开始);
#   - Exit-TmuxAlternateScreen: finally 中写 \e[?1049l 恢复原屏幕,
#     try 块无论正常结束还是抛异常/Ctrl-C 都会执行到 finally;
#   - Clear-TmuxScreen(第五轮修复引入)已删除(2026-11-07 架构精简):
#     主循环由 Show-TmuxTuiDashboard 内 Terminal.Gui Init/Run/Shutdown
#     独占备用屏与画面缓冲, 迭代间不再需要循环外清屏调用点;
#   - 幂等: Enter/Exit 由 $script:TmuxAltScreenActive 状态位守护, 重复
#     Enter/Exit 不会写出多余的协议序列。
#   - 全屏交互子动作(tmux attach / 新建并附着 / 直连 SSH)执行前后由调用方
#     显式 Exit -> 执行 -> Enter 暂停/恢复管理器屏幕, 保证 tmux 拿到的是
#     干净的主屏幕, detach 后再回到管理器备用屏重新绘制。
#
# 终端所有权 (2026-10-30 TGUI 迁移):
#   $script:TmuxTerminalOwner 标记"当前谁在管终端":
#     - 'Legacy'(默认): 本模块自管备用屏, Enter/Exit 照旧发 \e[?1049h / \e[?1049l;
#     - 'Tgui'        : Terminal.Gui 仪表盘接管终端, **它自己**发 ESC[?1049h/l
#                       管理备用屏生命周期。此时本模块再发一次 1049 会造成
#                       备用屏双层嵌套(屏幕翻转与恢复彻底错乱), 因此
#                       Enter/Exit 一律直接返回: 不发协议序列, 也不改状态位。

$script:TmuxAltScreenActive = $false
$script:TmuxTerminalOwner = 'Legacy'

function Enter-TmuxAlternateScreen {
    <#
    .SYNOPSIS
        切换到终端备用屏幕(\e[?1049h), 保存主屏幕现场以备恢复。

    .DESCRIPTION
        幂等: 已处于备用屏幕时不重复发送协议序列。
        与 Exit-TmuxAlternateScreen 成对使用, 推荐外层 try/finally:

            Enter-TmuxAlternateScreen
            try { ...主循环... } finally { Exit-TmuxAlternateScreen }

        切换后主循环的画面由 Terminal.Gui 独占管理(Init/Run/Shutdown),
        迭代间不再有独立的清屏调用点(Clear-TmuxScreen 已随旧主循环轨删除,
        2026-11-07 架构精简), 备用屏内容语义单一: 只负责换屏, 不负责清屏。

        TGUI 模式($script:TmuxTerminalOwner = 'Tgui'): 终端由 Terminal.Gui 独占,
        备用屏由它自己发 ESC[?1049h/l 管理 —— 本函数直接返回, 绝不发第二条
        1049 序列(双层嵌套会让屏幕生命周期彻底错乱)。

    .EXAMPLE
        Enter-TmuxAlternateScreen
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    # TGUI 接管终端时不做任何事: 不发协议序列, 也不改状态位
    if ($script:TmuxTerminalOwner -eq 'Tgui') { return }
    if ($script:TmuxAltScreenActive) { return }
    Write-Host -NoNewline "`e[?1049h"
    $script:TmuxAltScreenActive = $true
}

function Exit-TmuxAlternateScreen {
    <#
    .SYNOPSIS
        退出备用屏幕(\e[?1049l), 恢复进入前的主屏幕现场。

    .DESCRIPTION
        幂等: 不在备用屏幕时不发送协议序列。
        本函数设计为 try/finally 的 finally 调用点 —— 退出管理器、子动作
        完成, 以及异常/Ctrl-C 中断路径都会回到调用前的屏幕。

        TGUI 模式($script:TmuxTerminalOwner = 'Tgui'): 备用屏由 Terminal.Gui
        自己恢复, 本函数直接返回(不发 \e[?1049l, 不改状态位), 避免双层嵌套。

    .EXAMPLE
        finally { Exit-TmuxAlternateScreen }
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    # TGUI 接管终端时不做任何事: 不发协议序列, 也不改状态位
    if ($script:TmuxTerminalOwner -eq 'Tgui') { return }
    if (-not $script:TmuxAltScreenActive) { return }
    Write-Host -NoNewline "`e[?1049l"
    $script:TmuxAltScreenActive = $false
}

# Clear-TmuxScreen 已随旧主循环轨删除(2026-11-07 架构精简审计):
#   当前主循环由 Show-TmuxTuiDashboard 内 Terminal.Gui Init/Run/Shutdown 独占
#   备用屏与画面缓冲, 迭代间不存在循环外清屏调用点。
