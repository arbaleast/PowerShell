# New-TmuxTuiSessionDetailPanel.Tests.ps1 - tmux 仪表盘**右侧会话工作区**(三段式)的契约测试
#
# 覆盖 (2026-11-06 阶段一 · 视觉层级与工作区布局重构):
#   1. New-TmuxTuiSessionDetailPanel: 面板是**普通 View**(无 FrameView 外框,
#      消除"双重竖线"), 三段区块标题 SESSION OVERVIEW / WINDOWS / ACTIONS,
#      值标签键集为 Session/Status/Index/Windows/Host/WindowsSummary/Actions,
#      ACTIONS 段暴露 Enter/n/r/x 四组键位与说明;
#   2. Set-TmuxTuiSessionDetail: 真实行落到各值标签, Status 是**徽标串**
#      (● Attached / ○ Detached), Index 取代旧 No, WindowsSummary 是窗口摘要,
#      $null 时全部显示 '—' 且不残留上一个会话的数据(绝不出现陈旧会话名),
#      状态配色按 Attached(绿)/Detached(灰)切换, 同一行重复写入文本保持不变,
#      超长会话名按值列宽裁剪(不越界);
#   3. RawValues 守卫: 原值未变时不再重复裁剪。
#
# 说明: Terminal.Gui 视图可以在无 TTY 的环境下**构造**(不进事件循环),
#       本文件只组装/刷新视图, 不 Init / 不 Run。

Describe 'New-TmuxTuiSessionDetailPanel: 三段式工作区组装' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It '值标签键集是 Session/Status/Index/Windows/Host/WindowsSummary/Actions' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 20 -Theme $theme -Tgui $tg
            [PSCustomObject]@{ Keys = @($panel.Labels.Keys | Sort-Object) }
        }
        $result.Keys | Should -Be @('Actions', 'Host', 'Index', 'Session', 'Status', 'Windows', 'WindowsSummary')
    }

    It '面板容器是普通 View, **不是** FrameView(无外框 => 无双重竖线)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 20 -Theme $theme -Tgui $tg
            [PSCustomObject]@{
                ViewType = $panel.View.GetType().Name
                CardType = $panel.Card.GetType().Name
                SameObj  = [object]::ReferenceEquals($panel.View, $panel.Card)
            }
        }
        $result.ViewType | Should -Not -Be 'FrameView' -Because '阶段一去掉 FrameView 外框(旧实现有双重竖线)'
        $result.CardType | Should -Not -Be 'FrameView'
        $result.SameObj | Should -BeTrue -Because '.Card 是 .View 的别名(同一对象)'
    }

    It '三个区块标题分别是 SESSION OVERVIEW / WINDOWS / ACTIONS' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 20 -Theme $theme -Tgui $tg
            [PSCustomObject]@{
                SectionNames  = @($panel.Sections | ForEach-Object { $_.Name })
                SectionTitles = @($panel.Sections | ForEach-Object { [string]$_.Title.Text })
                ContainerText = @($panel.View.SubViews | ForEach-Object { [string]$_.Text })
            }
        }
        $result.SectionNames | Should -Be @('Overview', 'Windows', 'Actions')
        $result.SectionTitles | Should -Be @('SESSION OVERVIEW', 'WINDOWS', 'ACTIONS')
        # 标题必须是容器里**可见**的 Label 文本
        $result.ContainerText | Should -Contain 'SESSION OVERVIEW'
        $result.ContainerText | Should -Contain 'WINDOWS'
        $result.ContainerText | Should -Contain 'ACTIONS'
    }

    It 'ACTIONS 段暴露 Enter/n/r/x 四组键位与说明标签' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 20 -Theme $theme -Tgui $tg
            [PSCustomObject]@{
                Keys    = @($panel.ActionKeyLabels.Keys | Sort-Object)
                Desc    = @($panel.ActionDescLabels.Keys | Sort-Object)
                KeyText = @($panel.ActionKeyLabels.Keys | Sort-Object | ForEach-Object { [string]$panel.ActionKeyLabels[$_].Text })
            }
        }
        $result.Keys | Should -Be @('Enter', 'n', 'r', 'x')
        $result.Desc | Should -Be @('Enter', 'n', 'r', 'x')
        $result.KeyText | Should -Be @('Enter', 'n', 'r', 'x')
    }

    It '高度不足时从下往上裁剪(先砍 ACTIONS), 但概览段永远保留' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 6 -Theme $theme -Tgui $tg
            [PSCustomObject]@{
                OverviewTitle = [string]$panel.Sections[0].Title.Text
                ActionKeyText = [string]$panel.ActionKeyLabels['Enter'].Text
            }
        }
        $result.OverviewTitle | Should -BeExactly 'SESSION OVERVIEW' -Because '概览段是主视觉, 任何高度下都必须保留'
        $result.ActionKeyText | Should -BeNullOrEmpty -Because '高度不够时先裁 ACTIONS 段'
    }
}

Describe 'Set-TmuxTuiSessionDetail: 字段落位' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It '真实行的字段分别落到对应值标签(Status 是徽标串)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 20 -HostName 'deb' -Theme $theme -Tgui $tg
            $row = [PSCustomObject]@{ No = 3; Session = 'alpha'; Status = 'Attached'; Windows = 7; Name = 'alpha' }
            Set-TmuxTuiSessionDetail -Panel $panel -Row $row
            [PSCustomObject]@{
                Session = [string]$panel.Labels['Session'].Text
                Status  = [string]$panel.Labels['Status'].Text
                Index   = [string]$panel.Labels['Index'].Text
                Windows = [string]$panel.Labels['Windows'].Text
                Host    = [string]$panel.Labels['Host'].Text
                Summary = [string]$panel.Labels['WindowsSummary'].Text
            }
        }
        $result.Session | Should -BeExactly 'alpha'
        $result.Status | Should -BeExactly '● Attached' -Because 'Status 是"符号 + 文字"的徽标串, 不是裸 Attached'
        $result.Index | Should -BeExactly '3' -Because 'Index 取代旧 No 键'
        $result.Windows | Should -BeExactly '7'
        $result.Host | Should -BeExactly 'deb'
        $result.Summary | Should -BeExactly '● 7 active window(s) in this session'
    }

    It '编排层没传主机名时, Host 显示 "—" 而不是空串(没有数据就写 "—")' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            # 不传 -HostName(默认空串)
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 20 -Theme $theme -Tgui $tg
            $row = [PSCustomObject]@{ No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 2; Name = 'alpha' }
            Set-TmuxTuiSessionDetail -Panel $panel -Row $row
            [string]$panel.Labels['Host'].Text
        }
        $result | Should -BeExactly ([string][char]0x2014) -Because '空串会渲染成一条空行, 看着像漏字'
    }

    It 'Detached 会话的 Status 徽标是 ○ Detached' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 20 -HostName 'deb' -Theme $theme -Tgui $tg
            $row = [PSCustomObject]@{ No = 1; Session = 'beta'; Status = 'Detached'; Windows = 2; Name = 'beta' }
            Set-TmuxTuiSessionDetail -Panel $panel -Row $row
            [PSCustomObject]@{
                Status  = [string]$panel.Labels['Status'].Text
                Summary = [string]$panel.Labels['WindowsSummary'].Text
            }
        }
        $result.Status | Should -BeExactly '○ Detached'
        $result.Summary | Should -BeExactly '○ 2 window(s) in this session'
    }

    It 'Row=$null 时各值字段全部变成 "—"(不残留上一个会话的数据)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 20 -HostName 'deb' -Theme $theme -Tgui $tg
            $row = [PSCustomObject]@{ No = 3; Session = 'alpha'; Status = 'Attached'; Windows = 7; Name = 'alpha' }
            Set-TmuxTuiSessionDetail -Panel $panel -Row $row
            Set-TmuxTuiSessionDetail -Panel $panel -Row $null
            [PSCustomObject]@{
                Session = [string]$panel.Labels['Session'].Text
                Status  = [string]$panel.Labels['Status'].Text
                Index   = [string]$panel.Labels['Index'].Text
                Windows = [string]$panel.Labels['Windows'].Text
                Host    = [string]$panel.Labels['Host'].Text
                Summary = [string]$panel.Labels['WindowsSummary'].Text
            }
        }
        $dash = [string][char]0x2014
        $result.Session | Should -BeExactly $dash
        $result.Index | Should -BeExactly $dash
        $result.Windows | Should -BeExactly $dash
        $result.Host | Should -BeExactly $dash
        # 空态的徽标与摘要明确写"没有选中", 不是残留的旧值
        $result.Status | Should -BeExactly '○ no session selected'
        $result.Summary | Should -BeExactly '— no active window(s)'
    }

    It '空态不得显示陈旧会话名(整窗文本里查不到上一个会话)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 20 -HostName 'deb' -Theme $theme -Tgui $tg
            $row = [PSCustomObject]@{ No = 3; Session = 'stale-session-name'; Status = 'Attached'; Windows = 7; Name = 'stale-session-name' }
            Set-TmuxTuiSessionDetail -Panel $panel -Row $row
            Set-TmuxTuiSessionDetail -Panel $panel -Row $null
            [PSCustomObject]@{
                AllText = (@($panel.View.SubViews | ForEach-Object { [string]$_.Text }) -join '|')
                Session = [string]$panel.Labels['Session'].Text
            }
        }
        $result.AllText | Should -Not -Match 'stale-session-name' -Because '空态绝不能残留上一个会话名'
        $result.Session | Should -BeExactly ([string][char]0x2014)
    }

    It '状态列配色跟随 Attached(绿) / Detached(灰)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 20 -Theme $theme -Tgui $tg
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
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 20 -Theme $theme -Tgui $tg
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
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 20 -Theme $theme -Tgui $tg
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
            $panel = New-TmuxTuiSessionDetailPanel -Width 40 -Height 20 -Theme $theme -Tgui $tg
            $row = [PSCustomObject]@{ No = 1; Session = ('x' * 80); Status = 'Attached'; Windows = 1; Name = 'x' }
            Set-TmuxTuiSessionDetail -Panel $panel -Row $row
            $text = [string]$panel.Labels['Session'].Text
            [PSCustomObject]@{
                Text       = $text
                Visible    = (Get-TguiTextWidth -Text $text)
                ValueWidth = [Math]::Max(6, $panel.ValueWidth)
            }
        }
        $result.Visible | Should -BeLessOrEqual $result.ValueWidth
        $result.Text.EndsWith([string][char]0x2026) | Should -BeTrue
    }
}
