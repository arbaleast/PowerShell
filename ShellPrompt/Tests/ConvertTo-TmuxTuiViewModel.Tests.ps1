# ConvertTo-TmuxTuiViewModel.Tests.ps1 - TGUI 视图模型转换契约测试(阶段 A, Goal 六-1/2)
# 覆盖:
#   1. UI 数据模型和会话状态映射(行序/列设计/统计);
#   2. 空状态与错误状态: Mode 分型, 不伪造会话行, 错误码在独立字段而非表格行;
#   3. 刷新后选中保留(PreviousSelected 幸存则保留, 消失则 $null)。
# 说明: 纯函数, 不触碰控制台/网络; 输入用 Get-TmuxSessionState 真实产出的同形状对象。

Describe 'TGUI 视图模型转换 (ConvertTo-TmuxTuiViewModel)' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It '有会话: Mode=Session, 行列 #/SESSION/STATUS/WINDOWS 与输入序一致' {
        $state = & $script:mod {
            Get-TmuxSessionState -SessionData @{
                Available = $true
                Sessions  = @(
                    [PSCustomObject]@{ Name = 'work'; Status = 'detached'; Windows = 3 }
                    [PSCustomObject]@{ Name = 'ci';   Status = 'attached';  Windows = 1 }
                )
            }
        }
        $vm = & $script:mod { param($s) ConvertTo-TmuxTuiViewModel -State $s } $state

        $vm.Mode | Should -BeExactly 'Session'
        $vm.SessionRows.Count | Should -Be 2
        $vm.SessionRows[0].No | Should -Be 1
        $vm.SessionRows[0].Session | Should -BeExactly 'work'
        $vm.SessionRows[0].Status | Should -BeExactly 'Detached'
        $vm.SessionRows[0].Windows | Should -BeOfType [int]
        $vm.SessionRows[0].Windows | Should -Be 3
        $vm.SessionRows[1].Session | Should -BeExactly 'ci'
        $vm.SessionRows[1].Status | Should -BeExactly 'Attached'
    }

    It '顶部统计: Total/Attached/Detached 与会话枚举一致' {
        $state = & $script:mod {
            Get-TmuxSessionState -SessionData @{
                Available = $true
                Sessions  = @(
                    [PSCustomObject]@{ Name = 'a'; Status = 'attached' }
                    [PSCustomObject]@{ Name = 'b'; Status = 'detached' }
                    [PSCustomObject]@{ Name = 'c'; Status = 'detached' }
                )
            }
        }
        $vm = & $script:mod { param($s) ConvertTo-TmuxTuiViewModel -State $s } $state

        $vm.Counts.Total | Should -Be 3
        $vm.Counts.Attached | Should -Be 1
        $vm.Counts.Detached | Should -Be 2
    }

    It '空状态: Mode=Empty, 表格行恒空(不伪造占位会话)' {
        $state = & $script:mod {
            Get-TmuxSessionState -SessionData @{ Available = $true; Sessions = @() }
        }
        $vm = & $script:mod { param($s) ConvertTo-TmuxTuiViewModel -State $s } $state

        $vm.Mode | Should -BeExactly 'Empty'
        $vm.SessionRows.Count | Should -Be 0
        $vm.ErrorCode | Should -BeExactly ''
    }

    It '错误状态: Mode=Error, 错误码/说明/提示在独立字段而非表格行' {
        $state = & $script:mod {
            Get-TmuxSessionState -SessionData @{ Available = $false; TimedOut = $true }
        }
        $vm = & $script:mod { param($s) ConvertTo-TmuxTuiViewModel -State $s } $state

        $vm.Mode | Should -BeExactly 'Error'
        $vm.SessionRows.Count | Should -Be 0
        $vm.ErrorCode | Should -BeExactly 'E_SSH_TIMEOUT'
        $vm.ErrorMessage | Should -Not -BeNullOrEmpty
        $vm.Hint | Should -Match '重试'
    }

    It 'SessionData 为 $null: 按 Error 兜底(E_UNKNOWN), 不伪造行' {
        $vm = & $script:mod { ConvertTo-TmuxTuiViewModel -State $null }

        $vm.Mode | Should -BeExactly 'Error'
        $vm.SessionRows.Count | Should -Be 0
        $vm.ErrorCode | Should -BeExactly 'E_UNKNOWN'
    }

    It '刷新后选中保持: 幸存会话保留, 消失会话不保留' {
        $state1 = & $script:mod {
            Get-TmuxSessionState -SessionData @{
                Available = $true
                Sessions  = @([PSCustomObject]@{ Name = 'work'; Status = 'detached' })
            }
        }
        $vm1 = & $script:mod { param($s) ConvertTo-TmuxTuiViewModel -State $s -PreviousSelected 'work' } $state1
        $vm1.SelectedSession | Should -BeExactly 'work'

        $state2 = & $script:mod {
            Get-TmuxSessionState -SessionData @{
                Available = $true
                Sessions  = @([PSCustomObject]@{ Name = 'other'; Status = 'detached' })
            }
        }
        $vm2 = & $script:mod { param($s) ConvertTo-TmuxTuiViewModel -State $s -PreviousSelected 'work' } $state2
        $vm2.SelectedSession | Should -BeNullOrEmpty
    }
}
