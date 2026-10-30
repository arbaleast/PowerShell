# 🎨 配置

## 配置文件位置

```powershell
$HOME/.ShellPrompt/config.ps1
```

## 配置优先级

**用户配置 → 默认配置**。用户自定义项覆盖模块内置默认值，见 [`Initialize-Config.ps1`](../../ShellPrompt/Private/Initialize-Config.ps1)。

> **加载顺序（2026-10-29 修正）**：用户配置在 `Initialize-Config.ps1` 内加载，并且**必须早于**预热缓存 `$script:ColorCache` 生成 —— 否则 `Get-CachedConfig` 会优先命中预热快照，把你在 `config.ps1` 里的覆盖静默遮蔽（改了配置却看不到任何变化）。修正后，启动期欢迎语与模块内读取用的是同一份已合并用户配置的值。
>
> **由此带来的一条约束**：配置文件会在**模块作用域**与**启动期全局作用域**各执行一次，所以它只应做 `$Config.*` 赋值（本文示例即如此），不要在文件里调用模块内函数或设置别名 —— 那类写法在启动期作用域里不存在。

## 配置项

配置共 **5 个域**：本页收录 `Paths` / `Colors` / `SSH`；`Weather` 域见 [功能特点·天气](features.md#-交互菜单标题区天气)，`UI` 域（`UI.Theme`，TGUI 配色槽位）见 [tmux 管理器 TUI 仪表盘](tui-dashboard.md#27-配置)。

> **2026-10-30 迁移**：`UI.GridViewFocus` / `UI.GridViewFullScreen` / `UI.DashboardTuiEnabled` / `UI.DashboardFullScreen` 已随 PSTui 轨与自研回退轨一并移除, `UI` 域当前只剩 `UI.Theme`。旧键残留在 `config.ps1` 里无害（静默忽略）。

> 下表「状态」列标注该键**当前是否有消费方**（2026-10-29 核对）。
>
> **2026-10-29 清理**：以下键因长期无消费方已从模块中删除，在 `config.ps1` 里继续配置会被**静默忽略**（不报错）：
> `Paths.LogPath`、`SSH.ConnectTimeout`、`SSH.ForceTTy`、整个 `Keys` 域（`Up` / `Down` / `Enter` / `Esc`）、
> `Colors.LightGray` / `White` / `BgDarker` / `Bold` / `Dim`。

### Paths 域

| 键 | 类型 | 默认值 | 说明 | 状态 |
|----|------|--------|------|------|
| `Quotes` | string | `{moduleRoot}/data/quotes.txt` | 随机语录文件路径（`Show-UserScoopLogo` / `Write-TmuxWelcomeBanner` 读取） | ✅ 消费中 |

### Colors 域（ANSI 转义码）

| 键 | 默认值 | 说明 | 状态 |
|----|--------|------|------|
| `FreshGreen` | `\e[38;2;137;209;133m` | 主色调（亮绿）；语义 `Primary` / `Border` | ✅ 消费中 |
| `SageGreen` | `\e[38;2;159;177;159m` | 辅助绿；语义 `Accent` | ✅ 消费中 |
| `DarkGray` | `\e[38;2;50;50;50m` | 深灰；语义 `Dark`（当前无调用方请求，未预热） | 语义可扩展 |
| `MidGray` | `\e[38;2;100;100;100m` | 中灰；语义 `Muted` | ✅ 消费中 |
| `Cyan` | `\e[38;2;112;199;209m` | 标题色；语义 `Cyan`（当前无调用方请求；Title 区配色现由 TG Scheme 接管） | 语义可扩展 |
| `Danger` | `\e[38;2;220;90;90m` | 危险项色（State 列 `⚠ 危险` 文字染色） | ✅ 消费中 |
| `Warning` | `\e[38;2;220;180;80m` | 警告项色（State 列 `⚠ 备选` 文字染色） | ✅ 消费中 |
| `SelectedBg` | `\e[48;2;112;199;209;30m\e[38;2;20;20;20m` | 选中态反色背景；语义 `SelectedBg`（当前无调用方请求；高亮已由 TG Scheme `Focus` 接管） | 语义可扩展 |
| `Rst` | `\e[0m` | 重置样式（所有输出末尾防颜色泄漏） | ✅ 消费中 |

> 语义键 → 配置键的映射集中在 [`Resolve-ColorTable.ps1`](../../ShellPrompt/Private/Resolve-ColorTable.ps1) 的 `$script:ColorSemanticMap`；
> 新增语义只需要改这一处，不必改各渲染文件。

### SSH 域

| 键 | 类型 | 默认值 | 说明 | 状态 |
|----|------|--------|------|------|
| `LastHost` | string | `$null` | 上次使用的主机（会话管理器置顶 + `★ 最近` 标注） | ✅ 消费中 |

## 用户配置示例

```powershell
# ~/.ShellPrompt/config.ps1
# 注意: PowerShell 双引号字符串不解析 \e, 用反引号转义 `e 或单引号 + [char]27
$Config.Colors.FreshGreen = "`e[38;2;0;255;0m"  # 覆盖主色调为亮绿色
$Config.SSH.LastHost = 'my-server'               # 预置置顶主机
```
