<#
.SYNOPSIS
    交互式 UI 主轨 (Terminal.Gui v2 ALC) 可用性检测的 Pester 测试

.DESCRIPTION
    兼容性说明:
    1) 本文件统一使用 Pester v5+ 的 `Should -Be` /
       `Should -Not -BeNullOrEmpty` 写法 (Pester 6 兼容)。
    2) 模块作用域访问: 在 BeforeAll 内把模块对象存入 `$script:mod`, 再用
       `& $script:mod { ... }` 调用。不依赖文件顶层变量, 兼容 v6 收紧后的作用域。
    3) 2026-10-30 PSTui 移除: 原 PSTui 可发现性 / Out-ConsoleGridView 冲突 /
       Terminal.Gui 运行时争用检测与 Get-GridViewFocus / Invoke-GridViewPrompt
       的用例随其实现删除; 本文件改为覆盖 vendored Terminal.Gui 探测与
       交互判定 (Backend 恒为 'TerminalGui')。
#>

Describe 'Get-ConsoleUiBackend' {

    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..\ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module ShellPrompt
    }

    It '应返回结构完整的后端判定对象' {
        $result = & $script:mod { Get-ConsoleUiBackend }

        $result | Should -Not -BeNullOrEmpty
        foreach ($field in @('Backend', 'Available', 'Reason', 'TerminalGuiVersion')) {
            $result.PSObject.Properties[$field] | Should -Not -BeNullOrEmpty
        }
    }

    It 'Backend 恒为 TerminalGui (AnsiFallback / PSTui GridView 轨均已移除)' {
        $result = & $script:mod { Get-ConsoleUiBackend }
        $result.Backend | Should -Be 'TerminalGui'
    }

    It '不可用时 Reason 必须为非空字符串(可诊断)' {
        $result = & $script:mod { Get-ConsoleUiBackend }
        if (-not $result.Available) {
            $result.Reason | Should -BeOfType [string]
            $result.Reason.Length | Should -BeGreaterThan 0
        }
    }

    It 'vendored Terminal.Gui 探测结果应与 Backend 字段一致' {
        $result = & $script:mod {
            $probe = Test-ConsoleUiTguiAssembly
            [PSCustomObject]@{
                ProbeExists = ($null -ne $probe)
                Available   = (Get-ConsoleUiBackend).Available
            }
        }
        if ($result.ProbeExists) {
            # 探测到 vendored 程序集时, 可用性只取决于交互判定, 不做死断言;
            # 版本目录探测到的版本必须回填到 TerminalGuiVersion
            $version = & $script:mod { (Get-ConsoleUiBackend).TerminalGuiVersion }
            $version | Should -Match '^\d+(\.\d+)*$'
        } else {
            $result.Available | Should -Be $false
        }
    }

    It '不再提供 UI.Backend 配置键' {
        $hasKey = & $script:mod { @($script:Config.UI.Keys) -contains 'Backend' }
        $hasKey | Should -Be $false
    }

    It '重复调用应稳定返回同一后端(无副作用)' {
        $first = & $script:mod { Get-ConsoleUiBackend }
        $second = & $script:mod { Get-ConsoleUiBackend }
        $second.Backend | Should -Be $first.Backend
    }
}

Describe 'Test-ConsoleUiTguiAssembly (vendored 程序集探测)' {

    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..\ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module ShellPrompt
    }

    It '应返回 Version / Path 两个字段(仓库 vendored 目录正常时)' {
        $probe = & $script:mod { Test-ConsoleUiTguiAssembly }
        if ($null -ne $probe) {
            $probe.PSObject.Properties.Name | Should -Contain 'Version'
            $probe.PSObject.Properties.Name | Should -Contain 'Path'
            $probe.Version | Should -BeOfType [version]
        }
    }

    It '探测不得加载任何程序集到默认上下文' {
        # 契约: 探测只做文件系统查找, 不加载 DLL,
        # 否则会把 ALC 隔离设计打穿(默认上下文绑定 TG 类型身份)。
        $loaded = & $script:mod {
            $before = @([System.AppDomain]::CurrentDomain.GetAssemblies() |
                    Where-Object { $_.GetName().Name -eq 'Terminal.Gui' })
            $null = Test-ConsoleUiTguiAssembly
            $after = @([System.AppDomain]::CurrentDomain.GetAssemblies() |
                    Where-Object { $_.GetName().Name -eq 'Terminal.Gui' })
            @($after).Count - @($before).Count
        }
        $loaded | Should -Be 0
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
        $result.First.Backend | Should -Be 'TerminalGui'
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
                Backend   = 'TerminalGui'
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
        # PSTui 已移除, 错误信息不得再要求安装 PSTui
        $message | Should -Not -BeLike '*PSTui*'
    }
}

Describe 'Test-ConsoleUiInteractive' {

    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..\ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module ShellPrompt
    }

    It '应返回 Ok / Reason 两个字段' {
        $result = & $script:mod { Test-ConsoleUiInteractive }
        $result.PSObject.Properties.Name | Should -Contain 'Ok'
        $result.PSObject.Properties.Name | Should -Contain 'Reason'
    }

    It 'Ok 应为布尔类型' {
        $result = & $script:mod { Test-ConsoleUiInteractive }
        $result.Ok | Should -BeOfType [bool]
    }
}

Describe 'Menu dispatchers (主机选择器单轨契约)' {

    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..\ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module ShellPrompt
    }

    It 'Show-HostSelector 不再提供 -Backend 参数' {
        $keys = & $script:mod { (Get-Command Show-HostSelector).Parameters.Keys }
        $keys | Should -Not -Contain 'Backend'
    }

    It 'Terminal.Gui 主机选择器实现函数应存在于模块私有作用域' {
        foreach ($name in @('Invoke-TguiHostSelector', 'New-TguiHostSelectorWindow',
                'Get-HostSelectorRow', 'Get-ConsoleUiBackend', 'Assert-ConsoleUiReady')) {
            $found = & $script:mod {
                param($n) [bool](Get-Command $n -CommandType Function -ErrorAction SilentlyContinue)
            } $name
            $found | Should -Be $true
        }
    }

    It '已删除的 PSTui GridView 实现函数不得再存在' {
        foreach ($name in @(
                'Invoke-GridViewPrompt', 'Invoke-GridViewHostSelector',
                'Get-GridViewColumnPlan', 'Get-GridViewHostRow',
                'Restore-GridViewSelection', 'Initialize-GridViewColorScheme',
                'Set-TgColorScheme', 'Resolve-TgThemeName',
                'Test-ConsoleUiHostPrerequisite', 'Test-ConsoleUiCommandConflict',
                'Test-ConsoleUiTerminalGuiConflict', 'Get-ConsoleUiModuleOnDisk')) {
            $found = & $script:mod {
                param($n) [bool](Get-Command $n -CommandType Function -ErrorAction SilentlyContinue)
            } $name
            $found | Should -BeFalse
        }
    }

    It '主机选择器实现不得被导出到调用方可见的命令列表' {
        $exported = @(Get-Command -Module ShellPrompt | Select-Object -ExpandProperty Name)
        foreach ($name in @('Invoke-TguiHostSelector', 'New-TguiHostSelectorWindow',
                'Get-HostSelectorRow', 'Get-ConsoleUiBackend', 'Assert-ConsoleUiReady')) {
            $exported | Should -Not -Contain $name
        }
    }
}
