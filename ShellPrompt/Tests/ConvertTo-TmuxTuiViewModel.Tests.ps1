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

    Context '相对时间 (ConvertTo-TmuxRelativeTime)' {

        It '固定 now 下产出确定性的相对时间文本' {
            $now = [DateTimeOffset]::FromUnixTimeSeconds(1700000000)
            $r = & $script:mod {
                param($n)
                @(
                    ConvertTo-TmuxRelativeTime -Epoch 1700000000 -Now $n
                    ConvertTo-TmuxRelativeTime -Epoch (1700000000 - 30) -Now $n
                    ConvertTo-TmuxRelativeTime -Epoch (1700000000 - 300) -Now $n
                    ConvertTo-TmuxRelativeTime -Epoch (1700000000 - 7200) -Now $n
                    ConvertTo-TmuxRelativeTime -Epoch (1700000000 - 172800) -Now $n
                    ConvertTo-TmuxRelativeTime -Epoch (1700000000 - 1814400) -Now $n
                )
            } $now

            $r[0] | Should -BeExactly 'just now'
            $r[1] | Should -BeExactly 'just now'
            $r[2] | Should -BeExactly '5m ago'
            $r[3] | Should -BeExactly '2h ago'
            $r[4] | Should -BeExactly '2d ago'
            $r[5] | Should -BeExactly '3w ago'
        }

        It '时间戳未知(0/负数/空)时返回 N/A' {
            $r = & $script:mod {
                @(
                    ConvertTo-TmuxRelativeTime -Epoch 0
                    ConvertTo-TmuxRelativeTime -Epoch -5
                    ConvertTo-TmuxRelativeTime -Epoch $null
                    ConvertTo-TmuxRelativeTime -Epoch 'not-a-number'
                )
            }

            $r | ForEach-Object { $_ | Should -BeExactly 'N/A' }
        }

        It '远端时钟略快(负差)按 just now 处理' {
            $now = [DateTimeOffset]::FromUnixTimeSeconds(1700000000)
            $r = & $script:mod { param($n) ConvertTo-TmuxRelativeTime -Epoch 1700000100 -Now $n } $now

            $r | Should -BeExactly 'just now'
        }
    }

    Context '路径折叠 (ConvertTo-TmuxShortPath)' {

        It '已知 HOME 时把 HOME 前缀折叠成 ~' {
            $r = & $script:mod {
                ConvertTo-TmuxShortPath -Path '/home/debian/work/hermes' -HomePath '/home/debian'
            }

            $r | Should -BeExactly '~/work/hermes'
        }

        It '路径恰好等于 HOME 时折叠成 ~' {
            $r = & $script:mod {
                ConvertTo-TmuxShortPath -Path '/home/debian' -HomePath '/home/debian'
            }

            $r | Should -BeExactly '~'
        }

        It 'HOME 缺失时用 home 用户目录兜底启发式' {
            $r = & $script:mod {
                ConvertTo-TmuxShortPath -Path '/home/debian/work/hermes' -HomePath ''
            }

            $r | Should -BeExactly '~/work/hermes'
        }

        It 'HOME 缺失时用 Users 用户目录兜底启发式' {
            $r = & $script:mod {
                ConvertTo-TmuxShortPath -Path '/Users/alice/work' -HomePath ''
            }

            $r | Should -BeExactly '~/work'
        }

        It '不匹配 HOME 的路径原样返回' {
            $r = & $script:mod {
                ConvertTo-TmuxShortPath -Path '/var/log/syslog' -HomePath '/home/debian'
            }

            $r | Should -BeExactly '/var/log/syslog'
        }
    }

    Context 'ANSI 剥离 (ConvertTo-TmuxPlainText)' {

        It '剥离 CSI 颜色序列, 保留可见文本' {
            $r = & $script:mod {
                ConvertTo-TmuxPlainText -Text "$([char]27)[31mred$([char]27)[0m"
            }

            $r | Should -BeExactly 'red'
        }

        It '纯文本原样返回' {
            $r = & $script:mod { ConvertTo-TmuxPlainText -Text 'plain text' }

            $r | Should -BeExactly 'plain text'
        }
    }

    Context '窗口拓扑与预览映射进视图模型' {

        It '窗口数组/预览/时间戳映射到会话行与 SessionDetails' {
            $state = & $script:mod {
                Get-TmuxSessionState -SessionData @{
                    Available = $true
                    Sessions  = @(
                        [PSCustomObject]@{
                            Name       = 'work'
                            Status     = 'detached'
                            Windows    = 2
                            Created    = 1700000000
                            Activity   = 1700000900
                            HomePath   = '/home/debian'
                            WindowList = @(
                                [PSCustomObject]@{
                                    Index = 0; Name = 'main'; Active = $true; Panes = 2
                                    Command = 'vim'; Path = '/home/debian/work/hermes'
                                }
                                [PSCustomObject]@{
                                    Index = 1; Name = 'logs'; Active = $false; Panes = 1
                                    Command = 'tail'; Path = '/var/log'
                                }
                            )
                            PreviewLines = @("$([char]27)[32m$ ls$([char]27)[0m", 'total 3')
                        }
                    )
                }
            }
            $vm = & $script:mod { param($s) ConvertTo-TmuxTuiViewModel -State $s } $state

            $row = $vm.SessionRows[0]
            $row.CreatedEpoch | Should -Be 1700000000
            $row.ActivityEpoch | Should -Be 1700000900
            # 相对时间文本由真实时钟算出, 断言其**形状**而不是具体值(避免时间依赖)
            $row.Created | Should -Match '^(just now|\d+[mhdw] ago)$'
            $row.Activity | Should -Match '^(just now|\d+[mhdw] ago)$'
            $row.WindowList.Count | Should -Be 2
            $row.WindowList[0].Name | Should -BeExactly 'main'
            $row.WindowList[0].Index | Should -Be 0
            $row.WindowList[0].Active | Should -BeTrue
            $row.WindowList[0].Panes | Should -Be 2
            $row.WindowList[0].Command | Should -BeExactly 'vim'
            $row.WindowList[0].Path | Should -BeExactly '/home/debian/work/hermes'
            $row.WindowList[0].PathShort | Should -BeExactly '~/work/hermes'
            $row.WindowList[1].PathShort | Should -BeExactly '/var/log'
            $row.PaneCount | Should -Be 3
            $row.PreviewLines.Count | Should -Be 2
            # ANSI 被剥离, 可见文本保留
            $row.PreviewLines[0] | Should -BeExactly '$ ls'

            # 平行结构: 右面板按 SessionDetails 取用
            $vm.SessionDetails.Count | Should -Be 1
            $detail = $vm.SessionDetails[0]
            $detail.Name | Should -BeExactly 'work'
            $detail.Windows.Count | Should -Be 2
            $detail.WindowCount | Should -Be 2
            $detail.PaneCount | Should -Be 3
            $detail.PreviewLines.Count | Should -Be 2
        }

        It 'attached 会话的 Activity 显示 Active now' {
            $state = & $script:mod {
                Get-TmuxSessionState -SessionData @{
                    Available = $true
                    Sessions  = @(
                        [PSCustomObject]@{ Name = 'ci'; Status = 'attached'; Windows = 1; Created = 1700000000; Activity = 1700000000 }
                    )
                }
            }
            $vm = & $script:mod { param($s) ConvertTo-TmuxTuiViewModel -State $s } $state

            $vm.SessionRows[0].Activity | Should -BeExactly 'Active now'
        }
    }

    Context '向后兼容: 旧数据(无新字段)' {

        It '旧会话对象不抛异常, 新字段给出安全默认值' {
            $state = & $script:mod {
                Get-TmuxSessionState -SessionData @{
                    Available = $true
                    Sessions  = @([PSCustomObject]@{ Name = 'legacy'; Status = 'detached'; Windows = 3 })
                }
            }
            $vm = & $script:mod { param($s) ConvertTo-TmuxTuiViewModel -State $s } $state

            $row = $vm.SessionRows[0]
            $row.Created | Should -BeExactly 'N/A'
            $row.Activity | Should -BeExactly 'N/A'
            $row.CreatedEpoch | Should -Be 0
            $row.ActivityEpoch | Should -Be 0
            $row.WindowList.Count | Should -Be 0
            $row.PreviewLines.Count | Should -Be 0
            $row.PaneCount | Should -Be 3   # 无分屏信息时退回窗口数
            $row.Windows | Should -Be 3
        }

        It '旧会话对象(空数组字段)同样不抛异常' {
            $state = & $script:mod {
                Get-TmuxSessionState -SessionData @{
                    Available = $true
                    Sessions  = @(
                        [PSCustomObject]@{
                            Name = 'legacy'; Status = 'detached'; Windows = 1
                            WindowList = @(); PreviewLines = @()
                        }
                    )
                }
            }
            $vm = & $script:mod { param($s) ConvertTo-TmuxTuiViewModel -State $s } $state

            $vm.SessionRows[0].WindowList.Count | Should -Be 0
            $vm.SessionRows[0].PreviewLines.Count | Should -Be 0
            $vm.SessionDetails[0].Windows.Count | Should -Be 0
        }
    }
}
