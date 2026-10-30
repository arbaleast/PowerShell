# Resolve-TmuxTuiKeyAction.Tests.ps1 - TGUI 键位到业务动作映射契约测试(阶段 A, Goal 六-3/4)
# 覆盖:
#   Enter->Attach(需会话)/N New/R Refresh/S Ssh/X Remove(需会话)/Esc 与 Q->Quit/
#   未命中为空串(方向键等交给 TG 内建导航, 不冒充业务动作)。
# 说明: 纯函数; 键位契约复用 Get-TmuxActionDefinition 唯一事实来源。

Describe 'TGUI 键位动作映射 (Resolve-TmuxTuiKeyAction)' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'

        function Get-KeyStub {
            param(
                [string]$Key = '',
                [char]$KeyChar = [char]0
            )
            [PSCustomObject]@{ Key = $Key; KeyChar = $KeyChar }
        }
    }

    It 'Enter + 有会话 -> Attach; 无会话 -> 空串(死键防护)' {
        $enter = Get-KeyStub -Key 'Enter' -KeyChar ([char]13)
        (& $script:mod { param($k, $h) Resolve-TmuxTuiKeyAction -KeyInfo $k -HasSessions $h } $enter $true) |
            Should -BeExactly 'Attach'
        (& $script:mod { param($k, $h) Resolve-TmuxTuiKeyAction -KeyInfo $k -HasSessions $h } $enter $false) |
            Should -BeExactly ''
    }

    It '单字母键 N/R/S/X 分别映射 New/Refresh/Ssh/Remove' {
        foreach ($pair in @(
                @('n', 'New'), @('r', 'Refresh'), @('s', 'Ssh')
            )) {
            $stub = Get-KeyStub -KeyChar ([char]$pair[0])
            (& $script:mod { param($k) Resolve-TmuxTuiKeyAction -KeyInfo $k -HasSessions $true } $stub) |
                Should -BeExactly $pair[1]
        }
        $xKey = Get-KeyStub -KeyChar ([char]'x')
        (& $script:mod { param($k) Resolve-TmuxTuiKeyAction -KeyInfo $k -HasSessions $true } $xKey) |
            Should -BeExactly 'Remove'
        (& $script:mod { param($k) Resolve-TmuxTuiKeyAction -KeyInfo $k -HasSessions $false } $xKey) |
            Should -BeExactly ''
    }

    It 'Esc 与 Q 都是退出(Goal 三-3 两键同义)' {
        $esc = Get-KeyStub -Key 'Escape' -KeyChar ([char]27)
        $q = Get-KeyStub -KeyChar ([char]'q')
        (& $script:mod { param($k) Resolve-TmuxTuiKeyAction -KeyInfo $k -HasSessions $true } $esc) |
            Should -BeExactly 'Quit'
        (& $script:mod { param($k) Resolve-TmuxTuiKeyAction -KeyInfo $k -HasSessions $true } $q) |
            Should -BeExactly 'Quit'
    }

    It '未命中键(方向键/未知字母)返回空串, 交给 TG 内建导航' {
        $left = Get-KeyStub -Key 'LeftArrow' -KeyChar ([char]0)
        # stub 形状自检: Windows/Linux 对 [char]0 的求值必须一致 —— 若 Windows
        # 出偏差会在这里以具体 char 码暴露, 而不是 puzzling 地命中 Quit。
        [int]$left.KeyChar | Should -Be 0
        (& $script:mod { param($k) Resolve-TmuxTuiKeyAction -KeyInfo $k -HasSessions $true } $left) |
            Should -BeExactly ''

        $z = Get-KeyStub -KeyChar ([char]'z')
        [int]$z.KeyChar | Should -Be 122
        (& $script:mod { param($k) Resolve-TmuxTuiKeyAction -KeyInfo $k -HasSessions $true } $z) |
            Should -BeExactly ''
    }

    It 'KeyInfo 为 $null 返回空串(防御)' {
        (& $script:mod { Resolve-TmuxTuiKeyAction -KeyInfo $null }) | Should -BeExactly ''
    }
}
