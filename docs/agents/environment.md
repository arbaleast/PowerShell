# 📍 本地环境准备（pwsh）

> 本文件描述**可复现的环境准备方式**，不是某一台机器的快照。
> 安装路径、用户名、已装的第三方工具都因机器而异 —— **不要把个人机器的状态当成项目要求**。

## 项目要求的运行时

| 组件 | 要求 | 依据 |
| --- | --- | --- |
| PowerShell | **7.6 或更高** | `ShellPrompt/ShellPrompt.psd1` 声明 `PowerShellVersion = '7.6'`；`ShellPrompt/Tests/Invoke-Tests.ps1` 有同样的版本守卫，低于该版本直接拒绝运行 |
| Pester | **5 或更高**（v5+/v6 语法） | 测试套件使用 `Should -Be` / `Should -Invoke` 等 v5+ 语法；旧版 Pester 3.x 无法运行 |
| PSScriptAnalyzer | 任意较新版本 | 静态分析门禁；CI 使用官方源安装的最新版 |

CI 一律跑在 `windows-latest` 上，并自行准备上述依赖（见 `.github/workflows/test.yml`）。
本地只需保证版本不低于上表即可。

## 可复现的环境配置

安装方式因机器而异，任选其一即可 —— 本仓库不要求任何特定的包管理器或安装目录。

```powershell
# PowerShell 7.6+（任选其一）
winget install --id Microsoft.PowerShell --source winget
scoop install pwsh
# 或从官方 release 下载对应平台的压缩包并加入 PATH:
#   https://github.com/PowerShell/PowerShell/releases

# 测试与静态分析依赖（CurrentUser 作用域，无需管理员）
Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force -AllowClobber
Install-Module PSScriptAnalyzer -Scope CurrentUser -Force -AllowClobber
```

非 Windows（Linux / WSL）同样可用官方 tarball：`powershell-<ver>-linux-x64.tar.gz` 解压后把其中的
`pwsh` 放进 PATH 即可；模块安装命令与上面一致。

## 定位 pwsh

```powershell
# PowerShell 内部查询（pwsh 已在 PATH 时有效）
Get-Command pwsh | Select-Object -ExpandProperty Source

# cmd 内部查询（pwsh 已在 PATH 时有效）
where pwsh

# 版本自检
pwsh --version
```

若 `Get-Command` / `where` 查不到，说明 `pwsh` 没在 PATH 里：用上面任意一种安装方式重装或把
安装目录加入 PATH，**不要**用全盘扫描去猜路径。

## 必要的环境差异说明

- **Windows 与 Linux / WSL 不等价**：模块与测试套件是按 Windows 写的（硬编码 `ssh.exe` / `LOCALAPPDATA` /
  `TEMP` / `USERPROFILE`）。典型差异：pwsh 的 `$HOME` 在 Windows 上由 `$env:USERPROFILE` 派生，
  在 Linux 上由 `$env:HOME` 派生 —— 涉及"用户配置目录"的用例在两边行为不同。
  **CI 只跑 `windows-latest`**；在 Linux 上本地跑套件时，个别 Windows 专属用例会失败，属预期。
- **可选依赖缺失不影响门禁**：`starship` / `fnm` / `PSReadLine` 属于可选工具，没装不会让 profile 启动失败，
  也不会让 CI 的 Profile 冒烟检查失败。相关代码路径应自行做存在性判断。
- **网络**：测试与冒烟检查都不访问业务网络（`wttr.in` 在测试里已被 Mock）；
  安装 Pester / PSScriptAnalyzer 需要访问 PowerShell Gallery，属于工具安装而非被测行为。
