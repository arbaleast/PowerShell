<#
.SYNOPSIS
    控制台 UI 后端检测 (Get-ConsoleUiBackend 及其前置检查) 的 Pester 测试

.DESCRIPTION
    兼容性说明:
    1) 仓库既有测试使用 Pester v3 旧断言语法 (`Should Be`)。Pester 6 已移除该语法,
       本机安装的正是 Pester 6.2.0, 因此本文件统一使用 v5+ 的 `Should -Be` /
       `Should -Not -BeNullOrEmpty` 写法, 在 v5 与 v6 下均可运行。
    2) 模块作用域访问: 在 BeforeAll 内把模块对象存入 `$script:mod`, 再用
       `& $script:mod { ... }` 调用。不依赖文件顶层变量, 兼容 v6 收紧后的作用域。
#>

Describe 'Get-ConsoleUiBackend' {

    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..\ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module ShellPrompt
    }

    It '应返回结构完整的后端判定对象' {
        $result = & $script:mod { Get-ConsoleUiBackend }

        $result | Should -Not -BeNullOrEmpty
        foreach ($field in @('Backend', 'Available', 'Reason', 'Conflicts', 'PstuiVersion', 'TerminalGuiVersion')) {
            $result.PSObject.Properties[$field] | Should -Not -BeNullOrEmpty
        }
    }

    It 'Backend 恒为 GridView (已移除 AnsiFallback 降级轨)' {
        $result = & $script:mod { Get-ConsoleUiBackend }
        $result.Backend | Should -Be 'GridView'
    }

    It 'Available 为 $true 时不应报告任何命令冲突' {
        $result = & $script:mod { Get-ConsoleUiBackend }
        if ($result.Available) {
            @($result.Conflicts).Count | Should -Be 0
        } else {
            # 不可用时必须给出可读原因, 否则启动期告警会失去诊断价值
            [bool]$result.Reason | Should -Be $true
        }
    }

    It '不可用时 Reason 必须为非空字符串' {
        $result = & $script:mod { Get-ConsoleUiBackend }
        if (-not $result.Available) {
            $result.Reason | Should -BeOfType [string]
            $result.Reason.Length | Should -BeGreaterThan 0
        }
    }

    It '不再提供 UI.Backend 配置键' {
        # AnsiFallback 降级轨已移除, 强制后端的配置项随之失效, 应从配置中消失
        # 注意: $script:Config.UI 是有序哈希表, 取键必须用 .Keys (PSObject.Properties.Name 会得到哈希表自身成员)
        $hasKey = & $script:mod { @($script:Config.UI.Keys) -contains 'Backend' }
        $hasKey | Should -Be $false
    }

    It '重复调用应稳定返回同一后端(无副作用)' {
        $first = & $script:mod { Get-ConsoleUiBackend }
        $second = & $script:mod { Get-ConsoleUiBackend }
        $second.Backend | Should -Be $first.Backend
    }
}

Describe 'Get-ConsoleUiState (惰性检测)' {

    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..\ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module ShellPrompt
    }

    It '模块加载期不得执行主轨检测(检测结果必须为空)' {
        # 契约: Import-Module 阶段不跑 Get-ConsoleUiBackend, 该检测在启动期
        # 属于最大单一热点(实测约 500ms), 必须推迟到真正弹菜单时。
        $state = & $script:mod { $script:ConsoleUiBackend }
        $state | Should -BeNullOrEmpty
    }

    It 'Get-ConsoleUiState 首次调用后应完成检测并缓存结果' {
        $result = & $script:mod {
            $script:ConsoleUiBackend = $null
            $first = Get-ConsoleUiState
            $cached = $script:ConsoleUiBackend
            [PSCustomObject]@{
                First        = $first
                CachedIsNull = ($null -eq $cached)
                SameObject   = [object]::ReferenceEquals($first, $cached)
            }
        }
        $result.First | Should -Not -BeNullOrEmpty
        $result.First.Backend | Should -Be 'GridView'
        $result.CachedIsNull | Should -Be $false
        $result.SameObject | Should -Be $true
    }

    It 'Get-ConsoleUiState 重复调用应复用缓存(不再重跑检测)' {
        $result = & $script:mod {
            $script:ConsoleUiBackend = $null
            $null = Get-ConsoleUiState
            $second = Get-ConsoleUiState
            $third = Get-ConsoleUiState
            [object]::ReferenceEquals($second, $third)
        }
        $result | Should -Be $true
    }
}

Describe 'Assert-ConsoleUiReady' {

    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..\ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module ShellPrompt
    }

    It '主轨可用时应静默放行' {
        $available = & $script:mod { (Get-ConsoleUiBackend).Available }
        if ($available) {
            { & $script:mod { Assert-ConsoleUiReady -Feature '测试' } } | Should -Not -Throw
        }
    }

    It '主轨不可用时应抛出可定位的终止错误' {
        # $script:ConsoleUiBackend 是模块作用域共享状态, 必须用 try/finally 还原,
        # 否则会污染同批次执行的其它测试文件。
        & $script:mod {
            $script:ConsoleUiBackend = [PSCustomObject]@{
                Backend   = 'GridView'
                Available = $false
                Reason    = '测试注入的不可用原因'
            }
            $script:thrownMessage = ''
            try {
                Assert-ConsoleUiReady -Feature '单元测试功能'
            } catch {
                $script:thrownMessage = $_.Exception.Message
            } finally {
                # 还原为真实检测结果, 避免把注入状态泄漏给后续测试
                $script:ConsoleUiBackend = Get-ConsoleUiBackend
            }
        }
        $threw = [bool](& $script:mod { $script:thrownMessage })
        $message = & $script:mod { $script:thrownMessage }
        $threw | Should -Be $true
        $message | Should -BeLike '*单元测试功能*'
        $message | Should -BeLike '*测试注入的不可用原因*'
    }
}

Describe 'Test-ConsoleUiHostPrerequisite' {

    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..\ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module ShellPrompt
    }

    It '应返回 Ok / Reason / Details / PstuiVersion 四个字段' {
        $result = & $script:mod { Test-ConsoleUiHostPrerequisite }
        foreach ($field in @('Ok', 'Reason', 'Details', 'PstuiVersion')) {
            $result.PSObject.Properties[$field] | Should -Not -BeNullOrEmpty
        }
    }

    It 'Ok 应为布尔类型' {
        $result = & $script:mod { Test-ConsoleUiHostPrerequisite }
        $result.Ok | Should -BeOfType [bool]
    }

    It 'Details 应为字符串数组' {
        $result = & $script:mod { Test-ConsoleUiHostPrerequisite }
        # 用 -is 而非管道断言: 空数组经管道不会向 Should 送入任何输入
        ($result.Details -is [array]) | Should -Be $true
    }
}

Describe 'Test-ConsoleUiCommandConflict' {

    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..\ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module ShellPrompt
    }

    It '应返回 Ok / Conflicts / Reason 三个字段' {
        $result = & $script:mod { Test-ConsoleUiCommandConflict }
        foreach ($field in @('Ok', 'Conflicts', 'Reason')) {
            $result.PSObject.Properties[$field] | Should -Not -BeNullOrEmpty
        }
    }

    It 'Ok 为 $true 时 Conflicts 必须为空' {
        $result = & $script:mod { Test-ConsoleUiCommandConflict }
        if ($result.Ok) {
            @($result.Conflicts).Count | Should -Be 0
        }
    }

    It '冲突列表应为数组' {
        $result = & $script:mod { Test-ConsoleUiCommandConflict }
        ($result.Conflicts -is [array]) | Should -Be $true
    }
}

Describe 'Test-ConsoleUiTerminalGuiConflict' {

    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..\ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module ShellPrompt
    }

    It '应返回 Ok / Conflicts / TerminalGuiVersion / Reason 四个字段' {
        $result = & $script:mod { Test-ConsoleUiTerminalGuiConflict }
        foreach ($field in @('Ok', 'Conflicts', 'TerminalGuiVersion', 'Reason')) {
            $result.PSObject.Properties[$field] | Should -Not -BeNullOrEmpty
        }
    }

    It '检测不应把 ShellPrompt 自身的依赖模块判为冲突' {
        $result = & $script:mod { Test-ConsoleUiTerminalGuiConflict }
        # PwshSpectreConsole 依赖的是 Spectre.Console, 不绑定 Terminal.Gui, 不应出现在冲突里
        @($result.Conflicts) -contains 'PwshSpectreConsole' | Should -Be $false
    }
}

Describe 'Test-ConsoleUiInteractive' {

    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..\ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module ShellPrompt
    }

    It '应返回 Ok / Reason 两个字段' {
        $result = & $script:mod { Test-ConsoleUiInteractive }
        $result.PSObject.Properties['Ok'] | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties['Reason'] | Should -Not -BeNullOrEmpty
    }

    It 'Ok 应为布尔类型' {
        $result = & $script:mod { Test-ConsoleUiInteractive }
        $result.Ok | Should -BeOfType [bool]
    }
}

Describe 'Get-GridViewFocus' {

    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..\ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module ShellPrompt
    }

    It '默认应返回 Table' {
        $result = & $script:mod {
            $original = $script:Config.UI.GridViewFocus
            try {
                $script:Config.UI.GridViewFocus = 'Table'
                Get-GridViewFocus
            } finally {
                $script:Config.UI.GridViewFocus = $original
            }
        }
        $result | Should -Be 'Table'
    }

    It '配置为 Filter 时应返回 Filter' {
        $result = & $script:mod {
            $original = $script:Config.UI.GridViewFocus
            try {
                $script:Config.UI.GridViewFocus = 'Filter'
                Get-GridViewFocus
            } finally {
                $script:Config.UI.GridViewFocus = $original
            }
        }
        $result | Should -Be 'Filter'
    }

    It '非法配置值应静默回退到 Table' {
        $result = & $script:mod {
            $original = $script:Config.UI.GridViewFocus
            try {
                $script:Config.UI.GridViewFocus = 'NotAValidFocus'
                Get-GridViewFocus
            } finally {
                $script:Config.UI.GridViewFocus = $original
            }
        }
        $result | Should -Be 'Table'
    }
}

Describe 'Invoke-GridViewPrompt' {

    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..\ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module ShellPrompt
    }

    It '空行集合应直接返回 $null 而不弹窗' {
        $result = & $script:mod { Invoke-GridViewPrompt -Rows @() -Title '空表' }
        $result | Should -BeNullOrEmpty
    }

    It '非交互环境下弹窗失败应被兜住, 不得抛出到调用方' {
        # 本用例运行在输入被重定向的 Pester 进程内, Out-ConsoleGridView 会抛
        # "Not supported in this environment"; Invoke-GridViewPrompt 必须捕获并返回 $null。
        { & $script:mod {
                Invoke-GridViewPrompt -Rows @(
                    [PSCustomObject]@{ Name = 'a'; Value = 'a' }
                ) -Title '测试表' -WarningAction SilentlyContinue
            } } | Should -Not -Throw
    }
}

Describe 'Menu dispatchers' {

    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..\ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module ShellPrompt
    }

    It 'Show-HostSelector 不再提供 -Backend 参数' {
        # 2026-10-30: tmux UI 入口收敛为 TGI 轨 Show-TmuxTuiDashboard(私有),
        # 回退轨视图已删除 —— 该断言收敛到仍存活的 Show-HostSelector。
        foreach ($name in @('Show-HostSelector')) {
            $cmd = & $script:mod { param($n) Get-Command -Name $n -CommandType Function } $name
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.Parameters.ContainsKey('Backend') | Should -Be $false
        }
    }

    It 'Show-TmuxSessionList 不再提供 -Backend 参数' {
        $cmd = & $script:mod { Get-Command -Name 'Show-TmuxSessionList' -CommandType Function }
        $cmd | Should -Not -BeNullOrEmpty
        $cmd.Parameters.ContainsKey('Backend') | Should -Be $false
    }

    It 'GridView 实现函数应存在于模块私有作用域' {
        foreach ($name in @(
                'Invoke-GridViewHostSelector', 'Invoke-GridViewSessionList')) {
            $found = & $script:mod { param($n) [bool](Get-Command $n -CommandType Function -ErrorAction SilentlyContinue) } $name
            $found | Should -Be $true
        }
    }

    It '已删除的 AnsiFallback 实现函数不得再存在' {
        foreach ($name in @(
                'Invoke-AnsiHostSelector', 'Invoke-AnsiSessionManager',
                'Invoke-AnsiMenu', 'Invoke-ConsoleMenu', 'Invoke-MenuMachine',
                'New-AnsiLayout', 'Clear-AnsiScreen', 'Write-MenuItem',
                'New-StatusBadge', 'New-DynamicHelpPanel', 'Get-SessionActionHelp')) {
            $found = & $script:mod { param($n) [bool](Get-Command $n -CommandType Function -ErrorAction SilentlyContinue) } $name
            $found | Should -Be $false
        }
    }

    It '新菜单实现不得被导出到调用方可见的命令列表' {
        # 用模块对象的 ExportedCommands 判定, 不能在模块作用域内用 Get-Command -Module
        # (那样会把模块私有函数一并列出来)
        $exported = @($script:mod.ExportedCommands.Keys)
        foreach ($name in @(
                'Invoke-GridViewHostSelector', 'Invoke-GridViewSessionList',
                'Invoke-GridViewPrompt', 'Get-ConsoleUiBackend')) {
            $exported -contains $name | Should -Be $false
        }
    }
}
