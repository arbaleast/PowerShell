# New-TmuxTuiShortcutList.ps1 - TGUI 底部快捷键栏的 Shortcut 列表工厂(阶段 A 视图层)
#
# 背景 (2026-10-30 TGUI 迁移 · 阶段 A):
#   Goal 三-3 底部固定操作栏: Enter 附着 / N 新建 / R 刷新 / S SSH / X 删除 /
#   Esc 与 Q 退出; 无会话时附着与删除不可用(明确显示"不可用", 不是默默消失)。
#   危险操作(X 删除)的二次确认由 Remove-TmuxSession 内部承担 —— 本层仅分发
#   动作值到业务回调, 不复刻确认逻辑(防拆这道防误删闸)。
#
# 2.4.10 实测 API:
#   Terminal.Gui.Input.Key  **不是枚举** —— 是带静态属性的类: Key.A / Key.Enter
#     / Key.Esc 等(静态属性 getter 返回 Key 实例; 注意 Esc 不叫 Escape!)。
#   Shortcut ctor: (Key key, String commandText, Action action, String helpText)
#     属性: Title/HelpText/Key/Enabled/Action/Command。
#   Shortcut 屏幕渲染序(2026-10-30 真机复验+子视图取证): KeyView(键名)
#     -> HelpView(HelpText) -> CommandView(Title) —— HelpText 再放会把"键 标签"
#     渲染两遍(真机底栏 "n 新建 [n] 新建"); 本工厂因此 Title=纯标签, HelpText=''。
#   Action delegate 由 PowerShell 脚本块直接转换; 动作分发闭包走
#     **$global:TguiActionDispatch + 动作值内联字面量**([scriptblock]::Create)。
#
# ★ 派发接线(2026-10-30 阶段 B · 反射实测修正):
#   Terminal.Gui 2.4.10 的 Shortcut **默认 BindKeyToApplication = $false**,
#   此时它只把键登记进**自己的** HotKeyBindings/KeyBindings, 应用级键表里没有它 ——
#   真实按键永远到不了 Shortcut, Action 不会触发(实测: 状态栏是纯展示件)。
#   置 BindKeyToApplication = $true 后, TG 用 `KeyBindings.AddApp(key, target, HotKey)`
#   把它登记到**应用级**键表 —— 真实按键才会下沉到 Action。
#   两个必须遵守的约束(均为实测踩坑):
#     1. `Shortcut.Command` 必须保持 **NotBound**。若同时设成 Accept, 会形成
#        InvokeCommandsBoundToKey -> RaiseActivated -> DefaultHotKeyHandler ->
#        InvokeCommands -> InvokeCommandsBoundToKey 的死循环, **StackOverflow 崩进程**。
#     2. **Esc 不能设 BindKeyToApplication** —— TG 应用级键表默认已绑定
#        `Esc -> Quit`(退出整个应用), 重复 AddApp 会抛
#        "A binding for Esc exists"。因此 Esc 走 TG 内建的 Quit 退出路径,
#        这里的 Esc 项只承担**展示**职责(告诉用户 Esc 可退出)。
#        编排层把"Run 返回且没有待处理动作"一律判定为用户主动退出。
#
# 分发闭包的坑记录(实测两连):
#   1. [scriptblock]::Create 的闭包在 TG 事件循环触发时会换 runtime 会话 ---
#      函数局部($Dispatch/$actionValue)看不见, 函数局部的 GetNewClosure 也
#      看不见 —— 唯一稳的载荷通路是 global:+动作值内联(白名单文字, 无注入面);
#   2. 闭包文本必须**单引号拼接**生成, 双引号内 `` 转义容易产生坏脚本串
#      (报 "The term 'param' is not recognized")。
[CmdletBinding()]
param()

$script:TguiShortcutsFactory = $null

function New-TmuxTuiShortcutList {
    <#
    .SYNOPSIS
        生成底部快捷键栏的 Terminal.Gui Shortcut 列表(纯工厂, 无头可测)。

    .DESCRIPTION
        动作契约复用 Get-TmuxActionDefinition(键位唯一事实来源)。
        - HasSessions=true: 七项 Entry(Enter 附着/n/r/s/x/q/Esc);
        - HasSessions=false: 无附着(死键防护), x 标注"(不可用)", 其余可用;
        - 每项 Action = Invoke `$global:TguiActionDispatch(业务回调, 动作值参数)。
          注意一次性会话的局限: 同一时点只有一份 Dispatch —— Stage B 编排层
          每次重建仪表盘都会重调本工厂, Dispatch 值随之刷新(不会跨窗泄漏)。

    .PARAMETER HasSessions
        当前是否存在 tmux 会话

    .PARAMETER Dispatch
        业务回调脚本块: 接收动作值(Attach/New/Refresh/Ssh/Remove/Quit)
        真机运行时由编排层传入; 测试用 stub 验证分发契约。

    .OUTPUTS
        [object[]] Shortcut 列表

    .EXAMPLE
        $shortcuts = New-TmuxTuiShortcutList -HasSessions $true -Dispatch { param($a) }
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '')]
    # $Dispatch 实际被 $appendShortcut 闭包读取(挂 global)——*& $appendShortcut* 调用形态
    # 下 PSSA 的数据流分析看不到这次使用, 属工具局限(参见 Read-TmuxConsoleLine 同先例)。
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Dispatch', Justification = '被嵌套闭包读取, PSSA 数据流分析不可见')]
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $false)]
        [bool]$HasSessions = $false,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Dispatch
    )

    $tg = Get-TguiContext
    $keyType = $tg.Types.Key
    $shortcutType = $tg.Types.Shortcut
    $shortcutCtor = $shortcutType.GetConstructors() |
        Where-Object { $_.GetParameters().Count -eq 4 } |
        Select-Object -First 1
    if ($null -eq $shortcutCtor) {
        throw 'TGUI 载入失败: Shortcut 缺少 (Key,commandText,Action,helpText) 四参构造。vendored 版本可能已变更。'
    }

    $result = [System.Collections.Generic.List[object]]::new()

    $appendShortcut = {
        # 见文件头"分发闭包的坑记录": 动作值**内联进文本**, Dispatch 挂 global。
        # $BindApp: 是否登记到 TG 应用级键表(真实按键才能到达 Action)。
        #           Esc 必须传 $false —— 应用级已有 Esc->Quit, 重复登记会抛异常。
        # $Enabled: 不可用项(无会话时的删除)既不显示为可按, 也不登记键位。
        # $NoDispatch: 纯展示项不挂分发(2026-10-30 阶段B收口实测: Esc 的视图级
        #           热键会额外触发一次本项 Action, 与 TG 内建 Esc->Quit 各走一遍
        #           —— 键盘注入用例出现双 Quit)。按文件头既定契约, Esc 退出统一
        #           走 TG 内建路径, 展示项动作改为 no-op。
        param($keyName, $title, $actionValue, $helpText, $BindApp = $true, $Enabled = $true, $NoDispatch = $false)
        if (-not $NoDispatch) {
            $global:TguiActionDispatch = $Dispatch
            $escaped = ([string]$actionValue).Replace("'", "''")
            $code = '& $global:TguiActionDispatch ' + "'$escaped'"
            $actionDelegate = [System.Action]([scriptblock]::Create($code))
        } else {
            $actionDelegate = [System.Action]([scriptblock]::Create(''))
        }
        $keyObj = $keyType.GetProperty($keyName).GetValue($null)
        $sc = [System.Activator]::CreateInstance(
            $shortcutType,
            @($keyObj, $title, $actionDelegate, $helpText))
        # Command 必须保持 NotBound: 与 Accept 同时出现会死循环崩进程(见文件头)
        $sc.Command = [Enum]::Parse($tg.Types.Command, 'NotBound')
        $sc.BindKeyToApplication = [bool]$BindApp
        $sc.Enabled = [bool]$Enabled
        $result.Add($sc) | Out-Null
    }

    # 键位定义(单一事实来源): HasSessions=$true 拉**全量**定义 ——
    # 传 $false 会把 RequiresSessions 的删除项过滤掉, 而 Goal 三-3 要求
    # 禁用项"明确显示不可用"而非消失, 因此这里必须拉全量再禁用。
    $definitions = @(Get-TmuxActionDefinition -HasSessions $true -Context 'Normal')
    foreach ($def in $definitions) {
        if ($def.Value -eq 'Attach') {
            # 附着以 Enter 键呈现; 无会话时**不出现**(死键防护)
            # ★ 渲染契约(2026-10-30 真机复验, IL+子视图取证): TG 2.4.10 的 Shortcut
            #   屏幕渲染序 = KeyView(键名) -> HelpView(HelpText) -> CommandView(Title)。
            #   HelpText 再放标签会把"键 标签"渲染两遍(真机底栏"Enter 附着  Enter 附着");
            #   Title 也不再带 "[键]" 前缀(KeyView 已有键名) => Title = 纯标签, HelpText = ''。
            if ($HasSessions) {
                & $appendShortcut 'Enter' $def.Label $def.Value '' $true $true
            }
            continue
        }

        $needsSession = $def.Value -in @('Attach', 'Remove')
        $disabled = $needsSession -and -not $HasSessions
        $title = $def.Label
        if ($disabled) { $title = "$title (不可用)" }
        # 不可用项: 既不绑定键位(按了没反应), 也不置灰可按状态
        & $appendShortcut $def.Key.ToUpperInvariant() $title $def.Value '' (-not $disabled) (-not $disabled)
    }

    # Esc 同义 Q 退出(Goal 三-3 两键同义)。
    # Esc 走 TG 内建的 Quit 退出路径, 这里只展示 —— 设 BindKeyToApplication 会与
    # 应用级已有的 Esc->Quit 绑定冲突(见文件头"派发接线"第 2 条)。
    & $appendShortcut 'Esc' '退出' 'Quit' '' $false $true $true

    return $result.ToArray()
}
