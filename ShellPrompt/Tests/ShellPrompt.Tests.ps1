<#
.SYNOPSIS
    ShellPrompt 模块 Pester 测试套件 (由 Pester v3 旧断言语法最小迁移而来)
.DESCRIPTION
    历史沿革:
    1) 本文件源自 `git show HEAD:ShellPrompt/Tests/ShellPrompt.Tests.ps1` (1102 行),
       采用 Pester v3 旧断言语法 (`Should Be` / `Should Not Be` / `Should Match` ...)。
    2) 本机安装的是 Pester 6.2.0, 实测全部旧语法在运行时抛
       `ParameterBindingException: Parameter set cannot be resolved using the specified
       named parameters.` (12/12 旧写法全部失败, 仅新写法 `Should -Be` 通过),
       因此必须把旧语法改写为 Pester v5+ 的 `Should -Be` / `Should -Not -Be` 形式。
    3) 2026-10-18 控制台 UI 单轨化 (自研 ANSI 降级轨移除, 用例按存续实现重写),
       原文件中针对已删除函数 (Test-FilterCharacter / Get-FilteredItems /
       Update-FilterString / New-StatusBadge / Format-StatusBadge / New-MenuItem /
       Write-MenuItem / New-DynamicHelpPanel / Get-SessionActionHelp / New-AnsiLayout /
       Add-MainLine / Set-FooterLine / Write-AnsiLine / Update-InputBuffer /
       Test-InputValidation / Send-MenuKey / ConvertTo-CsiArrowKey) 的用例已按
       "存续实现等价覆盖" 重写, 而不是简单删除。
    4) 文件末尾追加 "交互式 UI 单轨契约" 断言组, 覆盖:
       Backend 恒为 TerminalGui / Assert-ConsoleUiReady 抛错与放行 /
       已删除降级轨与 PSTui GridView 轨函数在模块作用域不存在 /
       已删除源文件不在模块目录内 (基于 ModuleBase, 不依赖仓库工作区路径)。
#>

# 模块路径：相对于测试目录的父目录
$moduleRoot = (Resolve-Path "$PSScriptRoot\..").Path
$manifestPath = Join-Path $moduleRoot 'ShellPrompt.psd1'

BeforeAll {
    $script:manifestPath = Join-Path (Resolve-Path "$PSScriptRoot\..").Path 'ShellPrompt.psd1'
    Import-Module $script:manifestPath -Force -ErrorAction Stop
    $script:mod = Get-Module ShellPrompt
}

Describe 'Module Import' {

    It '应能成功导入模块' {
        { Import-Module $script:manifestPath -Force -ErrorAction Stop } | Should -Not -Throw
    }

    It '导入后模块应可用' {
        $module = Get-Module ShellPrompt
        $module | Should -Not -BeNullOrEmpty
        $module.Name | Should -Be 'ShellPrompt'
    }
}

Describe 'Command Export' {

    It '应导出 Invoke-Reload' {
        Get-Command -Module ShellPrompt -Name 'Invoke-Reload' -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It '应导出 Show-UserScoopLogo' {
        Get-Command -Module ShellPrompt -Name 'Show-UserScoopLogo' -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It '应导出 Start-TmuxSession' {
        Get-Command -Module ShellPrompt -Name 'Start-TmuxSession' -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It '应导出 Copy-SshPublicKey' {
        Get-Command -Module ShellPrompt -Name 'Copy-SshPublicKey' -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It '不应导出旧命令 reload' {
        Get-Command -Module ShellPrompt -Name 'reload' -ErrorAction SilentlyContinue |
            Should -BeNullOrEmpty
    }

    It '不应导出内部辅助函数' {
        $privateNames = @(
            'Get-CachedConfig', 'Get-SshConfigHosts', 'Get-TmuxAvailability',
            'Get-TmuxSessions', 'Invoke-SshCommand',
            'Invoke-SshCaptureOutput', 'New-RandomSessionName', 'Reset-TerminalMode',
            'Get-SshArgs',
            'New-TmuxSession', 'ConvertTo-SshEscapedString',
            'Test-SshHostName', 'Save-OriginalTerminalState'
        )
        $exported = @(Get-Command -Module ShellPrompt | Select-Object -ExpandProperty Name)
        foreach ($name in $privateNames) {
            $exported | Should -Not -Contain $name
        }
    }

    It '不应导出单轨化后新增的内部实现函数' {
        $privateNames = @(
            # 2026-10-30 PSTui 移除: GridView 轨实现随 Modules/PSTui 删除,
            # 主机选择器改由 ALC 原生 Terminal.Gui v2 轨承接(以下均为内部实现)
            'Invoke-TguiHostSelector', 'New-TguiHostSelectorWindow',
            'Get-HostSelectorRow', 'Resolve-TguiThemeName',
            'Get-ConsoleUiBackend', 'Assert-ConsoleUiReady',
            'Invoke-TmuxAttach',
            # 2026-10-30 TUI 重构: 单视图 + 单行动作条 + 后台取数的内部实现
            # 2026-10-30 回退轨移除: Show-TmuxSessionDashboard/Show-TmuxActionBar/
            #   Read-TmuxActionKey/Get-TmuxPlaceholderRow 已随回退轨删除(文件不存在,
            #   断言改为存在性, 见 Start-TmuxSession.TuiDispatch.Tests.ps1)
            'Get-TmuxActionDefinition',
            'Get-TmuxSessionState', 'Get-TmuxErrorCode',
            'Submit-TmuxBackgroundTask', 'Receive-TmuxBackgroundTask',
            'Invoke-TmuxSessionFetch', 'Submit-WttrPrefetch', 'Receive-WttrPrefetch',
            # 2026-10-30 第三轮 TUI 修复: Input 态输入机 / 备用屏幕生命周期
            # 2026-10-30 第五轮修复: Clear-TmuxScreen(绝对的全量重绘原语)
            # 2026-10-30 TGUI 迁移阶段 A: Terminal.Gui 上下文加载器
            # + UI 视图模型/键位动作纯函数映射
            'Read-TmuxConsoleLine', 'Enter-TmuxAlternateScreen', 'Exit-TmuxAlternateScreen',
            'Clear-TmuxScreen', 'Get-TguiContext',
            'ConvertTo-TmuxTuiViewModel',
            'New-TmuxTuiColumnPlan', 'New-TmuxTuiSessionTable', 'Show-TmuxTuiDashboard',
            # 2026-10-30 TGUI 迁移阶段 B: 仪表盘编排/工厂/动作分发(导出盲区收口)
            'New-TmuxTuiShortcutList', 'New-TmuxTuiDashboardWindow',
            'Invoke-TmuxSessionDeletion', 'Invoke-TmuxTuiAction',
            'New-TmuxTuiLayoutPlan', 'Test-TmuxTuiInteractive'
        )
        $exported = @(Get-Command -Module ShellPrompt | Select-Object -ExpandProperty Name)
        foreach ($name in $privateNames) {
            $exported | Should -Not -Contain $name
        }
    }
}

Describe 'Verb-Noun Compliance' {

    It '所有导出命令的动词应在 Get-Verb 批准列表中' {
        $approvedVerbs = @(Get-Verb | Select-Object -ExpandProperty Verb)
        $exported = @(Get-Command -Module ShellPrompt)
        foreach ($cmd in $exported) {
            $verb = $cmd.Name -split '-' | Select-Object -First 1
            $approvedVerbs | Should -Contain $verb
        }
    }
}

Describe 'Config Access' {

    It '$script:Config 应包含所有域' {
        $config = & $script:mod { $script:Config }
        $config | Should -Not -BeNullOrEmpty
        $config.Contains('Colors') | Should -BeTrue
        $config.Contains('Keys') | Should -BeFalse  # 2026-10-29 清理: 无消费方, Keys 域已移除
        $config.Contains('Paths') | Should -BeTrue
        $config.Contains('SSH') | Should -BeTrue
        $config.Contains('UI') | Should -BeTrue
    }

    It 'UI 域应保留 Theme 配置且不再存在 PSTui 双轨开关' {
        $keys = & $script:mod { @($script:Config.UI.Keys) }
        $keys | Should -Contain 'Theme'
        # 2026-10-30 PSTui 移除: GridViewFocus / GridViewFullScreen 是
        # PSTui Out-ConsoleGridView 专用开关, 随该轨删除一并移除
        $keys | Should -Not -Contain 'GridViewFocus'
        $keys | Should -Not -Contain 'GridViewFullScreen'
        # 2026-10-30 第四轮修复: GridViewMinUI 撤回, 换成仪表盘显式全屏开关
        $keys | Should -Not -Contain 'GridViewMinUI'
        # 2026-10-30 回退轨移除: sss 仪表盘唯一实现在 TGUI 轨, 旧开关一并删除
        $keys | Should -Not -Contain 'DashboardFullScreen'
        $keys | Should -Not -Contain 'DashboardTuiEnabled'
    }

    It 'UI 域不应再提供 Backend 后端选择项' {
        $keys = & $script:mod { @($script:Config.UI.Keys) }
        $keys | Should -Not -Contain 'Backend'
    }
}

Describe 'ConvertTo-SshEscapedString' {

    It '应正确处理普通字符' {
        $result = & $script:mod { ConvertTo-SshEscapedString -Value 'hello' }
        $result | Should -Be 'hello'
    }

    It '应转义单引号' {
        $result = & $script:mod { ConvertTo-SshEscapedString -Value "it's a test" }
        $result | Should -Be "it'\''s a test"
    }

    It '应通过管道处理输入' {
        $result = "don't stop" | & $script:mod { $input | ConvertTo-SshEscapedString }
        $result | Should -Be "don'\''t stop"
    }
}

Describe 'Test-SshHostName' {

    It '合法主机名应返回 $true' {
        & $script:mod { Test-SshHostName -HostName 'example.com' } | Should -BeTrue
    }

    It '带短横线的合法主机名应返回 $true' {
        & $script:mod { Test-SshHostName -HostName 'my-server-01' } | Should -BeTrue
    }

    It '含空格的主机名应返回 $false' {
        & $script:mod { Test-SshHostName -HostName 'bad host' } | Should -BeFalse
    }

    It '含管道符的主机名应返回 $false' {
        & $script:mod { Test-SshHostName -HostName 'host|danger' } | Should -BeFalse
    }
}

Describe 'P2-2 New-WelcomeBanner (纯函数)' {

    It '默认应返回 10 行' {
        $lines = & $script:mod { New-WelcomeBanner -Title 'TEST' }
        $lines.Count | Should -Be 10
    }

    It '首行与末行应为空行' {
        $lines = & $script:mod { New-WelcomeBanner -Title 'TEST' }
        $lines[0] | Should -Be ''
        $lines[9] | Should -Be ''
    }

    It 'Title 应出现在第 2 行' {
        $lines = & $script:mod { New-WelcomeBanner -Title 'MYTEST' }
        $lines[1] | Should -Match 'MYTEST'
    }

    It 'Subtitle 应出现在第 5 行' {
        $lines = & $script:mod { New-WelcomeBanner -Subtitle 'HELLOTEST' }
        $lines[4] | Should -Match 'HELLOTEST'
    }

    It 'Width=60 时 HLine 应有 56 个 =' {
        $lines = & $script:mod { New-WelcomeBanner -Title 'X' -Width 60 }
        # 第 9 行形如 '  +<hLine>---'
        $line9 = $lines[8]
        $eqCount = ([regex]::Matches($line9, '=')).Count
        $eqCount | Should -Be 56
    }

    It 'Width 小于 40 应抛 ValidationRange 错误' {
        $threw = $false
        try {
            & $script:mod { New-WelcomeBanner -Title 'X' -Width 10 }
        } catch {
            $threw = $true
        }
        $threw | Should -BeTrue
    }
}

Describe 'P2-2 Get-RandomQuote' {

    It '空 QuotesPath 应返回 Fallback' {
        $q = & $script:mod { Get-RandomQuote -QuotesPath '' -Fallback 'FB' }
        $q | Should -Be 'FB'
    }

    It '不存在的文件应返回 Fallback' {
        $q = & $script:mod {
            Get-RandomQuote -QuotesPath 'C:\nonexistent\file.txt' -Fallback 'FB'
        }
        $q | Should -Be 'FB'
    }

    It '存在且非空的文件应返回非空 Trim 后的语录' {
        $tmp = [System.IO.Path]::GetTempFileName()
        try {
            Set-Content -LiteralPath $tmp -Value "line one`nline two`nline three" -Encoding UTF8
            $q = & $script:mod {
                param($p) Get-RandomQuote -QuotesPath $p -Fallback 'FB'
            } -p $tmp
            $q | Should -Match 'line (one|two|three)'
        } finally {
            Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
        }
    }

    It '多文件调用应使用 mtime 缓存' {
        $tmp = [System.IO.Path]::GetTempFileName()
        try {
            Set-Content -LiteralPath $tmp -Value 'cached' -Encoding UTF8
            $q1 = & $script:mod { param($p) Get-RandomQuote -QuotesPath $p } -p $tmp
            $q2 = & $script:mod { param($p) Get-RandomQuote -QuotesPath $p } -p $tmp
            $q1 | Should -Be $q2
            # 验证 cache 存在
            $hasCache = & $script:mod {
                param($p) $script:QuotesCache -ne $null -and $script:QuotesCache.Path -eq $p
            } -p $tmp
            $hasCache | Should -BeTrue
        } finally {
            Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Resolve-ColorTable (颜色语义解析)' {

    It '应返回请求的语义键' {
        $table = & $script:mod { Resolve-ColorTable -Name 'Primary', 'Accent', 'Rst' }
        $table.Keys | Should -Contain 'Primary'
        $table.Keys | Should -Contain 'Accent'
        $table.Keys | Should -Contain 'Rst'
    }

    It '调用方覆盖值优先于配置层' {
        $table = & $script:mod {
            Resolve-ColorTable -Name 'Primary' -Colors @{ Primary = 'ZZ-OVERRIDE' }
        }
        $table.Primary | Should -Be 'ZZ-OVERRIDE'
    }

    It 'Border 语义键应跟随 Primary' {
        $table = & $script:mod {
            Resolve-ColorTable -Name 'Primary', 'Border' -Colors @{ Primary = 'ZZ-OWN' }
        }
        $table.Border | Should -Be 'ZZ-OWN'
    }

    It '未知语义键应解析为空串而不抛错' {
        $table = & $script:mod { Resolve-ColorTable -Name 'NotARealSemanticKey' }
        $table.NotARealSemanticKey | Should -Be ''
    }
}

Describe 'Get-HostSelectorRow (主机选择表格行)' {

    It '应按输入顺序生成行' {
        $rows = & $script:mod {
            Get-HostSelectorRow -Hosts @('debian', 'ubuntu')
        }
        $rows.Count | Should -Be 2
        $rows[0].Host | Should -Be 'debian'
        $rows[1].Host | Should -Be 'ubuntu'
    }

    It '列属性集应不再包含 Desc(2026-10-19 P0 删除冗余列)' {
        # 旧 Desc 列内容'SSH 远程主机'与 Host 列重复, 已随 P0 改进移除。
        # 锁定回归: 任何让 Desc 字段再次出现的改动都视为破坏本契约。
        $rows = & $script:mod { Get-HostSelectorRow -Hosts @('debian') }
        $rows[0].PSObject.Properties.Name | Should -Not -Contain 'Desc'
    }

    It 'Value 应等于主机名' {
        $rows = & $script:mod { Get-HostSelectorRow -Hosts @('debian') }
        $rows[0].Value | Should -Be 'debian'
    }

    It 'LastHost 应被置顶' {
        $rows = & $script:mod {
            Get-HostSelectorRow -Hosts @('debian', 'ubuntu', 'arch') -LastHost 'ubuntu'
        }
        $rows[0].Host | Should -Be 'ubuntu'
    }

    It 'LastHost 行应标注 ● last(兼容 ★ 最近变体)' {
        $rows = & $script:mod {
            Get-HostSelectorRow -Hosts @('debian', 'ubuntu') -LastHost 'ubuntu'
        }
        $rows[0].State | Should -Match '● last|★ 最近'
    }

    It '非 LastHost 行的 State 应为空' {
        $rows = & $script:mod {
            Get-HostSelectorRow -Hosts @('debian', 'ubuntu') -LastHost 'ubuntu'
        }
        $rows[1].State | Should -Be ''
    }

    It 'Disabled 应恒为 false' {
        $rows = & $script:mod { Get-HostSelectorRow -Hosts @('debian') }
        $rows[0].Disabled | Should -BeFalse
    }
}

Describe '已删除的全局操作菜单实现(2026-10-30 TUI 重构)' {

    # 原"全局操作菜单"是第二个表格面板, 与会话列表上下重复渲染。
    # 重构后它被"唯一主视图 + 底部单行动作条"取代, 相关实现必须**不再存在**,
    # 否则就可能出现两套并存的全局动作入口(用户看到两处入口 = 重构没做完)。
    It '全局操作菜单相关实现不得再存在' {
        foreach ($name in @(
                'Show-SessionManager', 'Invoke-GridViewSessionManager',
                'Get-GridViewManagerRow', 'Write-TmuxAvailabilityNotice')) {
            $found = & $script:mod {
                param($n) [bool](Get-Command $n -CommandType Function -ErrorAction SilentlyContinue)
            } $name
            $found | Should -BeFalse
        }
    }

    It '全局操作菜单相关源文件不得再出现在模块目录内' {
        $privateDir = Join-Path $script:mod.ModuleBase 'Private'
        foreach ($file in @(
                'Show-SessionManager.ps1', 'Get-GridViewManagerRow.ps1',
                'Write-TmuxAvailabilityNotice.ps1')) {
            Test-Path (Join-Path $privateDir $file) | Should -BeFalse
        }
    }
}


Describe '交互式 UI 单轨契约 (Terminal.Gui v2 回归防护)' {

    It 'Get-ConsoleUiBackend 的 Backend 恒为 TerminalGui' {
        $state = & $script:mod { Get-ConsoleUiBackend }
        $state.Backend | Should -Be 'TerminalGui'
    }

    It 'Get-ConsoleUiBackend 不得返回 AnsiFallback / GridView 旧轨名' {
        $state = & $script:mod { Get-ConsoleUiBackend }
        $state.Backend | Should -Not -Be 'AnsiFallback'
        $state.Backend | Should -Not -Be 'GridView'
    }

    It 'Get-ConsoleUiBackend 应返回统一的字段集合(不再有 PSTui 专用字段)' {
        $state = & $script:mod { Get-ConsoleUiBackend }
        foreach ($field in @('Backend', 'Available', 'Reason', 'TerminalGuiVersion')) {
            $state.PSObject.Properties.Name | Should -Contain $field
        }
        $state.PSObject.Properties.Name | Should -Not -Contain 'PstuiVersion'
        $state.PSObject.Properties.Name | Should -Not -Contain 'Conflicts'
    }

    It 'Assert-ConsoleUiReady 在主轨可用时不应抛错' {
        # 注入 Available=$true 的状态, 断言"可用即放行"这条契约与真实环境无关
        $threw = $false
        try {
            & $script:mod {
                $original = $script:ConsoleUiBackend
                try {
                    $script:ConsoleUiBackend = [PSCustomObject]@{
                        Backend   = 'TerminalGui'
                        Available = $true
                        Reason    = '测试注入的可用状态'
                    }
                    Assert-ConsoleUiReady -Feature '单元测试功能'
                } finally {
                    $script:ConsoleUiBackend = $original
                }
            }
        } catch {
            $threw = $true
        }
        $threw | Should -BeFalse
    }

    It 'Assert-ConsoleUiReady 在主轨不可用时应抛出可定位的终止错误' {
        $message = & $script:mod {
            $original = $script:ConsoleUiBackend
            try {
                $script:ConsoleUiBackend = [PSCustomObject]@{
                    Backend   = 'TerminalGui'
                    Available = $false
                    Reason    = '测试注入的不可用原因'
                }
                $script:thrownMessage = ''
                try {
                    Assert-ConsoleUiReady -Feature '单元测试功能'
                } catch {
                    $script:thrownMessage = $_.Exception.Message
                }
            } finally {
                $script:ConsoleUiBackend = $original
            }
            $script:thrownMessage
        }
        $message | Should -Not -BeNullOrEmpty
        $message | Should -BeLike '*单元测试功能*'
        $message | Should -BeLike '*测试注入的不可用原因*'
    }

    It 'Show-HostSelector 不再提供 -Backend 参数' {
        $keys = & $script:mod { (Get-Command Show-HostSelector).Parameters.Keys }
        $keys | Should -Not -Contain 'Backend'
    }

    It '已删除的 AnsiFallback 降级轨函数在模块作用域内应不存在' {
        $removed = @(
            'Invoke-AnsiMenu', 'Invoke-AnsiHostSelector', 'Invoke-AnsiSessionManager',
            'Invoke-ConsoleMenu', 'Invoke-MenuMachine', 'New-AnsiLayout',
            'Clear-AnsiScreen', 'Write-MenuItem', 'New-MenuItem',
            'New-StatusBadge', 'Format-StatusBadge', 'New-DynamicHelpPanel',
            'Get-SessionActionHelp', 'Resolve-MenuColorTable',
            'Get-TmuxSessionMenuOption', 'Test-FilterCharacter',
            'Get-FilteredItems', 'Update-FilterString', 'Send-MenuKey',
            'ConvertTo-CsiArrowKey', 'Update-InputBuffer', 'Test-InputValidation'
        )
        foreach ($name in $removed) {
            $found = & $script:mod {
                param($n) [bool](Get-Command $n -CommandType Function -ErrorAction SilentlyContinue)
            } $name
            $found | Should -BeFalse
        }
    }

    It '已删除的降级轨源文件不应出现在模块目录内' {
        # 基于 (Get-Module ShellPrompt).ModuleBase 推导, 不依赖仓库工作区路径,
        # 因此模块被安装到任意位置时该断言同样成立
        $privateDir = Join-Path $script:mod.ModuleBase 'Private'
        foreach ($file in @(
                'Invoke-AnsiMenu.ps1', 'Invoke-ConsoleMenu.ps1', 'Invoke-MenuMachine.ps1',
                'New-AnsiLayout.ps1', 'Clear-AnsiScreen.ps1', 'Write-MenuItem.ps1',
                'New-MenuItem.ps1', 'New-StatusBadge.ps1', 'Format-StatusBadge.ps1',
                'New-DynamicHelpPanel.ps1', 'Get-TmuxSessionMenuOption.ps1',
                'Get-KeyboardFilter.ps1', 'Show-InputPrompt.ps1',
                # 2026-10-30 PSTui 移除: GridView 轨实现文件全部删除
                'Invoke-GridViewMenu.ps1', 'Get-GridViewColumnPlan.ps1',
                'Restore-GridViewSelection.ps1', 'Initialize-GridViewColorScheme.ps1',
                'Set-TgColorScheme.ps1', 'Get-GridViewHostRow.ps1')) {
            Test-Path (Join-Path $privateDir $file) | Should -BeFalse
        }
    }

    It '已删除的 PSTui GridView 轨函数在模块作用域内应不存在' {
        $removed = @(
            'Invoke-GridViewMenu', 'Invoke-GridViewPrompt', 'Invoke-GridViewHostSelector',
            'Get-GridViewColumnPlan', 'Get-GridViewHostRow',
            'Get-GridViewRenderParam', 'Get-GridViewFocus',
            'ConvertTo-GridViewPlainText', 'Restore-GridViewSelection',
            'Initialize-GridViewColorScheme',
            'Set-TgColorScheme', 'New-TgColor', 'New-TgAttribute',
            'Set-TgSchemeSlot', 'Get-TgTargetScheme', 'Resolve-TgThemeName',
            'Sync-TgSchemeSlot', 'Test-TgColorSchemeSupport', 'Get-TgAssemblyPath',
            'Get-ConsoleUiModuleOnDisk', 'Test-ConsoleUiHostPrerequisite',
            'Test-ConsoleUiCommandConflict', 'Test-ConsoleUiTerminalGuiConflict'
        )
        foreach ($name in $removed) {
            $found = & $script:mod {
                param($n) [bool](Get-Command $n -CommandType Function -ErrorAction SilentlyContinue)
            } $name
            $found | Should -BeFalse
        }
    }

    It 'TerminalGui 主轨实现文件应存在于模块目录内' {
        $privateDir = Join-Path $script:mod.ModuleBase 'Private'
        foreach ($file in @(
                'New-TguiHostSelectorWindow.ps1', 'Invoke-TguiHostSelector.ps1',
                'Get-HostSelectorRow.ps1', 'Get-HostSelectorStateText.ps1',
                'Show-HostSelector.ps1', 'Get-ConsoleUiBackend.ps1',
                'Set-TguiTheme.ps1', 'Resolve-TguiThemeName.ps1',
                'Get-TguiContext.ps1')) {
            Test-Path (Join-Path $privateDir $file) | Should -BeTrue
        }
    }

    It 'TUI 重构新增的实现文件应存在于模块目录内' {
        # 2026-10-30: 单主视图 + 单行动作条 + 后台取数的实现文件;
        # 2026-10-30 晚回退轨移除: Show-TmuxSessionDashboard/Show-TmuxActionBar/
        # Resolve-TmuxActionKey/Read-TmuxActionKey/Get-TmuxPlaceholderRow 已删除(见下一条)。
        $privateDir = Join-Path $script:mod.ModuleBase 'Private'
        foreach ($file in @(
                'Get-TmuxActionDefinition.ps1',
                'Get-TmuxSessionState.ps1',
                'Submit-TmuxBackgroundTask.ps1', 'Receive-TmuxBackgroundTask.ps1',
                'Invoke-TmuxSessionFetch.ps1', 'Submit-WttrPrefetch.ps1')) {
            Test-Path (Join-Path $privateDir $file) | Should -BeTrue
        }
    }

    It '已删除的旧仪表盘 / 旧会话列表源文件不应出现在模块目录内' {
        # 2026-10-30 晚用户裁定移除: sss 回退轨(main 循环 + 双视图 + 键分发/占位行);
        # 2026-10-31 死代码清理: TGUI 单轨化后失去最后调用方的旧会话列表链与旧键位映射
        #   (AST 可达性分析: 从 5 个公开命令 / profile / 动态 dot-source 均不可达)。
        $privateDir = Join-Path $script:mod.ModuleBase 'Private'
        foreach ($file in @(
                'Show-TmuxSessionDashboard.ps1', 'Show-TmuxActionBar.ps1',
                'Read-TmuxActionKey.ps1', 'Get-TmuxPlaceholderRow.ps1',
                'Connect-TmuxSession.ps1', 'Remove-TmuxSession.ps1',
                'Show-TmuxSessionList.ps1', 'Resolve-TmuxActionKey.ps1',
                'Resolve-TmuxTuiKeyAction.ps1', 'ConvertTo-TguiKeyInfo.ps1',
                'Format-TmuxToolbarText.ps1', 'Format-GridViewStateText.ps1',
                'Get-TmuxSessionGridRow.ps1', 'Get-TmuxSessionStateText.ps1',
                'Get-TmuxSessionSummary.ps1', 'ConvertTo-TmuxRefreshSelection.ps1',
                'Get-TmuxRefreshedSession.ps1')) {
            Test-Path (Join-Path $privateDir $file) | Should -BeFalse
        }
    }
}
