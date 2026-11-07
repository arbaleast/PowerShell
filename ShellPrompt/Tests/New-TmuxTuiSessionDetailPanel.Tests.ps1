# New-TmuxTuiSessionDetailPanel.Tests.ps1 - tmux 仪表盘**右侧驾驶舱**的契约测试
#
# 覆盖 (2026-11-06 #9b871512 "Forest Matrix"(非对称三区驾驶舱)):
#   1. New-TmuxTuiSessionDetailPanel: 面板是**普通 View**(无 FrameView 外框),
#      四个区块 Session/Summary/Windows/Preview, 值标签键集为
#      Session/State/Host/Summary/Created/Windows/Preview;
#      **没有** Session Index 标签, **没有** ACTIONS 段;
#   2. 三区结构: 行 0 = "SESSION // <name>" + "SUMMARY"(宽屏并排, 窄屏堆叠),
#      行 3 = "─" 细分隔线, 行 4 = "WINDOWS & ACTIVE PROCESSES",
#      底部贴底 = "TERMINAL PREVIEW [<session>:<win>.0]" + 线框预览;
#   3. Set-TmuxTuiSessionDetail: 真实行落到各值标签(State 是"符号 + 文字"徽标串),
#      $null 时全部降级为 '—'/'N/A' 且不残留上一个会话的数据;
#   4. Update-TmuxTuiWindowRows: 窗口拓扑渲染(活动窗口 "*" 标记 / "└─" 路径行),
#      空拓扑显示占位提示;
#   5. Update-TmuxTuiPreviewBox: 线框 ┌ ┐ └ ┘ + "│" 前缀内容行, 内容按可用宽度裁剪,
#      无快照时显示 "[No preview output available]"。
#
# 说明: Terminal.Gui 视图可以在无 TTY 的环境下**构造**(不进事件循环),
#       本文件只组装/刷新视图, 不 Init / 不 Run。

Describe 'New-TmuxTuiSessionDetailPanel: 驾驶舱组装' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It '值标签键集是 Session/State/Host/Summary/Created/Windows/Preview' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 30 -Theme $theme -Tgui $tg
            [PSCustomObject]@{ Keys = @($panel.Labels.Keys | Sort-Object) }
        }
        $result.Keys | Should -Be @('Created', 'Host', 'Preview', 'Session', 'State', 'Summary', 'Windows')
    }

    It 'Session Index 已被移除: 键集里没有 Index, 也没有 Session Index / Session Inde 文本' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 30 -Theme $theme -Tgui $tg
            $texts = @($panel.View.SubViews | ForEach-Object { [string]$_.Text })
            [PSCustomObject]@{
                HasIndexKey = @($panel.Labels.Keys | Where-Object { $_ -eq 'Index' }).Count
                AllText     = ($texts -join '|')
            }
        }
        $result.HasIndexKey | Should -Be 0 -Because '"#2"这种行号对用户没有价值, Session Index 已被删除'
        $result.AllText | Should -Not -Match 'Session Index' -Because '不得残留 Session Index 文案'
        $result.AllText | Should -Not -Match 'Session Inde' -Because '阶段一的 "Session Inde" 截断缺陷必须彻底消失'
    }

    It 'ACTIONS 段已移除(与底栏重复): 没有 Actions 键, 视图里没有 ACTIONS 文本' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 30 -Theme $theme -Tgui $tg
            $texts = @($panel.View.SubViews | ForEach-Object { [string]$_.Text })
            [PSCustomObject]@{
                HasActionsKey = @($panel.Labels.Keys | Where-Object { $_ -eq 'Actions' }).Count
                AllText       = ($texts -join '|')
                SectionNames  = @($panel.Sections | ForEach-Object { $_.Name })
            }
        }
        $result.HasActionsKey | Should -Be 0 -Because 'ACTIONS 与底部快捷键栏 100% 重复, 已整体删除'
        $result.AllText | Should -Not -Match 'ACTIONS' -Because '视图里不得再出现 ACTIONS 段'
        $result.SectionNames | Should -Not -Contain 'Actions'
    }

    It '面板容器是普通 View, **不是** FrameView(无外框 => 无双重竖线)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 30 -Theme $theme -Tgui $tg
            [PSCustomObject]@{
                ViewType = $panel.View.GetType().Name
                CardType = $panel.Card.GetType().Name
                SameObj  = [object]::ReferenceEquals($panel.View, $panel.Card)
            }
        }
        $result.ViewType | Should -Not -Be 'FrameView' -Because '新驾驶舱去掉了 FrameView 外框(旧实现有双重竖线)'
        $result.CardType | Should -Not -Be 'FrameView'
        $result.SameObj | Should -BeTrue -Because '.Card 是 .View 的别名(同一对象)'
    }

    It '四个区块分别是 Session / Summary / Windows / Preview' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 30 -Theme $theme -Tgui $tg
            [PSCustomObject]@{
                SectionNames  = @($panel.Sections | ForEach-Object { $_.Name })
                SectionTitles = @($panel.Sections | ForEach-Object { [string]$_.Title.Text })
                ContainerText = @($panel.View.SubViews | ForEach-Object { [string]$_.Text })
            }
        }
        $result.SectionNames | Should -Be @('Session', 'Summary', 'Windows', 'Preview')
        $result.SectionTitles[0] | Should -BeExactly 'SESSION //'
        $result.SectionTitles[1] | Should -BeExactly 'SUMMARY'
        $result.SectionTitles[2] | Should -BeExactly 'WINDOWS & ACTIVE PROCESSES'
        # 标题必须是容器里**可见**的 Label 文本
        $result.ContainerText | Should -Contain 'SESSION //'
        $result.ContainerText | Should -Contain 'SUMMARY'
        $result.ContainerText | Should -Contain 'WINDOWS & ACTIVE PROCESSES'
    }

    It '区块小标题用 ForestAccent(竹青)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 30 -Theme $theme -Tgui $tg
            [PSCustomObject]@{
                Session  = ($panel.Labels['Session'].GetScheme() -eq $theme.ForestAccent)
                Summary  = ($panel.Labels['Summary'].GetScheme() -eq $theme.ForestAccent)
                Windows  = (@($panel.Sections | Where-Object { $_.Name -eq 'Windows' })[0].Title.GetScheme() -eq $theme.ForestAccent)
                Preview  = ($panel.Labels['Preview'].GetScheme() -eq $theme.ForestAccent)
            }
        }
        $result.Session | Should -BeTrue
        $result.Summary | Should -BeTrue
        $result.Windows | Should -BeTrue
        $result.Preview | Should -BeTrue
    }

    It 'SUMMARY 堆叠: 宽度 40 时落在第 0 列, 宽度 60 时落在 30, 宽度 51 时落在 25' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $narrow = New-TmuxTuiSessionDetailPanel -Width 40 -Height 30 -Theme $theme -Tgui $tg
            $wide = New-TmuxTuiSessionDetailPanel -Width 60 -Height 30 -Theme $theme -Tgui $tg
            $mid = New-TmuxTuiSessionDetailPanel -Width 51 -Height 30 -Theme $theme -Tgui $tg
            [PSCustomObject]@{
                NarrowX = [int][regex]::Match($narrow.Labels['Summary'].X.ToString(), '\d+').Value
                WideX = [int][regex]::Match($wide.Labels['Summary'].X.ToString(), '\d+').Value
                MidX = [int][regex]::Match($mid.Labels['Summary'].X.ToString(), '\d+').Value
                SessionX = [int][regex]::Match($wide.Labels['Session'].X.ToString(), '\d+').Value
            }
        }
        $result.NarrowX | Should -Be 0 -Because '窄面板放不下并排, SUMMARY 落到左缘纵向堆叠'
        $result.WideX | Should -Be 30 -Because '60 列时 SUMMARY 落在右半起点 floor(60/2)'
        $result.MidX | Should -Be 25 -Because '51 列时 SUMMARY 落在 floor(51/2)=25'
        $result.SessionX | Should -Be 0
    }

    It '分隔线在第 3 行, 内容全是 "─"(宽度个), 且用 ForestFrame' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 30 -Theme $theme -Tgui $tg
            $text = [string]$panel.Separator.Text
            [PSCustomObject]@{
                Y = [int][regex]::Match($panel.Separator.Y.ToString(), '\d+').Value
                DashCount = ([regex]::Matches($text, [string][char]0x2500)).Count
                OtherChars = (([regex]::Replace($text, [string][char]0x2500, '')) -replace '\s', '').Length
                IsFrame = ($panel.Separator.GetScheme() -eq $theme.ForestFrame)
            }
        }
        $result.Y | Should -Be 3 -Because '分隔线固定在第 3 行(上方两行信息 + 标题行之下)'
        $result.DashCount | Should -Be 60 -Because '分隔线铺满整行宽度'
        $result.OtherChars | Should -Be 0 -Because '分隔线上不得混入其它可见字符'
        $result.IsFrame | Should -BeTrue
    }

    It 'WINDOWS & ACTIVE PROCESSES 标题在第 4 行' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 30 -Theme $theme -Tgui $tg
            $title = @($panel.Sections | Where-Object { $_.Name -eq 'Windows' })[0].Title
            [PSCustomObject]@{ Y = [int][regex]::Match($title.Y.ToString(), '\d+').Value }
        }
        $result.Y | Should -Be 4
    }

    It '预览块贴底: 预览框下沿落在面板最后一行(标题 1 + 上框 1 + 内容 8 + 下框 1)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 30 -Theme $theme -Tgui $tg
            # 预览内容槽位是懒创建的: 写一次详情才会生成 8 行内容槽位
            $row = [PSCustomObject]@{
                No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 1; Name = 'alpha'
                Activity = 'Active now'; PaneCount = 1
                WindowList = @(); PreviewLines = @('x')
            }
            Set-TmuxTuiSessionDetail -Panel $panel -Row $row
            [PSCustomObject]@{
                Height = $panel.Height
                BlockHeight = $panel.PreviewBlockHeight
                TitleY = [int][regex]::Match($panel.Labels['Preview'].Y.ToString(), '\d+').Value
                BottomY = [int][regex]::Match($panel.PreviewBoxBottom.Y.ToString(), '\d+').Value
                ContentTop = $panel.PreviewContentTop
                PreviewRows = @($panel.PreviewRows).Count
            }
        }
        $result.BlockHeight | Should -Be 11 -Because '预览块固定 11 行(标题 + 上框 + 8 行内容 + 下框)'
        $result.TitleY | Should -Be 19 -Because '30 行面板里预览标题落在 Height - 11 = 19'
        $result.BottomY | Should -Be 29 -Because '预览框下沿贴在面板最后一行'
        $result.ContentTop | Should -Be 21
        $result.PreviewRows | Should -Be 8 -Because '预览内容最多 8 行'
    }
}

Describe 'Set-TmuxTuiSessionDetail: 字段落位' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It '真实行的字段分别落到对应值标签(State 是徽标串)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 30 -HostName 'deb' -Theme $theme -Tgui $tg
            $row = [PSCustomObject]@{
                No = 3; Session = 'alpha'; Status = 'Attached'; Windows = 7; Name = 'alpha'
                Created = '2d ago'; Activity = 'Active now'; PaneCount = 0
                WindowList = @(); PreviewLines = @()
            }
            Set-TmuxTuiSessionDetail -Panel $panel -Row $row
            [PSCustomObject]@{
                Session = [string]$panel.Labels['Session'].Text
                State   = [string]$panel.Labels['State'].Text
                Host    = [string]$panel.Labels['Host'].Text
                Created = [string]$panel.Labels['Created'].Text
                Windows = [string]$panel.Labels['Windows'].Text
            }
        }
        $result.Session | Should -BeExactly 'SESSION // alpha' -Because '标题行是 "SESSION // <name>" 形态'
        $result.State | Should -BeExactly ('State: {0} Attached (Active now)' -f [string][char]0x25CF) -Because 'State 是"符号 + 文字"的徽标串'
        $result.Host | Should -BeExactly 'Host : deb'
        $result.Created | Should -BeExactly 'Created : 2d ago'
        $result.Windows | Should -BeExactly 'Windows : 7' -Because 'PaneCount 为 0 时不显示 "(Np)" 后缀'
    }

    It 'Detached 会话且 Activity 是相对时间: "State: ○ Detached (Active 5m ago)"' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 30 -HostName 'deb' -Theme $theme -Tgui $tg
            $row = [PSCustomObject]@{
                No = 1; Session = 'beta'; Status = 'Detached'; Windows = 2; Name = 'beta'
                Created = '5h ago'; Activity = '5m ago'; PaneCount = 0
                WindowList = @(); PreviewLines = @()
            }
            Set-TmuxTuiSessionDetail -Panel $panel -Row $row
            [string]$panel.Labels['State'].Text
        }
        $result | Should -BeExactly ('State: {0} Detached (Active 5m ago)' -f [string][char]0x25CB)
    }

    It 'Activity 已经是 "Active now" 时不重复加 "Active " 前缀' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 30 -HostName 'deb' -Theme $theme -Tgui $tg
            $row = [PSCustomObject]@{
                No = 1; Session = 'beta'; Status = 'Attached'; Windows = 2; Name = 'beta'
                Activity = 'Active now'; PaneCount = 0
                WindowList = @(); PreviewLines = @()
            }
            Set-TmuxTuiSessionDetail -Panel $panel -Row $row
            [string]$panel.Labels['State'].Text
        }
        $result | Should -BeExactly ('State: {0} Attached (Active now)' -f [string][char]0x25CF)
        $result | Should -Not -Match 'Active Active'
    }

    It 'Created / Activity 缺失时降级为 N/A(不编造假时间)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 30 -HostName 'deb' -Theme $theme -Tgui $tg
            $row = [PSCustomObject]@{
                No = 1; Session = 'beta'; Status = 'Detached'; Windows = 2; Name = 'beta'
                WindowList = @(); PreviewLines = @()
            }
            Set-TmuxTuiSessionDetail -Panel $panel -Row $row
            [PSCustomObject]@{
                Created = [string]$panel.Labels['Created'].Text
                State = [string]$panel.Labels['State'].Text
            }
        }
        $result.Created | Should -BeExactly 'Created : N/A'
        $result.State | Should -BeExactly ('State: {0} Detached (Active N/A)' -f [string][char]0x25CB)
    }

    It 'PaneCount > 0 时 Windows 显示 "(Np)" 后缀' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 30 -HostName 'deb' -Theme $theme -Tgui $tg
            $row = [PSCustomObject]@{
                No = 1; Session = 'beta'; Status = 'Attached'; Windows = 3; Name = 'beta'
                Activity = 'Active now'; PaneCount = 4
                WindowList = @(); PreviewLines = @()
            }
            Set-TmuxTuiSessionDetail -Panel $panel -Row $row
            [string]$panel.Labels['Windows'].Text
        }
        $result | Should -BeExactly 'Windows : 3 (4p)'
    }

    It '编排层没传主机名时, Host 显示 "—" 而不是空串(没有数据就写 "—")' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            # 不传 -HostName(默认空串)
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 30 -Theme $theme -Tgui $tg
            $row = [PSCustomObject]@{
                No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 2; Name = 'alpha'
                Activity = 'Active now'; PaneCount = 0
                WindowList = @(); PreviewLines = @()
            }
            Set-TmuxTuiSessionDetail -Panel $panel -Row $row
            [string]$panel.Labels['Host'].Text
        }
        $result | Should -BeExactly ('Host : {0}' -f [string][char]0x2014) -Because '空串会渲染成一条空行, 看着像漏字'
    }

    It 'Row=$null 时各值字段全部降级(不残留上一个会话的数据)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 30 -HostName 'deb' -Theme $theme -Tgui $tg
            $row = [PSCustomObject]@{
                No = 3; Session = 'alpha'; Status = 'Attached'; Windows = 7; Name = 'alpha'
                Created = '2d ago'; Activity = 'Active now'; PaneCount = 4
                WindowList = @(); PreviewLines = @()
            }
            Set-TmuxTuiSessionDetail -Panel $panel -Row $row
            Set-TmuxTuiSessionDetail -Panel $panel -Row $null
            [PSCustomObject]@{
                Session = [string]$panel.Labels['Session'].Text
                State   = [string]$panel.Labels['State'].Text
                Host    = [string]$panel.Labels['Host'].Text
                Created = [string]$panel.Labels['Created'].Text
                Windows = [string]$panel.Labels['Windows'].Text
                Preview = [string]$panel.Labels['Preview'].Text
            }
        }
        $result.Session | Should -BeExactly 'SESSION //'
        $result.State | Should -BeExactly ('State: {0} (no session selected)' -f [string][char]0x2014)
        $result.Host | Should -BeExactly ('Host : {0}' -f [string][char]0x2014)
        $result.Created | Should -BeExactly 'Created : N/A'
        $result.Windows | Should -BeExactly 'Windows : N/A'
        $result.Preview | Should -BeExactly 'TERMINAL PREVIEW'
    }

    It '空态不得显示陈旧会话名(整窗文本里查不到上一个会话)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 30 -HostName 'deb' -Theme $theme -Tgui $tg
            $row = [PSCustomObject]@{
                No = 3; Session = 'stale-session-name'; Status = 'Attached'; Windows = 7; Name = 'stale-session-name'
                Activity = 'Active now'; PaneCount = 0
                WindowList = @(); PreviewLines = @()
            }
            Set-TmuxTuiSessionDetail -Panel $panel -Row $row
            Set-TmuxTuiSessionDetail -Panel $panel -Row $null
            [PSCustomObject]@{
                AllText = (@($panel.View.SubViews | ForEach-Object { [string]$_.Text }) -join '|')
                Session = [string]$panel.Labels['Session'].Text
            }
        }
        $result.AllText | Should -Not -Match 'stale-session-name' -Because '空态绝不能残留上一个会话名'
        $result.Session | Should -BeExactly 'SESSION //'
    }

    It '同一行重复写入时, 值标签文本保持不变(不变的内容不被重写)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 30 -Theme $theme -Tgui $tg
            $row = [PSCustomObject]@{
                No = 3; Session = 'alpha'; Status = 'Attached'; Windows = 7; Name = 'alpha'
                Activity = 'Active now'; PaneCount = 0
                WindowList = @(); PreviewLines = @()
            }
            Set-TmuxTuiSessionDetail -Panel $panel -Row $row
            $first = [string]$panel.Labels['Session'].Text
            Set-TmuxTuiSessionDetail -Panel $panel -Row $row
            $second = [string]$panel.Labels['Session'].Text
            [PSCustomObject]@{ First = $first; Second = $second; Same = ($first -ceq $second) }
        }
        $result.Same | Should -BeTrue
        $result.First | Should -BeExactly 'SESSION // alpha'
    }

    It '窗口数取自合并行的 int 字段(Windows 仍是窗口数, 不是拓扑数组)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 30 -HostName 'deb' -Theme $theme -Tgui $tg
            $row = [PSCustomObject]@{
                No = 1; Session = 'beta'; Status = 'Attached'; Windows = 3; Name = 'beta'
                Activity = 'Active now'; PaneCount = 4
                WindowList = @(
                    [PSCustomObject]@{ Index = 0; Name = 'main'; Active = $true; Panes = 1; Command = 'nvim'; Path = '/home/u/w'; PathShort = '~/w' }
                )
                PreviewLines = @()
            }
            Set-TmuxTuiSessionDetail -Panel $panel -Row $row
            [PSCustomObject]@{
                Windows = [string]$panel.Labels['Windows'].Text
            }
        }
        $result.Windows | Should -BeExactly 'Windows : 3 (4p)'
    }
}

Describe 'Update-TmuxTuiWindowRows: 窗口拓扑渲染' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It '活动窗口行以 "*" 开头, 非活动窗口行不以 "*" 开头' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 30 -HostName 'deb' -Theme $theme -Tgui $tg
            $row = [PSCustomObject]@{
                No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 2; Name = 'alpha'
                Activity = 'Active now'; PaneCount = 2
                WindowList = @(
                    [PSCustomObject]@{ Index = 0; Name = 'main'; Active = $true; Panes = 1; Command = 'nvim'; Path = '/home/u/work/src'; PathShort = '~/work/src' }
                    [PSCustomObject]@{ Index = 1; Name = 'editor'; Active = $false; Panes = 1; Command = 'bash'; Path = '/home/u/other'; PathShort = '~/other' }
                )
                PreviewLines = @()
            }
            Set-TmuxTuiSessionDetail -Panel $panel -Row $row
            # ★ 槽位模型: 一个槽位 = 一行。窗口 k 占第 2k(名称行) 与 2k+1(路径行)
            #   两个槽位; 活动标记 `*` 单独占一个 2 列的 Label(Marker),
            #   所以它能独立用 BrightGreen(窗口名则用 BrightWhite)。
            $wr = @($panel.WinRows)
            [PSCustomObject]@{
                ActiveMarker    = [string]$wr[0].Marker.Text
                ActiveMarkerIsGreen = ($wr[0].Marker.GetScheme() -eq $theme.ForestActive)
                ActiveName      = [string]$wr[0].Label.Text
                ActiveNameIsWhite  = ($wr[0].Label.GetScheme() -eq $theme.ForestActiveName)
                ActivePath      = [string]$wr[1].Label.Text
                PathIsForest      = ($wr[1].Label.GetScheme() -eq $theme.ForestPath)
                InactiveMarker  = [string]$wr[2].Marker.Text
                InactiveName    = [string]$wr[2].Label.Text
                InactiveNameIsForest = ($wr[2].Label.GetScheme() -eq $theme.ForestPaneName)
                InactivePath    = [string]$wr[3].Label.Text
                MarkerX = $wr[0].Marker.X.ToString()
                LabelX  = $wr[0].Label.X.ToString()
            }
        }
        $result.ActiveMarker | Should -BeExactly ([string][char]0x2A) -Because '活动窗口用 * 标记'
        $result.ActiveMarkerIsGreen | Should -BeTrue -Because '活动标识 * 用 ForestActive(BrightGreen)'
        $result.ActiveName | Should -BeExactly '0:main (nvim)' -Because '标记单独占一列, 名称列不含前导空格'
        $result.ActiveNameIsWhite | Should -BeTrue -Because '活动窗口名用 ForestActiveName(白)'
        $result.ActivePath | Should -BeExactly ('  {0}{1} ~/work/src' -f [string][char]0x2514, [string][char]0x2500) -Because '路径行带 "└─" 前缀与 ~ 折叠路径'
        $result.PathIsForest | Should -BeTrue -Because '路径行用 ForestPath(DarkGray)'
        $result.InactiveMarker | Should -BeExactly ' ' -Because '非活动窗口的标记位留空'
        $result.InactiveName | Should -BeExactly '1:editor (bash)'
        $result.InactiveNameIsForest | Should -BeTrue -Because '非活动窗口名用 ForestPaneName(灰)'
        $result.InactivePath | Should -BeExactly ('  {0}{1} ~/other' -f [string][char]0x2514, [string][char]0x2500)
        # 标记列与名称列相邻且不重叠
        $result.MarkerX | Should -BeExactly 'Absolute(0)'
        $result.LabelX | Should -BeExactly 'Absolute(2)'
    }

    It '没有窗口拓扑时显示占位提示(不画空白)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 30 -HostName 'deb' -Theme $theme -Tgui $tg
            $row = [PSCustomObject]@{
                No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 0; Name = 'alpha'
                Activity = 'Active now'; PaneCount = 0
                WindowList = @(); PreviewLines = @()
            }
            Set-TmuxTuiSessionDetail -Panel $panel -Row $row
            [string]@($panel.WinRows)[0].Label.Text
        }
        $result | Should -BeExactly '(no window details available)'
    }
}

Describe 'Update-TmuxTuiPreviewBox: 终端预览线框' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It '预览标题是 "TERMINAL PREVIEW [会话名:窗口号.0]"' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 30 -HostName 'deb' -Theme $theme -Tgui $tg
            $row = [PSCustomObject]@{
                No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 1; Name = 'alpha'
                Activity = 'Active now'; PaneCount = 1
                WindowList = @(
                    [PSCustomObject]@{ Index = 0; Name = 'main'; Active = $true; Panes = 1; Command = 'zsh'; Path = '/home/u'; PathShort = '~' }
                )
                PreviewLines = @('hello')
            }
            Set-TmuxTuiSessionDetail -Panel $panel -Row $row
            [string]$panel.Labels['Preview'].Text
        }
        $result | Should -BeExactly 'TERMINAL PREVIEW [alpha:0.0]'
    }

    It '线框上/下沿是 ┌…┐ / └…┘, 内容行以 "│" 前缀' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 30 -HostName 'deb' -Theme $theme -Tgui $tg
            $row = [PSCustomObject]@{
                No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 1; Name = 'alpha'
                Activity = 'Active now'; PaneCount = 1
                WindowList = @(); PreviewLines = @('debian@server:~$ git log --oneline')
            }
            Set-TmuxTuiSessionDetail -Panel $panel -Row $row
            $pr = @($panel.PreviewRows)
            [PSCustomObject]@{
                Top      = [string]$panel.PreviewBoxTop.Text
                Bottom   = [string]$panel.PreviewBoxBottom.Text
                First    = [string]$pr[0].Text
                Second   = [string]$pr[1].Text
                TopIsBox    = ($panel.PreviewBoxTop.GetScheme() -eq $theme.ForestPreviewBox)
                ContentIsBox = ($pr[0].GetScheme() -eq $theme.ForestPreview)
            }
        }
        $result.Top | Should -Match ('^[{0}]' -f [string][char]0x250C) -Because '上沿以 ┌ 开头'
        $result.Top | Should -Match ('[{0}]$' -f [string][char]0x2510) -Because '上沿以 ┐ 结尾'
        $result.Bottom | Should -Match ('^[{0}]' -f [string][char]0x2514) -Because '下沿以 └ 开头'
        $result.Bottom | Should -Match ('[{0}]$' -f [string][char]0x2518) -Because '下沿以 ┘ 结尾'
        $result.First | Should -Match ('^[{0}]' -f [string][char]0x2502) -Because '内容行以 │ 前缀'
        $result.First | Should -Match ('[{0}]$' -f [string][char]0x2502) -Because '内容行以 │ 收尾(框是闭合的)'
        $result.First | Should -Match ('^' + [regex]::Escape([string][char]0x2502) + ' debian') -Because '首行内容原样呈现'
        $result.Second | Should -Match ('^[{0} ]+[{0}]$' -f [string][char]0x2502) -Because '多余的内容槽位只留竖线与空白'
        $result.TopIsBox | Should -BeTrue -Because '框线用 ForestPreviewBox'
        $result.ContentIsBox | Should -BeTrue -Because '正文用 ForestPreview'
    }

    It '内容按可用内宽裁剪(不越出面板宽度)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 40 -Height 30 -HostName 'deb' -Theme $theme -Tgui $tg
            $long = 'x' * 200
            $row = [PSCustomObject]@{
                No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 1; Name = 'alpha'
                Activity = 'Active now'; PaneCount = 1
                WindowList = @(); PreviewLines = @($long)
            }
            Set-TmuxTuiSessionDetail -Panel $panel -Row $row
            $text = [string]@($panel.PreviewRows)[0].Text
            [PSCustomObject]@{
                Visible = (Get-TguiTextWidth -Text $text)
                Width = $panel.Width
                HasEllipsis = $text.Contains([string][char]0x2026)
            }
        }
        $result.Visible | Should -BeLessOrEqual ($result.Width - 1) -Because '内容行不得越出面板宽度'
        $result.HasEllipsis | Should -BeTrue -Because '超长内容按显示宽度裁剪并加省略号'
    }

    It '没有预览快照时显示 "[No preview output available]"' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 30 -HostName 'deb' -Theme $theme -Tgui $tg
            $row = [PSCustomObject]@{
                No = 1; Session = 'alpha'; Status = 'Attached'; Windows = 1; Name = 'alpha'
                Activity = 'Active now'; PaneCount = 1
                WindowList = @(); PreviewLines = @()
            }
            Set-TmuxTuiSessionDetail -Panel $panel -Row $row
            [string]@($panel.PreviewRows)[0].Text
        }
        $result | Should -Match ('^' + [regex]::Escape([string][char]0x2502) + ' \[No preview') -Because '无快照时显示占位提示'
        $result | Should -Match ('[{0}]$' -f [string][char]0x2502) -Because '占位提示行同样以 │ 收尾'
    }
}
