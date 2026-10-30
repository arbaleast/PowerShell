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

        切换后主循环迭代开头会立刻调用 Clear-TmuxScreen(.NET 原生清屏 +
        SetCursorPosition(0,0), 2026-10-30 第六轮: Goal 1 规范), 这里不再
        重复发送 \e[2J\e[H, 备用屏内容语义单一: 只负责换屏, 不负责清屏。

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

function Clear-TmuxScreen {
    <#
    .SYNOPSIS
        全量重绘前的绝对清屏:.NET 原生 [Console]::Clear + SetCursorPosition(0,0)。

    .DESCRIPTION
        第六轮修复(2026-10-30): 按 Goal 1 规范改用 .NET 原生清屏 ——
            [Console]::Clear()
            [Console]::SetCursorPosition(0, 0)
        收益: 某些 conhost 宿主上纯 ANSI \e[2J 只清可视区、历史仍可回滚;
        .NET 清屏把回滚历史一起抹掉, 即使终端不支持 1049 备用屏协议
        也不会翻出进入 TUI 前的 Shell 历史("Esc 后见 detached 历史"的根因)。

        重定向控制台(测试/管道)上 Clear 会抛"句柄无效"异常 —— 回退为
        等效 ANSI 序列, 行为永不中断。主事件循环 while 的**每一次迭代
        开头**调用本函数; PSTui 全屏弹窗独占渲染期间由它自己管理屏幕。

    .EXAMPLE
        while ($true) {
            Clear-TmuxScreen
            ...渲染与交互...
        }
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    # TGUI 接管终端时不做任何事: 不清屏, 不触碰 TG 的画面缓冲区
    # (防御纵深, 2026-10-30 审计 #3: TG 路径下 [Console]::Clear 会抹掉
    #  Terminal.Gui 自管的备用屏内容 —— 屏幕所有权归 'Tgui' 时必须整体静音)
    if ($script:TmuxTerminalOwner -eq 'Tgui') { return }
    try {
        [Console]::Clear()
        [Console]::SetCursorPosition(0, 0)
    } catch {
        # 重定向控制台(测试/管道)取不到屏幕缓冲句柄: 回退等效 ANSI 清屏序列
        Write-Host -NoNewline "`e[2J`e[H"
    }
}
