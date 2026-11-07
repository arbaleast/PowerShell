# Enter-TmuxAlternateScreen.Tests.ps1 - 备用屏幕生命周期契约测试
# 覆盖:
#   1. Enter 写出 \e[?1049h (NoNewline), 且幂等(重复调用只写一次);
#   2. Exit 写出 \e[?1049l (NoNewline), 且幂等;
#   3. 未进入时 Exit 是无操作(不误发 1049l, 避免与 PSTui FullScreen 缓冲错位);
#   4. 终端所有权分流: 'Legacy' 照旧发 1049 协议; 'Tgui' 下 Enter/Exit 全部静默
#      且不改状态位(TG 自己管备用屏, 再发一次就是双层嵌套)。
# 说明: 终端写入口都是 Write-Host, 用 Pester Mock 接住参数断言, 不触碰真实终端。

Describe '备用屏幕生命周期 (Enter/Exit-TmuxAlternateScreen)' {

    BeforeAll {
        # Pester v6: 路径与模块引用必须放在 BeforeAll 内解析
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    BeforeEach {
        # 重置模块内的屏幕状态位与终端所有权标记, 保证每个用例从"未进入 + Legacy"出发
        & $script:mod { $script:TmuxAltScreenActive = $false; $script:TmuxTerminalOwner = 'Legacy' }
        Mock -CommandName Write-Host -ModuleName ShellPrompt -MockWith { }
    }

    It 'Enter 写出 \e[?1049h (NoNewline)' {
        & $script:mod { Enter-TmuxAlternateScreen }

        Should -Invoke -CommandName Write-Host -ModuleName ShellPrompt -Exactly 1 `
            -ParameterFilter { $NoNewline -and $Object -match '\[\?1049h' }
    }

    It 'Enter 幂等: 已在备用屏幕时不重复发送协议序列' {
        & $script:mod { Enter-TmuxAlternateScreen; Enter-TmuxAlternateScreen }

        Should -Invoke -CommandName Write-Host -ModuleName ShellPrompt -Exactly 1 `
            -ParameterFilter { $NoNewline -and $Object -match '\[\?1049h' }
    }

    It '未进入时 Exit 是无操作(不误发 \e[?1049l)' {
        & $script:mod { Exit-TmuxAlternateScreen }

        Should -Invoke -CommandName Write-Host -ModuleName ShellPrompt -Exactly 0 `
            -ParameterFilter { $Object -match '1049' }
    }

    It 'Exit 写出 \e[?1049l 并复位状态位, 且幂等' {
        & $script:mod { Enter-TmuxAlternateScreen; Exit-TmuxAlternateScreen; Exit-TmuxAlternateScreen }

        Should -Invoke -CommandName Write-Host -ModuleName ShellPrompt -Exactly 1 `
            -ParameterFilter { $NoNewline -and $Object -match '\[\?1049l' }
    }

    It '成对调用后可再次进入(暂停/恢复语义)' {
        & $script:mod {
            Enter-TmuxAlternateScreen
            Exit-TmuxAlternateScreen
            Enter-TmuxAlternateScreen
        }

        Should -Invoke -CommandName Write-Host -ModuleName ShellPrompt -Exactly 2 `
            -ParameterFilter { $NoNewline -and $Object -match '\[\?1049h' }
        Should -Invoke -CommandName Write-Host -ModuleName ShellPrompt -Exactly 1 `
            -ParameterFilter { $NoNewline -and $Object -match '\[\?1049l' }
    }
}

Describe '终端所有权分流 (Legacy / Tgui 备用屏协议)' {

    BeforeAll {
        # Pester v6: 路径与模块引用必须放在 BeforeAll 内解析
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    BeforeEach {
        & $script:mod { $script:TmuxAltScreenActive = $false; $script:TmuxTerminalOwner = 'Legacy' }
        Mock -CommandName Write-Host -ModuleName ShellPrompt -MockWith { }
    }

    AfterEach {
        # 复位所有权标记: 模块实例在同一会话内共享, 不复位会污染后续用例
        & $script:mod { $script:TmuxTerminalOwner = 'Legacy' }
    }

    It 'Legacy 模式下 Enter 发出 \e[?1049h 且 Exit 发出 \e[?1049l' {
        & $script:mod {
            Enter-TmuxAlternateScreen
            Exit-TmuxAlternateScreen
        }

        Should -Invoke -CommandName Write-Host -ModuleName ShellPrompt -Exactly 1 `
            -ParameterFilter { $NoNewline -and $Object -match '\[\?1049h' }
        Should -Invoke -CommandName Write-Host -ModuleName ShellPrompt -Exactly 1 `
            -ParameterFilter { $NoNewline -and $Object -match '\[\?1049l' }
    }

    It 'Tgui 模式下 Enter 不发出任何 1049 序列, 且不改变状态位' {
        & $script:mod {
            $script:TmuxTerminalOwner = 'Tgui'
            Enter-TmuxAlternateScreen
        }

        Should -Invoke -CommandName Write-Host -ModuleName ShellPrompt -Exactly 0 `
            -ParameterFilter { $Object -match '1049' }
        (& $script:mod { $script:TmuxAltScreenActive }) | Should -BeFalse
    }

    It 'Tgui 模式下 Exit 不发出任何 1049 序列, 且不改变状态位' {
        & $script:mod {
            $script:TmuxAltScreenActive = $true
            $script:TmuxTerminalOwner = 'Tgui'
            Exit-TmuxAlternateScreen
        }

        Should -Invoke -CommandName Write-Host -ModuleName ShellPrompt -Exactly 0 `
            -ParameterFilter { $Object -match '1049' }
        (& $script:mod { $script:TmuxAltScreenActive }) | Should -BeTrue
    }

    It 'Tgui 模式下成对调用不产生任何屏幕翻转序列(不双层嵌套备用屏)' {
        & $script:mod {
            $script:TmuxTerminalOwner = 'Tgui'
            Enter-TmuxAlternateScreen
            Exit-TmuxAlternateScreen
        }

        Should -Invoke -CommandName Write-Host -ModuleName ShellPrompt -Exactly 0 `
            -ParameterFilter { $Object -match '1049' }
        (& $script:mod { $script:TmuxAltScreenActive }) | Should -BeFalse
    }
}
