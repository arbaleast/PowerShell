# Set-ProfileAliases.ps1 - 模块作用域别名
# 仅保留 ssh-copy-id; ll / which 由 Microsoft.PowerShell_profile.ps1 在模块
# 加载前以全局别名注册,模块内的 Set-Alias 会被覆盖,无附加价值。

Set-Alias ssh-copy-id Copy-SshPublicKey -ErrorAction SilentlyContinue
