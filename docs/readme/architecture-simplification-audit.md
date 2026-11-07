# D1 · 架构精简与死代码深度审计（只读，2026-11-07）

- 审计日：2026-11-07（只读审计，本文件是唯一 README 侧写入产物；分析脚本与中间数据在 `.agent_cache/audit-tui/`、`.agent_cache/audit2/`、`.agent_cache/audit-tests/`，不在仓库交付面内）。
- 方法：PowerShell 7.6.9 `Parser::ParseFile` 全仓 AST 调用图（`.agent_cache/audit-tui/ast-callgraph.ps1` → `callgraph.json` / `callgraph-summary.txt`），区分生产调用（排除 Tests、排除 `[/\\][Tt]ests[/\\]` 路径）与测试调用；`&`/`.` 调用运算符、`Invoke-Expression` 动态调用、字符串形式引用函数名均已在 Token 级取证，确认**不存在可动态复活**旧轨函数的通路；另做只读文档/配置 SSOT 比对与测试套件耦合分析（`.agent_cache/audit2/DOC-SSOT-FINDINGS.md`、`.agent_cache/audit-tests/test-suite-audit.md`）。
- 用语约定：本文件一律用全角「涉及」「不涉及」「配置键」等措辞，正文**零未转义尖括号**；处置标签只有四档：`【保留】`（维持现状 / 已达标 SSOT 实践）、`【合并】`（收敛双头 / 迁移夹具）、`【删除】`（AST 证实生产零调用链的死代码 / 重复段）、`【暂缓】`（有相似性但语义有差异，合并收益小于风险）。

---

## A · 总体结论

1. **交互 UI 是 Terminal.Gui v2.4.10 单轨，进度动画是 PwshSpectreConsole 2.6.3 单轨，边界清晰**（`docs/readme/architecture.md:225`、`ShellPrompt/ShellPrompt.psd1:9-10`）。生产路径由 AST 实证：
   - SSH：`Start-TmuxSession.ps1:98 → Show-HostSelector(私有) :64/:80 → Show-SshHostDashboard :80 → Invoke-SshHostDashboard(1674 行，最大编排层)`；
   - tmux：`Start-TmuxSession.ps1:120 → Show-TmuxTuiDashboard(423 行) :236 → New-TmuxTuiDashboardWindow(727 行) → New-TmuxTuiSessionRowList / New-TmuxTuiSessionDetailPanel / New-TmuxTuiShortcutList`。
2. **旧 TUI 残留集中在一条「旧主机选择器轨」+ 一个「旧 TableView 会话表轨」+ 3 个孤岛函数**，合计生产死代码约 **1 142 行**（`Invoke-TguiHostSelector.ps1` 393 + `New-TguiHostSelectorWindow.ps1` 313 + `Get-HostSelectorRow.ps1` 51 + `Get-HostSelectorStateText.ps1` 47 + `New-TmuxTuiSessionTable.ps1` 169 + `New-TmuxTuiColumnPlan.ps1` 97 + `Clear-TmuxScreen`（`Enter-TmuxAlternateScreen.ps1:95` 内 40 行）+ `Set-SshHostListRowFocus`（`New-SshHostListView.ps1:538` 内 32 行））。其中 `Invoke-TguiHostSelector` / `New-TmuxTuiSessionTable` / `Clear-TmuxScreen` 生产调用方为 0（仅测试）、`Set-SshHostListRowFocus` 连测试也是 0（AST `callgraph.json` 双零）；`New-TguiHostSelectorWindow` 生产调用方只有已死的 `Invoke-TguiHostSelector.ps1:152`，`Get-HostSelectorStateText` 生产调用方只有已死的 `Get-HostSelectorRow.ps1:44`——即删除入口后调用链整体塌缩。
3. **「保留可用、可随时回退」的说法不再成立**：`Show-HostSelector.ps1:6-8` 注释与 `docs/readme/tui-dashboard.md:13,298-300`、`docs/readme/architecture.md:105-120`、`docs/agents/architecture.md:31` 均称旧轨非默认路径，但 `Show-HostSelector` 自 PSTui 移除后已无 `-Backend` 参数（`ShellPrompt.Tests.ps1:470-473` 与 `Get-ConsoleUiBackend.Tests.ps1:219-222` 双重断言），**没有任何代码路径能把用户送回旧轨**；旧轨唯一的可见性只有测试调用与 `Get-ConsoleUiBackend.Tests.ps1:225-226` 的存在性断言。按「测试不得仅因『测试还调用』而判定存活」的规则，该轨实用性 = 0、维护成本 = 每 6 处文档注释 + 4 个测试文件都要继续背着它。
4. **文档 SSOT 有 12 处必须修正的漂移 + 约 360-420 行可删/可链接的重复段**（候选详见 `.agent_cache/audit2/DOC-SSOT-FINDINGS.md` F1-F51）。最严重三处：`docs/agents/wttr.md:3,9` 仍把天气后缀写进 `Invoke-TguiHostSelector -Title`（真实链路 `Show-HostSelector.ps1:76-80 → Show-SshHostDashboard -TitleSuffix → Invoke-SshHostDashboard.ps1:217`）；`README.md:49-75` 整段仍是旧 tmux 形态（紫底选中 / 双退出项 / 已删行号 / 旧列名）；`docs/readme/architecture.md:36` 测试清单写 38 条目 / 31 测试而实际 51 条目 / 44 测试，且 `docs/agents/testing.md:31,113` 正在引用其中已被漏记的 `ModuleLoad.Tests.ps1`。
5. **测试套件 44 个文件 / 静态 698 个 It 消耗庞大夹具样板**（模块导入样板 96 处 3 变体、tmux VM 工厂 6 份、tg 反射样板 15 处、键注入 2 套、跨文件重复断言 ≥14 对不变量），可提取 `Tests/Fixtures/` 公共夹具 - 重复断言本身是「两端都要同步」的隐式维护点。
6. **红线全部安全**：5 个公开导出（`Show-UserScoopLogo` / `Start-TmuxSession` / `Copy-SshPublicKey` / `Invoke-Reload` / `Update-Weather`，生产 prodFiles=0 是 profile / CLI 入口，非死代码）、`sss` 仪表盘、SSH 主机管理、tmux 删除二次确认、配置向后兼容（`Initialize-Config.ps1:9-12,56-62` 已有静默忽略策略）、Pester / PSSA 门禁均不受本轮删除影响；旧轨删除后 MinPassed 300（现有静态 698，删后约 660）与 MinTestFiles 15（44→43）余量充足。

---

## B · 四层处置表

第一层「模块骨架与启动链路」，第二层「旧 TUI 轨 / 孤岛代码」，第三层「测试套件与门禁」，第四层「文档 SSOT」。行号格式 = 文件:行。

### B-1 模块骨架与启动链路

| # | 对象 | 证据 | 处置 |
|---|---|---|---|
| B1-1 | `ShellPrompt.psm1` 六步加载（清单校验 → 存在性 → Initialize-Config → Spectre → Private 全量 Ordinal → Public → SSH 补全器） | ast-callgraph: 全部 `Private/*.ps1`/`Public/*.ps1` 均被 dot-source | 【保留】 |
| B1-2 | `CoreScripts.psd1` 清单 73 条（Private 68 + Public 5）与磁盘完全一致（本审计实测 diff 空集）；有 `ModuleLoad.Tests.ps1:384-406` 一致性断言兜底 | `CoreScripts.psd1:22-91,93-99`；audit2 F39 | 【保留】 |
| B1-3 | profile `StartupLoadOrder` 5 文件 + AST 自检（`. $full` dot-source 于 profile 顶层 + 缺失/失败/命令解析报警） | `Microsoft.PowerShell_profile.ps1:37-48,62-77,89-140` | 【保留】 |
| B1-4 | `Invoke-DeferredInit`（profile:287-341, 345 同步调用）与 fnm / starship / PSReadLine 链路：函数命名残留「Deferred」但已是**同步**启动期调用；`fnm env` 输出经 `Invoke-Expression`（`Initialize-FnmEnvironment.ps1:202,251`） | ast-callgraph CallOperator 清单 | 【暂缓】（生产已全部同步调用、无功能死区；仅建议在函数头注释补写「同步调用、非延迟执行」说明，避免读者误判时机） |

### B-2 旧 TUI 轨 / 孤岛代码

| # | 对象 | 证据 | 处置 |
|---|---|---|---|
| B2-1 | 旧主机选择器轨 4 文件整族删除：`Invoke-TguiHostSelector.ps1:1-393`、`New-TguiHostSelectorWindow.ps1:1-313`、`Get-HostSelectorRow.ps1:1-51`、`Get-HostSelectorStateText.ps1:1-47` | ast-callgraph：`Invoke-TguiHostSelector` prodFiles=0 / testFiles=1（`New-TguiHostSelectorWindow.Tests.ps1:93,101`）；`New-TguiHostSelectorWindow` prod 唯一调用 = `Invoke-TguiHostSelector.ps1:152`；`Get-HostSelectorRow` prod=0 / test=2；`Get-HostSelectorStateText` prod 唯一调用 = `Get-HostSelectorRow.ps1:44`。`Show-HostSelector.ps1:6-8` 注释自证「旧轨可回退」但无 `-Backend` 通路 | 【删除】 |
| B2-2 | 旧 TableView 会话表轨 2 文件删除：`New-TmuxTuiSessionTable.ps1:1-169`、`New-TmuxTuiColumnPlan.ps1:1-97` | ast-callgraph：`New-TmuxTuiSessionTable` prodFiles=0 / testFiles=1；`New-TmuxTuiColumnPlan` 生产唯一调用 = `New-TmuxTuiLayoutPlan.ps1:181`，但 `.Columns` 产物**无任何生产消费点**（全仓 `\.Columns` 生产 grep 仅该构造行 + `:48` 注释） | 【删除】 |
| B2-3 | `Clear-TmuxScreen`（`Enter-TmuxAlternateScreen.ps1:95-135`，40 行孤岛） | ast-callgraph prodFiles=0 / testFiles=1；`ShellPrompt.Tests.ps1:111` 仅作「不导出名单」，非功能依赖 | 【删除】 |
| B2-4 | `Set-SshHostListRowFocus`（`New-SshHostListView.ps1:538-569`，32 行） | ast-callgraph prodFiles=0 / testFiles=0 —— 完全孤立，连测试也没引用 | 【删除】 |
| B2-5 | 配置键 `Colors.DarkGray`（`Initialize-Config.ps1:28`） | 全仓生产 grep 无消费（ConsoleColor 默认 `DarkGray` 是 `Get-SshHostDashboardTheme.ps1:151,155` 等处的另一机制，非本键） | 【删除】 |
| B2-6 | `Show-TguiFrameRate`/`Set-TguiFrameRate`/`New-TguiHostWindow`/`Get-TguiVm`/`ConvertFrom-SshXtermOutput` 形态校验 | ast-callgraph prodFiles ≥ 1 有稳定调用方（`Tui-Navigation.Tests.ps1:190` 与生产视图共享） | 【保留】 |
| B2-7 | `New-TmuxTuiLayoutPlan` 在删掉 `New-TmuxTuiColumnPlan` 后剩余产物（`TitleRow / StatsRow / HintRow / TableRow / TableHeight / SplitMode / ListWidth / DividerX / DetailX / DetailWidth`） | `New-TmuxTuiDashboardWindow.ps1:302-452` 全部消费点实证 | 【保留】 |

### B-3 测试套件与门禁

| # | 对象 | 证据 | 处置 |
|---|---|---|---|
| B3-1 | `New-TmuxTuiSessionTable.Tests.ps1`（186 行 / 12 It，整文件绑死旧轨） | audit-tests §一-1：L13 / L41-179 直调两函数 | 【删除】 |
| B3-2 | `New-TguiHostSelectorWindow.Tests.ps1`（195 行）：前 2 个 Describe（8 It）绑死旧轨；第 3 个 Describe `Show-HostSelector (分发器业务装配)`（L107-195, 6 It）mock `Show-SshHostDashboard`，测的是生产分发器 | audit-tests §一-2 → 整文件改名为 `Show-HostSelector.Tests.ps1` 并删前两个 Describe | 【合并】 |
| B3-3 | `ShellPrompt.Tests.ps1:323-371`（Get-HostSelectorRow 7 It + L533-543 存在性断言 + L91-118 负名单 3 名）与 `Get-ConsoleUiBackend.Tests.ps1:224-232,249-255`（孤岛建档检查 + 空断言） | audit-tests §一-3/§一-4：删源文件后 L536-537、L225-226 **必红** | 【合并】（就地修剪，逐 It 改「函数不存在」断言并同步注释） |
| B3-4 | `Tmux-SessionState.Tests.ps1:107` 注释提及旧轨 | 无断言依赖 | 【合并】（只改注释） |
| B3-5 | `Tests/Fixtures/` 公共夹具抽取：模块导入样板 96 处 / tmux VM 工厂 6 份 / tg 反射样板 15 处 / 键注入 2 套 / 子进程 harness 3 份 / Mock 样板 136 处 | audit-tests §四：`New-TmuxTuiDashboardWindow.Tests.ps1` 单文件 8 次 `Import-Module`、`Show-TmuxTuiDashboard.Tests.ps1:24 Get-TguiVm` 等 | 【合并】 |
| B3-6 | 跨文件重复断言 ≥14 对（Backend 恒 TerminalGui、无 -Backend、UI 无 Backend 键、Assert 注入抛错、不导出名单 5 名重叠、PSTui 已删名单 23 ⊃ 12、回退轨入口、LayoutPlan 分栏断点全量两份、零重叠、Get-SshHostListClip、Get-TguiTextWidth CJK、迟到竞态、Shutdown 补偿） | audit-tests §四逐条 | 【暂缓】（先抽夹具，再裁断言；一次性合并易与门禁基线交错） |
| B3-7 | 3 个 Diag-TguiXxx 手工诊断脚本（134/208/245 行）不进 CI 但 PSSA 扫描占用 36 条豁免 | audit-tests §二：`pssa-warning-baseline.txt:29,34` | 【保留】 |
| B3-8 | 11 个 `-Skip:$IsWindows` 用例在 windows-latest 恒跳过 | `Get-SshHostDetail.Tests.ps1:370`、`Invoke-SshCaptureOutput.Tests.ps1:193` | 【保留】 |
| B3-9 | PSSA 双套规则名（`Settings.ScriptAnalyzer.psd1:11,48` 的 `PSAvoidUsingGlobalVariables` / `PSUseShouldProcessForStateChangingFunctions` vs 基线 `PSAvoidGlobalVars` / `PSShouldProcess`）+ `PSUseCmdletCorrectly`（基线 L18）依赖 PSSA 默认规则集未 pin | audit-tests §三-1/§三-2 | 【暂缓】（未 pin 默认规则集是最大隐式耦合；改动前先在 issue 里留指纹对照风险） |

### B-4 文档 SSOT

| # | 对象 | 证据 | 处置 |
|---|---|---|---|
| B4-1 | `docs/readme/architecture.md:36`（测试清单计数 38/31）+ `:37-74` 全量明细，与 `docs/agents/testing.md:31,113` 引用的 `ModuleLoad.Tests.Tests.ps1` 冲突，且违反 testing.md:18-20「不记数字」政策 | audit2 F2 | 【删除】（改链接） |
| B4-2 | `docs/readme/architecture.md:75-142`（Private 68 全量树，写 67 / 缺 1 文件）+ `docs/agents/architecture.md:93`（42） | audit2 F1 | 【合并】（改「主要文件 + 链接 CoreScripts.psd1」） |
| B4-3 | `README.md:49-75` 旧 tmux 形态（紫底 :63 、双退出 :60、行号 :63、旧列名 :75） | audit2 F22-F26 | 【合并】（改短图 + 链接 features/tui） |
| B4-4 | `docs/agents/wttr.md:3,9`（旧轨天气渲染链路，与 `docs/agents/architecture.md:211` 自相矛盾） | audit2 F27 | 【合并】（改 `Show-HostSelector.ps1:76-80 → Show-SshHostDashboard -TitleSuffix → Invoke-SshHostDashboard.ps1:217`） |
| B4-5 | 4 份键位表互相矛盾（`tui:118-126` 大写 / `tui:999-1018` 小写 / README:65-73 / features:63-71） | audit2 F8 + `Get-TmuxActionDefinition.ps1:62-67` | 【合并】（以源函数为唯一事实源，其余改链接） |
| B4-6 | `docs/readme/tui-dashboard.md` 历史段（§2.14.1/2.14.2 :560-605、§2.15 :725-843、孤儿验收残段 :1116-1129、阶段演进三处 :64-75/727-730/858-865、:661 旧紫底取证）+ 章节错位（§2.15/2.16 挂在写有「五、已知限制」章下） | audit2 F32-F37 | 【合并】（§2.15 压成 3-5 行变更记录；残段删除；章节重编号列为二阶段） |
| B4-7 | 12 处档案型重复（公开命令×6、公钥顺序×3、SSH 示意×3、tmux 示意×3-4、配置示例×3、天气×5、Colors×2、Scheme×3、门禁命令×3、环境×3、导航×4、双加载×2） | audit2 F3-F21 | 【暂缓】（先落实「必更新」12 处与 B4-1/2/5，摊后逐对收敛） |
| B4-8 | `ShellPrompt.psd1:9-10` 注释「UI 渲染全部走 PwshSpectreConsole」+ `New-TmuxTuiDashboardWindow.ps1:5` 注释「含会话表格 New-TmuxTuiSessionTable」+ `Start-TmuxSession.ps1:10`、`Show-HostSelector.ps1:6-8` 旧轨注释 | audit2 F47/F48 | 【删除】（注释就地改写，随源码删除一并提交，不算独立变动） |

---

## C · 新旧 TUI 对比表

口径：《PwshSpectreConsole(2.6.3, 进度/格式化) vs Terminal.Gui v2.4.10(全屏交互)》为**职责层**；《旧轨 vs 现行轨》为**实现层**。两侧均由实测（2.4.10 反射探针 `.agent_cache/tgui-probe/REPORT.md`，现行 Lineage `#9b871512 Forest Matrix`）。

| 维度 | PwshSpectreConsole 2.6.3（现役） | Terminal.Gui v2.4.10（现役） | 旧轨（待删） |
|---|---|---|---|
| 职责 | `Invoke-WithProgress` / 旋转样式 / `Write-Host` 完成后的格式化 | 3 个全屏入口：SSH 主机选择 `Show-SshHostDashboard` → `Invoke-SshHostDashboard`、tmux 仪表盘 `Show-TmuxTuiDashboard` → `New-TmuxTuiDashboardWindow`、业务子面板（`New-SshHostDetailPanel` 等） | 单表格主机选择 `Invoke-TguiHostSelector` + TableView 会话表 `New-TmuxTuiSessionTable` |
| 关键类型 | Spinners / ProgressTask / Markup | `Application`、`Window`、`Label`、`View.NewKeyDownEvent`、`Keyboard`、`TableView`（仅旧轨） | `TableView` + `EnumerableTableSource` + `ColumnStyle` |
| 状态 | Vendored 2.6.3；`Get-SpinnerStyleMapping.ps1:49-56` 与测试钉死 | Vendored 2.4.10；驱动固定 `'ansi'`（`Show-TmuxTuiDashboard.ps1:24-28`），SCENE 在 `New-SshHostDashboardWindow.ps1` / `New-TmuxTuiDashboardWindow.ps1` | Vendored 2.4.10，`Get-TguiContext.ps1` 同机制但**无生产入口** |
| 备注 | `ShellPrompt.psd1:9-10` 注释应改双轨（audit2 F47） | `Initialize-Config.ps1:53-62` 已明确唯一轨 | `Show-HostSelector.ps1:6-8` / 同文件 :6-8 注释须同步删 |

（表中全表零尖括号。）

---

## D · 量化收益

| 类目 | 现值 | 删除后 | 来源 |
|---|---|---|---|
| 生产源文件行数（Private 68 + Public 5 = 16 319 行） | 16 319 | 约 15 177（-1 142 行 / -7.0%） | 本审计 A 节死代码集合 LOC |
| `ShellPrompt/Private` 文件数 | 68 | 63（-5 文件：B2-1 4 个 + B2-2 2 个 = 6 文件、加回 Enter-TmuxAlternateScreen / New-SshHostListView 2 个文件就地剪函数） | `CoreScripts.psd1:22-91`，B2 逐条 |
| CoreScripts 清单条目 | 73 | 66-67 | B2-1/B2-2 联动 |
| It 用例数（静态） | 698 | 约 660-663（-27 It → 删除 12+8+7，另补「不存在」正断言 +4-6） | audit-tests §一 / §五 |
| 测试文件数 | 44 | 43（`New-TguiHostSelectorWindow.Tests.ps1` 改名 `Show-HostSelector.Tests.ps1` + `New-TmuxTuiSessionTable.Tests.ps1` 整删） | 同上 |
| CI 门禁余量 | MinPassed 300 / MinTestFiles 15 | 660/43 ≈ 2.2 倍 / 2.9 倍 | `test.yml:91` |
| 文档行数（README+AGENTS+docs/*） | 3 043 | 约 2 640-2 680（-360~-420 行，-12%~-14%） | audit2 F1-F40 + 本表 B4 |
| 配置键 | 17（Paths1 + Colors9 + SSH1 + Weather2 + UI.Theme4） | 16 - `Colors.DarkGray` | B2-5 |
| 夹具重复 | 96 导入样板 / 6 VM 工厂 / 15 反射样板 / 136 Mock | 迁到 `Tests/Fixtures/` 后每类 1 份 | audit-tests §四 |
| 仓库总行数 | 31 586（`.ps1/.psm1/.psd1`）。 | -约 2 200-2 400（含测试与文档） | 本审计合计 |

---

## E · 风险防御

**硬红线（一条都不许破）**
1. 5 个公开导出（`Show-UserScoopLogo` / `Start-TmuxSession` / `Copy-SshPublicKey` / `Invoke-Reload` / `Update-Weather`）零变更：B 表四层每一项都**不触碰**任何 `Public/*.ps1`，B1-1 六步加载不动。
2. `sss` tmux 仪表盘、SSH 主机仪表盘、tmux 删除二次确认（`Invoke-TmuxSessionDeletion.ps1:79` 已含 `ConvertTo-SshEscapedString` + 确认参数）路径无改动；删除的 `New-TmuxTuiSessionTable` / `New-TmuxTuiColumnPlan` 从未在 `Show-TmuxTuiDashboard → New-TmuxTuiDashboardWindow` 主路上出现过。
3. 配置向后兼容：`Initialize-Config.ps1:9-12` 「已删键静默忽略」合同不变；`Colors.DarkGray` 删除后，用户若有 `Colors.DarkGray` 覆盖也走**同一静默忽略**通路（与 2026-10-29 的 `Paths.LogPath` / `SSH.ConnectTimeout` / Keys 域清理案例同型）。
4. Pester / PSSA 门禁零放水：MinPassed 300 / MinTestFiles 15 由 `test.yml:91` 单点维护，**文档侧不新增这两个数字**（testing.md:10-13 已有政策）。删旧轨后基线文件 `pssa-warning-baseline.txt` 无条目指向旧轨测试文件（audit-tests §三-5），`Diag-TguiXxx` 若不删则免除不减。
5. Terminal.Gui 2.4.10 边界不动：所有界面敏感性变更（引用性责备、估算、`Application.ScreenChanged`、`RequestStop`、`BindKeyToApplication`）均未列入本轮任何【删除】项。

**删除联动四件套（做【删除】必做的四份修缮）**
- ① `CoreScripts.psd1`：删 `Get-HostSelectorRow.ps1, Get-HostSelectorStateText.ps1, Invoke-TguiHostSelector.ps1, New-TguiHostSelectorWindow.ps1, New-TmuxTuiColumnPlan.ps1, New-TmuxTuiSessionTable.ps1` 六条（L30,31,54,63,65,70）→ `ModuleLoad.Tests.ps1:384-406` 一致性断言兜底；
- ② 测试六处联动（B3-1/2/3/4）：`ShellPrompt.Tests.ps1:91-118,323-371,533-543` + `Get-ConsoleUiBackend.Tests.ps1:224-232,249-255` 就地改「不存在」断言；
- ③ 4 处旧轨注释：`Show-HostSelector.ps1:6-8`、`Start-TmuxSession.ps1:10`、`New-TmuxTuiDashboardWindow.ps1:5`、`Tmux-SessionState.Tests.ps1:105-108` + `docs/readme/architecture.md:105-120` 树条目 + `docs/agents/architecture.md:31` 一句话 + `tui-dashboard.md:13,298-300`；
- ④ `audit2 F27` wttr 链路改写：删除 B2-1 后语义即明确「旧轨不再存在」，与本条处置联动，改写为 `Show-HostSelector.ps1:76-80 → Invoke-SshHostDashboard.ps1:217` 链路。

**反例保护（防误删）**
- `New-TmuxTuiLayoutPlan` 必须留：删掉的只是 `New-TmuxTuiColumnPlan` 这个**分支**；`New-TmuxTuiLayoutPlan.ps1:181` 会改为 `#`。测试上注意 `Show-TmuxTuiDashboard.Tests.ps1:49`、`Tui-Navigation.Tests.ps1:190-200` 都断言 `New-TmuxTuiLayoutPlan` 契约，别误伤。
- `Get-ConsoleUiBackend` / `Assert-ConsoleUiReady` / `Set-TguiTheme` / `Resolve-TguiThemeName` / `Get-TguiContext` / `Get-TguiTextWidth` 是**新轨公共设施**，B2-1 删的是「选择器窗口族」不是「TGUI 基础设施」，注意分开。
- `binding` 上的 `$_` 型字符串保留（`ConvertTo-SshEscapedString` / `Get-TguiContext` 等 30 处 `& $var` 代表 scriptblock/委托调用，非旧轨）——已逐条核对 callgraph Token 区，无敌复活入口。

**门禁联动时序**
- PSSA：改 `Initialize-Config.ps1`（删 `DarkGray` 一行）与源文件删除会造成**告警条数下降**，需执行 `-UpdateBaseline` 或在 `.github/workflows/test.yml:138` 的基线文件上同步收缩（`ShellPrompt/Tests/Invoke-Lint.ps1:766-772`）。
- Pester：不动 `Invoke-Tests.ps1`，只靠 `MinPassed 300` 与 `MinTestFiles 15` 自适应余量。

---

## F · 六阶段安全执行计划

> 每阶段结束跑 `pwsh -NoProfile -File ./ShellPrompt/Tests/Invoke-Tests.ps1 -MinPassed 300 -MinTestFiles 15`、`Invoke-Lint.ps1`、`Invoke-ProfileSmoke.ps1` 三道门禁（命令见 `docs/readme/development.md:22-31`），全绿才进下一阶段；每阶段独立一个 commit，遵循 `docs/agents/commit-convention.md`。

### 阶段 1 · 零风险文档 / 注释清洗（无源码变动）
- 删 `docs/readme/architecture.md:36-74`（测试明细改链接 `ShellPrompt/Tests/` + `docs/agents/testing.md`）；`readme/architecture.md:75-142` 全量树改「主要文件 + 链接 CoreScripts.psd1」；`docs/agents/architecture.md:93` 42 → 链接。
- 改 `docs/agents/wttr.md:3,9`（B4-4）、`README.md:49-75` 短图 + 链接（B4-3）、`tui-dashboard.md:9` 「一条轨」表述、`testing.md:25` 集成测试清单（B3-3 关联）与 `:62` 补 `Modules/**` 触发、`ShellPrompt.psd1:9-10` 注释、`New-TmuxTuiDashboardWindow.ps1:5` 注释（audit2 F47/F48）。
- 删 `tui-dashboard.md:1116-1129` 孤儿验收残段、压缩 §2.15 至 3-5 行变更注记（§B4-6）。**门禁：三道全绿（PSSA 基线不变）。**

### 阶段 2 · 测试侧先行修剪（不删源码，先让测试适配「文件将不存在」的未来态）
- 改 `ShellPrompt.Tests.ps1:91-118` 负名单（删 3 个旧轨名）+ `:323-371` 删 Get-HostSelectorRow 7 It + `:533-543` 存在性断言改为「文件不存在」正断言；`Get-ConsoleUiBackend.Tests.ps1:224-232,249-255` 改「函数不存在」正断言。
- `New-TguiHostSelectorWindow.Tests.ps1` 删前 2 个 Describe → 改名 `Show-HostSelector.Tests.ps1`。
- 同步 `Tmux-SessionState.Tests.ps1:107` 注释。**门禁：三道全绿（It 698 → 约 660，文件 44 → 43）。**

### 阶段 3 · 删除旧主机选择器轨 4 文件（B2-1）+ 孤岛 2 函数（B2-3/B2-4）+ 配置键 1 项（B2-5）
- 删 `ShellPrompt/Private/Invoke-TguiHostSelector.ps1` / `New-TguiHostSelectorWindow.ps1` / `Get-HostSelectorRow.ps1` / `Get-HostSelectorStateText.ps1`；`Enter-TmuxAlternateScreen.ps1:95-135` 剪 `Clear-TmuxScreen`；`New-SshHostListView.ps1:538-569` 剪 `Set-SshHostListRowFocus`；`Initialize-Config.ps1:28` 剪 `DarkGray` 行。
- 同步 `CoreScripts.psd1`（4 条）+ `Show-HostSelector.ps1:6-8` / `Start-TmuxSession.ps1:10` 注释。**门禁：三道全绿；PSSA 基线同步收缩。**

### 阶段 4 · 删除旧 TableView 会话表轨 2 文件（B2-2）
- 删 `ShellPrompt/Private/New-TmuxTuiSessionTable.ps1` / `New-TmuxTuiColumnPlan.ps1`；`New-TmuxTuiLayoutPlan.ps1:181` 的 `Columns = @(New-TmuxTuiColumnPlan ...)` 一行为 `Columns = @()` 占位或直接删字段（后者推荐，测试 `New-TmuxTuiDashboardWindow.Tests.ps1:537-591` 只断言布局量）。
- 同步 `CoreScripts.psd1`（2 条 L65,L70）+ `docs/readme/tui-dashboard.md` §2.x 相关「保留轨」说明去重。**门禁：三道全绿。**

### 阶段 5 · 文档 SSOT 收敛第二波（audit2 F7-F21 的键位表、示意、公钥、配置示例重复收敛 + F32-F37 章节重编号 + tui 历史段落压缩）
- **只做去重与链接**，不改任何字段语义；`Get-TmuxActionDefinition.ps1` / `ShellPrompt.psd1` / `Initialize-Config.ps1` / `New-TmuxTuiLayoutPlan.ps1` 为四个事实源，本次只收敛引用侧。**门禁：三道全绿（PSSA 基线不变）。**

### 阶段 6 · 测试夹具抽取（B3-5）
- 建 `ShellPrompt/Tests/Fixtures/`：`Import-ShellPrompt.ps1`、`New-TestTmuxViewModel.ps1`、`Get-TguiApplicationApi.ps1`、`Invoke-TguiKeyDown.ps1`、`Invoke-TestChildProcess.ps1`（audit-tests §四建议清单）。
- **暂不做**跨文件重复断言一键删除（B3-6 暂缓）与 PSSA 规则集 pin（B3-9 暂缓）；这两项建议开独立 issue 用长期分支跟踪。**门禁：三道全绿全量基线对比（567→660+ 无 I-It 退化）。**

### 阶段完成判据
- 每阶段末 `git diff --stat` 的行数变化与 D 表对应行吻合：阶段 1 ≈ -280 文档行；阶段 2 ≈ -30 测试 It；阶段 3 ≈ -840 生产行；阶段 4 ≈ -266 生产行 + -186 测试行；阶段 5 ≈ -200 文档行；阶段 6 ≈ 夹具行迁置。
- 审计中间产物（`.agent_cache/audit-tui/callgraph.json`、`.agent_cache/audit2/DOC-SSOT-FINDINGS.md`、`.agent_cache/audit-tests/test-suite-audit.md`）不进仓库，不随 commit 变动。

---

* 审计方法与原始数据（可再跑）：`.agent_cache/audit-tui/ast-callgraph.ps1`（AST 调用图生成器，全仓函数定义/调用点/调用操作符/动态调用/字符串引用 5 类取证）、`.agent_cache/audit2/DOC-SSOT-FINDINGS.md`（F1-F51 文档 SSOT）、`.agent_cache/audit-tests/test-suite-audit.md`（测试套件与门禁耦合）。红线条目与「删除联动四件套」如本文件 E 节；不改变 B/C/D 三表任意处置标签。
