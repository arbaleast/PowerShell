# 🌤️ wttr 天气实现说明

交互 UI 标题行天气走 [`Get-WttrTitleSuffix`](../../ShellPrompt/Private/Get-WttrTitleSuffix.ps1)（拼装后缀），基于 [`Get-WttrWeatherDescMap`](../../ShellPrompt/Private/Get-WttrWeatherDescMap.ps1) 的中文翻译映射；当前唯一渲染点在 [`Private/Show-HostSelector.ps1`](../../ShellPrompt/Private/Show-HostSelector.ps1) —— `Get-WttrTitleSuffix` 的返回值拼进传给 [`Invoke-TguiHostSelector`](../../ShellPrompt/Private/Invoke-TguiHostSelector.ps1) 的 `-Title` 参数，由 TGUI 整窗行 0 的标题 Label 渲染。

**配置域**：`$config.Weather.*`
- `Weather.Enabled` — 总开关（默认 `$true`）。
- `Weather.ExtraWeatherDescMap` — 用户扩展映射（`[ordered]@{}` 形式），合并到内置字典之上。

**文件分工**：`Get-WttrTitleSuffix.ps1`（拼装后缀）与 `Get-WttrWeatherDescMap.ps1`（中文字典）各司其职、各自独立成文件；`Show-HostSelector.ps1` 只调用 `Get-WttrTitleSuffix`，**不内联**天气逻辑。改动范围按实际依赖决定：改字典只动 `Get-WttrWeatherDescMap.ps1`，改后缀拼装/端点只动 `Get-WttrTitleSuffix.ps1`，只有标题渲染方式变化才需要碰 `Invoke-TguiHostSelector.ps1` / `New-TguiHostSelectorWindow.ps1`（标题行在组装层行 0）。

**端点与缓存**：标题区走 [`Get-WttrWeather`](../../ShellPrompt/Private/Get-WttrWeather.ps1) 的自拼端点 `https://wttr.in/?format=j1&lang=zh`，与公开命令 [`Update-Weather`](../../ShellPrompt/Public/Update-Weather.ps1)（`?format=3` 短格式）缓存**键**不同互不命中（`CustomUrl|...` vs `Short|...`），但底层是**单槽**缓存，一方成功抓取会挤掉另一方的条目。

**容错**：`Get-WttrWeather` 对超时/网络失败/空响应一律返回 `""` + `Write-Verbose`，绝不抛异常污染菜单标题。
