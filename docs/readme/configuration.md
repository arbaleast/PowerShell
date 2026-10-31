# 🎨 配置

## 配置文件位置

```powershell
$HOME/.ShellPrompt/config.ps1
```

在 Windows 上 `$HOME` 就是用户主目录（`$env:USERPROFILE`）。该文件**默认不存在**，需要自定义行为时自行创建。仓库不提供模板文件。

## 配置优先级

**用户配置 → 默认配置**：用户配置中的同名键覆盖模块内置默认值，未设置的键继续使用默认值。默认值定义在 [`ShellPrompt/Private/Initialize-Config.ps1`](../../ShellPrompt/Private/Initialize-Config.ps1)。

配置文件会被**启动流程**和 **ShellPrompt 模块**各加载一次，因此：

- 只应做 `$Config.*` 赋值；
- 不要在配置文件中调用模块内部函数或设置别名（启动阶段这些函数尚未加载）。

修改后执行 `Invoke-Reload` 即可生效（需要 ShellPrompt 模块已加载）。

## 配置项

配置共 **5 个域**：

| 域 | 作用 | 本文档 |
|----|------|--------|
| `Paths` | 数据文件路径 | 本页 |
| `Colors` | ANSI 文本颜色 | 本页 |
| `SSH` | SSH 主机使用状态 | 本页 |
| `Weather` | 主机选择器标题行天气 | [功能特点 · 天气](features.md#交互菜单标题区天气) |
| `UI` | TUI 主题 | 本页 + [TUI 仪表盘 · 配置](tui-dashboard.md#27-配置) |

### Paths 域

| 键 | 类型 | 默认值 | 说明 |
|----|------|--------|------|
| `Quotes` | string | `<仓库根>/data/quotes.txt` | 欢迎 Banner 随机语录文件路径 |

### Colors 域（ANSI 转义序列）

| 键 | 默认值 | 说明 |
|----|--------|------|
| `FreshGreen` | `\e[38;2;137;209;133m` | 主色调（亮绿） |
| `SageGreen` | `\e[38;2;159;177;159m` | 辅助绿（弱化强调） |
| `DarkGray` | `\e[38;2;50;50;50m` | 深灰 |
| `MidGray` | `\e[38;2;100;100;100m` | 中灰（弱化文字） |
| `Cyan` | `\e[38;2;112;199;209m` | 青色（标题类） |
| `Danger` | `\e[38;2;220;90;90m` | 危险色（删除等不可逆操作） |
| `Warning` | `\e[38;2;220;180;80m` | 警告色（需确认的操作） |
| `SelectedBg` | `\e[48;2;112;199;209;30m\e[38;2;20;20;20m` | 选中态反色背景 |
| `Rst` | `\e[0m` | 样式重置（防止颜色泄漏） |

> 这些颜色用于 ANSI / Spectre 文本输出。**TUI 界面配色不走 `Colors.*`**，而是由 `UI.Theme.Slots` 单独控制（见下文）。

### SSH 域

| 键 | 类型 | 默认值 | 说明 |
|----|------|--------|------|
| `LastHost` | string | `$null` | 上次使用的 SSH 主机；在主机选择器中置顶并标记 `★ 最近` |

运行一次 `sss` 并选择主机后，该值会在**当前 PowerShell 会话内**自动更新；它不会写回配置文件。如果希望每次启动都预置置顶主机，请手动在 `config.ps1` 中设置 `$Config.SSH.LastHost`。

### Weather 域

| 键 | 类型 | 默认值 | 说明 |
|----|------|--------|------|
| `Enabled` | bool | `$true` | 是否在主机选择器标题行显示天气 |
| `ExtraWeatherDescMap` | ordered dict | `{}` | 自定义天气描述英文 → 中文映射，同名键覆盖内置字典 |

```powershell
$Config.Weather.Enabled = $false
$Config.Weather.ExtraWeatherDescMap = [ordered]@{
    'smoky haze' = '烟霞'
}
```

更多行为说明见 [功能特点 · 天气](features.md#交互菜单标题区天气)。

### UI 域

`UI` 域当前只有 `Theme`，用于配置 Terminal.Gui v2 界面的配色方案。

| 键 | 类型 | 默认值 | 说明 |
|----|------|--------|------|
| `Theme.Enabled` | bool | `$true` | 是否应用自定义主题；`$false` 时使用组件内置配色 |
| `Theme.Name` | string[] | `@('Base', 'Menu', 'Dialog')` | 要覆写的方案名；未知名称回退到 `Base`，兼容旧配置中的单个字符串 |
| `Theme.Slots` | ordered dict | 见源码 | 各方案共用的槽位配色，键为 Terminal.Gui `Scheme` 的槽位名，值为 `@{ Fg = 'R,G,B'; Bg = 'R,G,B' }` |
| `Theme.SchemeOverrides` | ordered dict | 见源码 | 按方案追加差异化槽位（当前用于 `Menu` 表头/标题带与 `Dialog` 连接状态徽标） |

```powershell
$Config.UI.Theme.Enabled = $false   # 使用组件默认配色
```

槽位清单、默认 RGB 与配色契约见 [TUI 仪表盘](tui-dashboard.md) 的配置与配色章节。

## 用户配置示例

```powershell
# ~/.ShellPrompt/config.ps1
# 注意: PowerShell 双引号字符串不解析 \e，用反引号转义 `e，或使用 [char]27

# 主色调改成亮绿色
$Config.Colors.FreshGreen = "`e[38;2;0;255;0m"

# 关闭主机选择器标题行的天气
$Config.Weather.Enabled = $false

# 预置置顶主机
$Config.SSH.LastHost = 'my-server'

# 使用组件内置的 TUI 配色
$Config.UI.Theme.Enabled = $false
```

## 注意事项

- 旧版本中已移除、当前无消费方的键（如 `Paths.LogPath`、`SSH.ConnectTimeout`、`SSH.ForceTTy`、`Keys` 域，以及部分 `Colors.*` 键）在配置文件中继续书写会被**静默忽略**，不会报错。
- 修改配置后优先执行一次 `Invoke-Reload` 并观察输出，确认没有被静默忽略或回退到默认值。
- 用户配置不会写入仓库文件，`git pull` 不会覆盖 `$HOME/.ShellPrompt/config.ps1`。
