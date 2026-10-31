# New-TmuxTuiSessionTable.ps1 - TGUI 会话表格视图构建(阶段 A 视图层, 无头可测)
#
# 背景 (2026-10-30 TGUI 迁移 · 阶段 A 视图层):
#   把 ConvertTo-TmuxTuiViewModel 的会话行挂到 Terminal.Gui 2.4.10 的
#   TableView 上, 列宽/对齐由 New-TmuxTuiColumnPlan 的计划驱动。
#   2.4.10 实测 API:
#     数据源  Terminal.Gui.Views.EnumerableTableSource<PSCustomObject>
#             (IEnumerable<PSCustomObject>, Dictionary<string,
#              Func<PSCustomObject, object>>)  —— 列名 -> 行取值函数,
#             字典键序 = 列序。
#     列样式  TableView.Style.ColumnStyles = Dictionary<int, ColumnStyle>",
#             ColumnStyle 无参 ctor, MinWidth/MaxWidth/Alignment 可变
#             (Alignment 枚举: Start/End/Center/Fill)。
#     构造    TableView(ITableSource) 无需 Application.Init(无头可测)。
#
# 契约: 只创建对象, 不进事件循环(Run 由调用方驱动); 传入的视图模型与
# 列计划均为纯函数产物 —— 本函数是"组装层"。

function New-TmuxTuiSessionTable {
    <#
    .SYNOPSIS
        按视图模型 + 列计划构建 Terminal.Gui 会话表格视图(无头可测)。

    .DESCRIPTION
        步骤:
          1. 以视图模型的 SessionRows 为数据源(PSCustomObject[], 不伪造行);
          2. 只把计划里 Visible=$true 的列挂进 EnumerableTableSource 的
             列字典(键 = 列名, 取值函数 = 行属性);
          3. TableView(ITableSource) 构建表格, 逐可见列写
             ColumnStyle.MinWidth/MaxWidth/(Alignment=End 若 RightAlign);
          4. 返回 { Source; Table; VisibleColumns }。

        列计划来自 New-TmuxTuiColumnPlan(纯函数, 窄窗口自动隐藏)。

    .PARAMETER ViewModel
        ConvertTo-TmuxTuiViewModel 的产物。

    .PARAMETER ColumnPlan
        New-TmuxTuiColumnPlan 的产物。

    .OUTPUTS
        [PSCustomObject] .Source(数据源) / .Table(TableView) / .VisibleColumns(string[])
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$ViewModel,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$ColumnPlan
    )

    if ($PSCmdlet.ShouldProcess('TGUI 会话表格视图', 'Construct')) { } else { return $null }

    $tg = Get-TguiContext

    # ---- 1. 数据源: 只挂可见列, 列字典键序 = 列序 ----
    # 行泛型用 [object] 而非 [PSCustomObject]: PSObject 类型解析会撞上
    # "PSCustomObject -> PSCustomObject 转换失败"(不同 ALC/程序集同名类型),
    # object 泛型无此坑, 取值函数闭包由 PowerShell 动态取属性, 行为等价。
    $visible = @($ColumnPlan | Where-Object { $_.Visible })
    $columnDict = [System.Collections.Generic.Dictionary[ [string], [System.Func[ [object], [object] ] ] ]]::new()
    foreach ($col in $visible) {
        switch ($col.Name) {
            'No'      { $columnDict['No']      = [System.Func[[object],[object]]]{ param($r) $r.No } }
            'SESSION' { $columnDict['SESSION'] = [System.Func[[object],[object]]]{ param($r) $r.Session } }
            'STATUS'  { $columnDict['STATUS']  = [System.Func[[object],[object]]]{ param($r) $r.Status } }
            'WINDOWS' { $columnDict['WINDOWS'] = [System.Func[[object],[object]]]{ param($r) $r.Windows } }
            default   { throw "TGUI 列计划含未知列: $($col.Name)" }
        }
    }

    $rowsForSource = [object[]]@($ViewModel.SessionRows)
    $sourceType = $tg.Assembly.GetExportedTypes() |
        Where-Object { $_.FullName -match '^Terminal.Gui.Views.EnumerableTableSource' } |
        Select-Object -First 1
    $genericSource = $sourceType.MakeGenericType([object])
    # 构造器必须按参数形状过滤(2 参: 行集合 + 列字典), 否则 TG 升级新增重载时会绑错
    # 实测形状(2.4.10): IEnumerable`1 + Dictionary`2[String, Func`2[Object,Object]]
    $sourceCtor = $genericSource.GetConstructors() |
        Where-Object {
            $p = $_.GetParameters()
            $p.Count -eq 2 -and $p[1].ParameterType.Name -in @('Dictionary`2', 'IDictionary`2')
        } |
        Select-Object -First 1
    if ($null -eq $sourceCtor) {
        throw "TGUI EnumerableTableSource 构造器形状已变(期望 2 参: 行集合 + 列字典)"
    }
    $source = $sourceCtor.Invoke(@($rowsForSource, $columnDict))

    # ---- 2. TableView 构建 + 列样式 ----
    $tableCtor = $tg.Types.TableView.GetConstructors() |
        Where-Object {
            $p = $_.GetParameters()
            $p.Count -eq 1 -and $p[0].ParameterType.Name -eq 'ITableSource'
        } |
        Select-Object -First 1
    $table = $tableCtor.Invoke(@($source))

    # ---- 2.1 关键退订: 摘掉 CollectionNavigator (type-ahead) ----
    # 2.4.10 IL 实测(证据 .agent_cache/tui-nprobe/probe11/15/17):
    #   TableView.OnKeyDown 内有 "key == Key.HotKey → CycleToNextTableEntryBeginningWith"
    #   的**字母键 type-ahead**(跳到"以该字母开头的行"), 实测无匹配行也把键标记
    #   已处理 => N/R/S/X/Q 这些应用级 Shortcut 热键永远到不了
    #   InvokeCommandsBoundToKey(manifest: "字母键被吞只触发 Enter" 键盘注入失败根因)。
    #   Cycle 首句是 "if (CollectionNavigator == null) return false" —— 置 null 即
    #   整段短路。牺牲 type-ahead(本产品未承诺该交互), 换 Goal 三-3 要求的
    #   N/R/S/X/Q 单键动作。置回 null 实测读回确实为 null, 行为已验证。
    $table.CollectionNavigator = $null

    # ---- 2.2 整行选中(2026-10-31 UI 升级) ----
    # 2.4.10 的 FullRowSelect 默认 $false: PTY 渲染取证(.agent_cache/uir/)实测,
    #   此时只有**选中单元格**(第 0 列"#")给出 Focus 背景高亮, 选中行的其余列
    #   全部普通底色 —— 选中状态不明显。置 $true 后整行都取 Focus 槽位,
    #   行选中一目了然(属性可读写已由无头探针验证, readback=True)。
    $table.FullRowSelect = $true

    # ColumnStyle 类型从列样式字典自身的泛型参数取第二项(第一项是 int 列序):
    # 不能用 Values.GetType().GetGenericArguments() —— ValueCollection 是
    # Dictionary<int, ColumnStyle> 的嵌套类型, 其 GetGenericArguments 带出
    # 外层为 [int, ColumnStyle] 两个参数, 取[0] 会拿到 Int32(Int32 上没有
    # MinWidth 属性, 即会得到"属性不存在"的失败)。
    $columnStyleType = $table.Style.ColumnStyles.GetType().GetGenericArguments()[1]
    $alignEnum = $columnStyleType.GetProperty('Alignment').PropertyType
    # ColumnStyles 字典按**源列序**(0..N-1)写 Min/Max/对齐
    for ($index = 0; $index -lt $visible.Count; $index++) {
        $plan = $visible[$index]
        $columnStyle = [System.Activator]::CreateInstance($columnStyleType)
        $columnStyle.MinWidth = $plan.MinWidth
        $columnStyle.MaxWidth = $plan.MaxWidth
        # 对齐: Start / End(右对齐) / Center(STATUS 列居中, 便于一眼扫状态)
        $alignmentName = 'Start'
        if ($plan.PSObject.Properties['Alignment'] -and $plan.Alignment) {
            $alignmentName = [string]$plan.Alignment
        }
        elseif ($plan.RightAlign) { $alignmentName = 'End' }
        elseif ($plan.PSObject.Properties['CenterAlign'] -and $plan.CenterAlign) { $alignmentName = 'Center' }
        $columnStyle.Alignment = [Enum]::Parse($alignEnum, $alignmentName)
        $table.Style.ColumnStyles[$index] = $columnStyle
    }

    # ---- 2.3 TG 的单元格宽度硬上限 = 100(不要改!) ----
    # TG 2.4.10 的 TableView.MaxCellWidth **默认 100**: 任何列的单元格宽度都被
    # 硬上限在 100 列 —— 真机 130/160 列取证: SESSION 列被截成 100, 整张表
    # 只有 128 列宽。
    # ★ **不要把 MaxCellWidth 调大**: 实测调成 102 / 132 后, TG 的 TableView 在
    #   布局阶段**死循环**(PTY 里 40 秒只吐 `[1;1H[?25l`, 事件循环根本起不来)——
    #   这是 TG 2.4.10 的上游限制, 不是本仓库能绕开的。
    #   列宽计划侧(New-TmuxTuiColumnPlan)已按 100 这个上限封顶, 计划与渲染一致。

    # ---- 2.4 关闭"末列自动拉伸"(2026-10-31 UI 升级) ----
    # 2.4.10 的 TableStyle.ExpandLastColumn 默认 $true: 末列(WINDOWS, 9 宽)
    # 会被拉伸成"吃掉全部余量的巨型空列"(真机 120 列取证里 SESSION 只剩两列时
    # 末列直接铺满 33 列)。现在列宽之和**正好等于终端宽**(见 New-TmuxTuiColumnPlan
    # 的几何公式), 不需要拉伸; 关掉它末列才保持 9 列的紧凑数值列。
    try {
        $table.Style.ExpandLastColumn = $false
    } catch {
        Write-Verbose "[New-TmuxTuiSessionTable] 设置 ExpandLastColumn 失败: $($_.Exception.Message)"
    }

    return [PSCustomObject]@{
        Source          = $source
        Table           = $table
        VisibleColumns  = @($visible | ForEach-Object { $_.Name })
    }
}
