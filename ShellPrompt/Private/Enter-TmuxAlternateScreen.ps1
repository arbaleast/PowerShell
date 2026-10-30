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
#   - Clear-TmuxScreen: 第五轮修复新增 —— 主事件循环**每一次迭代开头**
#     强制全量重绘前的绝对清屏(绝对的全量重绘机制), 消除状态切换后的
#     残影/双底栏/输入光标残留;
#   - 幂等: Enter/Exit 由 $script:TmuxAltScreenActive 状态位守护, 重复
#     Enter/Exit 不会写出多余的协议序列。
#   - 全屏交互子动作(tmux attach / 新建并附着 / 直连 SSH)执行前后由调用方
#     显式 Exit -> 执行 -> Enter 暂停/恢复管理器屏幕, 保证 tmux 拿到的是
#     干净的主屏幕, detach 后再回到管理器备用屏重新绘制。

$script:TmuxAltScreenActive = $false

function Enter-TmuxAlternateScreen {
    <#
    .SYNOPSIS
        切换到终端备用屏幕(\e[?1049h), 保存主屏幕现场以备恢复。

    .DESCRIPTION
        幂等: 已处于备用屏幕时不重复发送协议序列。
        与 Exit-TmuxAlternateScreen 成对使用, 推荐外层 try/finally:

            Enter-TmuxAlternateScreen
            try { ...主循环... } finally { Exit-TmuxAlternateScreen }

        切换后追发 \e[2J\e[H —— 备用屏从左上角开屏, 不基于当前光标位置。

    .EXAMPLE
        Enter-TmuxAlternateScreen
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if ($script:TmuxAltScreenActive) { return }
    Write-Host -NoNewline "`e[?1049h"
    # 硬清屏 + 光标归位: 1049h 本身给空备用屏, 这里再显式一次 —— 重入时
    # (attach 返回、异常路径残留光标位置)也保证从 (0,0) 开始渲染。
    Write-Host -NoNewline "`e[2J`e[H"
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

    .EXAMPLE
        finally { Exit-TmuxAlternateScreen }
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if (-not $script:TmuxAltScreenActive) { return }
    Write-Host -NoNewline "`e[?1049l"
    $script:TmuxAltScreenActive = $false
}

function Clear-TmuxScreen {
    <#
    .SYNOPSIS
        全量重绘前的绝对清屏(\e[2J\e[H): 清空可见区并把光标归位 (0,0)。

    .DESCRIPTION
        第五轮修复(2026-10-30): 主事件循环 while 的每一次迭代开头调用,
        保证任何状态切换(Normal -> Input / Input -> Normal / 附着返回)之后
        下一次渲染都从一张干净的整屏开始 —— 残影、双底栏、输入光标残留
        "> n" 全部是"不清屏直接续画"的产物。
        渲染层随后用**绝对坐标**布局: 标题 Y=0, 输入区 Y=$h-5 附近,
        底部状态栏 Y=$h-1($h = [Console]::WindowHeight)。

        注意: PSTui 全屏弹窗(-FullScreen)独占渲染期间由它自己管理屏幕,
        本函数只在弹窗之外的常驻画面(动作条 / 输入区)与迭代开头生效。

    .EXAMPLE
        while ($true) {
            Clear-TmuxScreen
            ...渲染与交互...
        }
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Write-Host -NoNewline "`e[2J`e[H"
}
