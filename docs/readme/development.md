# 🛠️ 开发者指南

本页是参与 ShellPrompt 开发的入口：环境准备、提交前必须跑的门禁、文档同步义务。**代码规范与领域红线的权威版本**在 [`docs/agents/`](../agents/)，本页只做导航和摘要，不重复维护规则原文。

## 环境准备

| 组件 | 要求 |
|------|------|
| PowerShell | **7.6+**（模块清单强制；`Tests/Invoke-Tests.ps1` 也会做版本守卫） |
| Pester | **5+**（测试使用 v5/v6 语法） |
| PSScriptAnalyzer | 任意较新版本 |

```powershell
Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force -AllowClobber
Install-Module PSScriptAnalyzer -Scope CurrentUser -Force -AllowClobber
```

更完整的本机环境说明见 [`docs/agents/environment.md`](../agents/environment.md)。CI 只跑在 `windows-latest`：模块与测试按 Windows 编写（`ssh.exe` / `LOCALAPPDATA` / `TEMP` / `USERPROFILE`），在 Linux 上跑套件时个别 Windows 专属用例失败属于预期。

## 提交前门禁

```powershell
# 单元 / 集成测试（出现 Fail 或以非零码结束）
pwsh -NoProfile -File ./ShellPrompt/Tests/Invoke-Tests.ps1

# 静态分析（Error 阻断；Warning 走增量基线）
pwsh -NoProfile -File ./ShellPrompt/Tests/Invoke-Lint.ps1

# Profile 启动冒烟（干净 pwsh 进程加载仓库 profile）
pwsh -NoProfile -File ./ShellPrompt/Tests/Invoke-ProfileSmoke.ps1
```

- 三个入口都可以在 CI 之外单独运行；测试不联网、不连真实 ssh/tmux 主机。
- 测试运行 / 静态分析 / 调试输出统一写到 `.agent_cache/`，不要在仓库根产生临时文件。
- PSScriptAnalyzer 的 Warning 基线在 [`pssa-warning-baseline.txt`](../../ShellPrompt/Tests/pssa-warning-baseline.txt)；确需接受新增 Warning 时在 PR 中说明理由并更新基线（`Invoke-Lint.ps1 -UpdateBaseline`）。
- 完整不变量与门禁说明见 [`docs/agents/testing.md`](../agents/testing.md)。

## 代码约定摘要

| 主题 | 要求 |
|------|------|
| 命令命名 | 使用 PowerShell 认可的动词（`Get-Verb`） |
| 函数 | 每个函数加 `[CmdletBinding()]` 和 `[OutputType()]`；职责单一，过长时拆分 |
| 作用域 | 优先 `$script:` / 局部作用域；避免 `$global:`（`Show-TmuxTuiDashboard` 与 TGUI 事件循环的跨线程状态除外，见源码注释） |
| 错误处理 | 参数校验用 `[ValidateScript()]` + `throw`；可恢复失败用 `Write-Warning`；外部命令先 `Get-Command` 检测 |
| 配置 | 不硬编码用户偏好；用户配置优先于默认配置 |
| 内部函数 | `Private/` 中的函数不导出，也不要在文档里当作公开命令介绍 |

领域细节见 [`docs/agents/development.md`](../agents/development.md)、[`docs/agents/domain-ssh-tmux.md`](../agents/domain-ssh-tmux.md) 与 [`docs/agents/architecture.md`](../agents/architecture.md)。

> **PSSA 已知约束**：[`Settings.ScriptAnalyzer.psd1`](../../ShellPrompt/Settings.ScriptAnalyzer.psd1) 中 `PSUseCorrectCasing` 的 `CheckCommands` 被关闭。原因是该规则读取参数元数据时会实例化 PwshSpectreConsole 的动态 `ValidateSet` 生成器，而 PSSA 调用时没有 Runspace，会导致整个文件的扫描结果作废。关键字 / 操作符 / 别名的大小写检查仍然生效。

## 人工测试

涉及 **profile 加载 / SSH / tmux / prompt 渲染** 的改动，必须在 PR 描述中标记 `[人工测试必做]`，并按 [`docs/agents/testing.md`](../agents/testing.md) 的最小真机验证集执行（SSH 主机选择器与 tmux 仪表盘各走一轮，测试用会话验证删除路径与终端还原）。

## 文档同步

- 用户可见行为变更（公开命令签名、配置键、默认值、菜单交互、模块加载顺序）需要同步更新 `README.md` 和/或 `docs/readme/` 下对应分片。
- `ShellPrompt/CHANGELOG.md` 已冻结为存根，不再新增条目；用户可见变更写入 PR 描述。
- 文档与代码行为冲突时，以源码为准，并同步修正文档。

## 提交规范

使用 Conventional Commits：`type(scope): message`

- **Types**：`feat`、`fix`、`docs`、`refactor`、`test`、`chore`
- 示例：`feat(tmux): add session rename support`
- 完整规范见 [`docs/agents/commit-convention.md`](../agents/commit-convention.md)。
