# Resolve-TmuxTuiKeyAction.ps1 - TGUI 键位 -> 业务动作的**纯函数映射**(阶段 A)
#
# 背景 (2026-10-30 TGUI 迁移 · 阶段 A):
#   Terminal.Gui 只负责"收到键盘事件并给出识别", 动作值契约复用
#   Get-TmuxActionDefinition(键位契约的唯一事实来源)。本函数把 TG 的
#   键事件信息(.Key 枚举名 / .KeyChar)映射回与 GridView 链路完全一致的
#   动作值: Attach / New / Refresh / Ssh / Remove / Quit / ''(未命中)。
#   —— 保证 TGUI 分支与旧 PSTui 链路对 Start-TmuxSession 的动作分发
#      契约不变, 编排层无需感知渲染实现。
#
# 键位对应 Goal 三-3: Enter 附着 / N 新建 / R 刷新 / S SSH / X 删除 /
# Esc 与 Q 退出(两键同义); 无会话时不解析 Attach/Remove(死键防护)。

function Resolve-TmuxTuiKeyAction {
    <#
    .SYNOPSIS
        把 TGUI 键事件信息解析成与旧动作条一致的业务动作值(纯函数)。

    .DESCRIPTION
        输入 PSCustomObject{Key=[string], KeyChar=[char]}(TG 事件的脱离
        组件形状; 真实 ConsoleKeyInfo 也可直接透传, 取 .Key/.KeyChar),
        输出动作值:
            Enter -> Attach (需有会话)
            N     -> New
            R     -> Refresh
            S     -> Ssh
            X     -> Remove (需有会话)
            Esc 或 Q -> Quit
            其他/未命中 -> ''
        无会话时 Attach/Remove 强制空串(与旧工具条"无会话不暴露"一致)。

    .PARAMETER KeyInfo
        含 .Key 与 .KeyChar 的对象(ConsoleKeyInfo 或测试 stub 均可)

    .PARAMETER HasSessions
        当前是否存在 tmux 会话

    .OUTPUTS
        [string] 动作值; 未命中为空串

    .EXAMPLE
        $action = Resolve-TmuxTuiKeyAction -KeyInfo @{ Key = 'Escape'; KeyChar = [char]27 } -HasSessions $false
        $action | Should -BeExactly 'Quit'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [object]$KeyInfo,

        [Parameter(Mandatory = $false)]
        [bool]$HasSessions = $false
    )

    if ($null -eq $KeyInfo) { return '' }

    $keyName = [string]$KeyInfo.Key
    $keyChar = try { [char]$KeyInfo.KeyChar } catch { [char]0 }

    # Esc(两种表达: Key=Escape/Esc 或 KeyChar=ESC)与 Q 都映射 Quit(Goal 三-3)
    # ★ 2026-10-30 CI(windows-latest)实测教训: 不要用 `"$keyChar"`(char 转字符串)
    #   与 ESC 字面 `` `e `` 做 -eq 比较 —— Windows 宿主上 LeftArrow stub
    #   (KeyChar=NUL)曾被误判命中 Quit(Linux 正确) —— char 比较 必须
    #   char-to-char 精确进行, 不经任何字符串插值。
    $escChar = [char]27
    if (($keyName -in @('Escape', 'Esc')) -or ($keyChar -eq $escChar)) { return 'Quit' }

    if ($keyName -eq 'Enter') {
        if ($HasSessions) { return 'Attach' }
        return ''
    }

    # 单字母键: 复用键位契约的唯一事实来源(与旧动作条/工具条一致)
    if ($keyChar -ne [char]0) {
        $definitions = @(Get-TmuxActionDefinition -HasSessions $HasSessions -Context 'Normal')
        $needle = "{0}" -f $keyChar
        $needle = $needle.ToLowerInvariant()
        foreach ($d in $definitions) {
            if ($d.Key -eq $needle) { return [string]$d.Value }
        }
    }

    # 未命中: 空串 —— TG 的事件循环按"交给内建导航"处理(方向键/Tab 等由 TG 自行路由)
    return ''
}
