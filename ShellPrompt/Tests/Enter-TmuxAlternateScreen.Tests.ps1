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

Describe '绝对的全量重绘 (Clear-TmuxScreen)' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    AfterEach {
        # 所有权标记复位: Tgui 静音用例改过它, 不复位会污染后续用例
        & $script:mod { $script:TmuxTerminalOwner = 'Legacy' }
    }

    BeforeEach {
        # 捕获式断言: 记录真实序列内容与顺序, 比 ParameterFilter 稳(上一版
        # 在过滤器里用 .Contains([char]27) 于部分宿主下求值异常, 计数归 0)。
        # 前缀 'N'/'+' 标记是否符合 -NoNewline 调用(信息略带, 顺带消耗参数
        # 以免 PSSA PSReviewUnusedParameter 误报)。
        $script:seen = [System.Collections.Generic.List[string]]::new()
        Mock -CommandName Write-Host -ModuleName ShellPrompt -MockWith {
            param($Object, $NoNewline)
            $prefix = if ($NoNewline) { 'N' } else { '+' }
            $script:seen.Add("$prefix$( [string]$Object )")
        }
    }

    It '清屏动作不抛错; 回退路径写出 \e[2J\e[H(仅在 Clear 异常的环境)' {
        # 第六轮起使用 .NET 原生 [Console]::Clear + SetCursorPosition。
        # Write-Host 明细因宿主而异: Windows 真机/Unix 重定向下 Console.Clear
        # 直接把 ANSI 写进底层流(不经过 Write-Host)→ 0 次捕获;
        # 若 Clear 异常则走 Write-Host 回退 → 1 次 2J/H。两种都合法。
        { & $script:mod { Clear-TmuxScreen } } | Should -Not -Throw

        if ($script:seen.Count -eq 1) {
            $script:seen[0] | Should -Match '\[2J'
        } else {
            $script:seen.Count | Should -Be 0
        }
    }

    It 'Tgui 模式下 Clear-TmuxScreen 整体静音(不触碰 TG 自管的画面缓冲区)' {
        # 2026-10-30 审计#3(防御纵深): 有 'Tgui'(Terminal.Gui 独占备用屏)时,
        # [Console]::Clear 会抹掉 TG 的画面 —— 清屏也必须遵守终端所有权。
        & $script:mod {
            $script:TmuxTerminalOwner = 'Tgui'
            Enter-TmuxAlternateScreen
            Clear-TmuxScreen
        }
        # Legacy 分支的 1049h 未发(Tgui 静音), 且 Clear 也未走 Write-Host 回退
        $script:seen.Where({ $_ -match '1049' }) | Should -BeNullOrEmpty
        $script:seen.Where({ $_ -match '\[2J' }) | Should -BeNullOrEmpty
        (& $script:mod { $script:TmuxAltScreenActive }) | Should -BeFalse
    }

    It '迭代开头清屏与备用屏切换的合法组合: 至多一次回退 2J/H' {
        # Enter-TmuxAlternateScreen = 1049h(第六轮起不再自带 2J/H);
        # Clear-TmuxScreen = .NET 原生清屏(异常才回退 Write-Host)
        & $script:mod { Enter-TmuxAlternateScreen; Clear-TmuxScreen }

        if ($script:seen.Count -eq 2) {
            $script:seen[0] | Should -Match '\[\?1049h'
            $script:seen[1] | Should -Match '\[2J'
        } else {
            # .NET Clear 直接写底层流的环境: 只有 1049h 经过 Write-Host
            $script:seen.Count | Should -Be 1
            $script:seen[0] | Should -Match '\[\?1049h'
        }
    }
}
