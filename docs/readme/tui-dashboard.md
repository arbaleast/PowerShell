# 🖥️ tmux 管理器 TUI 仪表盘（2026-10-30 重构）

本文记录 `sss`（[`Start-TmuxSession`](../../ShellPrompt/Public/Start-TmuxSession.ps1)）tmux 管理器在 2026-10-30 TUI 重构后的**结构、交互契约与异步取数**语义，供维护者查阅。

重构前的形态是**两个表格面板**——会话列表 + 「全局操作菜单」——上下重复渲染同一批会话信息；全局动作只能靠方向键 + Enter 触发；成功路径长期挂着 `[OK] 正在重新获取会话列表 ...` 成功 toast；SSH 探测失败时列表留白且无降级指引；天气（wttr.in）与 SSH 探测串行阻塞首屏。重构后：**一个主视图 + 一行动作条 + 单键直达 + 带错误码的降级占位面板 + 后台异步取数**。

---

## 一、模块拆分与重构思路

### 1.1 三层职责边界

| 层 | 职责 | 判定标准 |
|---|---|---|
| **数据层** | 把"远端到底发生了什么"变成**可判定的状态对象**：有会话 / 确实没会话 / 探测失败，以及失败时的稳定错误码 | 不碰控制台、不读配置、不做 UI 决策 |
| **渲染层** | 把状态对象变成**屏幕上的一行/一屏**：主视图（表格或占位面板）与单行工具条 | 不发起网络请求、不做动作分发 |
| **交互层** | 把"用户按了什么"变成**一个动作值**：单键读取 → 键位映射 → 事件循环 | 不区分"成功 / 失败"，只区分"登记过的键 / 没登记的键" |

分层的直接收益：键位契约（哪个键做什么）、失败判定（什么算失败）、渲染外观（长什么样）三者各自只有一个事实来源，互不牵连。

### 1.2 新增 Private 文件一览

本次重构新增 12 个 Private 文件，删除 3 个（见下表"旧 → 新"）。

**数据层**

| 文件 | 职责 |
|---|---|
| [`Get-TmuxSessionState.ps1`](../../ShellPrompt/Private/Get-TmuxSessionState.ps1) | 把探测结果归一成状态对象（`Get-TmuxSessionState`），并提供稳定错误码映射（`Get-TmuxErrorCode`） |
| [`Get-TmuxPlaceholderRow.ps1`](../../ShellPrompt/Private/Get-TmuxPlaceholderRow.ps1) | 构造占位面板行，列名与 `Get-TmuxSessionGridRow` 完全一致 |
| [`Invoke-TmuxSessionFetch.ps1`](../../ShellPrompt/Private/Invoke-TmuxSessionFetch.ps1) | SSH 探测入口：后台线程执行 `Get-TmuxSessions -Force`，后台不可用时退回同步调用 |
| [`Submit-TmuxBackgroundTask.ps1`](../../ShellPrompt/Private/Submit-TmuxBackgroundTask.ps1) | 后台线程任务**提交端**：用 `Start-ThreadJob` 跑脚本块，按 `-DependencyFile` dot-source 依赖文件 |
| [`Receive-TmuxBackgroundTask.ps1`](../../ShellPrompt/Private/Receive-TmuxBackgroundTask.ps1) | 后台线程任务**收割端**：等待完成，把成功/超时/作业内异常归一成统一形状 |
| [`Submit-WttrPrefetch.ps1`](../../ShellPrompt/Private/Submit-WttrPrefetch.ps1) | 标题区天气的后台预取（`Submit-WttrPrefetch`）与缓存回写（`Receive-WttrPrefetch`） |

**渲染层**

| 文件 | 职责 |
|---|---|
| [`Format-TmuxToolbarText.ps1`](../../ShellPrompt/Private/Format-TmuxToolbarText.ps1) | 把动作集合渲染成**一行**工具条文本 |
| [`Show-TmuxSessionDashboard.ps1`](../../ShellPrompt/Private/Show-TmuxSessionDashboard.ps1) | 唯一主视图：有会话时渲染会话表格，失败/空态渲染占位面板 |

**交互层**

| 文件 | 职责 |
|---|---|
| [`Get-TmuxActionDefinition.ps1`](../../ShellPrompt/Private/Get-TmuxActionDefinition.ps1) | 键位契约的**唯一事实来源**：键 → 文案 → 动作值 → 是否依赖会话 |
| [`Resolve-TmuxActionKey.ps1`](../../ShellPrompt/Private/Resolve-TmuxActionKey.ps1) | 纯函数：单键 → 动作值；未登记的键返回空串 |
| [`Read-TmuxActionKey.ps1`](../../ShellPrompt/Private/Read-TmuxActionKey.ps1) | 用 `[Console]::ReadKey($true)` 读**一个**键并归一化成 token；带 `-KeyReader` 注入口供测试注入 |
| [`Show-TmuxActionBar.ps1`](../../ShellPrompt/Private/Show-TmuxActionBar.ps1) | 底部单行状态栏 + 单键事件循环 |

**已删除**

| 文件 | 原职责 | 删除原因 |
|---|---|---|
| `Private/Show-SessionManager.ps1` | 「全局操作菜单」分发器 | 第二个表格面板已取消，全局动作收敛到动作条 |
| `Private/Get-GridViewManagerRow.ps1` | 全局操作菜单的行构造 | 随菜单一并移除；菜单文案改由 `Get-TmuxActionDefinition` 驱动 |
| `Private/Write-TmuxAvailabilityNotice.ps1` | 探测结果提示 | 提示语义收敛进状态对象（`ErrorCode` / `ErrorMessage` / `Hint`）与占位面板 |

`Invoke-GridViewSessionManager` 已从 [`Invoke-GridViewMenu.ps1`](../../ShellPrompt/Private/Invoke-GridViewMenu.ps1) 中移除；`Show-TmuxSessionList`（删除流程的会话列表）保留不变。

### 1.3 旧 → 新 对照表

| 维度 | 重构前 | 重构后 |
|---|---|---|
| **面板数量** | 两个表格面板：会话列表 + 「全局操作菜单」（上下重复渲染同一批会话信息） | 一个主视图（会话表格 / 带错误码的占位面板）+ 底部**单行**动作条 |
| **动作触发** | 方向键 + Enter，逐级进入菜单 | 单字母键直达（`a` / `n` / `r` / `s` / `x` / `q`），一次按键一次动作 |
| **成功反馈** | 成功路径输出 `[OK] 正在重新获取会话列表 ...` toast | **静默**：成功路径不再输出任何 toast，只有失败才提示 |
| **探测失败** | 列表留白 / 空表格，用户既不知道发生了什么也不知道下一步 | **带错误码的占位面板**：`Session` 列给一句话说明，`State` 列给 `错误码 · 降级指引` |
| **取数时机** | 天气（wttr.in）与 SSH 探测**串行**阻塞首屏 | 两者在**后台线程并行**，主线程只收割结果 |
| **空态语义** | 「没有会话」与「探测失败」在界面上长得一样 | 严格区分：`Empty`（查询成功但确实没有会话，不是故障）与 `Error`（查询失败） |
| **键位契约** | 散落在菜单行构造与 `if/else` 分支里 | 集中在 `Get-TmuxActionDefinition` 一处，键位是**数据**不是分支 |

### 1.4 为什么仍然只用 PSTui `Out-ConsoleGridView` 单轨

重构只改**信息结构**（面板数量、动作触发方式、失败呈现），不改**渲染实现**：

- 唯一渲染实现仍是 [`Invoke-GridViewPrompt`](../../ShellPrompt/Private/Invoke-GridViewMenu.ps1) → PSTui `Out-ConsoleGridView`。主视图的正常态与失败态走**同一条**渲染路径——因为 `Get-TmuxPlaceholderRow` 产出的行与 `Get-TmuxSessionGridRow` **列名完全一致**，无需"失败态专用渲染器"。
- **未引入第二套渲染实现**，也**未对 Terminal.Gui 做任何反射**。`TableView.Style` / `ColumnStyle.Width` 等 readonly 字段仍是仓库明令禁止改动的区域（见 [`docs/agents/architecture.md`](../agents/architecture.md)「PSTui TableView 留白约束」）。
- 底部动作条是**纯控制台输出**（`Write-Host` 单行文本），不是表格视图，不构成第二套表格渲染实现。它的内联 ANSI 在控制台里真实生效，因此「删除」项可以染成危险色（与 GridView 表格单元格内联 ANSI 会被剥离的行为不同）。
- 主轨可用性把关点不变：`Show-TmuxSessionDashboard` 入口仍统一执行 `Assert-ConsoleUiReady -Feature 'tmux 会话主视图'`，主轨不可用时抛可定位的终止错误，不静默降级。
- 单轨带来的直接好处：配色（`Focus` / `Active` / `Highlight` 三槽位同色）、焦点语义、过滤框行为、`Disabled` 阻断逻辑全部沿用既有实现，无需为新面板重新推导一遍。

---

## 二、核心 UI 布局与单键事件监听

> 本节代码片段为**示意**（sketch）：函数名与参数名取自真实实现，行文为突出结构做了精简，**不可直接复制粘贴**。真实实现见上文各文件的源码链接。

### 2.1 布局示意

正常态（`Status = Ok`）：

```text
┌──────────────────────────────────────────────────────────────────────────┐
│ TMUX 管理器 [debian] - 会话 2 (附 1 / 分 1)                               │
│            [a]附着  [n]新建  [r]刷新  [s]SSH  [x]删除  [q]退出           │ ← 单行工具条
├──────────────────────────────────────────────────────────────────────────┤     （拼进窗口标题）
│ No   Session          State         Windows                              │
│ 01   tmux-100001      ● 已附着            2                              │
│ 02   tmux-100002      ○ 已分离            1                              │
├──────────────────────────────────────────────────────────────────────────┤
│ Rows: 2 | Enter Accept | Esc Close                                       │ ← PSTui 自带状态栏
└──────────────────────────────────────────────────────────────────────────┘
[TMUX] [a]附着  [n]新建  [r]刷新  [s]SSH  [x]删除  [q]退出 >                ← 底部单行动作条
```

失败态（`Status = Error`）：

```text
┌──────────────────────────────────────────────────────────────────────────┐
│ TMUX 管理器 [debian] - E_SSH_TIMEOUT                                     │
│            [n]新建  [r]重试  [s]直连  [q]退出                           │ ← 失败态文案
├──────────────────────────────────────────────────────────────────────────┤
│ No   Session                                          State              │
│      SSH 连接超时, 未能获取 tmux 会话列表   E_SSH_TIMEOUT · 按 r 重试 · 按 s 直连 SSH │
├──────────────────────────────────────────────────────────────────────────┤
│ Rows: 1 | Enter Accept | Esc Close                                       │
└──────────────────────────────────────────────────────────────────────────┘
[TMUX] [n]新建  [r]重试  [s]直连  [q]退出 >
```

三处关键点：

1. **工具条在标题里**：表格打开期间键位也可见，用户不必猜。
2. **占位面板与正常态共用面板**：失败时屏幕上是"一行说明 + 一个错误码 + 一条降级指引"，而不是留白。
3. **动作条在表格之下**：表格内 `Esc` 进入动作条，动作条 `Esc` 退出管理器——与旧流程"列表 ESC → 菜单 ESC → 退出"的肌肉记忆一致。

### 2.2 动作定义表（键位契约的唯一事实来源）

```powershell
# —— 示意：Get-TmuxActionDefinition 的键位表 ——
# 键位与动作值的映射是"数据", 不是散落在 if/else 里的分支; 新增动作只改这一处。

function Get-TmuxActionDefinition {
    param(
        [bool]$HasSessions = $false,
        [ValidateSet('Normal', 'Error')][string]$Context = 'Normal'
    )

    $table = @(
        [PSCustomObject]@{ Key = 'a'; Value = 'Attach';  Normal = '附着'; Error = '附着'; RequiresSessions = $true  }
        [PSCustomObject]@{ Key = 'n'; Value = 'New';     Normal = '新建'; Error = '新建'; RequiresSessions = $false }
        [PSCustomObject]@{ Key = 'r'; Value = 'Refresh'; Normal = '刷新'; Error = '重试'; RequiresSessions = $false }
        [PSCustomObject]@{ Key = 's'; Value = 'Ssh';     Normal = 'SSH';  Error = '直连'; RequiresSessions = $false }
        [PSCustomObject]@{ Key = 'x'; Value = 'Remove';  Normal = '删除'; Error = '删除'; RequiresSessions = $true  }
        [PSCustomObject]@{ Key = 'q'; Value = 'Quit';    Normal = '退出'; Error = '退出'; RequiresSessions = $false }
    )

    # Context 只影响"文案", 不影响键位 —— 用户肌肉记忆不因状态切换而失效
    # RequiresSessions 的动作在无会话时不暴露, 避免出现点了没反应的死键
    ...
}
```

### 2.3 工具条渲染

```powershell
# —— 示意：Format-TmuxToolbarText ——
function Format-TmuxToolbarText {
    param(
        [bool]$HasSessions = $false,
        [ValidateSet('Normal', 'Error')][string]$Context = 'Normal',
        [string]$Separator = '  ',
        [switch]$HighlightDanger
    )

    $definitions = @(Get-TmuxActionDefinition -HasSessions $HasSessions -Context $Context)

    $parts = foreach ($definition in $definitions) {
        $text = "[$($definition.Key)]$($definition.Label)"
        # 动作条是纯控制台输出, 内联 ANSI 在这里真实生效
        if ($HighlightDanger -and $definition.Value -eq 'Remove') {
            $text = Format-GridViewStateText -Text $text -ColorKey 'Danger'
        }
        $text
    }

    return ($parts -join $Separator)
}

# 输出示例:
#   [a]附着  [n]新建  [r]刷新  [s]SSH  [x]删除  [q]退出
# 失败态:
#   [n]新建  [r]重试  [s]直连  [q]退出
```

### 2.4 单键读取（带可注入的 KeyReader）

```powershell
# —— 示意：Read-TmuxActionKey ——
# 归一化约定: 单字符 -> 该字符(转小写) / ESC -> 'ESC' / ENTER -> 'ENTER' / 无输入 -> ''
# 不用 Read-Host: 它读的是"一行", 用户必须按回车; [Console]::ReadKey 才是真正的单键读取。

function Read-TmuxActionKey {
    param([scriptblock]$KeyReader)

    # 注入口: 测试与非交互环境走这里, 不读真实控制台
    if ($KeyReader) {
        $token = & $KeyReader
        if ($null -eq $token) { return '' }
        return ([string]$token).Trim()
    }

    try {
        # 输入被重定向(管道/非交互宿主)时 ReadKey 会抛异常; 提前判定更干净
        if ([Console]::IsInputRedirected) { return '' }
        $info = [Console]::ReadKey($true)
    } catch {
        # Ctrl-C / 宿主不支持 / 终端异常: 一律按"无输入"处理, 绝不冒泡打断管理器
        return ''
    }

    if ($null -eq $info) { return '' }
    if ($info.Key -eq [ConsoleKey]::Escape) { return 'ESC' }
    if ($info.Key -eq [ConsoleKey]::Enter)  { return 'ENTER' }

    $char = [string]$info.KeyChar
    if ([string]::IsNullOrEmpty($char)) { return '' }
    return $char.ToLowerInvariant()
}
```

### 2.5 键位分发（纯函数）

```powershell
# —— 示意：Resolve-TmuxActionKey ——
function Resolve-TmuxActionKey {
    param(
        [string]$Key = '',
        [bool]$HasSessions = $false,
        [ValidateSet('Normal', 'Error')][string]$Context = 'Normal'
    )

    if ([string]::IsNullOrWhiteSpace($Key)) { return '' }

    $normalized = $Key.Trim().ToLowerInvariant()
    $definitions = @(Get-TmuxActionDefinition -HasSessions $HasSessions -Context $Context)

    foreach ($definition in $definitions) {
        if ($definition.Key -eq $normalized) { return [string]$definition.Value }
    }

    # 只认登记过的键位; 其余一律返回空串(未命中)
    return ''
}
```

### 2.6 动作条循环

```powershell
# —— 示意：Show-TmuxActionBar ——
function Show-TmuxActionBar {
    param(
        [bool]$HasSessions = $false,
        [ValidateSet('Normal', 'Error')][string]$Context = 'Normal',
        [scriptblock]$KeyReader,
        [ValidateRange(1, 100)][int]$MaxAttempts = 10
    )

    $toolbar = Format-TmuxToolbarText -HasSessions $HasSessions -Context $Context -HighlightDanger

    # 状态栏只打印一次; 未识别按键的提示就地追加, 避免刷屏
    Write-Host "[TMUX] $toolbar > " -NoNewline -ForegroundColor Cyan

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $token = Read-TmuxActionKey -KeyReader $KeyReader

        # 无输入(非交互终端 / Ctrl-C / 读取失败): 按"用户退出"处理
        if ([string]::IsNullOrEmpty($token)) { Write-Host ''; return $null }

        # ESC: 退出管理器(与旧流程的二级 ESC 一致)
        if ($token -eq 'ESC') { Write-Host ''; return $null }

        $action = Resolve-TmuxActionKey -Key $token -HasSessions $HasSessions -Context $Context
        if ($action) {
            Write-Host $token
            return [PSCustomObject]@{ Value = $action; Key = $token }
        }

        # 未登记的键: 提示一次并继续等键(最多 MaxAttempts 次)
        Write-Host "未识别的按键 '$token', 请按提示选择" -ForegroundColor DarkGray
    }

    Write-Host ''
    return $null
}
```

### 2.7 占位面板行构造

```powershell
# —— 示意：Get-TmuxPlaceholderRow ——
# 产出的行与 Get-TmuxSessionGridRow 完全同构(列名一致), 因此走同一条渲染路径。

function Get-TmuxPlaceholderRow {
    param([object]$State)

    $errorCode = [string]$State.ErrorCode
    $message   = [string]$State.ErrorMessage
    $hint      = [string]$State.Hint

    if ([string]::IsNullOrWhiteSpace($message)) { $message = '未获取到 tmux 会话数据' }

    # State 列: 错误码 + 降级指引(有错误码才带指引, 空会话态只给操作提示)
    $stateText = if ($errorCode) {
        if ($hint) { "$errorCode · $hint" } else { $errorCode }
    } elseif ($hint) {
        $hint
    } else {
        'EMPTY'
    }

    return [PSCustomObject]@{
        No       = ''
        Session  = $message
        State    = $stateText
        Windows  = ''
        Status   = ''
        Disabled = $false
        Value    = ''      # Value 为空串表示"这一行不是会话"
    }
}
```

`Value` 为空是**契约**：主视图据此判定"用户选中的不是会话"，转而进入动作条，而不是误把说明行当成会话名去附着。

### 2.8 主视图与编排

```powershell
# —— 示意：Show-TmuxSessionDashboard ——
function Show-TmuxSessionDashboard {
    param(
        [string]$HostName,
        [object]$State,
        [string]$Title = 'TMUX 管理器'
    )

    Assert-ConsoleUiReady -Feature 'tmux 会话主视图'

    $sessions = @($State.Sessions)
    $hasSessions = $sessions.Count -gt 0
    $context = [string]$State.Context
    if ([string]::IsNullOrWhiteSpace($context)) { $context = 'Normal' }

    # 状态摘要: 有会话 -> 计数; 失败态 -> 错误码; 空态 -> 会话 0
    $statusText = if ($hasSessions) {
        (Get-TmuxSessionSummary -Sessions $sessions).TitleSuffix
    } elseif ($context -eq 'Error') {
        [string]$State.ErrorCode
    } else {
        '会话 0'
    }

    # 单行工具条(顶部工具条): 表格打开期间也可见, 键位不必猜
    $toolbar = Format-TmuxToolbarText -HasSessions $hasSessions -Context $context
    $tableTitle = "$Title [$HostName] - $statusText - $toolbar"

    $wttrSuffix = Get-WttrTitleSuffix   # 标题区天气(失败时静默跳过, 绝不影响主视图)

    $rows = if ($hasSessions) {
        @(Get-TmuxSessionGridRow -Sessions $sessions -ShowStateBadge)
    } else {
        @(Get-TmuxPlaceholderRow -State $State)
    }

    $selected = Invoke-GridViewPrompt -Rows $rows -Title ($tableTitle + $wttrSuffix) `
        -HiddenColumns @{ Disabled = $false; Value = ''; Status = '' }
    if ($null -eq $selected) { return $null }

    # 占位行 / 禁用行: 不是一次有效选择, 交给上层转动作条
    if ($selected.Disabled) { return $null }

    $sessionName = [string]$selected.Value
    if ([string]::IsNullOrWhiteSpace($sessionName)) { return $null }

    return ConvertTo-TmuxSessionSelection -Name $sessionName -Status ([string]$selected.Status)
}
```

`Start-TmuxSession` 的编排顺序：

```text
主机选择
  → 提交天气预取 (Submit-WttrPrefetch)
  → 后台取会话 (Invoke-TmuxSessionFetch → Get-TmuxSessionState)
  → 唯一主视图 (Show-TmuxSessionDashboard)
  → 底部动作条 (Show-TmuxActionBar)
  → 动作分发
  → 回到主视图
```

动作分发的关键语义：**`Attach` 复用当前状态对象，不额外探测**；其余动作（新建 / 刷新 / 删除 / 直连 SSH）执行后把状态置空，回到循环顶部重新取数。刷新是**静默**的——不输出任何成功 toast。

---

## 三、异步刷新会话列表

### 3.1 为什么异步

重构前首屏要串行等两次网络往返：SSH 探测（连接超时 5s + 命令等待 10s）与标题区 wttr.in（HTTP 超时 5s）。两者都发生在菜单渲染之前，首屏被网络延迟直接卡住。

重构后：

- **入口探测被去掉**——列表探测本身的返回值就带 `Available` / `Version`，不需要额外一次 SSH。
- SSH 探测与天气预取都放到**后台线程并行**进行，主线程只在需要结果的那一刻收割。

### 3.2 提交端与收割端

线程作业（`Start-ThreadJob`）运行在**独立 runspace**，拿不到模块作用域里的私有函数，因此依赖必须显式列出——这是本次设计的**硬约束**，不是可选项。

```powershell
# —— 示意：Submit-TmuxBackgroundTask（提交端）——

function Submit-TmuxBackgroundTask {
    param(
        [scriptblock]$ScriptBlock,
        [string[]]$DependencyFile = @(),
        [hashtable]$Argument = @{},
        [string]$Name = ''
    )

    # 后台任务按文件名定位 Private 文件
    $privateDir = $script:ShellPromptPrivateDir
    if ([string]::IsNullOrWhiteSpace($privateDir)) {
        throw '后台任务依赖解析失败: $script:ShellPromptPrivateDir 未初始化(模块未按预期加载)。'
    }

    $initLines = [System.Collections.Generic.List[string]]::new()
    $initLines.Add('$ErrorActionPreference = ''Stop''') | Out-Null

    foreach ($name in @($DependencyFile)) {
        $path = Join-Path -Path $privateDir -ChildPath $name
        # 依赖缺失直接抛错, 不静默降级
        if (-not (Test-Path -Path $path)) { throw "后台任务依赖文件不存在: $name ($path)" }
        $escaped = $path.Replace("'", "''")
        $initLines.Add((". '{0}'" -f $escaped)) | Out-Null
    }

    $initScript = [scriptblock]::Create(($initLines -join "`n"))
    $job = Start-ThreadJob -InitializationScript $initScript -ScriptBlock $ScriptBlock -ArgumentList $Argument

    # 句柄包一层: 作业对象的运行时类型随 ThreadJob 版本浮动, 包一层后契约稳定
    return [PSCustomObject]@{ Task = $job; Name = $Name }
}
```

```powershell
# —— 示意：Receive-TmuxBackgroundTask（收割端）——

function Receive-TmuxBackgroundTask {
    param(
        [object]$Task,
        [ValidateRange(0, 600)][int]$TimeoutSeconds = 30
    )

    if ($null -eq $Task) {
        return [PSCustomObject]@{ Succeeded = $false; Result = $null; ErrorMessage = '后台任务未启动'; TimedOut = $false }
    }

    # 句柄可能是包装对象(.Task), 也可能是裸作业对象
    $job = $Task
    if ($Task.PSObject.Properties['Task']) { $job = $Task.Task }

    $completed = Wait-Job -Job $job -Timeout $TimeoutSeconds
    if ($null -eq $completed) {
        # 超时(或 TimeoutSeconds=0 且任务未完成): 放弃该任务
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        return [PSCustomObject]@{ Succeeded = $false; Result = $null `
            ErrorMessage = "后台任务未在 ${TimeoutSeconds}s 内完成"; TimedOut = $true }
    }

    $jobError = $null
    $output = Receive-Job -Job $job -ErrorAction SilentlyContinue -ErrorVariable $jobError
    # 本函数消费任务: 无论成功失败都会 Remove-Job, 因此每个任务只能收割一次
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue

    if ($jobError -and @($jobError).Count -gt 0) {
        $first = @($jobError)[0]
        $message = if ($first.Exception) { $first.Exception.Message } else { [string]$first }
        # 作业内异常被转成 ErrorMessage, 绝不向调用方冒泡
        return [PSCustomObject]@{ Succeeded = $false; Result = $null; ErrorMessage = $message; TimedOut = $false }
    }

    return [PSCustomObject]@{ Succeeded = $true; Result = $output; ErrorMessage = ''; TimedOut = $false }
}
```

### 3.3 SSH 探测入口与同步兜底

```powershell
# —— 示意：Invoke-TmuxSessionFetch ——

function Invoke-TmuxSessionFetch {
    param(
        [string]$HostName,
        [ValidateRange(1, 600)][int]$TimeoutSeconds = 30,
        [switch]$NoSpinner
    )

    # 依赖闭包: Get-TmuxSessions 的调用链(线程作业是独立 runspace)
    $dependencies = @(
        'Get-TmuxSessions.ps1'
        'Invoke-SshCommand.ps1'
        'Get-SshArgs.ps1'
        'Invoke-SshCaptureOutput.ps1'
        'ConvertTo-SshArgumentLine.ps1'
        'Test-SshHostName.ps1'
    )

    $task = $null
    try {
        $task = Submit-TmuxBackgroundTask -ScriptBlock {
                param($argument)
                Get-TmuxSessions -HostName $argument.HostName -Force
            } -Argument @{ HostName = $HostName } -DependencyFile $dependencies
    } catch {
        Write-Verbose "[Invoke-TmuxSessionFetch] 后台任务提交失败, 退回同步探测: $($_.Exception.Message)"
        $task = $null
    }

    if ($null -ne $task) {
        $received = Receive-TmuxBackgroundTask -Task $task -TimeoutSeconds $TimeoutSeconds
        if ($received.Succeeded -and $null -ne $received.Result) {
            return $received.Result
        }
        Write-Verbose "[Invoke-TmuxSessionFetch] 后台探测未成功($($received.ErrorMessage)), 退回同步探测"
    }

    # 同步兜底: 后台路径不可用时功能不缺失
    return Get-TmuxSessions -HostName $HostName -Force
}
```

三条降级路径（提交失败 / 作业内异常 / 等待超时）**全部**退回同步 `Get-TmuxSessions`。返回值形状与同步路径完全一致（`Sessions` / `Available` / `Version` / `Error` / `ExitCode` / `NetworkError` / `TimedOut`），上层无需区分数据来自哪条路径。

### 3.4 天气预取与探测并行

```powershell
# —— 示意：Submit-WttrPrefetch / Receive-WttrPrefetch ——

function Submit-WttrPrefetch {
    param([ValidateRange(0, 1440)][int]$CacheMinutes = 10)

    # 功能开关: 关闭时不做无用功
    if (-not ($script:Config -and $script:Config.Weather -and [bool]$script:Config.Weather.Enabled)) {
        return $null
    }

    try {
        $script:_WttrPrefetchTask = Submit-TmuxBackgroundTask -ScriptBlock {
                param($argument)
                Get-WttrWeather -Format CustomUrl -Url $argument.Url -CacheMinutes $argument.CacheMinutes
            } -Argument @{ Url = $script:_WttrTitleUrl; CacheMinutes = $CacheMinutes } `
            -DependencyFile @('Get-WttrWeather.ps1')
    } catch {
        Write-Verbose "[Submit-WttrPrefetch] 天气预取提交失败: $($_.Exception.Message)"
        $script:_WttrPrefetchTask = $null
    }

    return $script:_WttrPrefetchTask
}

function Receive-WttrPrefetch {
    # 未完成的预取保留在句柄里, 下次再收割(不提前丢弃); 不阻塞
    $task = $script:_WttrPrefetchTask
    if ($null -eq $task) { return $false }

    $job = $task.Task
    if ($null -eq $job -or $job.State -ne 'Completed') { return $false }

    $received = Receive-TmuxBackgroundTask -Task $task -TimeoutSeconds 0   # 0 = 只收割已完成的任务
    $script:_WttrPrefetchTask = $null
    if (-not $received.Succeeded) {
        Write-Verbose "[Receive-WttrPrefetch] 天气预取失败: $($received.ErrorMessage)"
        return $false
    }

    $raw = [string]$received.Result
    if ([string]::IsNullOrWhiteSpace($raw)) { return $false }

    # 写回模块缓存: 缓存键与同步路径一致, Get-WttrTitleSuffix 随即命中, 不再发 HTTP
    $script:_WttrCache.Result    = $raw
    $script:_WttrCache.FetchedAt = [datetime]::UtcNow
    $script:_WttrCache.CacheKey  = "CustomUrl|$($script:_WttrTitleUrl)"
    return $true
}
```

并行时序：

```text
t0  提交天气预取 (后台线程)      ────────────────┐
t0  提交 SSH 探测  (后台线程)      ─────────────┐│
t1  主线程收割 SSH 结果 → 渲染主视图            ││
t1  主线程渲染标题时先 Receive-WttrPrefetch：   ││
    · 已完成 → 写回缓存, 标题命中缓存, 零 HTTP  ││
    · 未完成 → 直接返回, 标题按"无天气"渲染     ││
                                              ↓↓
```

`Get-WttrTitleSuffix` 在发 HTTP 之前先调用 `Receive-WttrPrefetch`：预取已完成就写回缓存并命中，同步路径随即零 HTTP；预取未完成也**不等待**——标题区按"无天气"渲染，绝不阻塞首屏。天气预取失败同样静默降级，不影响主流程。

### 3.5 「失败绝不折叠成空列表」的语义

这是本次重构在数据层最重要的一条约束，分三层保证：

1. **探测层**：`Invoke-TmuxSessionFetch` 的三条降级路径都退回**同步**探测，而不是返回空集合。后台不可用只影响"快慢"，不影响"准不准"。
2. **归一层**：`Get-TmuxSessionState` 把原始返回值映射为 `Status`：

   | `Status` | 含义 | 是否故障 |
   |---|---|---|
   | `Ok` | 有会话 | 否 |
   | `Empty` | **查询成功但确实没有会话** | 否（不显示错误码，不显示降级指引） |
   | `Error` | 查询失败 | 是（显示错误码 + 降级指引） |

   `Get-TmuxErrorCode` 的判定顺序是**先特指后泛化**：超时 → 不可达 → 认证 → 命令失败 → 远端没装 tmux → 未知。

3. **渲染层**：只有 `Status = Error` 才渲染占位面板并显示错误码。`Status = Empty` 渲染的是"远端当前没有 tmux 会话 + 按 n 新建 / 按 r 刷新 / 按 s 直连"的操作提示，**不带错误码**。

因此：**探测失败永远不会显示成"没有会话"**。用户看到的空列表一定是"确实没有会话"，而失败一定有明确的错误码与下一步指引。

---

## 四、键位速查表

| 键 | 动作值 | 动作 | 需要会话 | 正常态文案 | 失败态文案 |
|----|--------|------|----------|------------|------------|
| `a` | `Attach` | 附着/恢复会话 | **是** | `[a]附着` | `[a]附着` |
| `n` | `New` | 新建 tmux 会话 | 否 | `[n]新建` | `[n]新建` |
| `r` | `Refresh` | 刷新会话列表 | 否 | `[r]刷新` | `[r]重试` |
| `s` | `Ssh` | 直连 SSH | 否 | `[s]SSH` | `[s]直连` |
| `x` | `Remove` | 删除会话（高危，二次确认在 `Remove-TmuxSession` 内） | **是** | `[x]删除` | `[x]删除` |
| `q` | `Quit` | 退出管理器 | 否 | `[q]退出` | `[q]退出` |

补充规则：

- **无会话时不暴露** `a`（附着）与 `x`（删除），避免出现"点了没反应"的死键；界面与行为保持一致（工具条不显示，键位也不解析）。
- **`Context` 只切换文案，不切换键位**：`r` 在任何状态下都是刷新/重试，`s` 在任何状态下都是 SSH/直连。用户的肌肉记忆不因状态切换而失效。
- **未登记的键**在动作条里提示一次并继续等待（最多 `-MaxAttempts` 次，默认 10）。
- **`ESC` 退出管理器**；**无输入**（非交互终端 / Ctrl-C / 读取失败）按"用户退出"处理。
- **表格内**：`↑↓` 选择，`Enter` 附着/恢复所选会话，`Esc` 进入底部动作条。

---

## 五、错误码表

| 错误码 | 含义 | 判定依据 | 用户指引 |
|--------|------|----------|----------|
| `E_SSH_TIMEOUT` | SSH 等待超时（作业被 Kill），与"远端命令失败"是两回事 | 探测结果标记超时 | 按 `r` 重试 · 按 `s` 直连 SSH |
| `E_SSH_UNREACHABLE` | 网络不可达 / 端口被拒绝 / DNS 失败 | 探测结果标记网络错误 | 按 `r` 重试 · 按 `s` 直连 SSH |
| `E_SSH_AUTH` | SSH 认证或主机密钥校验失败 | 错误文本命中认证关键字（如 `Permission denied` / `Host key verification failed`） | 按 `r` 重试 · 按 `s` 直连 SSH |
| `E_SSH_FAILED` | SSH 进程或远端命令失败（退出码非 0） | 退出码非 0 | 按 `r` 重试 · 按 `s` 直连 SSH |
| `E_NO_TMUX` | 命令跑通了但拿不到 tmux 版本（远端未安装 tmux / tmux server 未运行） | 退出码 0 且无版本信息 | 按 `r` 重试 · 按 `s` 直连 SSH |
| `E_UNKNOWN` | 没有任何探测信息（兜底，理论不可达） | 探测结果为空 | 按 `r` 重试 · 按 `s` 直连 SSH |

错误码在界面上出现在两个位置：**占位面板的 `State` 列**（`错误码 · 降级指引`）与**主视图标题的状态摘要**（失败态时标题摘要直接显示错误码）。

---

## 相关文档

- [交互菜单后端（PSTui GridView 单轨）](gridview-menus.md) —— 菜单能力边界、配色槽位、刷新语义
- [架构](architecture.md) —— 模块目录树与加载流程
- [命令一览](commands.md) —— 公开命令与交互流程
- [`docs/agents/architecture.md`](../agents/architecture.md) —— 架构不变量与 tmux 管理器交互契约
