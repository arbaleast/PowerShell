# New-TmuxTuiShortcutList.Tests.ps1 - TGUI 底部快捷键栏契约测试(阶段 A, Goal 六-3)
# 覆盖:
#   1. 快捷键到业务动作的分发(Action 调用进 Dispatch, 动作值正确);
#   2. 无会话时的死键防护: 不出现附着, 删除标题带"(不可用)";
#   3. Esc/Q 两键同义退出(Goal 三-3)。
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

    It '有会话: 含 Enter 附着/N/R/S/X/Q/Esc 七项, 动作值分发正确' {
        Set-Variable -Name 'dispatched' -Value ([System.Collections.Generic.List[string]]::new()) -Scope Global
        $shortcuts = & $script:mod {
            New-TmuxTuiShortcutList -HasSessions $true -Dispatch { param($action) (Get-Variable -Name 'dispatched' -Scope Global).Value.Add($action) }
        }

        $shortcuts.Count | Should -Be 7

        $r = $shortcuts | Where-Object { $_.Title -eq '[r] 刷新' } | Select-Object -First 1
        $r.Action.Invoke()
        (Get-Variable -Name 'dispatched' -Scope Global).Value -contains 'Refresh' | Should -BeTrue

        $x = $shortcuts | Where-Object { $_.Title -eq '[x] 删除' } | Select-Object -First 1
        $x.Action.Invoke()
        (Get-Variable -Name 'dispatched' -Scope Global).Value -contains 'Remove' | Should -BeTrue

        $esc = $shortcuts | Where-Object { $_.Title -eq '[Esc] 退出' } | Select-Object -First 1
        # 纯展示项 no-op(2026-10-30 阶段B收口): Esc 退出统一走 TG 内建 Esc->Quit,
        # 展示项不再分发 —— 防"内建 Quit + 展示项分发"双触发。
        $esc.Action.Invoke()
        (Get-Variable -Name 'dispatched' -Scope Global).Value -contains 'Quit' | Should -BeFalse

        $enter = $shortcuts | Where-Object { $_.Title -eq 'Enter 附着' } | Select-Object -First 1
        $enter.Action.Invoke()
        (Get-Variable -Name 'dispatched' -Scope Global).Value -contains 'Attach' | Should -BeTrue
    }

    It '无会话: 无附着项, 删除显式"(不可用)", 其余可用' {
        $shortcuts = & $script:mod {
            New-TmuxTuiShortcutList -HasSessions $false -Dispatch { param($action) [void]$action }
        }

        $titles = @($shortcuts | ForEach-Object { $_.Title })
        ($titles | Where-Object { $_ -like '*附着*' }).Count | Should -Be 0
        ($titles | Where-Object { $_ -eq '[x] 删除 (不可用)' }).Count | Should -Be 1
        ($titles | Where-Object { $_ -eq '[n] 新建' }).Count | Should -Be 1
        ($titles | Where-Object { $_ -eq '[Esc] 退出' }).Count | Should -Be 1
    }

    It 'Q 分发退出; Esc 展示项 no-op(退出走 TG 内建 Esc->Quit, 不重复分发)' {
        Set-Variable -Name 'dispatched' -Value ([System.Collections.Generic.List[string]]::new()) -Scope Global
        $shortcuts = & $script:mod {
            New-TmuxTuiShortcutList -HasSessions $true -Dispatch { param($action) (Get-Variable -Name 'dispatched' -Scope Global).Value.Add($action) }
        }

        $q = $shortcuts | Where-Object { $_.Title -eq '[q] 退出' } | Select-Object -First 1
        $q.Action.Invoke()
        $esc = $shortcuts | Where-Object { $_.Title -eq '[Esc] 退出' } | Select-Object -First 1
        $esc.Action.Invoke()

        $log = (Get-Variable -Name 'dispatched' -Scope Global).Value
        $log | Should -HaveCount 1
        $log -contains 'Quit' | Should -BeTrue
    }
}
