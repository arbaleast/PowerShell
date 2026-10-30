# Invoke-GridViewMenu.ps1 - PSTui Out-ConsoleGridView 菜单实现(主轨)
# 职责: 把 Show-HostSelector / Show-SessionManager 的交互层迁移到 PSTui 的
#       Out-ConsoleGridView(Terminal.Gui v2 表格视图)。
# 由两个同名分发器(Show-HostSelector.ps1 / Show-SessionManager.ps1)调用。
# 契约: 对外只返回含 .Value 字段的 PSCustomObject, 或 $null(用户 ESC/Ctrl-C 退出)。
#
# 能力补偿说明(相对原 ANSI 菜单的回退):
#   - PSTui 未暴露行级配色, 因此危险/提示语义改由 State 列文字 + 符号表达;
#   - 表格无底部快捷键提示条, 草案 A.2 已撤回 banner/hint 输出(alternate screen 隔离),
#     退出仅通过 ESC / Ctrl-C 表达;
#   - 不把"退出"混进表格行(会污染用户的过滤结果), 退出仅通过 ESC / Ctrl-C 表达;
#   - 表格不支持 Disabled 渲染, 因此选中后由调用侧阻断并给出明确告警。

# 注: Get-WttrWeatherDescMap 已拆到 ./Get-WttrWeatherDescMap.ps1(阶段 B.2, 2026-10-19),
#     42 条内置中英映射 + $script:Config.Weather.ExtraWeatherDescMap 用户扩展合并
#     逻辑保留在新文件, 由 profile Phase 1 依赖闭包自动 dot-source。
# 注: Get-WttrTitleSuffix 已拆到 ./Get-WttrTitleSuffix.ps1(阶段 B.1, 2026-10-19),
#     由 profile Phase 1 依赖闭包自动 dot-source, 此处不再内联定义。
#     调用方: Invoke-GridViewHostSelector / Invoke-GridViewSessionManager / Invoke-GridViewSessionList
# 注: 草案 A.2 已撤回(2026-10-19): Get-GridViewMenuTitleSuffix / Show-GridViewMenuBanner 的
#     共享拆分被回滚, 两个 Private 文件及其 Pester 测试一并删除.
#     撤回根因: PSTui -FullScreen 走 alternate screen buffer, banner/hint 的 stdout 输出被隔离;
#     同时 Terminal.Gui Window.Title 不支持 `\n` 多行, shortcutHint 二级摘要无法渲染.
#     撤回后, 3 个菜单 Title 区只保留单行 wttr 后缀(Get-WttrTitleSuffix 仍生效).

function Get-GridViewFocus {
    <#
    .SYNOPSIS
        解析 GridView 的初始焦点取值。

    .DESCRIPTION
        焦点取值来自 $script:Config.UI.GridViewFocus(用户配置优先, 缺省 Table)。
        以字符串形式返回, 交由 PowerShell 参数绑定器转换为 PSTui 的
        FocusTarget 枚举, 这样在调用点无需保证 PSTui.Models 已被加载。

    .OUTPUTS
        'Table' 或 'Filter'

    .EXAMPLE
        $focus = Get-GridViewFocus
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $focus = 'Table'
    if ($script:Config -and $script:Config.UI -and $script:Config.UI.GridViewFocus) {
        $focus = [string]$script:Config.UI.GridViewFocus
    }
    if ($focus -notin @('Table', 'Filter')) {
        # 配置值非法时静默回退到默认焦点, 不抛错阻断菜单
        $focus = 'Table'
    }
    return $focus
}

function ConvertTo-GridViewPlainText {
    <#
    .SYNOPSIS
        剥离 GridView 可见列文本中的内联 ANSI SGR 转义序列。

    .DESCRIPTION
        2026-10-30 根因修复: Terminal.Gui v2 的 TableView 基于 ConsoleDriver Cell
        Attribute 矩阵绘制, **不解析单元格内的内联 ANSI SGR 序列**(染色无效);
        且不可见的转义字节会干扰 Wcwidth 对 '⚠' 宽字符的列宽计算,
        导致 '⚠ 危险' 中间的半角空格被吞、终端里粘连显示。
        Format-GridViewStateText 的染色契约(含其 Pester 测试)保持不变, 它仍返回
        带色文本; 本函数仅在行数据**送入 Out-ConsoleGridView 之前**把可见列净化为
        纯文本。键列(KeyColumn)原样保留 —— Restore-GridViewSelection 依赖键列值
        与原始行匹配, 一旦键列被改写, 隐藏字段(Disabled/Value/Status)就回填不上。

    .PARAMETER Rows
        裁剪后的行数据(PSCustomObject 数组)

    .PARAMETER KeyColumn
        唯一键列名(原样保留, 不参与剥离)

    .OUTPUTS
        PSCustomObject 数组(非键列的 string 属性已剥离 ANSI SGR)

    .EXAMPLE
        $cleanRows = ConvertTo-GridViewPlainText -Rows $trimmedRows -KeyColumn 'Action'
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Rows,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$KeyColumn
    )

    # 仅剥离 SGR 染色序列(\e\[38;2;...m / \e\[0m 这类), 与 Format-GridViewStateText
    # 的产出形态一一对应; 仓库内其它可见列不产生 SGR, 该模式足够覆盖。
    $ansiPattern = [regex]::Escape([char]27) + '\[[0-9;]*m'
    $clean = [System.Collections.Generic.List[PSCustomObject]]::new($Rows.Count)
    foreach ($row in $Rows) {
        $clone = [ordered]@{}
        foreach ($prop in $row.PSObject.Properties) {
            $value = $prop.Value
            if ($prop.Name -ne $KeyColumn -and $value -is [string]) {
                $value = [regex]::Replace($value, $ansiPattern, '')
            }
            $clone[$prop.Name] = $value
        }
        $clean.Add([PSCustomObject]$clone)
    }
    return $clean.ToArray()
}

function Get-GridViewRenderParam {
    <#
    .SYNOPSIS
        组装 Out-ConsoleGridView 的渲染参数(单选模式 + 焦点 + 可选全屏)。

    .DESCRIPTION
        从 Invoke-GridViewPrompt 拆出, 保证入口函数不超过 ~80 行(见
        docs/agents/development.md 的函数拆分规约), 同时让参数装配可单独验证。
        全屏开关取自 $script:Config.UI.GridViewFullScreen: 默认 $false 时走 PSTui
        内联渲染, 3~4 行的轻量菜单不会被拉成整屏黑底空洞。

    .PARAMETER Title
        表格标题

    .OUTPUTS
        [hashtable] 可直接 splat 给 Out-ConsoleGridView 的参数表

    .EXAMPLE
        $gvParams = Get-GridViewRenderParam -Title 'TMUX 全局操作'
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Title
    )

    $gvParams = @{
        Title      = $Title
        OutputMode = 'Single'
        Focus      = Get-GridViewFocus
    }
    if ($script:Config -and $script:Config.UI -and $script:Config.UI.GridViewFullScreen) {
        $gvParams['FullScreen'] = $true
    }
    return $gvParams
}

function Invoke-GridViewPrompt {
    <#
    .SYNOPSIS
        统一的 GridView 弹窗调用与结果归一化入口。

    .DESCRIPTION
        负责四件事:
          1. 组装 Out-ConsoleGridView 的参数(单选模式 + 焦点 + 可选全屏),
             由 Get-GridViewRenderParam 承担;
          2. 裁剪隐藏列(防止内部字段泄漏到用户可见表格);
          3. 把可见列送入 Terminal.Gui 前剥离内联 ANSI SGR(TG TableView 不解析
             单元格内联转义且会引发宽字符列宽计算错误, 见 ConvertTo-GridViewPlainText);
          4. 捕获异常(输入被重定向等场景下 Out-ConsoleGridView 会抛可捕获错误
              并返回 $null, 不会挂起), 并在返回前恢复隐藏字段。

    .PARAMETER Rows
        行数据(PSCustomObject 数组), 建议包含 Value 列用于回传结果
    .PARAMETER Title
        表格标题
    .PARAMETER HiddenColumns
        哈希表: 键 = 隐藏列名, 值 = 默认恢复值(GridView 返回后注入到选中对象)。
        用于传递内部字段(Disabled/Value/Status)而不让它们出现在用户可见表格中。

    .OUTPUTS
        选中的行对象(含恢复的隐藏字段), 或 $null(退出/异常)

    .EXAMPLE
        $row = Invoke-GridViewPrompt -Rows $rows -Title 'SSH 主机选择器' -HiddenColumns @{ Disabled = $false; Value = '' }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Rows,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Title,
        [Parameter(Mandatory = $false)][hashtable]$HiddenColumns
    )

    if (-not $Rows -or $Rows.Count -eq 0) {
        return $null
    }

    # ---- 列裁剪: 只保留用户可见列, 隐藏内部字段 ----
    $plan = Get-GridViewColumnPlan -Rows $Rows -HiddenColumns $HiddenColumns
    $keyColumn = $plan.KeyColumn
    $hiddenKeys = $plan.HiddenKeys
    # 2026-10-30: 送入 Terminal.Gui 前剥离可见列的内联 ANSI(键列保留,
    # 隐藏字段回填依赖键列匹配)。Format-GridViewStateText 染色契约不受影响。
    $trimmedRows = ConvertTo-GridViewPlainText -Rows $plan.TrimmedRows -KeyColumn $keyColumn

    # 构建 Out-ConsoleGridView 参数, 用管道传数组(每个元素单独流入)
    # 注意: 不使用 -InputObject $Rows(数组整体), 因为 InputObject 类型是 [psobject]
    # (单一对象包装), 传入数组会导致 PowerShell 将整个数组包装为单一 PSObject,
    # GridView 枚举时看到的是数组类型的属性(Length/Count/SyncRoot...), 而非元素的
    # 属性(Action/State/Value)。改用管道传参后, 数组元素逐个流入, 行为正确。
    # 注: Desc 列已于 2026-10-19 删除(与 Action / Host 重复), 行对象的列集合为
    #     Action/Host/State/No/Session 这类"用户可见键", 内部字段则走 -HiddenColumns。
    $gvParams = Get-GridViewRenderParam -Title $Title

    # 配色属于纯视觉增强, 失败只告警一次并继续弹菜单(细节见 Initialize-GridViewColorScheme)
    Initialize-GridViewColorScheme

    try {
        # 管道传参: 数组元素逐个流入, 避免 -InputObject 将整个数组当单一 PSObject
        $selected = $trimmedRows | Out-ConsoleGridView @gvParams
    } catch {
        # 非交互终端(输入被重定向)会走到这里; 按"用户退出"语义处理, 不抛错
        Write-Warning "GridView 无法显示: $($_.Exception.Message)"
        return $null
    }

    if ($null -eq $selected) {
        return $null
    }

    # 归一化返回形态并恢复隐藏字段(Disabled/Value/Status)
    return (Restore-GridViewSelection -Selected $selected -Rows $Rows -KeyColumn $keyColumn `
            -HiddenKeys $hiddenKeys -HiddenColumns $HiddenColumns)
}

function Invoke-GridViewHostSelector {
    <#
    .SYNOPSIS
        主机选择菜单的 GridView 主轨实现。

    .DESCRIPTION
        以表格列出 ssh config 中的主机, LastHost 置顶并在 State 列标注。
        用户在表格内过滤(焦点在 Filter 时可打字)或用上下键移动, Enter 确认。
        退出请用 Esc 或 Ctrl-C(不提供退出行, 避免混入过滤结果)。

    .PARAMETER Hosts
        主机名数组(来自 Get-SshConfigHosts)

    .PARAMETER LastHost
        上次使用的主机名(用于置顶 + State 标注), 为空时从配置回退

    .PARAMETER Title
        菜单标题

    .PARAMETER ExitLabel
        退出提示文案(仅用于提示行, GridView 本身不渲染退出行)

    .OUTPUTS
        选中的行 PSCustomObject(.Value = 主机名), 或 $null(退出)

    .EXAMPLE
        $selected = Invoke-GridViewHostSelector -Hosts (Get-SshConfigHosts) -Title 'SSH 主机选择器' -ExitLabel '退出'
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    # ExitLabel 由调用方作为退出提示文案传入, 渲染在提示行; 当前实现里被 GridView 之外
    # 的调用链使用(Pester/Start-TmuxSession 间接消费). 显式抑制避免 PSSA 误报.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Hosts,
        [Parameter(Mandatory = $false)][string]$LastHost = "",
        [Parameter(Mandatory = $false)][string]$Title = "SSH 主机选择器",
        [Parameter(Mandatory = $false)][string]$ExitLabel = "退出"
    )

    if (-not $Hosts -or $Hosts.Count -eq 0) {
        Write-Warning "SSH 配置中未找到任何主机，请先在 ~/.ssh/config 中配置主机"
        return $null
    }

    if (-not $LastHost -and $script:Config -and $script:Config.SSH) {
        $LastHost = $script:Config.SSH.LastHost
    }

    $rows = @(Get-GridViewHostRow -Hosts $Hosts -LastHost $LastHost)

    # 草案 A.2 撤回: banner/hint 在 alternate screen 下不可见, Title `\n` 被 Terminal.Gui 单行截断
    # Title 区追加单行天气(顶部居中), 端点选择与清洗细节封装在 Get-WttrTitleSuffix 内
    $wttrSuffix = Get-WttrTitleSuffix
    $selected = Invoke-GridViewPrompt -Rows $rows -Title "$Title ($($Hosts.Count))$wttrSuffix" `
        -HiddenColumns @{ Disabled = $false; Value = '' }
    if ($null -eq $selected) {
        return $null
    }

    # Disabled 表格不支持灰显, 因此这里保留阻断逻辑作为兜底
    if ($selected.Disabled) {
        Write-Warning "该项当前不可用: $($selected.Host)"
        return $null
    }

    return $selected
}

function Invoke-GridViewSessionList {
    <#
    .SYNOPSIS
        tmux 会话列表选择菜单的 GridView 主轨实现(第三级菜单)。

    .DESCRIPTION
        以表格列出远程主机上的 tmux 会话, 列设计为 序号 / 会话名 / 状态。
        原 ANSI 菜单用 "[A]/[D]" 前缀徽章 + "▶" 指针表达状态与选中, GridView 无行级配色
        也无指针, 因此改由 State 列文本承载(与 Invoke-GridViewSessionManager 一致)。
        状态文案统一取自 Get-TmuxSessionStateText, 保证与其它渲染层完全一致。
        -AllowRefresh 时追加"⟳ 刷新会话列表"行, 选中后由上层重新拉取会话并重新弹窗
        (不引入定时轮询, 刷新完全由用户触发)。
        返回值统一归一化为含 Label / RawName / Desc / Value / Status 的对象,
        调用方无需感知实现细节。

    .PARAMETER Sessions
        会话数组(元素含 Name 与 Status, 来自 Get-TmuxSessions)
    .PARAMETER HostName
        远程主机名(用于标题)
    .PARAMETER Title
        菜单标题(不含主机名部分, 主机名由本函数拼接)
    .PARAMETER ExitLabel
        退出提示文案(仅用于提示行, GridView 本身不渲染退出行)
    .PARAMETER ShowStateBadge
        是否在 State 列显示 attached/detached 文本(删除场景可关掉以突出危险语义)
    .PARAMETER AllowRefresh
        是否追加"⟳ 刷新会话列表"行
    .PARAMETER TitleSuffix
        标题中的计数后缀(默认由 Get-TmuxSessionSummary 现场计算)

    .OUTPUTS
        含 .Value/.Label/.RawName 的 PSCustomObject, 或 $null(用户退出)
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')] # ExitLabel 参见 HostSelector 注释
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Sessions,
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $false)][string]$Title = "TMUX 会话列表",
        [Parameter(Mandatory = $false)][string]$ExitLabel = "返回",
        [Parameter(Mandatory = $false)][switch]$ShowStateBadge,
        [Parameter(Mandatory = $false)][switch]$AllowRefresh,
        [Parameter(Mandatory = $false)][string]$TitleSuffix = ""
    )

    if (-not $Sessions -or $Sessions.Count -eq 0) {
        Write-Warning "没有可用的 tmux 会话"
        return $null
    }

    $rows = @(Get-TmuxSessionGridRow -Sessions $Sessions -ShowStateBadge:$ShowStateBadge -AllowRefresh:$AllowRefresh)

    if (-not $TitleSuffix) {
        $summary = Get-TmuxSessionSummary -Sessions $Sessions
        $TitleSuffix = $summary.TitleSuffix
    }

    # 草案 A.2 撤回: banner/hint 在 alternate screen 下不可见, Title `\n` 被 Terminal.Gui 单行截断
    # Title 区追加单行天气(顶部居中), 端点选择与清洗细节封装在 Get-WttrTitleSuffix 内
    $wttrSuffix = Get-WttrTitleSuffix
    $selected = Invoke-GridViewPrompt -Rows $rows -Title "$Title [$HostName] ($TitleSuffix)$wttrSuffix" `
        -HiddenColumns @{ Disabled = $false; Value = ''; Status = '' }
    if ($null -eq $selected) {
        return $null
    }

    if ($selected.Disabled) {
        Write-Warning "该项当前不可用: $($selected.Session)"
        return $null
    }

    if ($selected.Value -eq $script:TmuxRefreshSignalValue) {
        return ConvertTo-TmuxRefreshSelection
    }

    $sessionName = [string]$selected.Value
    if (-not $sessionName) {
        return $null
    }
    return ConvertTo-TmuxSessionSelection -Name $sessionName -Status ([string]$selected.Status)
}
