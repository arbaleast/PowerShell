# Invoke-SshHostDashboard.Tests.ps1 - SSH 主机仪表盘**编排层**的契约测试
#
# 覆盖 Goal 四/七 的硬指标(无头可测的部分):
#   1. 非交互护栏: 输入/输出被重定向时**绝不**进事件循环(直接返回 $null);
#   2. 分类切换**不触发任何 SSH 请求**(只做本地过滤);
#   3. ↑↓ 移动选中: 键盘热路径**零网络**, 只改两行, 且详情面板**立即**
#      用本地数据落位(不等远端探测);
#   4. 详情加载不阻塞键盘: 探测请求由心跳发起, 不在按键回调里;
#   5. **旧请求不覆盖新选择**: RequestId + 主机名双重护栏;
#   6. 键位语义: ↑↓ / Enter / / / Tab / ←→ / Esc 与底栏文案一致;
#   7. 分发器契约: Show-SshHostDashboard 返回 .Value = 主机名。
#
# 说明: 全部用**合成档案**与**Mock**, 不读真实 ~/.ssh/config、不联网。

Describe 'Invoke-SshHostDashboard (编排层契约)' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'

        function New-TestProfile {
            # 测试夹具工厂(只 new 一个 PSCustomObject), 不改变系统状态
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
            param([string]$Name, [string]$Provider = '', [string]$Group = '', [string[]]$Tags = @(),
                [bool]$IsLocal = $false, [string]$User = 'root', [int]$Port = 22)
            [PSCustomObject]@{
                Name = $Name; HostName = "10.0.0.$([Math]::Abs($Name.GetHashCode() % 200))"
                Port = $Port; User = $User; IdentityFile = ''; ProxyJump = ''
                Provider = $Provider; Region = ''; Tags = $Tags; Group = $Group
                IsLocal = $IsLocal; Source = 'test'
            }
        }

        function New-TestState {
            # 测试夹具工厂(只 new 无头视图), 不改变系统状态
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
            param([object[]]$Profiles, [string]$LastHost = '', [string]$Category = 'All', [string]$Filter = '')
            & $script:mod {
                param($p, $lh, $cat, $flt)
                $tg = Get-TguiContext
                $theme = Get-SshHostDashboardTheme -Tgui $tg
                $state = New-SshHostDashboardState -Profiles $p -Activity @() -LastHost $lh `
                    -Category $cat -Filter $flt -Theme $theme -Tgui $tg
                $state.Rows = @(Get-SshHostDashboardRowList -State $state)
                $win = New-SshHostDashboardWindow -Rows $state.Rows -Title 'T' `
                    -Categories $state.Categories -ActiveCategory $state.Category `
                    -SelectedIndex 0 -Theme $theme -InfoText 'x' -WindowWidth 120 -WindowHeight 30
                $state.Window = $win.Window
                $state.ListView = $win.ListView
                $state.DetailPanel = $win.DetailPanel
                $state.CategoryBar = @($win.CategoryBar)
                $state.InfoLabel = $win.InfoLabel
                $state.SearchField = $win.SearchField
                $state.SearchPrompt = $win.SearchPrompt
                $state.ShortcutBar = $win.ShortcutBar
                if ($state.Rows.Count -gt 0) {
                    Update-SshHostDashboardSelection -State $state -NewIndex 0
                }
                $state
            } @($Profiles, $LastHost, $Category, $Filter)
        }
    }

    Describe '护栏' {
        It '非交互终端(重定向)时直接返回 $null, 不触碰 TG 事件循环' {
            $result = & $script:mod {
                Mock -CommandName Test-TmuxTuiInteractive -ModuleName ShellPrompt -MockWith { $false }
                Mock -CommandName Write-Warning -ModuleName ShellPrompt -MockWith { }
                $profiles = @([PSCustomObject]@{ Name = 'deb'; HostName = 'h'; Port = 22; User = ''; IdentityFile = ''; ProxyJump = ''; Provider = ''; Region = ''; Tags = @(); Group = ''; IsLocal = $false; Source = 't' })
                Invoke-SshHostDashboard -Profiles $profiles
            }
            $result | Should -BeNullOrEmpty
        }

        It '主机档案为空时返回 $null(不弹空窗)' {
            $result = & $script:mod { Invoke-SshHostDashboard -Profiles @() }
            $result | Should -BeNullOrEmpty
        }

        It '白名单过滤后没有主机时返回 $null' {
            $result = & $script:mod {
                $profiles = @([PSCustomObject]@{ Name = 'deb'; HostName = 'h'; Port = 22; User = ''; IdentityFile = ''; ProxyJump = ''; Provider = ''; Region = ''; Tags = @(); Group = ''; IsLocal = $false; Source = 't' })
                Invoke-SshHostDashboard -Profiles $profiles -AllowedHosts @('other-host')
            }
            $result | Should -BeNullOrEmpty
        }
    }

    Describe '分类切换(纯本地, 零网络)' {
        It '切换分类只重算本地行, **不发起任何 SSH 探测**' {
            $profiles = @(
                (New-TestProfile -Name 'a1' -Provider 'AWS')
                (New-TestProfile -Name 'a2' -Provider 'AWS')
                (New-TestProfile -Name 'b1' -Provider 'DigitalOcean')
            )
            & $script:mod {
                param($p)
                Mock -CommandName Start-SshHostDetailTask -ModuleName ShellPrompt -MockWith { throw '分类切换绝不允许发起 SSH 探测' }
                Mock -CommandName Invoke-SshCaptureOutput -ModuleName ShellPrompt -MockWith { throw '分类切换绝不允许发起 SSH 探测' }
                $state = & (Get-Module ShellPrompt) {
                    param($pp)
                    $tg = Get-TguiContext
                    $theme = Get-SshHostDashboardTheme -Tgui $tg
                    $s = New-SshHostDashboardState -Profiles $pp -Activity @() -LastHost '' -Category 'All' -Filter '' -Theme $theme -Tgui $tg
                    $s.Rows = @(Get-SshHostDashboardRowList -State $s)
                    $win = New-SshHostDashboardWindow -Rows $s.Rows -Title 'T' -Categories $s.Categories `
                        -ActiveCategory 'All' -SelectedIndex 0 -Theme $theme -InfoText 'x' -WindowWidth 120 -WindowHeight 30
                    $s.Window = $win.Window; $s.ListView = $win.ListView; $s.DetailPanel = $win.DetailPanel
                    $s.CategoryBar = @($win.CategoryBar); $s.InfoLabel = $win.InfoLabel
                    $s.ShortcutBar = $win.ShortcutBar
                    Update-SshHostDashboardSelection -State $s -NewIndex 0
                    $s
                } @($p)
                Set-SshHostDashboardCategory -State $state -Category 'AWS'
                $state.Category | Should -Be 'AWS'
                @($state.Rows).Count | Should -Be 2
                Should -Invoke -CommandName Start-SshHostDetailTask -ModuleName ShellPrompt -Exactly 0
            } @($profiles)
        }

        It '分类清单来自真实档案: All + 实际 Provider + Local + Other' {
            $profiles = @(
                (New-TestProfile -Name 'a1' -Provider 'AWS')
                (New-TestProfile -Name 'b1' -Provider 'DigitalOcean')
                (New-TestProfile -Name 'loc' -IsLocal $true)
                (New-TestProfile -Name 'plain')
            )
            $cats = & $script:mod { param($p) @(Get-SshHostCategoryList -Profiles $p) } @($profiles)
            $cats | Should -Contain 'All'
            $cats | Should -Contain 'AWS'
            $cats | Should -Contain 'DigitalOcean'
            $cats | Should -Contain 'Local'
            $cats | Should -Contain 'Other'
        }
    }

    Describe '键盘热路径(零网络, 立即响应)' {
        It '移动选中**不发起任何 SSH 请求**, 且详情面板立即用本地数据落位' {
            $profiles = @(
                (New-TestProfile -Name 'h1' -User 'alice' -Tags @('prod'))
                (New-TestProfile -Name 'h2' -User 'bob')
            )
            & $script:mod {
                param($p)
                Mock -CommandName Start-SshHostDetailTask -ModuleName ShellPrompt -MockWith { throw '按键路径绝不允许发起 SSH 探测' }
                $state = & (Get-Module ShellPrompt) {
                    param($pp)
                    $tg = Get-TguiContext
                    $theme = Get-SshHostDashboardTheme -Tgui $tg
                    $s = New-SshHostDashboardState -Profiles $pp -Activity @() -LastHost '' -Category 'All' -Filter '' -Theme $theme -Tgui $tg
                    $s.Rows = @(Get-SshHostDashboardRowList -State $s)
                    $win = New-SshHostDashboardWindow -Rows $s.Rows -Title 'T' -Categories $s.Categories `
                        -ActiveCategory 'All' -SelectedIndex 0 -Theme $theme -InfoText 'x' -WindowWidth 120 -WindowHeight 30
                    $s.Window = $win.Window; $s.ListView = $win.ListView; $s.DetailPanel = $win.DetailPanel
                    $s.CategoryBar = @($win.CategoryBar); $s.InfoLabel = $win.InfoLabel
                    $s.ShortcutBar = $win.ShortcutBar
                    Update-SshHostDashboardSelection -State $s -NewIndex 0
                    $s
                } @($p)

                Move-SshHostDashboardSelection -State $state -Delta 1
                $state.SelectedIndex | Should -Be 1
                $state.SelectedHost | Should -Be 'h2'
                # 详情面板: 基础信息**立即**是本地数据, 不等远端
                $state.DetailPanel.Labels['Host'].Text | Should -Be 'h2'
                $state.DetailPanel.Labels['User'].Text | Should -Be 'bob'
                # 远端状态**尚未**到达 => 明确显示"探测中", 绝不提前显示"在线"
                $state.DetailPanel.Labels['Status'].Text | Should -Match '探测中'
                Should -Invoke -CommandName Start-SshHostDetailTask -ModuleName ShellPrompt -Exactly 0
            } @($profiles)
        }

        It '移动选中只重刷旧/新两行(其余行不被标脏)' {
            $profiles = @(1..6 | ForEach-Object { New-TestProfile -Name "h$_" })
            & $script:mod {
                param($p)
                $state = & (Get-Module ShellPrompt) {
                    param($pp)
                    $tg = Get-TguiContext
                    $theme = Get-SshHostDashboardTheme -Tgui $tg
                    $s = New-SshHostDashboardState -Profiles $pp -Activity @() -LastHost '' -Category 'All' -Filter '' -Theme $theme -Tgui $tg
                    $s.Rows = @(Get-SshHostDashboardRowList -State $s)
                    $win = New-SshHostDashboardWindow -Rows $s.Rows -Title 'T' -Categories $s.Categories `
                        -ActiveCategory 'All' -SelectedIndex 0 -Theme $theme -InfoText 'x' -WindowWidth 120 -WindowHeight 30
                    $s.Window = $win.Window; $s.ListView = $win.ListView; $s.DetailPanel = $win.DetailPanel
                    $s.CategoryBar = @($win.CategoryBar); $s.InfoLabel = $win.InfoLabel
                    $s.ShortcutBar = $win.ShortcutBar
                    Update-SshHostDashboardSelection -State $s -NewIndex 0
                    $s
                } @($p)
                # 记录每一行当前的内容指纹, 移动后只有两行应当变化
                $before = @($state.ListView.Slots | ForEach-Object { "$($_.RowIndex)|$($_.Selected)|$($_.Name.Text)" })
                Move-SshHostDashboardSelection -State $state -Delta 1
                $after = @($state.ListView.Slots | ForEach-Object { "$($_.RowIndex)|$($_.Selected)|$($_.Name.Text)" })
                $changed = 0
                for ($i = 0; $i -lt $before.Count; $i++) {
                    if ($before[$i] -ne $after[$i]) { $changed++ }
                }
                $changed | Should -Be 2
            } @($profiles)
        }
    }

    Describe '旧请求不覆盖新选择(Goal 七 硬指标)' {
        It '迟到的旧探测结果不得回填当前选中主机的详情' {
            $profiles = @(
                (New-TestProfile -Name 'h1')
                (New-TestProfile -Name 'h2')
            )
            & $script:mod {
                param($p)
                $state = & (Get-Module ShellPrompt) {
                    param($pp)
                    $tg = Get-TguiContext
                    $theme = Get-SshHostDashboardTheme -Tgui $tg
                    $s = New-SshHostDashboardState -Profiles $pp -Activity @() -LastHost '' -Category 'All' -Filter '' -Theme $theme -Tgui $tg
                    $s.Rows = @(Get-SshHostDashboardRowList -State $s)
                    $win = New-SshHostDashboardWindow -Rows $s.Rows -Title 'T' -Categories $s.Categories `
                        -ActiveCategory 'All' -SelectedIndex 0 -Theme $theme -InfoText 'x' -WindowWidth 120 -WindowHeight 30
                    $s.Window = $win.Window; $s.ListView = $win.ListView; $s.DetailPanel = $win.DetailPanel
                    $s.CategoryBar = @($win.CategoryBar); $s.InfoLabel = $win.InfoLabel
                    $s.ShortcutBar = $win.ShortcutBar
                    Update-SshHostDashboardSelection -State $s -NewIndex 0
                    $s
                } @($p)

                # 选到 h1, 记下它的请求标识
                Update-SshHostDashboardSelection -State $state -NewIndex 0
                $staleProbe = [PSCustomObject]@{ HostName = 'h1'; RequestId = $state.ActiveRequestId }
                # 随后用户切到 h2 —— 请求标识随之改变
                Update-SshHostDashboardSelection -State $state -NewIndex 1
                $state.ActiveRequestId | Should -Not -Be $staleProbe.RequestId

                # h1 的迟到结果回来: 不得把 h2 的详情面板改成 h1 的
                $state.DetailPanel.Labels['Host'].Text | Should -Be 'h2'
                $staleDetail = [PSCustomObject]@{
                    Status = 'Online'; StatusText = '在线'; ErrorCode = ''; ErrorMessage = ''
                    RemoteHostname = 'stale-host'; ElapsedMs = 12
                }
                Set-SshHostDashboardProbeResult -State $state -Probe $staleProbe -Detail $staleDetail
                # 详情面板仍然是 h2(请求标识不匹配 => 不回填)
                $state.DetailPanel.Labels['Host'].Text | Should -Be 'h2'
                $state.DetailPanel.Labels['Status'].Text | Should -Not -Match '在线'
            } @($profiles)
        }

        It '请求标识匹配的探测结果**要**回填详情面板' {
            $profiles = @((New-TestProfile -Name 'h1'))
            & $script:mod {
                param($p)
                $state = & (Get-Module ShellPrompt) {
                    param($pp)
                    $tg = Get-TguiContext
                    $theme = Get-SshHostDashboardTheme -Tgui $tg
                    $s = New-SshHostDashboardState -Profiles $pp -Activity @() -LastHost '' -Category 'All' -Filter '' -Theme $theme -Tgui $tg
                    $s.Rows = @(Get-SshHostDashboardRowList -State $s)
                    $win = New-SshHostDashboardWindow -Rows $s.Rows -Title 'T' -Categories $s.Categories `
                        -ActiveCategory 'All' -SelectedIndex 0 -Theme $theme -InfoText 'x' -WindowWidth 120 -WindowHeight 30
                    $s.Window = $win.Window; $s.ListView = $win.ListView; $s.DetailPanel = $win.DetailPanel
                    $s.CategoryBar = @($win.CategoryBar); $s.InfoLabel = $win.InfoLabel
                    $s.ShortcutBar = $win.ShortcutBar
                    Update-SshHostDashboardSelection -State $s -NewIndex 0
                    $s
                } @($p)

                Update-SshHostDashboardSelection -State $state -NewIndex 0
                $probe = [PSCustomObject]@{ HostName = 'h1'; RequestId = $state.ActiveRequestId }
                $detail = [PSCustomObject]@{
                    Status = 'Online'; StatusText = '在线'; ErrorCode = ''; ErrorMessage = ''
                    RemoteHostname = 'real-host'; ElapsedMs = 42
                }
                Set-SshHostDashboardProbeResult -State $state -Probe $probe -Detail $detail
                $state.DetailPanel.Labels['Status'].Text | Should -Match '在线'
                # 缓存建立 => 回到该主机时不需要重复查询
                $state.DetailByHost.ContainsKey('h1') | Should -BeTrue
            } @($profiles)
        }
    }

    Describe '键位语义(与底栏文案一致)' {
        It '方向键 / Enter / / / Tab / ←→ / Esc 的处理结果符合约定' {
            $profiles = @(
                (New-TestProfile -Name 'h1' -Provider 'AWS')
                (New-TestProfile -Name 'h2' -Provider 'AWS')
                (New-TestProfile -Name 'h3' -Provider 'DigitalOcean')
            )
            & $script:mod {
                param($p)
                $tg = Get-TguiContext
                $state = & (Get-Module ShellPrompt) {
                    param($pp)
                    $t = Get-TguiContext
                    $theme = Get-SshHostDashboardTheme -Tgui $t
                    $s = New-SshHostDashboardState -Profiles $pp -Activity @() -LastHost '' -Category 'All' -Filter '' -Theme $theme -Tgui $t
                    $s.Rows = @(Get-SshHostDashboardRowList -State $s)
                    $win = New-SshHostDashboardWindow -Rows $s.Rows -Title 'T' -Categories $s.Categories `
                        -ActiveCategory 'All' -SelectedIndex 0 -Theme $theme -InfoText 'x' -WindowWidth 120 -WindowHeight 30
                    $s.Window = $win.Window; $s.ListView = $win.ListView; $s.DetailPanel = $win.DetailPanel
                    $s.CategoryBar = @($win.CategoryBar); $s.InfoLabel = $win.InfoLabel
                    $s.SearchField = $win.SearchField; $s.SearchPrompt = $win.SearchPrompt
                    $s.ShortcutBar = $win.ShortcutBar
                    Update-SshHostDashboardSelection -State $s -NewIndex 0
                    $s
                } @($p)

                $keyT = $tg.Types.Key
                $down = $keyT.GetProperty('CursorDown').GetValue($null)
                $up = $keyT.GetProperty('CursorUp').GetValue($null)
                $right = $keyT.GetProperty('CursorRight').GetValue($null)
                $esc = $keyT.GetProperty('Esc').GetValue($null)
                $tab = $keyT.GetProperty('Tab').GetValue($null)
                $enter = $keyT.GetProperty('Enter').GetValue($null)
                $slash = $keyT.GetConstructors() |
                    Where-Object { $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'Char' } |
                    Select-Object -First 1
                $slashKey = $slash.Invoke(@([char]'/'))

                # ↓ 移动选中
                (Invoke-SshHostDashboardKey -State $state -Key $down) | Should -BeTrue
                $state.SelectedIndex | Should -Be 1
                # ↑ 回到上一台
                (Invoke-SshHostDashboardKey -State $state -Key $up) | Should -BeTrue
                $state.SelectedIndex | Should -Be 0
                # → 切到下一个分类
                (Invoke-SshHostDashboardKey -State $state -Key $right) | Should -BeTrue
                $state.Category | Should -Be 'AWS'
                # / 进入搜索态
                (Invoke-SshHostDashboardKey -State $state -Key $slashKey) | Should -BeTrue
                $state.FocusArea | Should -Be 'Search'
                $state.SearchField.Visible | Should -BeTrue
                # Tab 从搜索态回到列表
                # 搜索态下 Enter / Tab 由**搜索框自己的处理器**接管 —— 通用 KeyDown
                # 必须返回 $false, 否则会和搜索框处理器双触发(按一次走两遍)。
                (Invoke-SshHostDashboardKey -State $state -Key $tab) | Should -BeFalse
                (Invoke-SshHostDashboardKey -State $state -Key $enter) | Should -BeFalse
                # 回到列表焦点后再验证 Enter / Esc
                Set-SshHostDashboardFocusArea -State $state -Area 'List'
                $state.FocusArea | Should -Be 'List'
                # Enter 选中当前主机 => 请求连接
                (Invoke-SshHostDashboardKey -State $state -Key $enter) | Should -BeTrue
                # 动作值经 global 传给事件循环(PSAvoidGlobalVars 用 Get-Variable 读取,
                # 避免在测试里写 $global: 变量表达式)
                (Get-Variable -Name 'TguiDashAction' -Scope Global -ValueOnly -ErrorAction SilentlyContinue) |
                    Should -Be 'Connect'
                # Esc => 退出
                (Invoke-SshHostDashboardKey -State $state -Key $esc) | Should -BeTrue
                (Get-Variable -Name 'TguiDashAction' -Scope Global -ValueOnly -ErrorAction SilentlyContinue) |
                    Should -Be 'Quit'
            } @($profiles)
        }
    }

    Describe '分发器契约' {
        It 'Show-SshHostDashboard 返回 .Value = 主机名(与 Show-HostSelector 契约一致)' {
            $result = & $script:mod {
                Mock -CommandName Get-SshHostProfile -ModuleName ShellPrompt -MockWith { @() }
                Mock -CommandName Get-SshHostActivity -ModuleName ShellPrompt -MockWith { @() }
                Mock -CommandName Invoke-SshHostDashboard -ModuleName ShellPrompt -MockWith {
                    [PSCustomObject]@{ HostName = 'deb'; Profile = $null; Row = $null }
                }
                Show-SshHostDashboard -Hosts @('deb')
            }
            $result | Should -Not -BeNullOrEmpty
            $result.Value | Should -Be 'deb'
            $result.Host | Should -Be 'deb'
            $result.Disabled | Should -BeFalse
        }

        It '仪表盘返回 $null 时分发器透传 $null' {
            $result = & $script:mod {
                Mock -CommandName Get-SshHostProfile -ModuleName ShellPrompt -MockWith { @() }
                Mock -CommandName Get-SshHostActivity -ModuleName ShellPrompt -MockWith { @() }
                Mock -CommandName Invoke-SshHostDashboard -ModuleName ShellPrompt -MockWith { $null }
                Show-SshHostDashboard -Hosts @('deb')
            }
            $result | Should -BeNullOrEmpty
        }
    }
}
