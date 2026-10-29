# ShellPrompt

快速、干净、可扩展的 PowerShell 终端增强体验。

[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](ShellPrompt/LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-7.6+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Starship](https://img.shields.io/badge/Starship-Prompt-8356ff.svg)](https://starship.rs)
[![Tmux](https://img.shields.io/badge/Tmux-Sessions-1BB91F.svg)](https://github.com/tmux/tmux)


> **本文已瘦身（2026-10-29）**：只留概览、安装与故障排除；细节按主题拆到 [`docs/readme/`](docs/readme/)，一章一文件，改内容时改分片、别写回本文。

## 📚 文档地图

| 原章节 | 去处 | 内容 |
|---|---|---|
| ✨ 功能特点 | [`docs/readme/features.md`](docs/readme/features.md) | 远程开发 / 终端增强 / UI 组件 / 工具链 / 天气（菜单标题区 + 提示符） |
| 🎨 配置 | [`docs/readme/configuration.md`](docs/readme/configuration.md) | 配置文件位置、优先级、配置项（Paths/Colors/SSH 域，含消费状态；Weather/UI 域交叉链接）、用户示例 |
| ⚡ 命令一览 | [`docs/readme/commands.md`](docs/readme/commands.md) | 公开命令、内部封装、别名、开发模式重载 |
| 🏗️ 架构 | [`docs/readme/architecture.md`](docs/readme/architecture.md) | 目录结构、加载流程、关注点分离、Spinner/Progress 单轨 Spectre 调度 |
| 🎛️ 交互菜单后端 | [`docs/readme/gridview-menus.md`](docs/readme/gridview-menus.md) | PSTui GridView 单轨契约、会话文案、配色槽位、能力与性能 |
| 🛠️ 开发者指南 | [`docs/readme/development.md`](docs/readme/development.md) | 命名/作用域/函数拆分/输出注解/错误处理 |

## ✨ 功能速览

- **远程开发** — `Start-TmuxSession` 菜单式管理 tmux 会话、`Copy-SshPublicKey` 一键推公钥、SSH config 主机 Tab 补全
- **终端体验** — ANSI 欢迎 Banner + 随机语录、PSReadLine 历史补全增强、profile 分阶段加载计时
- **交互式 UI** — Spectre.Console 单轨动画（`Invoke-WithProgress`：进度动画 + 异常重拋）、PSTui `Out-ConsoleGridView` 单轨菜单、5 套 spinner 样式名
- **工具链** — Starship prompt、fnm 自动切 Node 版本
- **天气** — 三个交互菜单标题区的 wttr.in 天气短串（10 分钟缓存 + 5 秒超时兜底，失败静默跳过）

细节见 [功能特点](docs/readme/features.md)。
## 🚀 安装

### 前置依赖

| 依赖 | 说明 |
|------|------|
| PowerShell 7.6+ | **唯一支持版本**。`ShellPrompt.psd1` 声明 `PowerShellVersion = '7.6'`；Windows PowerShell 5.1 已不再支持。抬高门槛的原因是交互菜单主轨依赖的 [`PSTui`](Modules/PSTui/1.0.5/README.md) 是 .NET 10 二进制模块, 要求 PS 7.6+ |
| `PSTui` | 交互菜单**唯一**渲染实现, 仓库内置于 `Modules/PSTui/`。缺失/版本冲突/非交互宿主时, 交互菜单调用会抛出可定位的终止错误（模块本身仍可正常加载） |
| starship | 可选 — 现代化 Prompt，通过 `Get-Command starship` 检测 |
| fnm | 可选 — Node.js 版本管理。**当前按 `fnm.exe` 检测**（Windows 实现）；Linux/WSL 上 `fnm` 名称探测尚未适配，Node 注入会静默跳过 |
| ssh | 可选 — 远程连接时按需使用 |
| tmux | 可选 — 远程会话管理时按需使用 |

> **注意**：本模块**未发布到 PSGallery**，请使用本地路径导入。

### 安装步骤

1. **克隆仓库**

   ```powershell
   git clone https://github.com/arbaleast/PowerShell.git "$HOME\Documents\PowerShell"
   ```

2. **激活 Profile（在 `$PROFILE` 中 dot-source 仓库内的 profile）**

   ⚠️ **不要把 `Microsoft.PowerShell_profile.ps1` 复制到 `$PROFILE` 位置**。该文件以**自身所在目录**为仓库根（`Split-Path -Parent $MyInvocation.MyCommand.Path`），再从根目录定位 `ShellPrompt/` 模块与 `Modules/` 依赖；复制出去会导致找不到模块。正确做法是在 `$PROFILE` 里引用仓库中的原文件：

   ```powershell
   # 确保 $PROFILE 所在目录存在
   New-Item -ItemType Directory -Force -Path (Split-Path $PROFILE) | Out-Null

   # 在 $PROFILE 末尾追加一行 dot-source（路径按你的实际克隆位置修改）
   Add-Content $PROFILE '. "$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"'
   ```

   之后每个新 pwsh 会话都会加载仓库内的 profile，`git pull` 更新仓库即可生效，无需重新复制文件。

3. **首次启动**

   启动新的 PowerShell 窗口：欢迎 Banner、别名（`ll` / `which` / `sss` / `ssh-copy-id`）立即可用；`ShellPrompt` 模块本身**懒加载**，首次调用 `sss`（`Start-TmuxSession`）或 `ssh-copy-id`（`Copy-SshPublicKey`）时才触发 `Import-Module`。

### 手动调试

如需手动验证模块加载：

```powershell
Import-Module ./ShellPrompt/ShellPrompt.psd1
```

### 平台注意事项

| 平台 | 注意事项 |
|------|----------|
| **Windows** | 建议使用 `code $PROFILE` 配对编辑器路径；本文安装步骤按 Windows 路径书写 |
| **Linux / WSL** | 注意 `ssh-agent` 转发配置；SSH ControlMaster socket 路径与 Windows 存在差异。安装流程与 Windows 相同（克隆 + 在 `$PROFILE` 中 dot-source），但两处实现当前为 **Windows 取向**：fnm 环境缓存写 `$env:LOCALAPPDATA`（Linux 未设置时该变量为空），fnm 按 `fnm.exe` 检测。本仓库文档修订时**未在 Linux / WSL 上实测验证**，遇到差异欢迎反馈 issue |


## 🎨 配置

```powershell
$HOME/.ShellPrompt/config.ps1
```

**用户配置 → 默认配置**，同名键覆盖模块内置默认值（见 [`Initialize-Config.ps1`](ShellPrompt/Private/Initialize-Config.ps1)）。完整配置项、域划分与示例见 [配置](docs/readme/configuration.md)。

> **2026-10-29 变更**：移除了长期无消费方的配置项 —— `Paths.LogPath`、`SSH.ConnectTimeout`、`SSH.ForceTTy`、整个 `Keys` 域、`Colors.LightGray` / `White` / `BgDarker` / `Bold` / `Dim`。在 `config.ps1` 里继续配置它们会被**静默忽略**（不报错）。

## ⚡ 命令

公开 5 个：`Show-UserScoopLogo`、`Start-TmuxSession`、`Update-Weather`、`Copy-SshPublicKey`、`Invoke-Reload`。别名、内部封装与 `Invoke-Reload` 开发模式重载见 [命令一览](docs/readme/commands.md)。

## 🏗️ 架构与交互菜单

目录结构与启动加载流程见 [架构](docs/readme/architecture.md)；菜单主轨契约、会话状态文案、GridView 配色与性能特征见 [交互菜单后端](docs/readme/gridview-menus.md)。

## 🛠️ 开发者

命名与作用域、函数拆分、输出注解、错误处理约定见 [开发者指南](docs/readme/development.md)；SSH/tmux 红线、测试义务、提交规范的**权威版本**在其路由的 [`docs/agents/`](docs/agents/) 子规约。

**测试与 CI**：跑测试统一用仓库入口 `pwsh -NoProfile -File ./ShellPrompt/Tests/Invoke-Tests.ps1`（默认在 Fail 时以非零退出码结束；交互会话内用 `&` 调用时加 `-NoExit`）。`.github/workflows/test.yml` 会在 `ShellPrompt/**`、profile 或 workflow 变更时自动跑同一套件与 PSScriptAnalyzer（仅 Error 失败），详见 [测试与文档](docs/agents/testing.md)。

## 🔧 故障排除

| 症状 | 可能原因 | 解决方案 |
|------|----------|----------|
| 启动后 `sss` 报找不到 `ShellPrompt` 模块 | 把 profile **复制**到了 `$PROFILE`，导致仓库根定位失效 | 恢复 `$PROFILE` 为一行 dot-source 仓库内的原文件（见「安装步骤 2」），不要复制 |
| Profile 启动报 `Get-RandomQuote` / `New-WelcomeBanner` / `Resolve-ColorTable` 未识别 | `Microsoft.PowerShell_profile.ps1` Phase 1 依赖未就绪 | Phase 1 按 `$script:StartupLoadOrder` 显式有序加载 5 个启动期文件；若仍出现，请查看 Phase 1 自检输出的 `缺失命令` / `缺失文件` 列表（格式为 `文件 -> 命令名`），据此把缺失的文件补进清单 |
| 显示 "ShellPrompt 模块未正确导入" | 模块未在启动流程中加载 | 手动执行 `Import-Module ./ShellPrompt/ShellPrompt.psd1` 验证 |
| `Start-TmuxSession` 提示 "SSH 配置中未找到任何主机" | `~/.ssh/config` 文件缺失或为空 | 编辑 `~/.ssh/config` 添加主机配置 |
| 远程主机无 tmux | 远程未安装 tmux | 黄色警告后**保留菜单**（UI-first，不自动降级）：可选手动 `Ssh 直连` / `Refresh` 重试 / `Exit` 退出 |
| 主机名包含非法字符 | 输入含 shell 特殊字符 | 主机名仅允许字母数字、`.`、`-`、`_` |
| `Copy-SshPublicKey` 提示 "未找到任何默认公钥" | 本地未生成 SSH 密钥对 | 执行 `ssh-keygen -t ed25519` 生成密钥 |
| Starship / Fnm 静默失败 | 外部命令未安装或不在 PATH 中 | 使用 `Get-Command starship` 和 `Get-Command fnm` 验证安装 |
| PSReadLine 不可用 | 未安装 PSReadLine 模块 | 执行 `Install-Module PSReadLine -Force` |
| 网络错误 | SSH 连接超时或网络不可达 | 标记为 `NetworkError` 跳过缓存，重试或检查网络连通性 |
| tmux 删除会话 | 误操作 | 删除会话**必须**通过交互式菜单显式选择目标会话 |

## 📜 协议

本项目基于 MIT 协议开源，详见 [`LICENSE`](ShellPrompt/LICENSE)。
