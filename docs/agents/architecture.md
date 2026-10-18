> 本文件由根 AGENTS.md 路由触发加载。上级约束见根文件“三层边界”。

# 架构与目录规则

## 目录职责

- `Microsoft.PowerShell_profile.ps1`: **MUST ONLY** handle module loading, environment initialization, and startup configuration. **NEVER** put complex business logic here.
- `Public/`: Contains user-facing commands. MUST maintain stable command behavior, use clear PowerShell naming, and include help comments (`.SYNOPSIS`, etc.).
- `Private/`: Contains internal helper functions. **MUST NOT** be exposed to users.
- `ShellPrompt/Settings.ScriptAnalyzer.psd1`: PSScriptAnalyzer configuration. MUST be kept in sync with actual code conventions.

## 兼容性与降级（Compatibility & Fallbacks）

- Prefer feature detection over version checking.
- 模块最低版本由 `ShellPrompt.psd1` 的 `PowerShellVersion` 统一把守, 代码内**不再**做 PS 5.1 分支。
- `PwshSpectreConsole` 是**硬依赖** (不是可选依赖): 加载失败时 `ShellPrompt.psm1` 直接 `throw`, 不做静默降级。
- 交互菜单是**双轨制**, 由 `Private/Get-ConsoleUiBackend.ps1` 的 `Get-ConsoleUiBackend` 在模块加载期判定, 结果存入 `$script:ConsoleUiBackend`:
  - `GridView` 主轨 = `Modules/PSTui` 的 `Out-ConsoleGridView` (由 `Private/Invoke-GridViewMenu.ps1` 实现)
  - `AnsiFallback` 降级轨 = 自研 ANSI 实时过滤菜单 (由 `Private/Invoke-AnsiMenu.ps1` 实现)
  - `Show-HostSelector` / `Show-SessionManager` 只做分发, 两条轨对外契约一致 (返回带 `.Value` 的 PSCustomObject, 或 `$null`)。**调用方 (如 `Start-TmuxSession`) 不感知后端差异, 无需修改。**
  - `PSTui` 缺失 / 版本冲突 / `Terminal.Gui` 主版本争用 / stdin 被重定向 → 一律降级并 `Write-Warning` 说明原因, **不 throw**。降级路径的可用性优先级高于"删除降级用文件"。
