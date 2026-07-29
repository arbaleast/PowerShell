@{
    RootModule        = 'ShellPrompt.psm1'
    ModuleVersion     = '1.2.0'
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author            = 'arbaleast'
    CompanyName       = 'arbaleast'
    Copyright         = '(c) 2024 arbaleast. All rights reserved.'
    Description       = 'PowerShell prompt and remote session management module'
    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Show-UserScoopLogo'
        'Start-TmuxSession'
        'Copy-SshPublicKey'
        'Invoke-Reload'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    # 别名由 Microsoft.PowerShell_profile.ps1 以 -Scope Global 注册
    AliasesToExport   = '*'

    PrivateData       = @{
        PSData = @{
            Tags       = @('PowerShell', 'Prompt', 'Tmux', 'SSH', 'Session')
            ProjectUri = 'https://github.com/arbaleast/PowerShell'
            LicenseUri = 'https://github.com/arbaleast/PowerShell/blob/main/LICENSE'
        }
    }
}
