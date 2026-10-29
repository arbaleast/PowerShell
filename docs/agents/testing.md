> 本文件由根 AGENTS.md 路由触发加载。上级约束见根文件"三层边界"。

# 测试与文档（Testing & Documentation）

## 测试基线

- **Pester**: 阶段 B(2026-10-19)实测 **249 → 264 Pass / 0 Fail**; 阶段 A 基线 249 Pass / 0 Fail,
  阶段 B 新增 `Get-WttrTitleSuffix.Tests.ps1`(9 用例) + `Get-WttrWeatherDescMap.Tests.ps1`(6 用例)。
  任何阶段后, 修改都不得让 Pass 数回退或引入 Fail。
- **测试分类**:
  - **单元测试**: `Get-*` / `Set-*` / `Test-*` / `Format-*` / `Connect-*` 等纯函数或近纯函数,
    每个被测函数至少 3-5 条用例(命中、未命中、错误兜底)。
  - **集成测试**: `Invoke-GridViewMenu` / `Show-*` 分发器 / `Start-TmuxSession`,
    覆盖多函数协作(列裁剪 + 颜色方案 + 隐藏字段恢复等)。
  - **行为测试**: `Update-Weather` / `Write-GridViewHint` 等含 I/O 副作用的函数,
    仅断言"不抛"与"关键调用次数", 不强求输出文本(避免改文案就碎套)。

## 静态分析

- **命令**: `Invoke-ScriptAnalyzer -Path ./ShellPrompt -Recurse -Settings ./ShellPrompt/Settings.ScriptAnalyzer.psd1`
  (`-Path` 为必填参数; 配置文件与代码约定同步维护)。
- **基线**(阶段 B 实测): **0 Error / 14 Warning / 4 Information**。
- **红线**:
  - **不允许新增 Error**; 发现 Error 立即修, 不得用 SuppressMessage 隐藏。
  - **新增 Warning 必须有合理理由**: 写入 CHANGELOG 条目并在 PR 描述中说明
    (如 `PSUseShouldProcessForStateChangingFunctions` 等已在模块约定内接受的忽略)。

## 文档同步核对

- **触发条件**: 任何用户可见行为变化(Public 函数签名 / 配置键 / 默认值 / 菜单交互)。
- **同步清单**: `git diff --name-only README.md ShellPrompt/CHANGELOG.md docs/agents/architecture.md`
  - `README.md`: 新增 / 修改 / 弃用命令必须给最小可运行示例。
  - `ShellPrompt/CHANGELOG.md`: HEAD 当前 134 行; 阶段 B 起的新条目**不再**写入 CHANGELOG
    (用户决定 CHANGELOG 永久丢失, 阶段 B 完后维持 134 行状态)。
  - `docs/agents/architecture.md`: 模块加载顺序 / 单轨菜单 / 依赖闭包 / 启动期时序变更时必须更新。
- **CHANGELOG 历史背景**: 阶段 A 之前 CHANGELOG 历史段已永久丢失, 不可重写或回填。

## 人工测试标记

- **必标场景**: 涉及 **profile 加载 / SSH / tmux / prompt 渲染** 的改动,
  必须在 CHANGELOG 条目末尾加 `[人工测试必做]` 标签(现阶段不进 CHANGELOG, 则改为 PR 描述中标注)。
- **最小真机验证集**:
  - 重启 pwsh 跑 `sss` / `Start-TmuxSession`, 标题区应仍显示 `城市名: 中文描述 +温度°C`
    (Get-WttrTitleSuffix 拆分前后行为必须完全一致)。
  - SSH 主机选择菜单 / tmux 会话列表 / tmux 管理器三种菜单各 1 轮交互。
  - Starship prompt 渲染正常, 无 ANSI 颜色错位或 escape 残留。

## 何时回跑基线(并刷新 Pester / PSScriptAnalyzer 计数)

- 新增 / 删除 Private 函数(拆分、合并、抽出)。
- 改动 `ShellPrompt.psd1` 的 `FunctionsToExport` 或 `CmdletsToExport`。
- 改动 `Microsoft.PowerShell_profile.ps1` Phase 1 dot-source 链。
- 改动 starship 接管路径(Starship 安装 / `$ENV:STARSHIP_CONFIG` / `$ENV:STARSHIP_DISTRO` 等)。
- 阶段验收(如阶段 A 8 项 / 阶段 B 6 项)完成后强制回跑。

## 调试与诊断

- **测试**: Before submitting changes, verify module loading (`Import-Module ./ShellPrompt`).
  Run tests via `Invoke-Pester ./ShellPrompt/Tests -Output Detailed` (Pester v5+ / v6 语法).
  任何 Pester 失败或新 Warning 必须先排查再提交流程。
- **临时输出约束**: 所有测试运行 / 静态分析 / 调试日志必须落到 `.agent_cache/` 下,
  仓库根目录禁止产生临时文件(`pester.txt` / `pssa.txt` / `*.tmp` 等)。

## 文档

- **Documentation**: 任何用户可见变更或配置更新必须在 `README.md` 留痕(用法示例、迁移说明)。