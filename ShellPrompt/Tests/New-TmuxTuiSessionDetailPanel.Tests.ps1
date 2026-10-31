# New-TmuxTuiSessionDetailPanel.Tests.ps1 - tmux 会话仪表盘**右侧会话详情卡**的契约测试
#
# 覆盖 (2026-10-31 sss 仪表盘视图层):
#   1. New-TmuxTuiSessionDetailPanel: 详情卡只提供四个真实字段
#      (Session / Status / Windows / No), FrameView 有非空标题;
#   2. Set-TmuxTuiSessionDetail: 真实行落到四个值标签, $null 时全部显示 '—'
#      (绝不残留上一个会话的数据), 状态列按 Attached(绿)/Detached(灰)着色,
#      同一行重复写入时文本保持不变, 超长会话名按值列宽裁剪(不越界)。
#
# 说明: Terminal.Gui 视图可以在无 TTY 的环境下**构造**(不进事件循环),
#       本文件只组装/刷新视图, 不 Init / 不 Run。

Describe 'New-TmuxTuiSessionDetailPanel: 详情卡组装' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It '值标签恰好是 Session / Status / Windows / No 四个' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 40 -Height 10 -Theme $theme -Tgui $tg
            [PSCustomObject]@{ Keys = @($panel.Labels.Keys | Sort-Object) }
        }
        $result.Keys | Should -Be @('No', 'Session', 'Status', 'Windows')
    }

    It '卡片有非空标题' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 40 -Height 10 -Theme $theme -Tgui $tg
            [PSCustomObject]@{ Title = [string]$panel.Card.Title }
        }
        $result.Title | Should -Not -BeNullOrEmpty
    }
}

Describe 'Set-TmuxTuiSessionDetail: 字段落位' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It '真实行的四个字段分别落到对应值标签' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 40 -Height 10 -Theme $theme -Tgui $tg
            $row = [PSCustomObject]@{ No = 3; Session = 'alpha'; Status = 'Attached'; Windows = 7; Name = 'alpha' }
            Set-TmuxTuiSessionDetail -Panel $panel -Row $row
            [PSCustomObject]@{
                Session = [string]$panel.Labels['Session'].Text
                Status  = [string]$panel.Labels['Status'].Text
                Windows = [string]$panel.Labels['Windows'].Text
                No      = [string]$panel.Labels['No'].Text
            }
        }
        $result.Session | Should -BeExactly 'alpha'
        $result.Status | Should -BeExactly 'Attached'
        $result.Windows | Should -BeExactly '7'
        $result.No | Should -BeExactly '3'
    }

    It 'Row=$null 时四个字段全部变成 "—"(不残留上一个会话的数据)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 40 -Height 10 -Theme $theme -Tgui $tg
            $row = [PSCustomObject]@{ No = 3; Session = 'alpha'; Status = 'Attached'; Windows = 7; Name = 'alpha' }
            Set-TmuxTuiSessionDetail -Panel $panel -Row $row
            Set-TmuxTuiSessionDetail -Panel $panel -Row $null
            [PSCustomObject]@{
                Session = [string]$panel.Labels['Session'].Text
                Status  = [string]$panel.Labels['Status'].Text
                Windows = [string]$panel.Labels['Windows'].Text
                No      = [string]$panel.Labels['No'].Text
            }
        }
        $dash = [string][char]0x2014
        $result.Session | Should -BeExactly $dash
        $result.Status | Should -BeExactly $dash
        $result.Windows | Should -BeExactly $dash
        $result.No | Should -BeExactly $dash
    }

    It '状态列配色跟随 Attached(绿) / Detached(灰)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 40 -Height 10 -Theme $theme -Tgui $tg
            $attached = [PSCustomObject]@{ No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 1; Name = 'alpha' }
            $detached = [PSCustomObject]@{ No = 2; Session = 'beta'; Status = 'Detached'; Windows = 2; Name = 'beta' }
            Set-TmuxTuiSessionDetail -Panel $panel -Row $attached
            $isAttached = ($panel.Labels['Status'].GetScheme() -eq $theme.Attached)
            Set-TmuxTuiSessionDetail -Panel $panel -Row $detached
            $isDetached = ($panel.Labels['Status'].GetScheme() -eq $theme.Detached)
            [PSCustomObject]@{ IsAttached = $isAttached; IsDetached = $isDetached }
        }
        $result.IsAttached | Should -BeTrue
        $result.IsDetached | Should -BeTrue
    }

    It '切换到不同状态的会话时, 状态列配色确实发生变化' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 40 -Height 10 -Theme $theme -Tgui $tg
            $attached = [PSCustomObject]@{ No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 1; Name = 'alpha' }
            $detached = [PSCustomObject]@{ No = 2; Session = 'beta'; Status = 'Detached'; Windows = 2; Name = 'beta' }
            Set-TmuxTuiSessionDetail -Panel $panel -Row $attached
            $first = $panel.Labels['Status'].GetScheme()
            Set-TmuxTuiSessionDetail -Panel $panel -Row $detached
            $second = $panel.Labels['Status'].GetScheme()
            [PSCustomObject]@{ Changed = -not ($first -eq $second) }
        }
        $result.Changed | Should -BeTrue -Because 'Attached -> Detached 必须换配色'
    }

    It '同一行重复写入时, 值标签文本保持不变(不变的内容不被重写)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 40 -Height 10 -Theme $theme -Tgui $tg
            $row = [PSCustomObject]@{ No = 3; Session = 'alpha'; Status = 'Attached'; Windows = 7; Name = 'alpha' }
            Set-TmuxTuiSessionDetail -Panel $panel -Row $row
            $first = [string]$panel.Labels['Session'].Text
            Set-TmuxTuiSessionDetail -Panel $panel -Row $row
            $second = [string]$panel.Labels['Session'].Text
            [PSCustomObject]@{ First = $first; Second = $second; Same = ($first -ceq $second) }
        }
        $result.Same | Should -BeTrue
        $result.First | Should -BeExactly 'alpha'
    }

    It '超长会话名按值列宽裁剪(可见宽度不越界)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 40 -Height 10 -Theme $theme -Tgui $tg
            $row = [PSCustomObject]@{ No = 1; Session = ('x' * 80); Status = 'Attached'; Windows = 1; Name = 'x' }
            Set-TmuxTuiSessionDetail -Panel $panel -Row $row
            $text = [string]$panel.Labels['Session'].Text
            [PSCustomObject]@{
                Text       = $text
                Visible    = (Get-TguiTextWidth -Text $text)
                ValueWidth = [Math]::Max(6, $panel.Width - 13)
            }
        }
        $result.Visible | Should -BeLessOrEqual $result.ValueWidth
        $result.Text.EndsWith([string][char]0x2026) | Should -BeTrue
    }
}
