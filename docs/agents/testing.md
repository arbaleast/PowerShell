> 本文件由根 [`AGENTS.md`](../../AGENTS.md) 文档导航按需路由加载；通用工作原则与安全边界见根文件。

# 测试与文档（Testing & Documentation）

## 测试基线

- **Pester 不变量**：任何阶段后，修改都不得引入 Fail，Pass 数不得低于最近一次实测基线。
- **最近一次实测基线**：`261 Pass / 0 Fail`（2026-10-29 GitHub Actions 在 `d666618` 上实测，13 个测试文件；`Invoke-Tests.ps1` 默认 Fail 即非零退出，所以"绿"本身就代表 0 Fail）。
- **真机覆盖状态（2026-10-29 起）**：自动化基线由 [CI](#持续集成ci) 实测并持续刷新（本节是唯一权威位置）；`sss` 三类菜单交互、tmux 删除路径的 `[OK]`/警告表现、starship 渲染等**交互项仍需人工真机验证**（见下文"最小真机验证集"），CI 不覆盖它们。
- **测试分类**:
  - **单元测试**: `Get-*` / `Set-*` / `Test-*` / `Format-*` / `Connect-*` 等纯函数或近纯函数,
    每个被测函数至少 3-5 条用例(命中、未命中、错误兜底)。
  - **集成测试**: `Invoke-GridViewMenu` / `Show-*` 分发器 / `Start-TmuxSession`,
    覆盖多函数协作(列裁剪 + 颜色方案 + 隐藏字段恢复等)。
  - **行为测试**: `Update-Weather` / `Copy-SshPublicKey` / `Remove-TmuxSession` 等含 I/O 副作用的函数,
    仅断言"不抛"与"关键调用次数", 不强求输出文本(避免改文案就碎套)。

## 静态分析

- **命令**: `Invoke-ScriptAnalyzer -Path ./ShellPrompt -Recurse -Settings ./ShellPrompt/Settings.ScriptAnalyzer.psd1`
  (`-Path` 为必填参数; 配置文件与代码约定同步维护)。
- **基线**（最近一次 CI 实测，2026-10-29 @ `d666618`）：**0 Error / 14 Warning / 4 Information**（与阶段 B 原测一致）。
- **红线**:
  - **不允许新增 Error**; 发现 Error 立即修, 不得用 SuppressMessage 隐藏。
  - **新增 Warning 必须有合理理由**: 在 PR 描述中说明
    (如 `PSUseShouldProcessForStateChangingFunctions` 等已在模块约定内接受的忽略)。

## 持续集成（CI）

- **配置文件**: [`.github/workflows/test.yml`](../../.github/workflows/test.yml)（全仓唯一的 workflow）。
- **触发条件**: `push` / `pull_request` 且改动命中 `ShellPrompt/**`、`Microsoft.PowerShell_profile.ps1` 或该 workflow 本身;
  文档改动不触发。另有 `workflow_dispatch` 供手动触发。
- **两个 job**:
  - `test`: 装 PowerShell 7.6+ → 装 Pester 5+ → 跑 `ShellPrompt/Tests/Invoke-Tests.ps1`（失败即非零退出）。
  - `lint`: 跑 PSScriptAnalyzer，**只在出现 Error 时失败**（与上面的红线一致），报告落 `.agent_cache/pssa.txt`。
- **运行环境**: `windows-latest`。原因: 当前模块硬编码了 `ssh.exe` / `LOCALAPPDATA` / `TEMP` / `USERPROFILE`，
  套件也是在 Windows 上写的；迁到 `ubuntu-latest` 需要先补跨平台地基。
- **CI 不做的事**: 不加载用户 profile、不连真实 ssh/tmux 主机、不访问业务网络（wttr.in 在测试里已被 Mock）、
  不在仓库外写文件。安装 Pester / PSScriptAnalyzer 需要访问 PowerShell Gallery, 属于工具安装而非被测行为。
- **新增/删除 Private 函数、修改 `FunctionsToExport`、改动 profile dot-source 链**时,
  除等 CI 结果外, 还要按下一节人工刷新本文件里的计数。

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

## 何时回跑基线(并刷新 Pester / PSScriptAnalyzer 计数)

- 新增 / 删除 Private 函数(拆分、合并、抽出)。
- 改动 `ShellPrompt.psd1` 的 `FunctionsToExport` 或 `CmdletsToExport`。
- 改动 `Microsoft.PowerShell_profile.ps1` Phase 1 dot-source 链。
- 改动 starship 接管路径(Starship 安装 / `$ENV:STARSHIP_CONFIG` / `$ENV:STARSHIP_DISTRO` 等)。
- 阶段验收完成后强制回跑。

## 调试与诊断

- **测试**: Before submitting changes, verify module loading (`Import-Module ./ShellPrompt`).
  Run tests via the single entry point (Pester v5+ / v6 语法):
  `pwsh -NoProfile -File ./ShellPrompt/Tests/Invoke-Tests.ps1`
  该入口默认在出现 Fail 时以**非零退出码**结束(CI 依赖它); 在交互会话里用 `&` 调用时加 `-NoExit`,
  否则 `exit` 会把当前会话一起结束。
  任何 Pester 失败或新 Warning 必须先排查再提交流程。
- **临时输出约束**: 所有测试运行 / 静态分析 / 调试日志必须落到 `.agent_cache/` 下,
  仓库根目录禁止产生临时文件(`pester.txt` / `pssa.txt` / `*.tmp` 等)。

## 文档

- **Documentation**: 任何用户可见变更或配置更新必须在 `README.md` 留痕(用法示例、迁移说明)。