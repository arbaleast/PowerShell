@{
    RootModule        = 'ShellPrompt.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author            = 'arbaleast'
    Description       = 'PowerShell prompt and remote session management module'

    FunctionsToExport = @(
        'Initialize-Environment'
        'Start-TmuxSession'
        'Start-WaterReminder'
        'Get-WaterReminderHistory'
        'reload'
        'Initialize-TUILogger'
        'Initialize-TUIPerformance'
        'Get-TUIPerformance'
        'Show-TUIDebugOverlay'
        'Test-TUIDebugMode'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
