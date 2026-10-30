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
#     (备用屏初始为空, 之前的 Shell 内容被完整保存在主缓冲);
#   - Exit-TmuxAlternateScreen: finally 中写 \e[?1049l 恢复原屏幕,
#     try 块无论正常结束还是抛异常/Ctrl-C 都会执行到 finally;
#   - 幂等: 两侧都由 $script:TmuxAltScreenActive 状态位守护, 重复 Enter/Exit
#     不会写出多余的协议序列 (避免与 PSTui -FullScreen 自己的缓冲交换错位)。
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

    .EXAMPLE
        Enter-TmuxAlternateScreen
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if ($script:TmuxAltScreenActive) { return }
    Write-Host -NoNewline "`e[?1049h"
    # 硬清屏 + 光标归位(2026-10-30 第四轮修复, 防御性): 1049h 切换本身会给
    # 空备用屏, 这里再显式 \e[2J\e[H 一次 —— 保证恢复/重入时(attach 返回、
    # 异常路径残留光标位置)界面从左上角开始渲染, 不基于当前光标位置下沉。
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
