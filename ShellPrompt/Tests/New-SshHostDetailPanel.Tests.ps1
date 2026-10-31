# New-SshHostDetailPanel.Tests.ps1 - SSH 主机仪表盘**右侧详情面板**的契约测试
#
# 覆盖 (2026-10-31 sss 仪表盘视图层):
#   1. Get-SshHostDetailCardPlan: Connection 永远保留; Activity/Tags 只在高度够
#      时出现; Infrastructure 只在 -HasInfrastructure 为真时出现; 卡片总高不超出
#      可用高度; 极小高度下只剩 Connection。
#   2. Format-SshHostActivityHistogram: 空桶/全零桶返回 "—"(不画假柱子);
#      有数据时长度 == 桶数, 且只用 5 档方块字符(空格/▁/▃/▅/█)。
#   3. Set-SshHostDetailBasic: 本地字段落位(Host/Address/User/端口), 缺省用户
#      显示 "(默认)", 探测结果未回填前 Status 显示 "未知"(绝不提前显示"在线"),
#      缺失的 Tags/Group/Provider/Region 显示 "—"; Row=$null 时清空全部值,
#      Status 归 "—"(不残留上一台主机的数据)。
#   4. Set-SshHostDetailState: Loading/Error/Unknown 三态文案。
#   5. Set-SshHostDetailRemote: 在线态显示"在线", 离线态显示错误码。
#
# 无头可测: Terminal.Gui 视图只构造不渲染(不进事件循环), 不依赖 TTY。

Describe 'Get-SshHostDetailCardPlan: 卡片高度分配' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It 'Connection 卡片永远保留(高度再小也不收起)' {
        foreach ($h in @(8, 12, 20, 31, 60)) {
            $plan = & $script:mod { param($x) Get-SshHostDetailCardPlan -Height $x } $h
            $plan.Connection | Should -BeGreaterThan 0 -Because "高度 $h 下 Connection 必须存在"
        }
    }

    It '高度不足时不显示 Activity / Tags 卡片' {
        $plan = & $script:mod { Get-SshHostDetailCardPlan -Height 8 }
        $plan.Activity | Should -Be 0
        $plan.Tags | Should -Be 0
    }

    It '高度足够时显示 Activity 与 Tags 卡片' {
        $plan = & $script:mod { Get-SshHostDetailCardPlan -Height 31 }
        $plan.Activity | Should -BeGreaterThan 0
        $plan.Tags | Should -BeGreaterThan 0
    }

    It 'Infrastructure 只在 -HasInfrastructure 为真时出现' {
        $without = & $script:mod { Get-SshHostDetailCardPlan -Height 31 -HasInfrastructure $false }
        $with = & $script:mod { Get-SshHostDetailCardPlan -Height 31 -HasInfrastructure $true }
        $without.Infrastructure | Should -Be 0
        $with.Infrastructure | Should -BeGreaterThan 0
    }

    It '卡片总高不超出可用高度(>= Connection 最小高度 7 的区间)' {
        foreach ($h in 7..60) {
            $plan = & $script:mod { param($x) Get-SshHostDetailCardPlan -Height $x } $h
            $plan.Total | Should -BeLessOrEqual $h -Because "高度 $h 下卡片总高不能溢出"
        }
    }

    It '极小高度下只剩 Connection 一张卡片' {
        $plan = & $script:mod { Get-SshHostDetailCardPlan -Height 7 -HasInfrastructure $true }
        $plan.Activity | Should -Be 0
        $plan.Tags | Should -Be 0
        $plan.Infrastructure | Should -Be 0
        $plan.Connection | Should -BeGreaterThan 0
    }
}

Describe 'Format-SshHostActivityHistogram: 7 日直方图' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It '空桶返回 "—"(不画空图)' {
        $result = & $script:mod { Format-SshHostActivityHistogram -Buckets @() }
        $result | Should -BeExactly ([string][char]0x2014)
    }

    It '全零桶返回 "—"(没有活动就不画柱子)' {
        $result = & $script:mod { Format-SshHostActivityHistogram -Buckets @(0, 0, 0, 0, 0, 0, 0) }
        $result | Should -BeExactly ([string][char]0x2014)
    }

    It '有数据时长度 == 桶数' {
        $result = & $script:mod { Format-SshHostActivityHistogram -Buckets @(0, 1, 3, 0, 5, 2, 0) }
        $result.Length | Should -Be 7
    }

    It '只使用 5 档方块字符(空格/▁/▃/▅/█)' {
        $result = & $script:mod { Format-SshHostActivityHistogram -Buckets @(0, 1, 3, 0, 5, 2, 0) }
        $allowed = @(' ', [string][char]0x2581, [string][char]0x2583, [string][char]0x2585, [string][char]0x2588)
        foreach ($ch in $result.ToCharArray()) {
            $allowed | Should -Contain ([string]$ch)
        }
    }

    It '最大值对应最高档方块, 零值对应空格' {
        $result = & $script:mod { Format-SshHostActivityHistogram -Buckets @(0, 3, 0) }
        $result[0] | Should -BeExactly ' '
        $result[1] | Should -BeExactly ([string][char]0x2588)
        $result[2] | Should -BeExactly ' '
    }
}

Describe 'Set-SshHostDetailBasic: 本地数据落位' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'

        # 行模型是纯数据, 在测试作用域里构造后传给模块内的私有函数
        $script:makeRow = {
            param([int]$port = 22, [string]$user = '', [string]$group = '', [string]$provider = '',
                [string]$region = '', [string[]]$tags = @())
            [PSCustomObject]@{
                Name = 'alpha'; HostName = 'a.example.com'; Port = $port; User = $user
                Tags = $tags; Group = $group; Provider = $provider; Region = $region
                IsLocal = $false; Status = 'Unknown'; StatusText = '未知'; StatusGlyph = [string][char]0x25CF
                StatusRole = 'Unknown'; LastActive = $null; LastActiveText = [string][char]0x2014
                HasActivity = $false; ConnectCount = 0; Indent = $false
                DisplayName = 'alpha'; Value = 'alpha'
            }
        }
    }

    It 'Host / Address / User 从行模型落位' {
        $row = & $script:makeRow -port 22 -user 'ops'
        $result = & $script:mod {
            param($r)
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $panel = New-SshHostDetailPanel -Width 56 -Height 31 -HasInfrastructure $true -Theme $theme -Tgui $tg
            Set-SshHostDetailBasic -Panel $panel -Row $r
            [PSCustomObject]@{
                Host    = [string]$panel.Labels['Host'].Text
                Address = [string]$panel.Labels['Address'].Text
                User    = [string]$panel.Labels['User'].Text
            }
        } $row
        $result.Host | Should -BeExactly 'alpha'
        $result.Address | Should -BeExactly 'a.example.com'
        $result.User | Should -BeExactly 'ops'
    }

    It '非默认端口(非 22)会出现在 Connection 卡片里(地址后缀或独立端口行)' {
        $row = & $script:makeRow -port 2222
        $result = & $script:mod {
            param($r)
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $panel = New-SshHostDetailPanel -Width 56 -Height 31 -HasInfrastructure $true -Theme $theme -Tgui $tg
            Set-SshHostDetailBasic -Panel $panel -Row $r
            $address = [string]$panel.Labels['Address'].Text
            $portLabel = if ($panel.Labels.ContainsKey('Port')) { [string]$panel.Labels['Port'].Text } else { '' }
            [PSCustomObject]@{ Address = $address; PortLabel = $portLabel; Combined = "$address|$portLabel" }
        } $row
        # 地址权威值始终是 HostName(端口不拼进地址行)
        $result.Address | Should -BeExactly 'a.example.com'
        # 端口信息不丢失: 或以 ":2222" 后缀出现, 或落在独立端口行
        ($result.Combined -match '2222') | Should -BeTrue
    }

    It '默认端口 22 不被追加到地址上' {
        $row = & $script:makeRow -port 22
        $result = & $script:mod {
            param($r)
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $panel = New-SshHostDetailPanel -Width 56 -Height 31 -HasInfrastructure $true -Theme $theme -Tgui $tg
            Set-SshHostDetailBasic -Panel $panel -Row $r
            [string]$panel.Labels['Address'].Text
        } $row
        $result | Should -Not -Match ':22'
        $result | Should -BeExactly 'a.example.com'
    }

    It 'User 为空时显示 "(默认)"' {
        $row = & $script:makeRow -user ''
        $result = & $script:mod {
            param($r)
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $panel = New-SshHostDetailPanel -Width 56 -Height 31 -HasInfrastructure $true -Theme $theme -Tgui $tg
            Set-SshHostDetailBasic -Panel $panel -Row $r
            [string]$panel.Labels['User'].Text
        } $row
        $result | Should -BeExactly '(默认)'
    }

    It '探测结果未回填前 Status 显示 "未知", 绝不显示 "在线"' {
        $row = & $script:makeRow
        $result = & $script:mod {
            param($r)
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $panel = New-SshHostDetailPanel -Width 56 -Height 31 -HasInfrastructure $true -Theme $theme -Tgui $tg
            Set-SshHostDetailBasic -Panel $panel -Row $r
            [string]$panel.Labels['Status'].Text
        } $row
        $result | Should -Not -BeNullOrEmpty
        $result | Should -Match '未知'
        $result | Should -Not -Match '在线'
    }

    It '缺失的 Tags / Group / Provider / Region 显示 "—"' {
        $row = & $script:makeRow
        $result = & $script:mod {
            param($r)
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $panel = New-SshHostDetailPanel -Width 56 -Height 31 -HasInfrastructure $true -Theme $theme -Tgui $tg
            Set-SshHostDetailBasic -Panel $panel -Row $r
            [PSCustomObject]@{
                Tags     = [string]$panel.Labels['Tags'].Text
                Group    = [string]$panel.Labels['Group'].Text
                Provider = [string]$panel.Labels['Provider'].Text
                Region   = [string]$panel.Labels['Region'].Text
            }
        } $row
        $result.Tags | Should -BeExactly ([string][char]0x2014)
        $result.Group | Should -BeExactly ([string][char]0x2014)
        $result.Provider | Should -BeExactly ([string][char]0x2014)
        $result.Region | Should -BeExactly ([string][char]0x2014)
    }

    It '有值时 Tags / Group / Provider / Region 展示真实内容' {
        $row = & $script:makeRow -group 'prod' -provider 'AWS' -region 'us-east-1' -tags @('web', 'pub')
        $result = & $script:mod {
            param($r)
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $panel = New-SshHostDetailPanel -Width 56 -Height 31 -HasInfrastructure $true -Theme $theme -Tgui $tg
            Set-SshHostDetailBasic -Panel $panel -Row $r
            [PSCustomObject]@{
                Tags     = [string]$panel.Labels['Tags'].Text
                Group    = [string]$panel.Labels['Group'].Text
                Provider = [string]$panel.Labels['Provider'].Text
                Region   = [string]$panel.Labels['Region'].Text
            }
        } $row
        $result.Tags | Should -BeExactly '#web #pub'
        $result.Group | Should -BeExactly 'prod'
        $result.Provider | Should -BeExactly 'AWS'
        $result.Region | Should -BeExactly 'us-east-1'
    }

    It 'Row=$null 时清空全部值, Status 归 "—"(不残留上一台主机的数据)' {
        $row = & $script:makeRow -port 2222 -user 'ops' -group 'prod' -provider 'AWS' -region 'us-east-1' -tags @('web')
        $result = & $script:mod {
            param($r)
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $panel = New-SshHostDetailPanel -Width 56 -Height 31 -HasInfrastructure $true -Theme $theme -Tgui $tg
            # 先填一台主机, 再传 $null: 必须全部被清掉
            Set-SshHostDetailBasic -Panel $panel -Row $r
            Set-SshHostDetailBasic -Panel $panel -Row $null
            [PSCustomObject]@{
                Host     = [string]$panel.Labels['Host'].Text
                Address  = [string]$panel.Labels['Address'].Text
                User     = [string]$panel.Labels['User'].Text
                Status   = [string]$panel.Labels['Status'].Text
                Tags     = [string]$panel.Labels['Tags'].Text
                Group    = [string]$panel.Labels['Group'].Text
                Provider = [string]$panel.Labels['Provider'].Text
                Region   = [string]$panel.Labels['Region'].Text
            }
        } $row
        $result.Host | Should -BeExactly ''
        $result.Address | Should -BeExactly ''
        $result.User | Should -BeExactly ''
        $result.Status | Should -BeExactly ([string][char]0x2014)
        $result.Tags | Should -BeExactly ''
        $result.Group | Should -BeExactly ''
        $result.Provider | Should -BeExactly ''
        $result.Region | Should -BeExactly ''
    }
}

Describe 'Set-SshHostDetailState: 状态三态' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It 'Loading => "● 探测中…"' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $panel = New-SshHostDetailPanel -Width 56 -Height 31 -Theme $theme -Tgui $tg
            Set-SshHostDetailState -Panel $panel -State 'Loading'
            [string]$panel.Labels['Status'].Text
        }
        $result | Should -Match '探测中'
        $result | Should -Match ([string][char]0x25CF)
    }

    It 'Error => "✗ " + 错误信息' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $panel = New-SshHostDetailPanel -Width 56 -Height 31 -Theme $theme -Tgui $tg
            Set-SshHostDetailState -Panel $panel -State 'Error' -Text 'E_SSH_TIMEOUT'
            [string]$panel.Labels['Status'].Text
        }
        $result | Should -Match ([string][char]0x2717)
        $result | Should -Match 'E_SSH_TIMEOUT'
    }

    It 'Unknown => "● 未知"' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $panel = New-SshHostDetailPanel -Width 56 -Height 31 -Theme $theme -Tgui $tg
            Set-SshHostDetailState -Panel $panel -State 'Unknown'
            [string]$panel.Labels['Status'].Text
        }
        $result | Should -Match '未知'
        $result | Should -Match ([string][char]0x25CF)
    }
}

Describe 'Set-SshHostDetailRemote: 远端探测结果落位' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It '在线结果: Status 显示 "在线"' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $panel = New-SshHostDetailPanel -Width 56 -Height 31 -Theme $theme -Tgui $tg
            $detail = [PSCustomObject]@{
                Status = 'Online'; StatusText = '在线'; ErrorCode = ''; ErrorMessage = ''
                RemoteHostname = 'remote-host'; Uptime = ''; Load = ''
                TmuxSessionCount = $null; ElapsedMs = 42; CheckedAt = [datetime]'2026-10-31T12:00:00'
            }
            Set-SshHostDetailRemote -Panel $panel -Detail $detail
            [string]$panel.Labels['Status'].Text
        }
        $result | Should -Match '在线'
    }

    It '离线结果: Status 带上错误码' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $theme = Get-SshHostDashboardTheme -Tgui $tg
            $panel = New-SshHostDetailPanel -Width 56 -Height 31 -Theme $theme -Tgui $tg
            $detail = [PSCustomObject]@{
                Status = 'Offline'; StatusText = '离线'; ErrorCode = 'E_SSH_TIMEOUT'; ErrorMessage = '连接超时'
                RemoteHostname = ''; Uptime = ''; Load = ''
                TmuxSessionCount = $null; ElapsedMs = 1000; CheckedAt = [datetime]'2026-10-31T12:00:00'
            }
            Set-SshHostDetailRemote -Panel $panel -Detail $detail
            [string]$panel.Labels['Status'].Text
        }
        $result | Should -Match 'E_SSH_TIMEOUT'
    }
}
