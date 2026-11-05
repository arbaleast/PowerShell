@{
    # ============================================================
    # ShellPrompt 核心脚本清单 (Core Scripts Inventory)
    # ------------------------------------------------------------
    # 用途: 让"核心脚本缺失"在**模块导入阶段**就被发现, 而不是等到
    #   用户第一次调用某个公开命令时才炸。
    #
    # 契约:
    #   1) Private/ 与 Public/ 下的每一个 .ps1 都是**核心脚本** —— 本模块
    #      没有"装了也能用、缺了也能用"的可选功能分支。
    #   2) 清单里的每一项都必须在磁盘上存在; 缺失 => 模块导入失败, 报错
    #      含该文件的绝对路径。
    #   3) 加载顺序由 ShellPrompt.psm1 决定(按文件名 Ordinal 升序), 与本
    #      清单的书写顺序无关 —— 因此清单只需保持**集合**准确即可。
    #
    # 维护约定:
    #   新增 / 删除 / 重命名 Private 或 Public 下的 .ps1 时, 必须同步更新
    #   本清单。ModuleLoad.Tests.ps1 里有"清单与目录必须一致"的断言,
    #   漏改会在 CI 上直接失败。
    # ============================================================

    Private = @(
        'Add-SshHostActivity.ps1'
        'ConvertTo-SshArgumentLine.ps1'
        'ConvertTo-SshEscapedString.ps1'
        'ConvertTo-TmuxTuiViewModel.ps1'
        'Enter-TmuxAlternateScreen.ps1'
        'Get-ConsoleUiBackend.ps1'
        'Get-HostSelectorRow.ps1'
        'Get-HostSelectorStateText.ps1'
        'Get-SpinnerStyleMapping.ps1'
        'Get-SshArgs.ps1'
        'Get-SshConfigHosts.ps1'
        'Get-SshHostActivity.ps1'
        'Get-SshHostDashboardRow.ps1'
        'Get-SshHostDashboardTheme.ps1'
        'Get-SshHostDetail.ps1'
        'Get-SshHostProfile.ps1'
        'Get-TguiContext.ps1'
        'Get-TguiTerminalSize.ps1'
        'Get-TguiTextWidth.ps1'
        'Get-TmuxActionDefinition.ps1'
        'Get-TmuxSessions.ps1'
        'Get-TmuxSessionState.ps1'
        'Get-WttrTitleSuffix.ps1'
        'Get-WttrWeather.ps1'
        'Get-WttrWeatherDescMap.ps1'
        'Initialize-Config.ps1'
        'Initialize-FnmEnvironment.ps1'
        'Invoke-SshCaptureOutput.ps1'
        'Invoke-SshCommand.ps1'
        'Invoke-SshHostDashboard.ps1'
        'Invoke-TguiHostSelector.ps1'
        'Invoke-TmuxAttach.ps1'
        'Invoke-TmuxSessionDeletion.ps1'
        'Invoke-TmuxSessionFetch.ps1'
        'Invoke-TmuxTuiAction.ps1'
        'Invoke-WithProgress.ps1'
        'New-SshHostDashboardWindow.ps1'
        'New-SshHostDetailPanel.ps1'
        'New-SshHostListView.ps1'
        'New-TguiHostSelectorWindow.ps1'
        'New-TmuxSession.ps1'
        'New-TmuxTuiColumnPlan.ps1'
        'New-TmuxTuiDashboardWindow.ps1'
        'New-TmuxTuiLayoutPlan.ps1'
        'New-TmuxTuiSessionDetailPanel.ps1'
        'New-TmuxTuiSessionRowList.ps1'
        'New-TmuxTuiSessionTable.ps1'
        'New-TmuxTuiShortcutList.ps1'
        'New-WelcomeBanner.ps1'
        'Read-TmuxConsoleLine.ps1'
        'Receive-TmuxBackgroundTask.ps1'
        'Reset-TerminalMode.ps1'
        'Resolve-ColorTable.ps1'
        'Resolve-TguiThemeName.ps1'
        'Save-OriginalTerminalState.ps1'
        'Set-TguiFrameRate.ps1'
        'Set-TguiTheme.ps1'
        'Show-HostSelector.ps1'
        'Show-SshHostDashboard.ps1'
        'Show-TmuxTuiDashboard.ps1'
        'Start-SshHostDetailTask.ps1'
        'Submit-TmuxBackgroundTask.ps1'
        'Submit-WttrPrefetch.ps1'
        'Test-SshHostName.ps1'
        'Test-TguiQuitKey.ps1'
        'Test-TmuxTuiInteractive.ps1'
        'Write-TmuxWelcomeBanner.ps1'
    )

    Public = @(
        'Copy-SshPublicKey.ps1'
        'Invoke-Reload.ps1'
        'Show-UserScoopLogo.ps1'
        'Start-TmuxSession.ps1'
        'Update-Weather.ps1'
    )
}

