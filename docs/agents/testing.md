> 本文件由根 [`AGENTS.md`](../../AGENTS.md) 文档导航按需路由加载；通用工作原则与安全边界见根文件。

# 测试与文档（Testing & Documentation）

## 测试门禁（不变量）

CI 强制以下四条不变量，任何一条不满足都会让 CI 变红：

- **测试失败必须阻断 CI**：`ShellPrompt/Tests/Invoke-Tests.ps1` 在出现 Fail 时以**非零退出码**结束。
- **测试规模不得低于 CI 设定的门槛**：测试入口支持 `-MinPassed`（通过用例数下限）与 `-MinTestFiles`（测试文件数下限），
  两者由 [CI workflow](../../.github/workflows/test.yml) **显式传参**（门槛数值只在该 workflow 里维护，改动会出现在 diff 里）。
  低于门槛同样以非零退出码结束 —— 整份测试文件被删除、或用例被大面积掏空时，CI 不会再"全绿蒙混过关"。
  门槛只做**下限**检查：新增测试不会让 CI 变红；降低门槛等于降低质量标准，必须在 PR 里说明理由。
- **静态分析不允许新增 Warning**：Error 永远阻断；Warning 走**增量基线**比对（见下文「静态分析」）。
- **Profile 冒烟检查必须通过**：`profile` job 用干净 pwsh 进程加载 `Microsoft.PowerShell_profile.ps1`，
  校验启动链路无 `[ShellPrompt]` 错误/警告、启动期自检通过、ShellPrompt 模块可导入。

> **实际测试结果以 CI 执行日志为准。** 本文件只描述不变量，**不记录任何一次运行的 Pass/Fail 数字、用例总数或测试文件数** ——
> 那些数字属于某一次快照，写进文档只会腐烂。需要看当前基线，去看最近一次 CI run 的日志；
> 需要在本地复现，按 [`docs/agents/environment.md`](environment.md) 的方式准备环境后跑同一批入口脚本。

- **测试分类**:
  - **单元测试**: `Get-*` / `Set-*` / `Test-*` / `Format-*` / `Connect-*` 等纯函数或近纯函数,
    每个被测函数至少 3-5 条用例(命中、未命中、错误兜底)。
  - **集成测试**: `Invoke-GridViewMenu` / `Show-*` 分发器 / `Start-TmuxSession`,
    覆盖多函数协作(列裁剪 + 颜色方案 + 隐藏字段恢复等)。
  - **行为测试**: `Update-Weather` / `Copy-SshPublicKey` / `Invoke-TmuxSessionDeletion` 等含 I/O 副作用的函数,
    仅断言"不抛"与"关键调用次数", 不强求输出文本(避免改文案就碎套)。

## 静态分析

- **命令**: `Invoke-ScriptAnalyzer -Path ./ShellPrompt -Recurse -Settings ./ShellPrompt/Settings.ScriptAnalyzer.psd1`
  (`-Path` 为必填参数; 配置文件与代码约定同步维护)。
- **入口脚本**: `pwsh -NoProfile -File ./ShellPrompt/Tests/Invoke-Lint.ps1`
  —— 扫描 → 与 Warning 基线比对 → 按结果给退出码（CI 依赖它）。
- **Warning 基线**: `ShellPrompt/Tests/pssa-warning-baseline.txt`。
  每行是一条**指纹**：`规则名|仓库相对路径|规范化消息|期望出现次数`。
  - 指纹**不含行号**：文件改动引起的行号漂移不会误报。
  - 出现次数用于区分"同一条消息在同一文件里出现多次"的情况（例如多条一模一样的 Empty catch）。
  - **当前次数超过基线次数** ⇒ 新增 Warning ⇒ CI 失败。
  - **当前次数少于基线次数** ⇒ 该 Warning 已被修复 ⇒ CI 不失败，但输出会提示**可以收紧基线**；
    确认修复无误后跑 `pwsh -NoProfile -File ./ShellPrompt/Tests/Invoke-Lint.ps1 -UpdateBaseline` 重新生成基线。
- **红线**:
  - **不允许新增 Error**; 发现 Error 立即修, 不得用 SuppressMessage 隐藏。
  - **不允许新增 Warning**; 确需接受时，在 PR 描述中说明理由，并同步更新基线文件（改动会出现在 diff 里，可审查）。
  - **不得**通过关闭规则、排除目录、忽略全部 Warning 等方式让门禁变绿。

## 持续集成（CI）

- **配置文件**: [`.github/workflows/test.yml`](../../.github/workflows/test.yml)（全仓唯一的 workflow）。
- **触发条件**: `push` / `pull_request` 且改动命中 `ShellPrompt/**`、`Microsoft.PowerShell_profile.ps1` 或该 workflow 本身;
  文档改动不触发。另有 `workflow_dispatch` 供手动触发。
- **三个 job**（互不依赖、可并行；任一失败都应立即可见）:
  - `test`: 装 PowerShell 7.6+ → 装 Pester 5+ → 跑 `ShellPrompt/Tests/Invoke-Tests.ps1`（含数量门禁参数）。
    退出码：0 = 全通过，1 = 存在 Fail，2 = 数量门槛未达标；非 0 一律让 job 失败。
  - `lint`: 装 PSScriptAnalyzer → 跑 `ShellPrompt/Tests/Invoke-Lint.ps1`。
    Error 或新增 Warning ⇒ job 失败；报告落 `.agent_cache/pssa.txt`。
  - `profile`: 装 PowerShell 7.6+ → 跑 `ShellPrompt/Tests/Invoke-ProfileSmoke.ps1`。
    用干净 pwsh 进程加载仓库根的 profile，断言启动链路无 `[ShellPrompt]` 错误/警告、自检通过、
    `$global:_MARKS` 存在且非空、`Ensure-ShellPrompt` 后模块可导入；失败即 job 失败。
    starship / fnm / PSReadLine 属于**可选依赖**，runner 上没装不算失败。
- **运行环境**: `windows-latest`。原因: 当前模块硬编码了 `ssh.exe` / `LOCALAPPDATA` / `TEMP` / `USERPROFILE`，
  套件也是在 Windows 上写的；迁到 `ubuntu-latest` 需要先补跨平台地基。
- **CI 不做的事**: 不加载用户 profile（`profile` job 用的是临时 HOME 下的干净 profile 路径）、
  不连真实 ssh/tmux 主机、不访问业务网络（wttr.in 在测试里已被 Mock）、不在仓库外写文件。
  安装 Pester / PSScriptAnalyzer 需要访问 PowerShell Gallery, 属于工具安装而非被测行为。

## 文档同步核对

- **触发条件**: 任何用户可见行为变化(Public 函数签名 / 配置键 / 默认值 / 菜单交互 / 渲染入口 / 模块加载顺序)。
- **同步清单**: `git diff --name-only README.md AGENTS.md docs/agents/architecture.md docs/readme/*`
  - `README.md`: 新增 / 修改 / 弃用命令必须给最小可运行示例。
  - `docs/agents/architecture.md`: 模块加载顺序 / 单轨菜单 / Phase 1 加载清单 / 启动期时序变更时必须更新。
  - `AGENTS.md` + `docs/readme/*`: README 已拆分, 用户可见变更按主题改对应分片
    (commands / configuration / features / architecture / gridview-menus), 不要写回 README 本体。
  - PR 描述: 新的用户可见变更写进 PR 描述(替代 CHANGELOG 条目)。
- **CHANGELOG 政策**: `ShellPrompt/CHANGELOG.md` **已收拢为存根**（2026-10-29）—— 历史段曾永久丢失,
  冻结前的条目描述的是当时已撤销 / 已移除的实现, 正文已由 git 历史替代。
  新条目**不写入** CHANGELOG; 用户可见变更同步规则见上面两行(README / PR 描述)。

## 人工测试标记

- **必标场景**: 涉及 **profile 加载 / SSH / tmux / prompt 渲染** 的改动,
  必须在 **PR 描述**中标注 `[人工测试必做]`(CHANGELOG 已冻结, 不进 CHANGELOG)。
- **最小真机验证集**:
  - 重启 pwsh 跑 `sss` / `Start-TmuxSession`, 标题区应仍显示 `城市名: 中文描述 +温度°C`
    (Get-WttrTitleSuffix 拆分前后行为必须完全一致)。
  - SSH 主机选择菜单 / tmux 会话列表 / tmux 管理器三种菜单各 1 轮交互。
  - 用一个**测试用** tmux 会话验证删除路径: 删除成功显示 `[OK]`, **失败(例如会话名不存在)必须显示警告且不显示 `[OK]`**。
  - Starship prompt 渲染正常, 无 ANSI 颜色错位或 escape 残留。

## 何时回跑基线

- 新增 / 删除 Private 函数(拆分、合并、抽出)。
- 改动 `ShellPrompt.psd1` 的 `FunctionsToExport` 或 `CmdletsToExport`。
- 改动 `Microsoft.PowerShell_profile.ps1` Phase 1 dot-source 链。
- 改动 starship 接管路径(Starship 安装 / `$ENV:STARSHIP_CONFIG` / `$ENV:STARSHIP_DISTRO` 等)。
- 阶段验收完成后强制回跑。
- 回跑结果看 CI 日志；**不要**把这次的 Pass/Fail 数字回抄进本文件。

## 调试与诊断

- **测试**: Before submitting changes, verify module loading (`Import-Module ./ShellPrompt`).
  Run tests via the single entry point (Pester v5+ / v6 语法):
  `pwsh -NoProfile -File ./ShellPrompt/Tests/Invoke-Tests.ps1`
  该入口默认在出现 Fail 时以**非零退出码**结束(CI 依赖它); 在交互会话里用 `&` 调用时加 `-NoExit`,
  否则 `exit` 会把当前会话一起结束。
  本地想复现 CI 的规模门禁, 可以显式带上 `-MinPassed` / `-MinTestFiles`（取 CI workflow 里同一组数值）。
- **静态分析**: `pwsh -NoProfile -File ./ShellPrompt/Tests/Invoke-Lint.ps1`
  （收紧基线时加 `-UpdateBaseline`）。
- **Profile 冒烟**: `pwsh -NoProfile -File ./ShellPrompt/Tests/Invoke-ProfileSmoke.ps1`
  （失败时返回非零；可选依赖缺失不算失败）。
- **临时输出约束**: 所有测试运行 / 静态分析 / 调试日志必须落到 `.agent_cache/` 下,
  仓库根目录禁止产生临时文件(`pester.txt` / `pssa.txt` / `*.tmp` 等)。

## 文档

- **Documentation**: 本文件是测试与文档义务的入口；文档同步清单见上文「文档同步核对」。
