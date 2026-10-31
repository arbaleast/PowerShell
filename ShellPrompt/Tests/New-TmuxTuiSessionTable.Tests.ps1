# New-TmuxTuiSessionTable.Tests.ps1 - TGUI 会话表格视图构建契约测试(阶段 A, Goal 六-1/2/8)
# 覆盖:
#   1. 纯列计划的三档宽度策略(160/120/100/72);
#   2. 会话表构建: 无头构造(不 Init) 数据源行数/列数与计划一致;
#   3. WINDOWS 列右对齐样式/SESSION 优先宽度/窄窗口隐藏 STATUS;
#   4. 空状态/错误状态: 表格行恒为 0(不伪造占位会话行)。
# 说明: 全部构造在 vendored Terminal.Gui 2.4.10 上实测(不 Run 事件循环)。

Describe 'TGUI 会话表格视图构建 (New-TmuxTuiSessionTable / New-TmuxTuiColumnPlan)' {

    BeforeAll {
        # Parser 快检: 防止新文件 parse 失败被模块 loader 静默警告吞掉
        foreach ($file in @('New-TmuxTuiColumnPlan.ps1', 'New-TmuxTuiSessionTable.ps1')) {
            $path = Join-Path (Split-Path -Path $PSScriptRoot -Parent) (Join-Path 'Private' $file)
            $tokens = $null; $parseErrors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
            $parseErrors.Count | Should -Be 0 -Because "$file 必须可解析(否则模块加载静默失败)"
        }

        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'

        # 共享会话状态: 2 会话(1 附 1 分离)
        $script:sampleState = & $script:mod {
            Get-TmuxSessionState -SessionData @{
                Available = $true
                Sessions  = @(
                    [PSCustomObject]@{ Name = 'work'; Status = 'detached'; Windows = 3 }
                    [PSCustomObject]@{ Name = 'ci';   Status = 'attached';  Windows = 1 }
                )
            }
        }
    }

    Context '列布局计划 (纯函数)' {

        It '100x30 档: 四列全渲染(STATUS 达最小可读宽度), SESSION 吃满余量(72)' {
            # 100 列是 Goal 三-5 的验证档之一; 96 列以下才隐藏 STATUS
            $plan = & $script:mod { param($w) New-TmuxTuiColumnPlan -WindowWidth $w } 100

            (($plan | Where-Object Name -eq 'STATUS').Visible) | Should -BeTrue
            (($plan | Where-Object Name -eq 'WINDOWS').Visible) | Should -BeTrue
            (($plan | Where-Object Name -eq 'WINDOWS').RightAlign) | Should -BeTrue
            # 2026-10-31 UI 升级: SESSION 吃满余量 = 100 - (4+10+9) - (4+1) = 72
            (($plan | Where-Object Name -eq 'SESSION').MaxWidth) | Should -Be 72
        }

        It '120x35 档: 四列全渲染, SESSION 吃满余量(92)' {
            $plan = & $script:mod { param($w) New-TmuxTuiColumnPlan -WindowWidth $w } 120

            (($plan | Where-Object Name -eq 'STATUS').Visible) | Should -BeTrue
            # 120 - (4+10+9) - (4+1) = 92
            (($plan | Where-Object Name -eq 'SESSION').MaxWidth) | Should -Be 92
        }

        It '160x45 档: SESSION 吃满余量但被 TG 的 100 列单元格上限封顶' {
            $plan = & $script:mod { param($w) New-TmuxTuiColumnPlan -WindowWidth $w } 160

            # 余量本该是 160 - (4+10+9) - (4+1) = 132, 但 TG 的 MaxCellWidth 默认 100
            # (且调大会让 TG 布局死循环), 故计划侧同步封顶 —— 计划与渲染一致。
            (($plan | Where-Object Name -eq 'SESSION').MaxWidth) | Should -Be 100
        }

        It '各档位列宽之和恰好等于终端宽(表格既不溢出也不留空洞)' {
            # 2026-10-31 UI 升级: 表格几何 = Σ列宽 + (可见列数 + 1)
            # (可见列数-1 个列间竖线 + 左右两条边框边 —— 40x10 真机实测 4+33+3=40)
            # ★ 例外: 终端宽于 128 列时, SESSION 列被 TG 的 MaxCellWidth(100) 封顶,
            #   表格保持 128 宽(右侧留白); 调大 MaxCellWidth 会让 TG 布局死循环。
            foreach ($width in @(40, 60, 72, 96, 100, 120)) {
                $plan = & $script:mod { param($w) New-TmuxTuiColumnPlan -WindowWidth $w } $width
                $visible = @($plan | Where-Object Visible)
                $sum = 0
                foreach ($col in $visible) { $sum += $col.MaxWidth }
                ($sum + $visible.Count + 1) | Should -Be $width
            }
        }

        It '超宽档(>128): SESSION 被 TG 的 100 列单元格上限封顶, 表格宽 128' {
            foreach ($width in @(130, 160)) {
                $plan = & $script:mod { param($w) New-TmuxTuiColumnPlan -WindowWidth $w } $width
                $visible = @($plan | Where-Object Visible)
                $session = $visible | Where-Object Name -EQ 'SESSION'
                $session.MaxWidth | Should -Be 100
                $sum = 0
                foreach ($col in $visible) { $sum += $col.MaxWidth }
                ($sum + $visible.Count + 1) | Should -Be 128
            }
        }

        It '超窄档(<72): 隐藏 WINDOWS 与 STATUS, 仅 # + SESSION' {
            $plan = & $script:mod { param($w) New-TmuxTuiColumnPlan -WindowWidth $w } 60
            (($plan | Where-Object Visible).Name -join ',') | Should -BeExactly 'No,SESSION'
        }
    }

    Context '会话表构建 (无头构造, 不进事件循环)' {

        It '2 会话 120 宽: 数据源 2 行 / 4 可见列 / 列名顺序与计划一致' {
            $vm = & $script:mod { param($s) ConvertTo-TmuxTuiViewModel -State $s } $script:sampleState
            $plan = & $script:mod { param($w) New-TmuxTuiColumnPlan -WindowWidth $w } 120

            $result = & $script:mod { param($v, $p) New-TmuxTuiSessionTable -ViewModel $v -ColumnPlan $p } $vm $plan

            $result.Source.Rows | Should -Be 2
            $result.Source.Columns | Should -Be 4
            ($result.Source.ColumnNames -join ',') | Should -BeExactly 'No,SESSION,STATUS,WINDOWS'
            $result.Source.Item(0, 1) | Should -BeExactly 'work'
            $result.Source.Item(1, 1) | Should -BeExactly 'ci'
            ($result.VisibleColumns -join ',') | Should -BeExactly 'No,SESSION,STATUS,WINDOWS'
        }

        It '列样式: #=4, SESSION 吃满余量(72), WINDOWS 右对齐(End), STATUS 居中(Center)' {
            $vm = & $script:mod { param($s) ConvertTo-TmuxTuiViewModel -State $s } $script:sampleState
            $plan = & $script:mod { param($w) New-TmuxTuiColumnPlan -WindowWidth $w } 100

            $result = & $script:mod { param($v, $p) New-TmuxTuiSessionTable -ViewModel $v -ColumnPlan $p } $vm $plan

            $styles = $result.Table.Style.ColumnStyles
            $styles[0].MinWidth | Should -Be 4
            $styles[0].MaxWidth | Should -Be 4
            # 2026-10-31 UI 升级: SESSION 吃满余量, Min=Max=72(100 - 23 - 5)
            $styles[1].MinWidth | Should -Be 72
            $styles[1].MaxWidth | Should -Be 72
            # 100 宽: STATUS 仍可见(≥96 档), 位于第三列, 居中对齐(便于一眼扫状态)
            $styles[2].Alignment.ToString() | Should -BeExactly 'Center'
            # 末列(WINDOWS)数值右对齐 -> Alignment = End
            $styles[3].Alignment.ToString() | Should -BeExactly 'End'
            # 2026-10-31: 关掉"末列自动拉伸", 否则末列会被撑成巨型空列
            $result.Table.Style.ExpandLastColumn | Should -BeFalse
        }

        It '空状态: 表格行恒为 0(不伪造占位会话行)' {
            $state = & $script:mod { Get-TmuxSessionState -SessionData @{ Available = $true; Sessions = @() } }
            $vm = & $script:mod { param($s) ConvertTo-TmuxTuiViewModel -State $s } $state
            $plan = & $script:mod { param($w) New-TmuxTuiColumnPlan -WindowWidth $w } 120

            $result = & $script:mod { param($v, $p) New-TmuxTuiSessionTable -ViewModel $v -ColumnPlan $p } $vm $plan

            $result.Source.Rows | Should -Be 0
        }

        It '错误状态: 同样 0 行, 占位文案禁止进表格(由独立错误区渲染)' {
            $state = & $script:mod { Get-TmuxSessionState -SessionData @{ Available = $false; TimedOut = $true } }
            $vm = & $script:mod { param($s) ConvertTo-TmuxTuiViewModel -State $s } $state
            $plan = & $script:mod { param($w) New-TmuxTuiColumnPlan -WindowWidth $w } 120

            $result = & $script:mod { param($v, $p) New-TmuxTuiSessionTable -ViewModel $v -ColumnPlan $p } $vm $plan

            $result.Source.Rows | Should -Be 0
            $result.Source.Columns | Should -Be 4
        }

        It 'CollectionNavigator 已摘除: 字母键不触发 type-ahead, 保证 N/R/S/X/Q 热键可达' {
            $vm = & $script:mod { param($s) ConvertTo-TmuxTuiViewModel -State $s } `
                (& $script:mod { Get-TmuxSessionState -SessionData @{
                        Available = $true
                        Sessions  = @([PSCustomObject]@{ Name = 'work'; Status = 'detached'; Windows = 2 })
                    } })
            $plan = & $script:mod { param($w) New-TmuxTuiColumnPlan -WindowWidth $w } 120

            $result = & $script:mod { param($v, $p) New-TmuxTuiSessionTable -ViewModel $v -ColumnPlan $p } $vm $plan

            # 2.4.10 实测(证据 .agent_cache/tui-nprobe/probe11/15/17): 有导航器时
            # TableView.OnKeyDown 的 type-ahead 会把字母键标记已处理,
            # 应用级 Shortcut 热键永远到不了 —— 必须保持 null。
            $result.Table.CollectionNavigator | Should -BeNullOrEmpty
        }

        It 'FullRowSelect 已开启: 选中行整行高亮(2026-10-31 UI 升级)' {
            $vm = & $script:mod { param($s) ConvertTo-TmuxTuiViewModel -State $s } `
                (& $script:mod { Get-TmuxSessionState -SessionData @{
                        Available = $true
                        Sessions  = @([PSCustomObject]@{ Name = 'work'; Status = 'detached'; Windows = 2 })
                    } })
            $plan = & $script:mod { param($w) New-TmuxTuiColumnPlan -WindowWidth $w } 120

            $result = & $script:mod { param($v, $p) New-TmuxTuiSessionTable -ViewModel $v -ColumnPlan $p } $vm $plan

            # 2.4.10 默认 $false 时只有选中"单元格"(第 0 列)高亮(PTY 取证),
            # 置 $true 后整行取 Focus 槽位 —— 选中反馈是行级别的。
            $result.Table.FullRowSelect | Should -BeTrue
        }
    }
}
