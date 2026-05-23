@{
    RootModule        = 'ShellPrompt.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author            = 'arbaleast'
    CompanyName       = 'arbaleast'
    Copyright         = '(c) 2024 arbaleast. All rights reserved.'
    Description       = 'PowerShell prompt and remote session management module'
    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Initialize-Environment'
        'Show-UserScoopLogo'
        'Start-TmuxSession'
        'reload'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    # 导出所有已注册的别名（ll、which 等由 Set-ProfileAliases.ps1 注册）
    AliasesToExport   = '*'

    PrivateData       = @{
        PSData = @{
            Tags       = @('PowerShell', 'Prompt', 'Tmux', 'SSH', 'Session')
            ProjectUri = 'https://github.com/arbaleast/ShellPrompt'
            LicenseUri = 'https://github.com/arbaleast/ShellPrompt/blob/main/LICENSE'
        }
    }
}
