@{
    RootModule        = 'ShellPrompt.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author            = 'arbaleast'
    Description       = 'PowerShell prompt and remote session management module'

    # 仅导出真实的函数名
    FunctionsToExport = @(
        'Initialize-Environment',
        'Show-UserScoopLogo',
        'Start-TmuxSession',
        'Invoke-Reload'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()

    # 允许导出所有别名（包括 reload, ll, which）
    AliasesToExport   = @('*')
}
