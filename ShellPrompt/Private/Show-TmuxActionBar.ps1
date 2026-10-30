# Show-TmuxActionBar.ps1 - tmux 管理器的**单行状态栏 + 单键事件循环**
# 职责: 取代原"全局操作菜单"(第二个表格面板), 用一行文本 + 一次按键完成全局动作分发。
#
# 为什么是单行(2026-10-30 TUI 重构):
#   原全局操作菜单与会话列表上下重复渲染, 屏幕信息密度过高, 视觉疲劳;
#   且只能靠方向键 + Enter 触发, 高频操作(附着/新建/刷新/直连)路径长。
#   降级为单行状态栏后, 主界面只剩**一个**会话面板, 全局动作由单字母键直达:
#       [a]附着  [n]新建  [r]刷新  [s]SSH  [x]删除  [q]退出
#
# 事件循环语义:
#   - 读到登记过的键 -> 立即返回对应动作(Attach/New/Refresh/Ssh/Remove/Quit);
#   - 读到未登记的键 -> 提示一次并继续等键(最多 MaxAttempts 次, 防止注入的读取器死循环);
#   - ESC -> 退出管理器(返回 $null); 与旧流程"列表 ESC -> 菜单 ESC -> 退出"的肌肉记忆一致;
#   - 无输入(非交互/Ctrl-C) -> 返回 $null, 调用方按"用户退出"处理。
#
# 返回契约: PSCustomObject(.Value = 动作值, .Key = 按下的键) 或 $null(退出)。

function Show-TmuxActionBar {
    <#
    .SYNOPSIS
        渲染单行动作条并等待一次按键, 返回对应动作。

    .DESCRIPTION
        打印形如 `[TMUX] [a]附着  [n]新建  [r]刷新  [s]SSH  [x]删除  [q]退出 > ` 的单行状态栏,
        随后读取一个键:
          - 登记过的键(a/n/r/s/x/q) -> 返回对应动作对象;
          - 未登记的键 -> 提示一次, 继续等待(最多 -MaxAttempts 次);
          - ESC 或无输入 -> 返回 $null(退出管理器)。

        "删除"项用危险色渲染: 动作条是纯控制台输出, 内联 ANSI 在这里真实生效
        (与 GridView 表格不同, 那里单元格内联 ANSI 会被剥离)。

    .PARAMETER HasSessions
        当前是否存在 tmux 会话。为 $false 时不显示"附着/删除"。

    .PARAMETER Context
        渲染上下文: Normal(默认) / Error(失败降级态, r=重试 s=直连)

    .PARAMETER KeyReader
        可选的按键读取脚本块(测试注入口); 不提供时读真实控制台。

    .PARAMETER MaxAttempts
        未登记按键的最大重试次数, 默认 10。超过则按"退出"处理, 避免死循环。

    .OUTPUTS
        PSCustomObject(.Value/.Key) 或 $null(用户退出)

    .EXAMPLE
        $action = Show-TmuxActionBar -HasSessions $true -KeyReader { 'n' }
        $action.Value   # -> New
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [bool]$HasSessions = $false,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Normal', 'Error')]
        [string]$Context = 'Normal',

        [Parameter(Mandatory = $false)]
        [scriptblock]$KeyReader,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 100)]
        [int]$MaxAttempts = 10
    )

    $toolbar = Format-TmuxToolbarText -HasSessions $HasSessions -Context $Context -HighlightDanger

    # 状态栏只打印一次; 未识别按键的提示就地追加, 避免刷屏
    Write-Host "[TMUX] $toolbar > " -NoNewline -ForegroundColor Cyan

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $token = Read-TmuxActionKey -KeyReader $KeyReader

        # 无输入(非交互终端 / Ctrl-C / 读取失败): 按"用户退出"处理
        if ([string]::IsNullOrEmpty($token)) {
            Write-Host ''
            return $null
        }

        # ESC: 退出管理器(与旧流程的二级 ESC 一致)
        if ($token -eq 'ESC') {
            Write-Host ''
            return $null
        }

        $action = Resolve-TmuxActionKey -Key $token -HasSessions $HasSessions -Context $Context
        if ($action) {
            Write-Host $token
            return [PSCustomObject]@{
                Value = $action
                Key   = $token
            }
        }

        Write-Host "未识别的按键 '$token', 请按提示选择" -ForegroundColor DarkGray
    }

    Write-Host ''
    return $null
}
