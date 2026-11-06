# New-TmuxTuiShortcutList.Tests.ps1 - TGUI 底部快捷键栏契约测试(阶段 A, Goal 六-3)
# 覆盖:
#   1. 快捷键到业务动作的分发(Action 调用进 Dispatch, 动作值正确);
#   2. 无会话时的死键防护: 不出现附着, 删除标题带"(不可用)";
#   3. 阶段一(2026-11-06): Esc 与 q 合并为**单一展示项** "q/Esc 退出",
#      真实绑定键仍是 q; 列表里**不再有** .Key -eq 'Esc' 的项, 但退出动作
#      仍然分发 'Quit'(Esc 键本身走 TG 内建 Esc->Quit + 列表容器 KeyDown 兜底)。
# 说明: 分发桩走 **Get/Set-Variable -Scope Global 动态访问** —— Shortcut.Action
# 的闭包在 TG 事件循环里于"模块态"被触发, 测试桩的函数局部/script 局部都
# 不可见(见 Private/New-TmuxTuiShortcutList.ps1 的坑记录); 同时这种写法
# 不含 `$global:` 文法 token, 规避 PSAvoidGlobalVars。

Describe 'TGUI 快捷键列表 (New-TmuxTuiShortcutList)' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It '有会话: 含 Enter 附着/N/R/S/X/Q 六项, 动作值分发正确' {
        Set-Variable -Name 'dispatched' -Value ([System.Collections.Generic.List[string]]::new()) -Scope Global
        $shortcuts = & $script:mod {
            New-TmuxTuiShortcutList -HasSessions $true -Dispatch { param($action) (Get-Variable -Name 'dispatched' -Scope Global).Value.Add($action) }
        }

        $shortcuts.Count | Should -Be 6 -Because '阶段一: Esc 与 q 合并成一项, 总项数从 7 降到 6'

        $r = $shortcuts | Where-Object { $_.Title -eq '刷新' } | Select-Object -First 1
        $r.Action.Invoke()
        (Get-Variable -Name 'dispatched' -Scope Global).Value -contains 'Refresh' | Should -BeTrue

        $x = $shortcuts | Where-Object { $_.Title -eq '删除' } | Select-Object -First 1
        $x.Action.Invoke()
        (Get-Variable -Name 'dispatched' -Scope Global).Value -contains 'Remove' | Should -BeTrue

        $enter = $shortcuts | Where-Object { $_.Title -eq '附着' } | Select-Object -First 1
        $enter.Action.Invoke()
        (Get-Variable -Name 'dispatched' -Scope Global).Value -contains 'Attach' | Should -BeTrue
    }

    It '无会话: 无附着项, 删除显式"(不可用)", 其余可用' {
        $shortcuts = & $script:mod {
            New-TmuxTuiShortcutList -HasSessions $false -Dispatch { param($action) [void]$action }
        }

        $titles = @($shortcuts | ForEach-Object { $_.Title })
        ($titles | Where-Object { $_ -like '*附着*' }).Count | Should -Be 0
        ($titles | Where-Object { $_ -eq '删除 (不可用)' }).Count | Should -Be 1
        ($titles | Where-Object { $_ -eq '新建' }).Count | Should -Be 1
        # 阶段一: 退出只剩**一项**(q/Esc 合并), 不再是两个同名"退出"
        ($titles | Where-Object { $_ -match '退出' }).Count | Should -Be 1
        ($titles | Where-Object { $_ -eq 'q/Esc 退出' }).Count | Should -Be 1
    }

    It '阶段一去重: 退出项合并为 "q/Esc 退出", 且列表里没有任何 .Key -eq Esc 的项' {
        $shortcuts = & $script:mod {
            New-TmuxTuiShortcutList -HasSessions $true -Dispatch { param($action) [void]$action }
        }

        $exitItems = @($shortcuts | Where-Object { [string]$_.Title -match '退出' })
        $exitItems | Should -HaveCount 1 -Because 'q 与 Esc 是同一个退出动作, 底栏只能展示一次'
        $exitItems[0].Title | Should -BeExactly 'q/Esc 退出'
        # 真实绑定的键仍是 q(展示文字与绑定键分离)
        [string]$exitItems[0].Key | Should -BeExactly 'q'
        # 不再有独立的 Esc 展示项
        @($shortcuts | Where-Object { [string]$_.Key -eq 'Esc' }).Count | Should -Be 0
        # 合并项仍然负责分发退出动作
        $exitItems[0].Enabled | Should -BeTrue
    }

    It '退出项的动作分发仍然是 Quit(合并只动展示, 不动语义)' {
        Set-Variable -Name 'dispatched' -Value ([System.Collections.Generic.List[string]]::new()) -Scope Global
        $shortcuts = & $script:mod {
            New-TmuxTuiShortcutList -HasSessions $true -Dispatch { param($action) (Get-Variable -Name 'dispatched' -Scope Global).Value.Add($action) }
        }

        $q = $shortcuts | Where-Object { [string]$_.Title -eq 'q/Esc 退出' } | Select-Object -First 1
        $q | Should -Not -BeNullOrEmpty
        $q.Action.Invoke()

        $log = (Get-Variable -Name 'dispatched' -Scope Global).Value
        $log | Should -HaveCount 1
        $log -contains 'Quit' | Should -BeTrue
    }

    It '渲染契约(TG 2.4.10 实测): Title=纯标签, HelpText 全空 —— 键名+标签不得双渲染' {
        # 真机(2026-10-30 Windows Terminal)证明 Shortcut 屏幕渲染序 = 键名+HelpText+Title,
        # HelpText/Title 各带一次标签 => 底栏 "Enter 附着 Enter 附着" 成对重复。
        $shortcuts = & $script:mod {
            New-TmuxTuiShortcutList -HasSessions $true -Dispatch { param($action) [void]$action }
        }
        foreach ($sc in $shortcuts) {
            $sc.HelpText | Should -Be ''
            $sc.Title | Should -Not -Match '^\['
        }
    }

    # ---------------- 响应式/上下文升级 (2026-10-31) ----------------

    It 'Context=Error: 刷新/SSH 文案换成 重试/直连(键位与动作值不变)' {
        Set-Variable -Name 'dispatched' -Value ([System.Collections.Generic.List[string]]::new()) -Scope Global
        $list = & $script:mod {
            New-TmuxTuiShortcutList -HasSessions $true -Dispatch { param($action) (Get-Variable -Name 'dispatched' -Scope Global).Value.Add($action) } -Context 'Error'
        }

        # r 项 Title = 重试(Normal 是 刷新); s 项 = 直连(Normal 是 SSH)
        $retry = $list | Where-Object { [string]$_.Key -eq 'r' } | Select-Object -First 1
        $retry.Title | Should -BeExactly '重试'
        $ssh = $list | Where-Object { [string]$_.Key -eq 's' } | Select-Object -First 1
        $ssh.Title | Should -BeExactly '直连'
        # 动作值不随文案切换(键位语义不变)
        $retry.Action.Invoke()
        $log = (Get-Variable -Name 'dispatched' -Scope Global).Value
        $log -contains 'Refresh' | Should -BeTrue
    }

    It 'WindowWidth 响应式: 按可用列宽取舍, 退出键(q)永远保留, 不显示被截断的半截项' {
        # 2026-10-31 UI 升级: Terminal.Gui 的 StatusBar 不换行, 放不下就右端硬截断
        # (真机 40x10 取证: "s SSH" 被截成 "s SS", x/q/Esc 完全不可见)。
        # 现按宽度预算取舍: 优先级 Enter 附着 > n 新建 > q 退出 > r > s > x > Esc。
        $wide = & $script:mod {
            New-TmuxTuiShortcutList -HasSessions $true -Dispatch { param($action) [void]$action } -WindowWidth 120
        }
        $wide.Count | Should -Be 6
        # Esc 已被合并进 q/Esc 项, 不再是独立项
        @($wide | Where-Object { [string]$_.Key -eq 'Esc' }).Count | Should -Be 0
        @($wide | Where-Object { [string]$_.Key -eq 'q' }).Count | Should -Be 1

        # 60 列实测底栏放得下 5 项, 放不下 6 项 -> 舍掉优先级最低的 X
        $narrow = & $script:mod {
            New-TmuxTuiShortcutList -HasSessions $true -Dispatch { param($action) [void]$action } -WindowWidth 60
        }
        $narrow.Count | Should -Be 5
        @($narrow | Where-Object { [string]$_.Key -eq 'Esc' }).Count | Should -Be 0
        @($narrow | Where-Object { [string]$_.Key -eq 'q' }).Count | Should -Be 1

        # 40 列(最小可用宽度): 只剩 3 项, 但**退出键必须可见**
        $tiny = & $script:mod {
            New-TmuxTuiShortcutList -HasSessions $true -Dispatch { param($action) [void]$action } -WindowWidth 40
        }
        $tiny.Count | Should -Be 3
        @($tiny | Where-Object { [string]$_.Key -eq 'q' }).Count | Should -Be 1
        @($tiny | Where-Object { [string]$_.Key -eq 'Enter' }).Count | Should -Be 1

        # 不传 WindowWidth(0) = 维持旧行为(全项, 兼容既有契约)
        $legacy = & $script:mod {
            New-TmuxTuiShortcutList -HasSessions $true -Dispatch { param($action) [void]$action }
        }
        @($legacy | Where-Object { [string]$_.Key -eq 'Esc' }).Count | Should -Be 0
        $legacy.Count | Should -Be 6
    }

    It '任何宽度下都只有一个退出项, 且从不出现独立的 Esc 键项' {
        foreach ($w in @(0, 40, 60, 80, 120, 200)) {
            $list = & $script:mod {
                param($width)
                if ($width -gt 0) {
                    New-TmuxTuiShortcutList -HasSessions $true -Dispatch { param($action) [void]$action } -WindowWidth $width
                }
                else {
                    New-TmuxTuiShortcutList -HasSessions $true -Dispatch { param($action) [void]$action }
                }
            } $w
            $exitCount = @($list | Where-Object { [string]$_.Title -match '退出' }).Count
            $exitCount | Should -Be 1 -Because "宽度 $w 下退出项不得重复展示"
            @($list | Where-Object { [string]$_.Key -eq 'Esc' }).Count | Should -Be 0 -Because "宽度 $w 下不得有独立的 Esc 项"
            @($list | Where-Object { [string]$_.Key -eq 'q' }).Count | Should -BeLessOrEqual 1
        }
    }

    It '取舍只影响"显示哪几项", 键位语义不变: 被舍掉的项按键依然生效' {
        # 键位/动作值由 Get-TmuxActionDefinition 决定, 工厂只筛"显示集合";
        # 应用级键表登记的是**全部**动作(未显示项不登记视图键, 但业务分发不变)。
        $tiny = & $script:mod {
            New-TmuxTuiShortcutList -HasSessions $true -Dispatch { param($action) [void]$action } -WindowWidth 40
        }
        # 40 列下 x 不显示, 但 q 仍在(退出能力可见)
        @($tiny | Where-Object { [string]$_.Key -eq 'x' }).Count | Should -Be 0
        # 显示项的动作值仍是完整契约值
        ($tiny | ForEach-Object { $_.Title }) -join ',' | Should -Not -Match '不可用'
    }
}
