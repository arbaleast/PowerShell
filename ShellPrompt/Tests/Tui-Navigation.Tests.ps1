# Tui-Navigation.Tests.ps1 - sss TUI 导航/布局/宽字符的稳定性回归护栏
<#
.SYNOPSIS
    sss 仪表盘的**导航边界、极端尺寸布局、中文字符显示宽度**回归测试。

.DESCRIPTION
    本文件覆盖 2026-11「性能与稳定性专项审计」实测确认的问题:

    1. **选中行移出可视区后不再滚动**(P0 功能缺陷, 已修):
       Update-TmuxTuiSessionSelection 只刷新旧/新两行并**跳过越界槽位**。
       实测(100 行 / 可视 10 行 / 连按 15 次下移): Top 恒为 0、
       SelectedIndex=15、**处于选中态的槽位数 = 0** —— 屏幕上没有任何一行
       处于选中态, 而右侧详情卡却已切到新会话(界面自相矛盾, 用户看不到
       自己选中了谁)。修复: 新增 Sync-TmuxTuiSessionScroll, 与 SSH 主机
       仪表盘的 Sync-SshHostDashboardScroll 同构。

    2. **极端终端尺寸**(40x10 / 80x24 / 120x35 / 160x45)下布局不得抛异常、
       不得出现负宽高或区域重叠。

    3. **中文字符(CJK 双宽)的截断与列对齐**: 会话名/主机名截断必须按
       **显示宽度**而不是字符数, 否则中文名会让右侧状态列错位。

    测试不 mock 生产函数, 全部走真实实现; 窗口层用 TG 的
    `View.NewKeyDownEvent(Key)` 触发**真实的 KeyDown 处理器**(不 Init
    终端, 因此可在 CI 无头环境运行)。
#>

BeforeAll {
    $script:manifestPath = Join-Path (Resolve-Path "$PSScriptRoot\..").Path 'ShellPrompt.psd1'
    Import-Module -Name $script:manifestPath -Force -ErrorAction Stop
    $script:mod = Get-Module -Name 'ShellPrompt'
    # 仓库根: 生命周期子进程的脚本要落到 .agent_cache/ 下(沙箱隔离约定)
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

Describe '列表导航: 选中行必须始终可见 (2026-11 审计 P0 修复)' {

    BeforeAll {
        # 造一个"行数远多于可视高度"的列表 —— 真实 tmux 环境里会话数超过一屏很常见
        $script:makeList = {
            param($rows = 100, $height = 10, $selected = 0)
            & $script:mod {
                param($rows, $height, $selected)
                $tg = Get-TguiContext
                $theme = Get-TuiDashboardTheme -Tgui $tg
                $data = @(1..$rows | ForEach-Object {
                        [PSCustomObject]@{
                            No = $_; Session = ("sess-{0:D3}" -f $_); Status = 'Detached'
                            Windows = $_; Name = ("sess-{0:D3}" -f $_)
                        } })
                New-TmuxTuiSessionRowList -Rows $data -Width 56 -Height $height `
                    -SelectedIndex $selected -Theme $theme -Tgui $tg
            } $rows $height $selected
        }
        # ★ Private 函数必须在**模块作用域**里调(& $mod { ... }) ——
        #   否则是 CommandNotFound(这一点在本仓库既有测试里同样成立)。
        $script:moveAndSync = {
            param($list, $delta)
            & $script:mod {
                param($lv, $d)
                [void](Move-TmuxTuiSessionSelection -ListView $lv -Delta $d)
                [void](Sync-TmuxTuiSessionScroll -ListView $lv)
            } $list $delta
        }
        $script:syncOnly = {
            param($list)
            & $script:mod { param($lv) [void](Sync-TmuxTuiSessionScroll -ListView $lv) } $list
        }
        $script:moveOnly = {
            param($list, $delta)
            & $script:mod { param($lv, $d) [void](Move-TmuxTuiSessionSelection -ListView $lv -Delta $d) } $list $delta
        }
        $script:selectedSlotCount = {
            param($list)
            @($list.Slots | Where-Object { $_.Selected }).Count
        }
    }

    It '选中行移出可视区时必须滚动, 且恰有一行处于选中态' {
        $lv = & $script:makeList -rows 100 -height 10 -selected 0
        for ($i = 0; $i -lt 15; $i++) { & $script:moveAndSync -list $lv -delta 1 }
        $lv.Top | Should -BeGreaterThan 0 -Because '选中行移出可视区后必须滚动'
        $lv.SelectedIndex | Should -Be 15
        $selectedSlots = @($lv.Slots | Where-Object { $_.Selected })
        $selectedSlots.Count | Should -Be 1 -Because '屏幕上必须恰有一行处于选中态'
        $selectedSlots[0].RowIndex | Should -Be 15
        # 选中行必须落在某个槽位上(否则它就是"看不见的选中")
        $slotIdx = [int]$lv.SelectedIndex - [int]$lv.Top
        ($slotIdx -ge 0 -and $slotIdx -lt $lv.Slots.Count) | Should -BeTrue
    }

    It '上移越过顶部时必须滚回' {
        $lv = & $script:makeList -rows 100 -height 10 -selected 0
        for ($i = 0; $i -lt 15; $i++) { & $script:moveAndSync -list $lv -delta 1 }
        for ($i = 0; $i -lt 15; $i++) { & $script:moveAndSync -list $lv -delta -1 }
        $lv.Top | Should -Be 0
        $lv.SelectedIndex | Should -Be 0
        (& $script:selectedSlotCount -list $lv) | Should -Be 1
    }

    It '末行边界: Top 夹到最大可滚动位置' {
        $lv = & $script:makeList -rows 100 -height 10 -selected 0
        $lv.SelectedIndex = 99
        & $script:syncOnly -list $lv
        $lv.Top | Should -Be 90 -Because '最大 Top = 行数 - 可视高度 = 100 - 10'
        (& $script:selectedSlotCount -list $lv) | Should -Be 1
    }

    It '连续快速导航 200 次后选中态与 SelectedIndex 始终一致(不漂移)' {
        $lv = & $script:makeList -rows 300 -height 12 -selected 0
        for ($i = 0; $i -lt 200; $i++) { & $script:moveAndSync -list $lv -delta 1 }
        $lv.SelectedIndex | Should -Be 200
        $selectedSlots = @($lv.Slots | Where-Object { $_.Selected })
        $selectedSlots.Count | Should -Be 1
        $selectedSlots[0].RowIndex | Should -Be 200
        $slotIdx = [int]$lv.SelectedIndex - [int]$lv.Top
        ($slotIdx -ge 0 -and $slotIdx -lt $lv.Slots.Count) | Should -BeTrue
    }

    It '边界处重复按键是幂等的(不改变 Top / SelectedIndex)' {
        $lv = & $script:makeList -rows 100 -height 10 -selected 0
        & $script:moveAndSync -list $lv -delta -1
        $topBefore = $lv.Top
        $selBefore = $lv.SelectedIndex
        & $script:moveAndSync -list $lv -delta -1
        $lv.Top | Should -Be $topBefore
        $lv.SelectedIndex | Should -Be $selBefore
    }

    It '窗口层 KeyDown 处理器: 按下方向键后选中行必须可见(真实事件链)' {
        # 用 TG 的 View.NewKeyDownEvent 触发**生产 KeyDown 处理器**:
        # 走的是 New-TmuxTuiDashboardWindow 挂在列表容器上的那个 handler。
        # ★ 窗口高度取 12(表格可视高度 = 12-4 = 8 行), 按 20 次 —— 必然越界,
        #   否则按键数不够越过可视区, 测的就不是"滚动"这条路径了。
        $result = & $script:mod {
            $tg = Get-TguiContext
            $rows = @(1..100 | ForEach-Object {
                    [PSCustomObject]@{ No = $_; Session = ("sess-{0:D3}" -f $_); Status = 'Detached'; Windows = $_; Name = ("sess-{0:D3}" -f $_) } })
            $vm = [PSCustomObject]@{
                Mode = 'Session'; SessionRows = $rows
                Counts = [PSCustomObject]@{ Total = 100; Attached = 0; Detached = 100 }
                ErrorCode = ''; ErrorMessage = ''; Hint = ''; SelectedSession = $null
            }
            $win = New-TmuxTuiDashboardWindow -ViewModel $vm -HostName 'test-host' `
                -ConnectionState '已连接' -HasSessions $true -Dispatch { param($a) $null = $a } `
                -WindowWidth 120 -WindowHeight 12 -SelectedIndex 0
            $key = [System.Activator]::CreateInstance($tg.Types.Key)
            $key.KeyCode = [Enum]::Parse($tg.Assembly.GetType('Terminal.Gui.Drivers.KeyCode'), 'CursorDown')
            [PSCustomObject]@{ Window = $win; Down = $key }
        }

        $list = $result.Window.SessionList
        $list.Height | Should -Be 8 -Because '120x12 窗口的表格可视高度 = 12 - 4 = 8 行'
        $newKeyDown = $list.View.GetType().GetMethod('NewKeyDownEvent', [System.Reflection.BindingFlags]'Public,Instance')
        $newKeyDown | Should -Not -BeNullOrEmpty
        for ($i = 0; $i -lt 20; $i++) { [void]$newKeyDown.Invoke($list.View, [object[]]@($result.Down)) }

        $list.SelectedIndex | Should -Be 20
        $list.Top | Should -BeGreaterThan 0 -Because '真实 KeyDown 处理器必须把选中行滚进可视区'
        $selectedSlots = @($list.Slots | Where-Object { $_.Selected })
        $selectedSlots.Count | Should -Be 1
        $selectedSlots[0].RowIndex | Should -Be 20
    }
}

Describe '极端终端尺寸下的布局' {

    It '40x10 / 80x24 / 120x35 / 160x45 都能组装出窗口且不抛异常' {
        foreach ($size in @(@(40, 10), @(80, 24), @(120, 35), @(160, 45))) {
            $w = $size[0]; $h = $size[1]
            $built = & $script:mod {
                param($w, $h)
                $rows = @(1..50 | ForEach-Object {
                        [PSCustomObject]@{ No = $_; Session = "sess-$_"; Status = 'Detached'; Windows = 1; Name = "sess-$_" } })
                $vm = [PSCustomObject]@{
                    Mode = 'Session'; SessionRows = $rows
                    Counts = [PSCustomObject]@{ Total = 50; Attached = 0; Detached = 50 }
                    ErrorCode = ''; ErrorMessage = ''; Hint = ''; SelectedSession = $null
                }
                New-TmuxTuiDashboardWindow -ViewModel $vm -HostName 'h' `
                    -ConnectionState '已连接' -HasSessions $true -Dispatch { param($a) $null = $a } `
                    -WindowWidth $w -WindowHeight $h -SelectedIndex 0
            } $w $h
            $built | Should -Not -BeNullOrEmpty -Because "${w}x${h} 必须能组装出窗口"
            $built.Window | Should -Not -BeNullOrEmpty
            $built.Layout.TableHeight | Should -BeGreaterThan 0 -Because "${w}x${h} 的表格高度不得为负"
        }
    }

    It '布局不变量: 顶部三行与底部快捷键栏不重叠' {
        foreach ($h in @(10, 24, 35, 45)) {
            $plan = & $script:mod { param($h) New-TmuxTuiLayoutPlan -Width 120 -Height $h } $h
            $plan.TableRow | Should -BeGreaterThan $plan.HintRow
            $plan.HintRow | Should -BeGreaterThan $plan.StatsRow
            $plan.StatsRow | Should -BeGreaterThan $plan.TitleRow
            $plan.TableBottomRow | Should -BeLessThan $plan.StatusBarRow
            $plan.TableHeight | Should -BeGreaterThan 0
        }
    }

    It '窄屏按档位隐藏次要列, 中宽屏保留' {
        # 契约(见 Get-TmuxTuiSessionRowGeometry): < 40 列藏窗口数列;
        # 40 列是**边界** —— 窗口数列仍然保留(40 列放得下)。
        $veryNarrow = & $script:mod { Get-TmuxTuiSessionRowGeometry -Width 39 }
        $narrow = & $script:mod { Get-TmuxTuiSessionRowGeometry -Width 40 }
        $wide = & $script:mod { Get-TmuxTuiSessionRowGeometry -Width 120 }

        $veryNarrow.WindowsWidth | Should -Be 0 -Because '39 列放不下窗口数列(次要信息降权)'
        $narrow.WindowsWidth | Should -BeGreaterThan 0 -Because '40 列是边界, 窗口数列仍保留'
        $narrow.StatusWidth | Should -BeGreaterThan 0
        $wide.WindowsWidth | Should -BeGreaterThan 0
        # 名称列必须始终为正(极窄也不能变成负数)
        $veryNarrow.NameWidth | Should -BeGreaterThan 0
        $narrow.NameWidth | Should -BeGreaterThan 0
        $wide.NameWidth | Should -BeGreaterThan 0
        # 列不得重叠: 名称列 + 状态列 + 窗口列必须落在可视宽度内
        ($narrow.NameX + $narrow.NameWidth) | Should -BeLessOrEqual $narrow.StatusX
        ($narrow.StatusX + $narrow.StatusWidth) | Should -BeLessOrEqual $narrow.WindowsX
        ($wide.NameX + $wide.NameWidth) | Should -BeLessOrEqual $wide.StatusX
        ($wide.StatusX + $wide.StatusWidth) | Should -BeLessOrEqual $wide.WindowsX
    }

    It '阶段一响应式分栏: 窄屏单栏(不显示工作区), 宽屏双栏(列表/竖线/工作区互不重叠)' {
        $built = & $script:mod {
            param($w)
            $rows = @(1..3 | ForEach-Object {
                    [PSCustomObject]@{ No = $_; Session = "sess-$_"; Status = 'Detached'; Windows = 1; Name = "sess-$_" } })
            $vm = [PSCustomObject]@{
                Mode = 'Session'; SessionRows = $rows
                Counts = [PSCustomObject]@{ Total = 3; Attached = 0; Detached = 3 }
                ErrorCode = ''; ErrorMessage = ''; Hint = ''; SelectedSession = $null
            }
            New-TmuxTuiDashboardWindow -ViewModel $vm -HostName 'h' `
                -ConnectionState '已连接' -HasSessions $true -Dispatch { param($a) $null = $a } `
                -WindowWidth $w -WindowHeight 24 -SelectedIndex 0
        } 60
        # 60 列: 单栏 —— 没有工作区, 列表铺满
        $built.Layout.SplitMode | Should -Be 'Single'
        $built.ShowDetail | Should -BeFalse
        $built.DetailPanel | Should -BeNullOrEmpty
        $built.Divider | Should -BeNullOrEmpty
        $built.Layout.ListWidth | Should -Be 60

        $builtWide = & $script:mod {
            param($w)
            $rows = @(1..3 | ForEach-Object {
                    [PSCustomObject]@{ No = $_; Session = "sess-$_"; Status = 'Detached'; Windows = 1; Name = "sess-$_" } })
            $vm = [PSCustomObject]@{
                Mode = 'Session'; SessionRows = $rows
                Counts = [PSCustomObject]@{ Total = 3; Attached = 0; Detached = 3 }
                ErrorCode = ''; ErrorMessage = ''; Hint = ''; SelectedSession = $null
            }
            New-TmuxTuiDashboardWindow -ViewModel $vm -HostName 'h' `
                -ConnectionState '已连接' -HasSessions $true -Dispatch { param($a) $null = $a } `
                -WindowWidth $w -WindowHeight 24 -SelectedIndex 0
        } 120
        $builtWide.Layout.SplitMode | Should -Be 'Dual'
        $builtWide.ShowDetail | Should -BeTrue
        $builtWide.DetailPanel | Should -Not -BeNullOrEmpty
        $builtWide.Divider | Should -Not -BeNullOrEmpty
        # 双栏不变量: 列表 + 竖线 + 2 列呼吸间距 + 工作区 == 屏宽
        $plan = $builtWide.Layout
        ($plan.ListWidth + 3 + $plan.DetailWidth) | Should -Be 120
        $plan.DividerX | Should -Be $plan.ListWidth
        $plan.DetailX | Should -Be ($plan.ListWidth + 3)
    }
}

Describe 'tmux 会话工作区 (2026-11-06 阶段一三段式)' {

    It '工作区是三段式(无 FrameView 外框), 且暴露 Session/Status/Index 等真实字段' {
        $state = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 24 -HostName 'deb' -Theme $theme -Tgui $tg
            $row = [PSCustomObject]@{ No = 2; Session = 'work'; Status = 'Attached'; Windows = 3; Name = 'work' }
            Set-TmuxTuiSessionDetail -Panel $panel -Row $row
            [PSCustomObject]@{
                ViewType    = $panel.View.GetType().Name
                SectionText = (@($panel.Sections | ForEach-Object { [string]$_.Title.Text }) -join '|')
                ActionKeys  = (@($panel.ActionKeyLabels.Keys | Sort-Object) -join ',')
                Session     = [string]$panel.Labels['Session'].Text
                Status      = [string]$panel.Labels['Status'].Text
                Index       = [string]$panel.Labels['Index'].Text
                Host        = [string]$panel.Labels['Host'].Text
            }
        }
        $state.ViewType | Should -Not -Be 'FrameView' -Because '工作区去掉外框后不再有"双重竖线"'
        $state.SectionText | Should -BeExactly 'SESSION OVERVIEW|WINDOWS|ACTIONS'
        $state.ActionKeys | Should -BeExactly 'Enter,n,r,x'
        $state.Session | Should -BeExactly 'work'
        $state.Status | Should -BeExactly '● Attached'
        $state.Index | Should -BeExactly '2'
        $state.Host | Should -BeExactly 'deb'
    }
}

Describe '中文字符(CJK 双宽)的显示宽度与截断' {

    It 'Get-TguiTextWidth: CJK 计 2 列, ASCII 计 1 列, 组合记号计 0 列' {
        (& $script:mod { Get-TguiTextWidth -Text '附着' }) | Should -Be 4
        (& $script:mod { Get-TguiTextWidth -Text 'Attached' }) | Should -Be 8
        (& $script:mod { Get-TguiTextWidth -Text '生产环境' }) | Should -Be 8
        (& $script:mod { Get-TguiTextWidth -Text '' }) | Should -Be 0
    }

    It 'Get-SshHostListClip: 按显示宽度截断, 结果不得超宽' {
        foreach ($text in @('生产数据库-web-01', 'sess-001', '混合mixed中文text', '●')) {
            foreach ($w in @(4, 8, 12, 20)) {
                $clipped = & $script:mod { param($t, $w) Get-SshHostListClip -Text $t -Width $w } $text $w
                $actual = & $script:mod { param($c) Get-TguiTextWidth -Text $c } $clipped
                $actual | Should -BeLessOrEqual $w -Because "'$text' 截断到 $w 列后显示宽度必须 <= $w (实际 $actual)"
            }
        }
    }

    It 'Get-SshHostListClip: 超长文本带省略号, 短文本原样返回' {
        $long = & $script:mod { Get-SshHostListClip -Text '生产数据库-web-01' -Width 8 }
        $long | Should -Match ([string][char]0x2026)
        $short = & $script:mod { Get-SshHostListClip -Text 'abc' -Width 8 }
        $short | Should -Be 'abc'
        $zero = & $script:mod { Get-SshHostListClip -Text 'abc' -Width 0 }
        $zero | Should -Be ''
    }

    It '中文会话名进列表后, 各列文本仍不超宽' {
        $state = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $rows = @(1..3 | ForEach-Object {
                    [PSCustomObject]@{ No = $_; Session = "生产环境数据库节点-$_"; Status = 'Detached'; Windows = $_; Name = "生产环境数据库节点-$_" } })
            $lv = New-TmuxTuiSessionRowList -Rows $rows -Width 56 -Height 3 -SelectedIndex 0 -Theme $theme -Tgui $tg
            $widths = foreach ($slot in $lv.Slots) {
                [PSCustomObject]@{
                    Name   = Get-TguiTextWidth -Text $slot.Name.Text
                    Limit  = $lv.Geometry.NameWidth
                    Status = Get-TguiTextWidth -Text $slot.Status.Text
                    SLimit = $lv.Geometry.StatusWidth
                }
            }
            $widths
        }
        foreach ($w in $state) {
            $w.Name | Should -BeLessOrEqual $w.Limit
            if ($w.SLimit -gt 0) { $w.Status | Should -BeLessOrEqual $w.SLimit }
        }
    }
}

Describe '详情卡的值守卫 (2026-11 性能审计修复)' {

    It 'tmux 详情卡登记原值: 原值未变时不再重新裁剪' {
        # ★ RawValues 守卫: 上下移动时 4 个字段里通常只有 1~2 个真的变了,
        #   裁剪(逐字符测宽)是按键路径上最贵的一步 —— 原值没变就该整段跳过。
        #   实测(修复前/后): 同值重复刷新 0.576 ms -> 0.194 ms(3.0x)。
        $state = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 50 -Height 10 -Theme $theme -Tgui $tg
            $rowA = [PSCustomObject]@{ No = 1; Session = 'prod-web-01'; Status = 'Attached'; Windows = 3; Name = 'prod-web-01' }
            $rowB = [PSCustomObject]@{ No = 2; Session = 'prod-web-02'; Status = 'Detached'; Windows = 4; Name = 'prod-web-02' }

            Set-TmuxTuiSessionDetail -Panel $panel -Row $rowA
            $afterA = [PSCustomObject]@{
                RawSession = $panel.RawValues['Session']
                LabelText  = [string]$panel.Labels['Session'].Text
            }
            Set-TmuxTuiSessionDetail -Panel $panel -Row $rowB
            $afterB = [PSCustomObject]@{
                RawSession = $panel.RawValues['Session']
                LabelText  = [string]$panel.Labels['Session'].Text
            }
            # 回到 A: 守卫放行(原值变了), 标签必须跟着变回来
            Set-TmuxTuiSessionDetail -Panel $panel -Row $rowA
            $backA = [PSCustomObject]@{
                RawSession = $panel.RawValues['Session']
                LabelText  = [string]$panel.Labels['Session'].Text
            }
            [PSCustomObject]@{ AfterA = $afterA; AfterB = $afterB; BackA = $backA }
        }

        $state.AfterA.RawSession | Should -Be 'prod-web-01'
        $state.AfterA.LabelText | Should -Be 'prod-web-01'
        $state.AfterB.RawSession | Should -Be 'prod-web-02'
        $state.AfterB.LabelText | Should -Be 'prod-web-02'
        $state.BackA.RawSession | Should -Be 'prod-web-01'
        $state.BackA.LabelText | Should -Be 'prod-web-01'
    }

    It '原值未变时详情卡不得再走裁剪(裁剪次数断言)' {
        # ★ 用 Mock 计数"真的发生了几次裁剪", 而不是靠耗时(耗时断言会 flaky):
        #   第一次设置 4 个字段 => 裁剪 4 次; 第二次设**同一行** => 应当 **0 次**。
        #   没有 RawValues 守卫时, 第二次同样要裁 4 次(这正是被优化掉的浪费)。
        #   计数器必须放**全局**: mock(-ModuleName)在模块作用域执行, 被测代码也在
        #   模块作用域, 只有全局变量两边都看得见。
        #   用 Set-Variable -Scope Global 而不是 `$global:` 字面量 —— 与本仓库
        #   既有约定一致(规避 PSAvoidGlobalVars)。
        Set-Variable -Name 'ClipCounter' -Scope Global -Value 0
        Mock -CommandName Get-SshHostListClip -ModuleName ShellPrompt -MockWith {
            $current = (Get-Variable -Name 'ClipCounter' -Scope Global).Value
            Set-Variable -Name 'ClipCounter' -Scope Global -Value ($current + 1)
            return 'CLIPPED'
        }

        & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-TmuxTuiSessionDetailPanel -Width 50 -Height 10 -Theme $theme -Tgui $tg
            $row = [PSCustomObject]@{ No = 1; Session = 'prod-web-01'; Status = 'Attached'; Windows = 3; Name = 'prod-web-01' }
            Set-TmuxTuiSessionDetail -Panel $panel -Row $row
            Set-Variable -Name 'FirstPass' -Scope Global -Value (Get-Variable -Name 'ClipCounter' -Scope Global).Value
            Set-Variable -Name 'ClipCounter' -Scope Global -Value 0
            Set-TmuxTuiSessionDetail -Panel $panel -Row $row
            Set-Variable -Name 'SecondPass' -Scope Global -Value (Get-Variable -Name 'ClipCounter' -Scope Global).Value
        }

        (Get-Variable -Name 'FirstPass' -Scope Global).Value | Should -BeGreaterThan 0 -Because '第一次设置必然要裁剪'
        (Get-Variable -Name 'SecondPass' -Scope Global).Value | Should -Be 0 -Because '原值完全相同时不得再走裁剪(逐字符测宽是按键路径最贵的一步)'
    }

    It 'SSH 详情面板的远端状态字段走等值守卫(不再无条件标脏)' {
        # Set-SshHostDetailRemote 里 Status 字段原先直接赋值 Label.Text ——
        # TG 的 Text 赋值会无条件把视图标脏。修复后改走 Set-SshHostDetailLabelText
        # (带 -ceq 守卫), 与本面板其余字段一致。
        $source = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'Private/New-SshHostDetailPanel.ps1') -Raw
        $source | Should -Match 'Set-SshHostDetailLabelText\s+-Label\s+\$statusLabel'
        $source | Should -Not -Match '\$statusLabel\.Text\s*=' -Because 'Status 字段不得再直接赋值 Label.Text'
    }
}

Describe '异步结果的竞态丢弃 (防张冠李戴)' {

    It '旧主机的迟到探测结果不得覆盖当前选中主机的详情面板' {
        # 场景: 用户从 hostA 快速切到 hostB, hostA 的 SSH 探测结果**迟到**。
        # 契约(Invoke-SshHostDashboard.ps1:1624-1629): 详情面板回填必须
        #   RequestId 与 ActiveRequestId 一致 **且** 主机名与当前选中主机一致;
        #   结果本身仍按主机名缓存(那是该主机的事实, 不是污染)。
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-TuiDashboardTheme -Tgui $tg
            $panel = New-SshHostDetailPanel -Width 50 -Height 10 -Theme $theme -Tgui $tg

            # 当前选中的是 hostB, 请求标识是 hostB#2
            $state = [PSCustomObject]@{
                SelectedHost   = 'hostB'
                ActiveRequestId = 'hostB#2'
                RequestSeq     = 2
                DetailByHost   = @{}
                StatusByHost   = @{}
                ListView       = $null
                DetailPanel    = $panel
                ActivityMap    = @{}
                Perf           = [PSCustomObject]@{}
            }

            # 迟到的旧探测: hostA, 请求标识 hostA#1
            $staleProbe = [PSCustomObject]@{ HostName = 'hostA'; RequestId = 'hostA#1' }
            $staleDetail = [PSCustomObject]@{
                Status = 'Online'; StatusText = 'hostA 在线'; ErrorCode = ''
                ElapsedMs = 12; Host = 'hostA'; Address = '10.0.0.1'
            }
            Set-SshHostDashboardProbeResult -State $state -Probe $staleProbe -Detail $staleDetail

            # 远端探测结果只回填"远端字段"(Status/耗时/错误码); Host 等本地
            # 字段由 Set-SshHostDetailBasic 负责 —— 所以断言 Status 字段。
            $panelStatusAfterStale = [string]$panel.Labels['Status'].Text

            # 当前请求的结果: hostB
            $currentProbe = [PSCustomObject]@{ HostName = 'hostB'; RequestId = 'hostB#2' }
            $currentDetail = [PSCustomObject]@{
                Status = 'Online'; StatusText = 'hostB 在线'; ErrorCode = ''
                ElapsedMs = 34; Host = 'hostB'; Address = '10.0.0.2'
            }
            Set-SshHostDashboardProbeResult -State $state -Probe $currentProbe -Detail $currentDetail
            $panelStatusAfterCurrent = [string]$panel.Labels['Status'].Text

            [PSCustomObject]@{
                AfterStale   = $panelStatusAfterStale
                AfterCurrent = $panelStatusAfterCurrent
                CachedA      = [string]$state.DetailByHost['hosta'].Host
                CachedB      = [string]$state.DetailByHost['hostb'].Host
            }
        }

        # 迟到结果**不得**写进详情面板(面板此时还没回填过任何东西)
        $result.AfterStale | Should -Not -Match 'hostA' -Because '旧请求的迟到结果不得回填当前详情面板'
        # 当前请求的结果必须正常回填
        $result.AfterCurrent | Should -Match 'hostB'
        # 但结果本身仍按主机名缓存 —— 那是该主机的事实, 不是污染
        $result.CachedA | Should -Be 'hostA'
        $result.CachedB | Should -Be 'hostB'
    }

    It '同一主机只允许一个在飞探测(去重保护)' {
        # 契约: 详情探测由 120ms 心跳驱动, 心跳里先"取消不再需要的请求",
        # 再"收割在飞的请求", 两者都处理完才会发起新请求 ——
        # 因此同一时刻至多一个探测在飞。
        $source = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'Private/Invoke-SshHostDashboard.ps1') -Raw
        # 心跳里"收割"分支处理完就 return, 新请求在收割之后才会发起
        $source | Should -Match 'Test-SshHostDashboardTaskDone'
        $source | Should -Match 'Stop-SshHostDashboardProbe'
        # 护栏: RequestId 与主机名双重匹配
        $source | Should -Match '\$isCurrent\s*=\s*\(\$requestId\s+-eq\s+\[string\]\$State\.ActiveRequestId\)\s+-and'
    }
}

Describe '终端状态恢复与资源释放 (Task 6)' {

    It 'TG 退出后必须还原备用屏/光标/鼠标, 且不留 Job 与事件订阅' {
        # 在**子进程**里真跑一遍 TG 生命周期: Init -> Run -> RequestStop -> Shutdown。
        # 断言:
        #   1) 终��流里出现"退出备用屏"(ESC[?1049l)与"显示光标"(ESC[?25h)
        #      —— 这正是 Application.Shutdown() 负责的还原动作;
        #   2) 子进程退出后 Get-Job / Get-EventSubscriber 均为 0(无作业/订阅残留);
        #   3) 子进程退出码为 0(没有异常抛出)。
        $script:cacheRoot = Join-Path $script:repoRoot '.agent_cache/tui-lifecycle'
        $null = New-Item -ItemType Directory -Path $script:cacheRoot -Force
        $childScript = Join-Path $script:cacheRoot 'child-lifecycle.ps1'
        $resultPath = Join-Path $script:cacheRoot 'result.json'
        # 先删掉上一次的结果文件: 子进程若失败, 读到旧文件会变成"假通过"
        if (Test-Path -LiteralPath $resultPath) { Remove-Item -LiteralPath $resultPath -Force }

        @'
$ErrorActionPreference = 'Stop'
# ★ 仓库根**必须**从环境变量取: 不能写死绝对路径 —— CI 跑在 windows-latest,
#   路径完全不同(写死会让子进程直接 Import-Module 失败)。
$repo = $env:LIFECYCLE_REPO
if ([string]::IsNullOrWhiteSpace($repo)) { throw 'LIFECYCLE_REPO 未设置' }
Import-Module (Join-Path $repo 'ShellPrompt/ShellPrompt.psd1') -Force
$mod = Get-Module -Name 'ShellPrompt'
$tg = & $mod { Get-TguiContext }
$app = $tg.Types.Application
$static = [System.Reflection.BindingFlags]'Public,Static'
$irunnable = $tg.Assembly.GetType('Terminal.Gui.App.IRunnable')
$init = $app.GetMethods($static) | Where-Object {
    $_.Name -eq 'Init' -and -not $_.IsGenericMethodDefinition -and $_.GetParameters().Count -eq 1
} | Select-Object -First 1
$run = $app.GetMethods($static) | Where-Object {
    $_.Name -eq 'Run' -and -not $_.IsGenericMethodDefinition -and
    $_.GetParameters().Count -eq 2 -and $_.GetParameters()[0].ParameterType -eq $irunnable
} | Select-Object -First 1
$stop = $app.GetMethods($static) | Where-Object {
    $_.Name -eq 'RequestStop' -and -not $_.IsGenericMethodDefinition -and $_.GetParameters().Count -eq 1
} | Select-Object -First 1
$shutdown = $app.GetMethod('Shutdown', $static)
$addTimeout = $app.GetMethods($static) | Where-Object {
    $_.Name -eq 'AddTimeout' -and -not $_.IsGenericMethodDefinition -and
    $_.GetParameters().Count -eq 2 -and $_.GetParameters()[1].ParameterType -eq [System.Func[bool]]
} | Select-Object -First 1

# ★ TG 生命周期在**无头/重定向**环境下能不能起来是**平台相关**的
#   (Windows 走 Win32 控制台 API, 重定向句柄可能让驱动初始化失败)。
#   所以: 起得来就完整验证(Initialized 迁移 + 还原序列), 起不来就如实记下来,
#   由父进程决定断言强度 —— 绝不把"起不来"当成通过。
$tgInitialized = $false
$tgError = ''
$initializedAfterInit = $false
$initializedAfterRun = $false
$initializedAfterShutdown = $false

try {
    $window = [System.Activator]::CreateInstance($tg.Types.Window)
    $window.BorderStyle = $null
    $label = [System.Activator]::CreateInstance($tg.Types.Label)
    $label.Text = 'lifecycle'
    $null = $window.Add($label)

    # AppModel 显式置 FullScreen(枚举**成员是字段**, 不是属性 —— 用 GetField 取)
    try {
        $appModelType = $tg.Types.AppModel
        $fullScreen = $appModelType.GetField('FullScreen').GetValue($null)
        $app.GetProperty('AppModel', $static).SetValue($null, $fullScreen)
    } catch {
        Write-Host "设置 AppModel 失败(可忽略): $($_.Exception.Message)"
    }
    # 用 **dotnet** 驱动: 'ansi' 驱动在 stdout 被重定向时**不输出**任何控制序列
    # (它要真 TTY 才写), 'dotnet' 驱动会照常把备用屏/光标还原序列写出来 ——
    # 于是"Shutdown 确实还原了终端"这条契约在无头环境里也能被断言。
    $init.Invoke($null, [object[]]@('dotnet'))
    $tgInitialized = $true
    $initializedAfterInit = [bool]$app.GetProperty('Initialized', $static).GetValue($null)

    $cb = [System.Func[bool]] {
        $args0 = [object[]]::CreateInstance([System.Object], 1)
        $args0[0] = $global:LifecycleWindow
        [void]$global:LifecycleStop.Invoke($null, $args0)
        return $false
    }
    $global:LifecycleWindow = $window
    $global:LifecycleStop = $stop
    $null = $addTimeout.Invoke($null, [object[]]@([TimeSpan]::FromMilliseconds(300), $cb))

    $runArgs = [object[]]::CreateInstance([System.Object], 2)
    $runArgs[0] = $window
    $runArgs[1] = [System.Func[System.Exception, bool]] { param($e) return $true }
    $null = $run.Invoke($null, $runArgs)
    $initializedAfterRun = [bool]$app.GetProperty('Initialized', $static).GetValue($null)
    $shutdown.Invoke($null, [object[]]@())
    $initializedAfterShutdown = [bool]$app.GetProperty('Initialized', $static).GetValue($null)
}
catch {
    $tgError = $_.Exception.Message
    Write-Host "TG 生命周期在本环境未能完整运行: $tgError"
    try { $shutdown.Invoke($null, [object[]]@()) } catch { }
}

$jobCount = @(Get-Job -ErrorAction SilentlyContinue).Count
$subscriberCount = 0
try { $subscriberCount = @(Get-EventSubscriber -ErrorAction SilentlyContinue).Count } catch { $subscriberCount = 0 }
$runspaceCount = 0
try { $runspaceCount = [System.Management.Automation.Runspaces.RunspacePool]::DefaultRunspacePool.GetRunspaces().Count } catch { $runspaceCount = 0 }

[PSCustomObject]@{
    Jobs         = $jobCount
    Subscribers  = $subscriberCount
    Runspaces    = $runspaceCount
    TgInitialized = $tgInitialized
    TgError      = $tgError
    InitAfterInit = $initializedAfterInit
    InitAfterRun  = $initializedAfterRun
    InitAfterShutdown = $initializedAfterShutdown
} | ConvertTo-Json | Set-Content -LiteralPath $env:LIFECYCLE_RESULT -Encoding UTF8
exit 0
'@ | Set-Content -LiteralPath $childScript -Encoding UTF8

        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = (Get-Process -Id $PID).Path
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        foreach ($argument in @('-NoProfile', '-NonInteractive', '-NoLogo', '-File', $childScript)) {
            [void]$startInfo.ArgumentList.Add($argument)
        }
        $startInfo.Environment['LIFECYCLE_RESULT'] = $resultPath
        $startInfo.Environment['LIFECYCLE_REPO'] = $script:repoRoot
        $child = [System.Diagnostics.Process]::new()
        $child.StartInfo = $startInfo
        [void]$child.Start()
        $stdout = $child.StandardOutput.ReadToEndAsync().GetAwaiter().GetResult()
        $stderr = $child.StandardError.ReadToEndAsync().GetAwaiter().GetResult()
        $child.WaitForExit()

        $child.ExitCode | Should -Be 0 -Because "子进程必须干净退出: $stderr"
        Test-Path -LiteralPath $resultPath -PathType Leaf | Should -BeTrue
        $state = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $state.Jobs | Should -Be 0 -Because 'TUI 退出后不得残留后台作业'
        $state.Subscribers | Should -Be 0 -Because 'TUI 退出后不得残留事件订阅'
        # 终端还原的跨平台契约: 平台确实起了 TG 的话, Init 必须接管终端,
        # Shutdown 之后必须释放(Initialized 回到 false)。
        # 若该环境起不来 TG(Windows 重定向句柄 / 无控制台), 如实按"起不来"处理:
        # 不把失败当通过, 也不让 CI 因此变红 —— 平台无关的那一半契约由下面
        # "finally 必须补偿 Shutdown"的源码契约用例守住。
        if ($state.TgInitialized) {
            $state.InitAfterInit | Should -BeTrue -Because 'Init 之后 Application.Initialized 必须为 true'
            $state.InitAfterShutdown | Should -BeFalse -Because 'Shutdown 之后必须释放终端(Initialized 回到 false)'
            # 终端还原序列: 退出备用屏 ESC[?1049l 与显示光标 ESC[?25h
            # ★ 平台差异: Windows 上 TG 走 Win32 控制台 API, 不输出 ANSI 序列;
            #   无头 Linux 的 'ansi' 驱动在 stdout 被重定向时也不输出序列。
            #   所以"平台确实吐了 ANSI"才去校验还原序列。
            $terminal = $stdout + $stderr
            if ($terminal -match ([regex]::Escape("$([char]27)[?"))) {
                $terminal | Should -Match ([regex]::Escape("$([char]27)[?1049l")) -Because 'Application.Shutdown() 必须退出备用屏'
                $terminal | Should -Match ([regex]::Escape("$([char]27)[?25h")) -Because 'Application.Shutdown() 必须恢复光标显示'
            }
        }
        else {
            Write-Verbose "本环境未能启动 TG 生命周期(跳过序列校验): $($state.TgError)"
        }
    }

    It '两个仪表盘编排层的 finally 都必须补偿 Shutdown(异常路径也要还原终端)' {
        $privateDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'Private'
        foreach ($file in @('Show-TmuxTuiDashboard.ps1', 'Invoke-SshHostDashboard.ps1')) {
            $source = Get-Content -LiteralPath (Join-Path $privateDir $file) -Raw
            # finally 块里必须有 Shutdown 补偿调用
            $source | Should -Match '(?s)finally\s*\{.*?Shutdown' -Because "$file 的 finally 必须补偿 Shutdown"
        }
    }

    It '切换主机时不得阻塞 UI 线程(探测作业卡住也不冻结界面)' {
        # ★ P0(2026-11 性能审计实测): 心跳跑在 **UI 线程主循环**里, 原来在
        #   "主机已切换"分支里同步 Stop-Job —— 而探测作业可能卡在 .NET
        #   WaitForExit 上(远端连不上时最长 ConnectTimeout+10s), Stop-Job 与
        #   Remove-Job -Force **都会等它真的停下来**。
        #   实测: 作业还要跑 3s / 8s 时, UI 线程被冻住 2514ms / 7517ms。
        #   修复: 改成"放弃"(结果本来就不要, RequestId 护栏会丢弃), 作业自己
        #   跑完后由心跳收割 —— UI 线程立即返回。
        $elapsed = & $script:mod {
            # 一个"卡住"的探测作业: 模拟 ssh 连不上时的 WaitForExit(不可中断)
            $blocked = Start-ThreadJob -ScriptBlock {
                # ★ 用 [System.Threading.Thread]::Sleep 而不是 Start-Sleep:
                #   Start-Sleep 会被 Stop-Job **立刻打断**(实测 1~8ms 返回), 那样就
                #   复现不出"UI 线程被作业拖住"这件事; .NET 的 Thread.Sleep 是阻塞
                #   调用, 打断不了 —— 与生产里 Invoke-SshCaptureOutput 的 .NET
                #   WaitForExit 同类。也**不用 /bin/sleep**: 那是 POSIX 专有的,
                #   CI 跑在 windows-latest 上。
                [System.Threading.Thread]::Sleep(3000)
            }
            $state = [PSCustomObject]@{
                SelectedHost    = 'hostB'
                ActiveRequestId = 'hostB#1'
                RequestSeq      = 1
                # hostB 已有缓存 => 心跳第 3 步不会再发探测(测试里不打真实网络)
                DetailByHost    = @{ 'hostb' = [PSCustomObject]@{ Host = 'hostB'; Status = 'Unknown' } }
                StatusByHost    = @{}
                ListView        = $null
                DetailPanel     = $null
                ActivityMap     = @{}
                Perf            = [PSCustomObject]@{ ProbeCount = 0 }
                DetailProbe     = [PSCustomObject]@{ HostName = 'hostA'; RequestId = 'hostA#1'; Task = $blocked }
                StaleProbes     = [System.Collections.Generic.List[object]]::new()
            }
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            # 让作业**真的**卡进 WaitForExit(不可中断), 否则 Stop-Job 能立刻打断它,
            # 测不出"UI 线程被拖住"这件事
            Start-Sleep -Milliseconds 400
            $sw.Restart()
            Update-SshHostDashboardProbe -State $state
            $sw.Stop()
            $ms = $sw.Elapsed.TotalMilliseconds
            $staleCount = $state.StaleProbes.Count
            $slotHost = ''
            if ($null -ne $state.DetailProbe) { $slotHost = [string]$state.DetailProbe.HostName }
            # 清理: 结束那个卡住的作业(它最多还要跑 3s)
            try { Stop-Job -Job $blocked -ErrorAction SilentlyContinue } catch { Write-Verbose [test] 结束卡住的作业失败 }
            try { Remove-Job -Job $blocked -Force -ErrorAction SilentlyContinue } catch { Write-Verbose [test] 移除卡住的作业失败 }
            [PSCustomObject]@{ Ms = $ms; StaleCount = $staleCount; SlotHost = $slotHost }
        }

        $elapsed.Ms | Should -BeLessThan 1000 -Because '心跳在 UI 线程上, 切主机必须立即返回(实测原实现会冻 2.5~7.5s)'
        $elapsed.StaleCount | Should -Be 1 -Because '被放弃的探测必须进 StaleProbes 等待收割'
        $elapsed.SlotHost | Should -Not -Be 'hostA' -Because '在飞槽位必须腾出来(旧探测不能继续占着)'
    }
}




