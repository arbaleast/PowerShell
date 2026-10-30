# Enter-TmuxAlternateScreen.Tests.ps1 - 备用屏幕生命周期契约测试
# 覆盖:
#   1. Enter 写出 \e[?1049h (NoNewline), 且幂等(重复调用只写一次);
#   2. Exit 写出 \e[?1049l (NoNewline), 且幂等;
#   3. 未进入时 Exit 是无操作(不误发 1049l, 避免与 PSTui FullScreen 缓冲错位)。
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
        # 重置模块内的屏幕状态位, 保证每个用例从"未进入"出发
        & $script:mod { $script:TmuxAltScreenActive = $false }
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

Describe '绝对的全量重绘 (Clear-TmuxScreen)' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
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

    It '写出 \e[2J\e[H(清屏 + 光标归位 0,0), 单次调用' {
        & $script:mod { Clear-TmuxScreen }

        $script:seen.Count | Should -Be 1
        $script:seen[0] | Should -Match '\[2J'
        $script:seen[0] | Should -Match '\[H'
    }

    It '迭代开头清屏与备用屏切换成同一次调用的合法组合(先 1049h, 后 2J/H)' {
        # Enter-TmuxAlternateScreen = 1049h + 2J/H; Clear-TmuxScreen = 2J/H
        & $script:mod { Enter-TmuxAlternateScreen; Clear-TmuxScreen }

        $script:seen.Count | Should -Be 3
        $script:seen[0] | Should -Match '\[\?1049h'
        $script:seen[1] | Should -Match '\[2J'
        $script:seen[2] | Should -Match '\[2J'
    }
}
