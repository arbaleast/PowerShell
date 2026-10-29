# 📍 pwsh 安装位置（本机环境记录）

> **机器专属快照**：以下路径与版本是维护者本机（Windows + Scoop）的实际状态记录，**不是对所有贡献者的要求**。在其它机器上请用本节的兜底查询命令自行定位 pwsh；内容随本机升级可能过时，改动前先按下方命令核实。

- **可执行文件绝对路径**：`D:\Env\UserScoop\apps\pwsh\current\pwsh.exe`（`current` 为指向版本目录 `D:\Env\UserScoop\apps\pwsh\7.6.3\pwsh.exe` 的 Scoop 链接，升级后真实版本目录会变，`current` 路径保持不变）。
- **已安装版本**：PowerShell 7.6.3（`pwsh --version` 输出 `PowerShell 7.6.3`）。
- **安装方式**：Scoop 安装（自定义 Scoop 根目录 `D:\Env\UserScoop`，非默认的 `%USERPROFILE%\scoop`）。
- **PATH 状态**：`D:\Env\UserScoop\shims` 已在用户 PATH 中，但**未生成 `pwsh` shim**，因此 `where pwsh` 与 `Get-Command pwsh` 均无结果；请直接使用上面的绝对路径，不要用全盘扫描（`where /r C:\ pwsh.exe`）定位。
- **WindowsApps 别名**：不存在（`%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe` 不存在），无 0 字节 app execution alias 误用风险。

常用查询命令：

```powershell
# PowerShell 内部查询（若已加入 PATH 时有效）
Get-Command pwsh | Select-Object -ExpandProperty Source

# cmd 内部查询（若已加入 PATH 时有效）
where pwsh

# 兜底：直接按本仓库记录的位置查询
Get-Item 'D:\Env\UserScoop\apps\pwsh\current\pwsh.exe' | Select-Object -ExpandProperty FullName
```

