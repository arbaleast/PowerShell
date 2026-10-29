@{
    RootModule        = 'ShellPrompt.psm1'
    ModuleVersion     = '2.0.0'
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author            = 'arbaleast'
    CompanyName       = 'arbaleast'
    Copyright         = '(c) 2024 arbaleast. All rights reserved.'
    Description       = 'PowerShell prompt and remote session management module (Spectre.Console UI)'
    # v2.0 单轨 Spectre: UI 渲染全部走 PwshSpectreConsole (要求 7.6+),
    # 已移除 PS 5.1 fallback 与 legacy ANSI 路径
    PowerShellVersion = '7.6'

    FunctionsToExport = @(
        'Show-UserScoopLogo'
        'Start-TmuxSession'
        'Copy-SshPublicKey'
        'Invoke-Reload'
        'Update-Weather'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    # 别名由 Microsoft.PowerShell_profile.ps1 以 -Scope Global 注册
    AliasesToExport   = @()

    PrivateData       = @{
        PSData = @{
            Tags       = @('PowerShell', 'Prompt', 'Tmux', 'SSH', 'Session')
            ProjectUri = 'https://github.com/arbaleast/PowerShell'
            # LICENSE 文件在 ShellPrompt/ 下 (仓库根没有 LICENSE), 旧路径 404
            LicenseUri = 'https://github.com/arbaleast/PowerShell/blob/main/ShellPrompt/LICENSE'
        }
    }
}
