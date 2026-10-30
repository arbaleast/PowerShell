<#
.SYNOPSIS
    ShellPrompt 模块 Pester 测试套件 (由 Pester v3 旧断言语法最小迁移而来)
.DESCRIPTION
    历史沿革:
    1) 本文件源自 `git show HEAD:ShellPrompt/Tests/ShellPrompt.Tests.ps1` (1102 行),
       采用 Pester v3 旧断言语法 (`Should Be` / `Should Not Be` / `Should Match` ...)。
    2) 本机安装的是 Pester 6.2.0, 实测全部旧语法在运行时抛
       `ParameterBindingException: Parameter set cannot be resolved using the specified
       named parameters.` (12/12 旧写法全部失败, 仅新写法 `Should -Be` 通过),
       因此必须把旧语法改写为 Pester v5+ 的 `Should -Be` / `Should -Not -Be` 形式。
    3) 2026-10-18 控制台 UI 单轨化 (仅保留 PSTui GridView 主轨, 自研 ANSI 降级轨已移除),
       原文件中针对已删除函数 (Test-FilterCharacter / Get-FilteredItems /
       Update-FilterString / New-StatusBadge / Format-StatusBadge / New-MenuItem /
       Write-MenuItem / New-DynamicHelpPanel / Get-SessionActionHelp / New-AnsiLayout /
       Add-MainLine / Set-FooterLine / Write-AnsiLine / Update-InputBuffer /
       Test-InputValidation / Send-MenuKey / ConvertTo-CsiArrowKey) 的用例已按
       "单轨 GridView 等价实现" 重写, 而不是简单删除。
    4) 文件末尾追加 "单轨 GridView 契约" 断言组, 覆盖:
       Backend 恒为 GridView / Assert-ConsoleUiReady 抛错与放行 /
       三个分发器无 -Backend 参数 / 已删除降级轨函数在模块作用域不存在 /
       已删除源文件不在模块目录内 (基于 ModuleBase, 不依赖仓库工作区路径)。
#>

# 模块路径：相对于测试目录的父目录
$moduleRoot = (Resolve-Path "$PSScriptRoot\..").Path
$manifestPath = Join-Path $moduleRoot 'ShellPrompt.psd1'

BeforeAll {
    $script:manifestPath = Join-Path (Resolve-Path "$PSScriptRoot\..").Path 'ShellPrompt.psd1'
    Import-Module $script:manifestPath -Force -ErrorAction Stop
    $script:mod = Get-Module ShellPrompt
}

Describe 'Module Import' {

    It '应能成功导入模块' {
        { Import-Module $script:manifestPath -Force -ErrorAction Stop } | Should -Not -Throw
    }

    It '导入后模块应可用' {
        $module = Get-Module ShellPrompt
        $module | Should -Not -BeNullOrEmpty
        $module.Name | Should -Be 'ShellPrompt'
    }
}

Describe 'Command Export' {

    It '应导出 Invoke-Reload' {
        Get-Command -Module ShellPrompt -Name 'Invoke-Reload' -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It '应导出 Show-UserScoopLogo' {
        Get-Command -Module ShellPrompt -Name 'Show-UserScoopLogo' -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It '应导出 Start-TmuxSession' {
        Get-Command -Module ShellPrompt -Name 'Start-TmuxSession' -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It '应导出 Copy-SshPublicKey' {
        Get-Command -Module ShellPrompt -Name 'Copy-SshPublicKey' -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It '不应导出旧命令 reload' {
        Get-Command -Module ShellPrompt -Name 'reload' -ErrorAction SilentlyContinue |
            Should -BeNullOrEmpty
    }

    It '不应导出内部辅助函数' {
        $privateNames = @(
            'Get-CachedConfig', 'Get-SshConfigHosts', 'Get-TmuxAvailability',
            'Get-TmuxSessions', 'Invoke-SshCommand',
            'Invoke-SshCaptureOutput', 'New-RandomSessionName', 'Reset-TerminalMode',
            'Get-SshArgs', 'Connect-TmuxSession',
            'New-TmuxSession', 'Remove-TmuxSession', 'ConvertTo-SshEscapedString',
            'Test-SshHostName', 'Save-OriginalTerminalState'
        )
        $exported = @(Get-Command -Module ShellPrompt | Select-Object -ExpandProperty Name)
        foreach ($name in $privateNames) {
            $exported | Should -Not -Contain $name
        }
    }

    It '不应导出单轨化后新增的内部实现函数' {
        $privateNames = @(
            'Invoke-GridViewPrompt', 'Invoke-GridViewHostSelector',
            'Invoke-GridViewSessionManager', 'Invoke-GridViewSessionList',
            'Get-GridViewColumnPlan', 'Get-GridViewHostRow', 'Get-GridViewManagerRow',
            'ConvertTo-GridViewPlainText', 'Get-GridViewRenderParam',
            'Get-TmuxSessionGridRow', 'Get-TmuxSessionStateText', 'Get-TmuxSessionSummary',
            'Restore-GridViewSelection', 'ConvertTo-TmuxRefreshSelection',
            'Get-TmuxRefreshedSession', 'Get-ConsoleUiBackend', 'Assert-ConsoleUiReady',
            'Invoke-TmuxAttach', 'Invoke-TmuxSessionListView', 'ConvertTo-TmuxSessionSelection'
        )
        $exported = @(Get-Command -Module ShellPrompt | Select-Object -ExpandProperty Name)
        foreach ($name in $privateNames) {
            $exported | Should -Not -Contain $name
        }
    }
}

Describe 'Verb-Noun Compliance' {

    It '所有导出命令的动词应在 Get-Verb 批准列表中' {
        $approvedVerbs = @(Get-Verb | Select-Object -ExpandProperty Verb)
        $exported = @(Get-Command -Module ShellPrompt)
        foreach ($cmd in $exported) {
            $verb = $cmd.Name -split '-' | Select-Object -First 1
            $approvedVerbs | Should -Contain $verb
        }
    }
}

Describe 'Config Access' {

    It '$script:Config 应包含所有域' {
        $config = & $script:mod { $script:Config }
        $config | Should -Not -BeNullOrEmpty
        $config.Contains('Colors') | Should -BeTrue
        $config.Contains('Keys') | Should -BeFalse  # 2026-10-29 清理: 无消费方, Keys 域已移除
        $config.Contains('Paths') | Should -BeTrue
        $config.Contains('SSH') | Should -BeTrue
        $config.Contains('UI') | Should -BeTrue
    }

    It 'UI 域应保留 GridView 行为配置' {
        $keys = & $script:mod { @($script:Config.UI.Keys) }
        $keys | Should -Contain 'GridViewFocus'
        $keys | Should -Contain 'GridViewFullScreen'
    }

    It 'UI 域不应再提供 Backend 后端选择项' {
        $keys = & $script:mod { @($script:Config.UI.Keys) }
        $keys | Should -Not -Contain 'Backend'
    }
}

Describe 'ConvertTo-SshEscapedString' {

    It '应正确处理普通字符' {
        $result = & $script:mod { ConvertTo-SshEscapedString -Value 'hello' }
        $result | Should -Be 'hello'
    }

    It '应转义单引号' {
        $result = & $script:mod { ConvertTo-SshEscapedString -Value "it's a test" }
        $result | Should -Be "it'\''s a test"
    }

    It '应通过管道处理输入' {
        $result = "don't stop" | & $script:mod { $input | ConvertTo-SshEscapedString }
        $result | Should -Be "don'\''t stop"
    }
}

Describe 'Test-SshHostName' {

    It '合法主机名应返回 $true' {
        & $script:mod { Test-SshHostName -HostName 'example.com' } | Should -BeTrue
    }

    It '带短横线的合法主机名应返回 $true' {
        & $script:mod { Test-SshHostName -HostName 'my-server-01' } | Should -BeTrue
    }

    It '含空格的主机名应返回 $false' {
        & $script:mod { Test-SshHostName -HostName 'bad host' } | Should -BeFalse
    }

    It '含管道符的主机名应返回 $false' {
        & $script:mod { Test-SshHostName -HostName 'host|danger' } | Should -BeFalse
    }
}

Describe 'P2-2 New-WelcomeBanner (纯函数)' {

    It '默认应返回 10 行' {
        $lines = & $script:mod { New-WelcomeBanner -Title 'TEST' }
        $lines.Count | Should -Be 10
    }

    It '首行与末行应为空行' {
        $lines = & $script:mod { New-WelcomeBanner -Title 'TEST' }
        $lines[0] | Should -Be ''
        $lines[9] | Should -Be ''
    }

    It 'Title 应出现在第 2 行' {
        $lines = & $script:mod { New-WelcomeBanner -Title 'MYTEST' }
        $lines[1] | Should -Match 'MYTEST'
    }

    It 'Subtitle 应出现在第 5 行' {
        $lines = & $script:mod { New-WelcomeBanner -Subtitle 'HELLOTEST' }
        $lines[4] | Should -Match 'HELLOTEST'
    }

    It 'Width=60 时 HLine 应有 56 个 =' {
        $lines = & $script:mod { New-WelcomeBanner -Title 'X' -Width 60 }
        # 第 9 行形如 '  +<hLine>---'
        $line9 = $lines[8]
        $eqCount = ([regex]::Matches($line9, '=')).Count
        $eqCount | Should -Be 56
    }

    It 'Width 小于 40 应抛 ValidationRange 错误' {
        $threw = $false
        try {
            & $script:mod { New-WelcomeBanner -Title 'X' -Width 10 }
        } catch {
            $threw = $true
        }
        $threw | Should -BeTrue
    }
}

Describe 'P2-2 Get-RandomQuote' {

    It '空 QuotesPath 应返回 Fallback' {
        $q = & $script:mod { Get-RandomQuote -QuotesPath '' -Fallback 'FB' }
        $q | Should -Be 'FB'
    }

    It '不存在的文件应返回 Fallback' {
        $q = & $script:mod {
            Get-RandomQuote -QuotesPath 'C:\nonexistent\file.txt' -Fallback 'FB'
        }
        $q | Should -Be 'FB'
    }

    It '存在且非空的文件应返回非空 Trim 后的语录' {
        $tmp = [System.IO.Path]::GetTempFileName()
        try {
            Set-Content -LiteralPath $tmp -Value "line one`nline two`nline three" -Encoding UTF8
            $q = & $script:mod {
                param($p) Get-RandomQuote -QuotesPath $p -Fallback 'FB'
            } -p $tmp
            $q | Should -Match 'line (one|two|three)'
        } finally {
            Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
        }
    }

    It '多文件调用应使用 mtime 缓存' {
        $tmp = [System.IO.Path]::GetTempFileName()
        try {
            Set-Content -LiteralPath $tmp -Value 'cached' -Encoding UTF8
            $q1 = & $script:mod { param($p) Get-RandomQuote -QuotesPath $p } -p $tmp
            $q2 = & $script:mod { param($p) Get-RandomQuote -QuotesPath $p } -p $tmp
            $q1 | Should -Be $q2
            # 验证 cache 存在
            $hasCache = & $script:mod {
                param($p) $script:QuotesCache -ne $null -and $script:QuotesCache.Path -eq $p
            } -p $tmp
            $hasCache | Should -BeTrue
        } finally {
            Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Resolve-ColorTable (颜色语义解析)' {

    It '应返回请求的语义键' {
        $table = & $script:mod { Resolve-ColorTable -Name 'Primary', 'Accent', 'Rst' }
        $table.Keys | Should -Contain 'Primary'
        $table.Keys | Should -Contain 'Accent'
        $table.Keys | Should -Contain 'Rst'
    }

    It '调用方覆盖值优先于配置层' {
        $table = & $script:mod {
            Resolve-ColorTable -Name 'Primary' -Colors @{ Primary = 'ZZ-OVERRIDE' }
        }
        $table.Primary | Should -Be 'ZZ-OVERRIDE'
    }

    It 'Border 语义键应跟随 Primary' {
        $table = & $script:mod {
            Resolve-ColorTable -Name 'Primary', 'Border' -Colors @{ Primary = 'ZZ-OWN' }
        }
        $table.Border | Should -Be 'ZZ-OWN'
    }

    It '未知语义键应解析为空串而不抛错' {
        $table = & $script:mod { Resolve-ColorTable -Name 'NotARealSemanticKey' }
        $table.NotARealSemanticKey | Should -Be ''
    }
}

Describe 'Get-TmuxSessionStateText (状态文案单一事实来源)' {

    It 'attached 应映射为 ● 已附着' {
        $text = & $script:mod { Get-TmuxSessionStateText -Status 'attached' }
        $text | Should -Be '● 已附着'
    }

    It 'detached 应映射为 ○ 已分离' {
        $text = & $script:mod { Get-TmuxSessionStateText -Status 'detached' }
        $text | Should -Be '○ 已分离'
    }

    It '空状态应映射为 ○ 已分离' {
        $text = & $script:mod { Get-TmuxSessionStateText -Status '' }
        $text | Should -Be '○ 已分离'
    }

    It '未知状态应映射为 ○ 已分离' {
        $text = & $script:mod { Get-TmuxSessionStateText -Status 'weird-state' }
        $text | Should -Be '○ 已分离'
    }
}

Describe 'Get-TmuxSessionSummary (会话计数汇总)' {

    It '空会话数组应得到全 0 计数' {
        $s = & $script:mod { Get-TmuxSessionSummary -Sessions @() }
        $s.Total | Should -Be 0
        $s.Attached | Should -Be 0
        $s.Detached | Should -Be 0
    }

    It 'attached 与 detached 应分别计数' {
        $s = & $script:mod {
            Get-TmuxSessionSummary -Sessions @(
                [PSCustomObject]@{ Name = 'a'; Status = 'attached' }
                [PSCustomObject]@{ Name = 'b'; Status = 'detached' }
                [PSCustomObject]@{ Name = 'c'; Status = 'detached' }
            )
        }
        $s.Total | Should -Be 3
        $s.Attached | Should -Be 1
        $s.Detached | Should -Be 2
    }

    It '已附着数与已分离数之和应等于总数' {
        $s = & $script:mod {
            Get-TmuxSessionSummary -Sessions @(
                [PSCustomObject]@{ Name = 'a'; Status = 'attached' }
                [PSCustomObject]@{ Name = 'b'; Status = 'unknown' }
            )
        }
        ($s.Attached + $s.Detached) | Should -Be $s.Total
    }

    It 'TitleSuffix 应符合统一计数口径' {
        $s = & $script:mod {
            Get-TmuxSessionSummary -Sessions @(
                [PSCustomObject]@{ Name = 'a'; Status = 'attached' }
                [PSCustomObject]@{ Name = 'b'; Status = 'detached' }
            )
        }
        $s.TitleSuffix | Should -Be '会话 2 附 1 / 分 1'
    }
}

Describe 'Get-GridViewHostRow (主机选择表格行)' {

    It '应按输入顺序生成行' {
        $rows = & $script:mod {
            Get-GridViewHostRow -Hosts @('debian', 'ubuntu')
        }
        $rows.Count | Should -Be 2
        $rows[0].Host | Should -Be 'debian'
        $rows[1].Host | Should -Be 'ubuntu'
    }

    It '列属性集应不再包含 Desc(2026-10-19 P0 删除冗余列)' {
        # 旧 Desc 列内容'SSH 远程主机'与 Host 列重复, 已随 P0 改进移除。
        # 锁定回归: 任何让 Desc 字段再次出现的改动都视为破坏本契约。
        $rows = & $script:mod { Get-GridViewHostRow -Hosts @('debian') }
        $rows[0].PSObject.Properties.Name | Should -Not -Contain 'Desc'
    }

    It 'Value 应等于主机名' {
        $rows = & $script:mod { Get-GridViewHostRow -Hosts @('debian') }
        $rows[0].Value | Should -Be 'debian'
    }

    It 'LastHost 应被置顶' {
        $rows = & $script:mod {
            Get-GridViewHostRow -Hosts @('debian', 'ubuntu', 'arch') -LastHost 'ubuntu'
        }
        $rows[0].Host | Should -Be 'ubuntu'
    }

    It 'LastHost 行应标注 ● last(兼容 ★ 最近变体)' {
        $rows = & $script:mod {
            Get-GridViewHostRow -Hosts @('debian', 'ubuntu') -LastHost 'ubuntu'
        }
        $rows[0].State | Should -Match '● last|★ 最近'
    }

    It '非 LastHost 行的 State 应为空' {
        $rows = & $script:mod {
            Get-GridViewHostRow -Hosts @('debian', 'ubuntu') -LastHost 'ubuntu'
        }
        $rows[1].State | Should -Be ''
    }

    It 'Disabled 应恒为 false' {
        $rows = & $script:mod { Get-GridViewHostRow -Hosts @('debian') }
        $rows[0].Disabled | Should -BeFalse
    }
}

Describe 'Get-GridViewManagerRow (tmux 全局操作菜单表格行)' {

    # 方案 A: 附着不再是菜单动作, 全局操作菜单只含 删除/创建/直连/刷新
    It '无会话时只应保留 创建/直连/刷新 三行' {
        $rows = & $script:mod { Get-GridViewManagerRow -HasSessions $false }
        $rows.Count | Should -Be 3
        $rows.Value | Should -Not -Contain 'Attach'
        $rows.Value | Should -Not -Contain 'Remove'
        $rows.Value | Should -Contain 'New'
    }

    It '有会话时应包含 删除/创建/直连/刷新 四行, 且不再提供附着项' {
        $rows = & $script:mod { Get-GridViewManagerRow -HasSessions $true }
        $rows.Count | Should -Be 4
        $rows.Value | Should -Not -Contain 'Attach'
        $rows.Value | Should -Contain 'Remove'
        $rows.Value | Should -Contain 'New'
        $rows.Value | Should -Contain 'Ssh'
        $rows.Value | Should -Contain 'Refresh'
        # 2026-10-19 P0: 锁定 Desc 列不再出现在 Manager 行对象上
        $rows[0].PSObject.Properties.Name | Should -Not -Contain 'Desc'
    }

    It '防呆语序: 创建置顶, 删除垫底(高安全动作拿默认焦点)' {
        # 2026-10-30 防呆修复: 默认 Focus='Table' 时第 0 行吃 Enter 直达,
        # 高危的删除动作绝不能排第 0 行, 必须垫底。
        $rows = & $script:mod { Get-GridViewManagerRow -HasSessions $true }
        $rows[0].Value | Should -Be 'New'
        $rows[1].Value | Should -Be 'Refresh'
        $rows[2].Value | Should -Be 'Ssh'
        $rows[3].Value | Should -Be 'Remove'
    }

    It '非删除动作的 State 应为同构中性徽章(消除 State 列空洞)' {
        # 2026-10-30: New/Refresh 原先是空串, 表格 State 列大段留白;
        # 改为与 '⚠ 危险' 同构的「符号 + 两汉字」纯文本徽章(不带 ANSI)。
        $rows = & $script:mod { Get-GridViewManagerRow -HasSessions $true }
        $new = @($rows | Where-Object { $_.Value -eq 'New' })[0]
        $refresh = @($rows | Where-Object { $_.Value -eq 'Refresh' })[0]
        $new.State | Should -Be '✓ 推荐'
        $refresh.State | Should -Be '⟳ 手动'
        $new.State | Should -Not -Match ([regex]::Escape([char]27))
        $refresh.State | Should -Not -Match ([regex]::Escape([char]27))
    }

    It '删除动作应以 ⚠ 危险 标注危险语义' {
        $rows = & $script:mod { Get-GridViewManagerRow -HasSessions $true }
        $remove = @($rows | Where-Object { $_.Value -eq 'Remove' })[0]
        # P1.3: 危险文字现在包裹 Colors.Danger ANSI 码(已含 ESC), 用 -Match 兼容
        $remove.State | Should -Match '⚠ 危险'
        $remove.State | Should -Match '\[38;2;220;90;90m'
    }

    It '直连动作应以 ⚠ 备选 标注' {
        $rows = & $script:mod { Get-GridViewManagerRow -HasSessions $true }
        $ssh = @($rows | Where-Object { $_.Value -eq 'Ssh' })[0]
        # P1.3: 备选文字现在包裹 Colors.Warning ANSI 码, 用 -Match 兼容
        $ssh.State | Should -Match '⚠ 备选'
        $ssh.State | Should -Match '\[38;2;220;180;80m'
    }
}

Describe 'Get-GridViewRenderParam (渲染参数装配)' {

    It '默认应装配单选模式且不带 FullScreen' {
        # 2026-10-30: GridViewFullScreen 默认 $false, 轻量菜单不再铺满全屏。
        $params = & $script:mod { Get-GridViewRenderParam -Title 'TMUX 全局操作' }
        $params | Should -BeOfType [hashtable]
        $params['Title'] | Should -Be 'TMUX 全局操作'
        $params['OutputMode'] | Should -Be 'Single'
        $params['Focus'] | Should -Be 'Table'
        $params.ContainsKey('FullScreen') | Should -BeFalse
    }

    It '配置为全屏时应装配 FullScreen 开关' {
        $params = & $script:mod {
            $original = $script:Config.UI.GridViewFullScreen
            try {
                $script:Config.UI.GridViewFullScreen = $true
                Get-GridViewRenderParam -Title 'T'
            } finally {
                $script:Config.UI.GridViewFullScreen = $original
            }
        }
        $params['FullScreen'] | Should -BeTrue
    }
}

Describe 'ConvertTo-GridViewPlainText (送入 Terminal.Gui 前的 ANSI 净化)' {

    # 2026-10-30 修复: TG TableView 不解析单元格内联 ANSI 且转义字节会干扰
    # Wcwidth 宽字符列宽计算, 因此行数据送入 Out-ConsoleGridView 前必须净化。
    It '应剥离非键列 string 属性里的 SGR 序列' {
        $rows = & $script:mod {
            $esc = [char]27
            ConvertTo-GridViewPlainText -Rows @(
                [PSCustomObject]@{
                    Action   = '删除 tmux 会话'
                    State    = "$esc[38;2;220;90;90m⚠ 危险$esc[0m"
                    Disabled = $false
                    Value    = 'Remove'
                }
            ) -KeyColumn 'Action'
        }
        $rows[0].State | Should -Be '⚠ 危险'
    }

    It '键列原样保留(隐藏字段回填依赖键列匹配)' {
        $rows = & $script:mod {
            $esc = [char]27
            ConvertTo-GridViewPlainText -Rows @(
                [PSCustomObject]@{
                    Action   = "$esc[32m染色键$esc[0m"
                    State    = ''
                    Disabled = $false
                    Value    = 'Remove'
                }
            ) -KeyColumn 'Action'
        }
        $rows[0].Action | Should -Be ("$([char]27)[32m染色键$([char]27)[0m")
    }

    It '非 string 属性与空串保持原样' {
        $rows = & $script:mod {
            ConvertTo-GridViewPlainText -Rows @(
                [PSCustomObject]@{
                    Action   = '创建新 tmux 会话'
                    State    = ''
                    Disabled = $false
                    Value    = 'New'
                }
            ) -KeyColumn 'Action'
        }
        $rows[0].State | Should -Be ''
        $rows[0].Disabled | Should -BeFalse
        $rows[0].Value | Should -Be 'New'
    }

    It '无 ANSI 的行集合经处理后无残留 ESC 字节' {
        $rows = & $script:mod {
            ConvertTo-GridViewPlainText -Rows @(
                [PSCustomObject]@{
                    Action   = '刷新会话列表'
                    State    = '⟳ 手动'
                    Disabled = $false
                    Value    = 'Refresh'
                }
            ) -KeyColumn 'Action'
        }
        # 输出数组不允许引入任何 ESC 控制字符
        @($rows | ForEach-Object { $_.PSObject.Properties.Value }) |
            ForEach-Object { $_ | Should -Not -Match ([regex]::Escape([char]27)) }
    }
}

Describe 'Get-TmuxSessionGridRow (会话列表表格行)' {

    It '应按会话顺序生成编号' {
        $rows = & $script:mod {
            Get-TmuxSessionGridRow -Sessions @(
                [PSCustomObject]@{ Name = 'a'; Status = 'attached' }
                [PSCustomObject]@{ Name = 'b'; Status = 'detached' }
            )
        }
        $rows.Count | Should -Be 2
        $rows[0].No | Should -Be '01'
        $rows[1].No | Should -Be '02'
    }

    It 'Session 与 Value 应为纯会话名' {
        $rows = & $script:mod {
            Get-TmuxSessionGridRow -Sessions @([PSCustomObject]@{ Name = 'btop'; Status = 'detached' })
        }
        $rows[0].Session | Should -Be 'btop'
        $rows[0].Value | Should -Be 'btop'
    }

    It 'ShowStateBadge 关闭时 State 应为空' {
        $rows = & $script:mod {
            Get-TmuxSessionGridRow -Sessions @([PSCustomObject]@{ Name = 'a'; Status = 'attached' })
        }
        $rows[0].State | Should -Be ''
    }

    It 'ShowStateBadge 开启时 State 应为统一状态文案' {
        $rows = & $script:mod {
            Get-TmuxSessionGridRow -Sessions @(
                [PSCustomObject]@{ Name = 'a'; Status = 'attached' }
                [PSCustomObject]@{ Name = 'b'; Status = 'detached' }
            ) -ShowStateBadge
        }
        $rows[0].State | Should -Be '● 已附着'
        $rows[1].State | Should -Be '○ 已分离'
    }

    It 'AllowRefresh 关闭时不应追加刷新行' {
        $rows = & $script:mod {
            Get-TmuxSessionGridRow -Sessions @([PSCustomObject]@{ Name = 'a'; Status = 'detached' })
        }
        $rows.Count | Should -Be 1
    }

    It 'AllowRefresh 开启时应追加刷新行且使用哨兵值' {
        $rows = & $script:mod {
            Get-TmuxSessionGridRow -Sessions @([PSCustomObject]@{ Name = 'a'; Status = 'detached' }) -AllowRefresh
        }
        # 哨兵值定义在模块作用域, 需从模块作用域读取后再断言
        $signal = & $script:mod { $script:TmuxRefreshSignalValue }
        $rows.Count | Should -Be 2
        $rows[1].Session | Should -Be '⟳ 刷新会话列表'
        $rows[1].Value | Should -Be $signal
    }

    It 'Windows 列应承载窗口数量, 缺失字段时置空(不伪装成 0/1)' {
        $rows = & $script:mod {
            Get-TmuxSessionGridRow -Sessions @(
                [PSCustomObject]@{ Name = 'a'; Status = 'attached'; Windows = 3 }
                [PSCustomObject]@{ Name = 'b'; Status = 'detached' }
            )
        }
        $rows[0].Windows | Should -Be '3'
        $rows[1].Windows | Should -BeNullOrEmpty
        # 刷新行同样携带 Windows 字段, 保证整表行形状一致
        $refreshRows = & $script:mod {
            Get-TmuxSessionGridRow -Sessions @([PSCustomObject]@{ Name = 'a'; Status = 'detached'; Windows = 1 }) -AllowRefresh
        }
        $refreshRows[0].Windows | Should -Be '1'
        $refreshRows[1].Windows | Should -Be ''
    }
}

Describe 'Get-GridViewColumnPlan (列裁剪计划)' {

    It '应优先选 Session 作为键列' {
        $plan = & $script:mod {
            Get-GridViewColumnPlan -Rows @(
                [PSCustomObject]@{ No = '01'; Session = 'a'; Status = 'attached' }
            ) -HiddenColumns @{ Status = '' }
        }
        $plan.KeyColumn | Should -Be 'Session'
    }

    It '应优先选 Host 作为键列' {
        $plan = & $script:mod {
            Get-GridViewColumnPlan -Rows @(
                [PSCustomObject]@{ Host = 'debian'; Desc = 'x' }
            ) -HiddenColumns @{ Value = '' }
        }
        $plan.KeyColumn | Should -Be 'Host'
    }

    It '无可用自然键列时应回退到 _RowIdx' {
        $plan = & $script:mod {
            Get-GridViewColumnPlan -Rows @(
                [PSCustomObject]@{ Foo = 'a' }
                [PSCustomObject]@{ Foo = 'b' }
            )
        }
        $plan.KeyColumn | Should -Be '_RowIdx'
    }

    It '隐藏列不应出现在可见列中' {
        $plan = & $script:mod {
            Get-GridViewColumnPlan -Rows @(
                [PSCustomObject]@{ Session = 'a'; Status = 'attached'; Disabled = $false; Value = 'a' }
            ) -HiddenColumns @{ Status = ''; Disabled = $false; Value = '' }
        }
        $plan.VisibleColumns | Should -Not -Contain 'Status'
        $plan.VisibleColumns | Should -Not -Contain 'Disabled'
        $plan.VisibleColumns | Should -Not -Contain 'Value'
        $plan.VisibleColumns | Should -Contain 'Session'
    }

    It '裁剪后的行不应再带隐藏字段' {
        $plan = & $script:mod {
            Get-GridViewColumnPlan -Rows @(
                [PSCustomObject]@{ Session = 'a'; Status = 'attached'; Disabled = $false; Value = 'a' }
            ) -HiddenColumns @{ Status = ''; Disabled = $false; Value = '' }
        }
        $plan.TrimmedRows[0].PSObject.Properties.Name | Should -Not -Contain 'Status'
        $plan.TrimmedRows[0].PSObject.Properties.Name | Should -Not -Contain 'Value'
    }

    It '裁剪后的行数应与原始行数一致' {
        $plan = & $script:mod {
            Get-GridViewColumnPlan -Rows @(
                [PSCustomObject]@{ Session = 'a' }
                [PSCustomObject]@{ Session = 'b' }
            ) -HiddenColumns @{ Value = '' }
        }
        $plan.TrimmedRows.Count | Should -Be 2
    }
}

Describe 'Restore-GridViewSelection (选中结果归一化与隐藏字段恢复)' {

    It '单对象形态应直接返回' {
        $sel = & $script:mod {
            param($r) Restore-GridViewSelection -Selected $r -Rows @() -KeyColumn 'Session'
        } ([PSCustomObject]@{ Session = 'a' })
        $sel.Session | Should -Be 'a'
    }

    It '单元素集合形态应归一化为单对象' {
        $sel = & $script:mod {
            param($r) Restore-GridViewSelection -Selected $r -Rows @() -KeyColumn 'Session'
        } @([PSCustomObject]@{ Session = 'a' })
        $sel.Session | Should -Be 'a'
    }

    It '应从原始行恢复隐藏字段' {
        $sel = & $script:mod {
            $rows = @(
                [PSCustomObject]@{ Session = 'a'; Status = 'attached'; Disabled = $false; Value = 'a' }
            )
            $trimmed = [PSCustomObject]@{ Session = 'a' }
            Restore-GridViewSelection -Selected $trimmed -Rows $rows -KeyColumn 'Session' `
                -HiddenKeys @('Status', 'Disabled', 'Value') -HiddenColumns @{ Status = ''; Disabled = $false; Value = '' }
        }
        $sel.Status | Should -Be 'attached'
        $sel.Value | Should -Be 'a'
        $sel.Disabled | Should -BeFalse
    }

    It '原始行缺失该列时应使用默认值' {
        $sel = & $script:mod {
            $rows = @([PSCustomObject]@{ Session = 'a' })
            $trimmed = [PSCustomObject]@{ Session = 'a' }
            Restore-GridViewSelection -Selected $trimmed -Rows $rows -KeyColumn 'Session' `
                -HiddenKeys @('Value') -HiddenColumns @{ Value = 'DEFAULT' }
        }
        $sel.Value | Should -Be 'DEFAULT'
    }
}

Describe 'ConvertTo-TmuxSessionSelection / ConvertTo-TmuxRefreshSelection (选择结果归一化)' {

    It '会话选择应产出统一形状且 Label 为纯会话名' {
        $sel = & $script:mod { ConvertTo-TmuxSessionSelection -Name 'btop' -Status 'detached' }
        $sel.Value | Should -Be 'btop'
        $sel.RawName | Should -Be 'btop'
        $sel.Label | Should -Be 'btop'
        $sel.Status | Should -Be 'detached'
        $sel.IsRefresh | Should -BeFalse
    }

    It '未指定状态时应按 detached 处理' {
        $sel = & $script:mod { ConvertTo-TmuxSessionSelection -Name 'btop' }
        $sel.Status | Should -Be 'detached'
    }

    It '刷新选择项应使用哨兵值并标记 IsRefresh' {
        $sel = & $script:mod { ConvertTo-TmuxRefreshSelection }
        # 哨兵值定义在模块作用域, 需从模块作用域读取后再断言
        $signal = & $script:mod { $script:TmuxRefreshSignalValue }
        $sel.Value | Should -Be $signal
        $sel.IsRefresh | Should -BeTrue
    }
}

Describe 'Get-TmuxRefreshedSession (用户触发的刷新)' {

    It '应返回刷新脚本块的结果' {
        $sessions = & $script:mod {
            Get-TmuxRefreshedSession -SessionRefresher {
                @([PSCustomObject]@{ Name = 'a'; Status = 'attached' })
            }
        }
        $sessions.Count | Should -Be 1
        $sessions[0].Name | Should -Be 'a'
    }

    It '应过滤掉 $null 元素' {
        $sessions = & $script:mod {
            Get-TmuxRefreshedSession -SessionRefresher {
                @($null, [PSCustomObject]@{ Name = 'a'; Status = 'attached' }, $null)
            }
        }
        $sessions.Count | Should -Be 1
    }

    It '空结果应返回空数组而不是 $null' {
        $sessions = & $script:mod {
            Get-TmuxRefreshedSession -SessionRefresher { $null }
        }
        $sessions.Count | Should -Be 0
    }
}

Describe '单轨 GridView 契约 (单轨化回归防护)' {

    It 'Get-ConsoleUiBackend 的 Backend 恒为 GridView' {
        $state = & $script:mod { Get-ConsoleUiBackend }
        $state.Backend | Should -Be 'GridView'
    }

    It 'Get-ConsoleUiBackend 不得返回 AnsiFallback 降级轨' {
        $state = & $script:mod { Get-ConsoleUiBackend }
        $state.Backend | Should -Not -Be 'AnsiFallback'
    }

    It 'Get-ConsoleUiBackend 应返回统一的字段集合' {
        $state = & $script:mod { Get-ConsoleUiBackend }
        foreach ($field in @('Backend', 'Available', 'Reason', 'Conflicts', 'PstuiVersion', 'TerminalGuiVersion')) {
            $state.PSObject.Properties.Name | Should -Contain $field
        }
    }

    It 'Assert-ConsoleUiReady 在主轨可用时不应抛错' {
        # 注入 Available=$true 的状态, 断言"可用即放行"这条契约与真实环境无关
        $threw = $false
        try {
            & $script:mod {
                $original = $script:ConsoleUiBackend
                try {
                    $script:ConsoleUiBackend = [PSCustomObject]@{
                        Backend   = 'GridView'
                        Available = $true
                        Reason    = '测试注入的可用状态'
                    }
                    Assert-ConsoleUiReady -Feature '单元测试功能'
                } finally {
                    $script:ConsoleUiBackend = $original
                }
            }
        } catch {
            $threw = $true
        }
        $threw | Should -BeFalse
    }

    It 'Assert-ConsoleUiReady 在主轨不可用时应抛出可定位的终止错误' {
        $message = & $script:mod {
            $original = $script:ConsoleUiBackend
            try {
                $script:ConsoleUiBackend = [PSCustomObject]@{
                    Backend   = 'GridView'
                    Available = $false
                    Reason    = '测试注入的不可用原因'
                }
                $script:thrownMessage = ''
                try {
                    Assert-ConsoleUiReady -Feature '单元测试功能'
                } catch {
                    $script:thrownMessage = $_.Exception.Message
                }
            } finally {
                $script:ConsoleUiBackend = $original
            }
            $script:thrownMessage
        }
        $message | Should -Not -BeNullOrEmpty
        $message | Should -BeLike '*单元测试功能*'
        $message | Should -BeLike '*测试注入的不可用原因*'
    }

    It 'Show-HostSelector 不再提供 -Backend 参数' {
        $keys = & $script:mod { (Get-Command Show-HostSelector).Parameters.Keys }
        $keys | Should -Not -Contain 'Backend'
    }

    It 'Show-SessionManager 不再提供 -Backend 参数' {
        $keys = & $script:mod { (Get-Command Show-SessionManager).Parameters.Keys }
        $keys | Should -Not -Contain 'Backend'
    }

    It 'Show-TmuxSessionList 不再提供 -Backend 参数' {
        $keys = & $script:mod { (Get-Command Show-TmuxSessionList).Parameters.Keys }
        $keys | Should -Not -Contain 'Backend'
    }

    It '已删除的 AnsiFallback 降级轨函数在模块作用域内应不存在' {
        $removed = @(
            'Invoke-AnsiMenu', 'Invoke-AnsiHostSelector', 'Invoke-AnsiSessionManager',
            'Invoke-ConsoleMenu', 'Invoke-MenuMachine', 'New-AnsiLayout',
            'Clear-AnsiScreen', 'Write-MenuItem', 'New-MenuItem',
            'New-StatusBadge', 'Format-StatusBadge', 'New-DynamicHelpPanel',
            'Get-SessionActionHelp', 'Resolve-MenuColorTable',
            'Get-TmuxSessionMenuOption', 'Test-FilterCharacter',
            'Get-FilteredItems', 'Update-FilterString', 'Send-MenuKey',
            'ConvertTo-CsiArrowKey', 'Update-InputBuffer', 'Test-InputValidation'
        )
        foreach ($name in $removed) {
            $found = & $script:mod {
                param($n) [bool](Get-Command $n -CommandType Function -ErrorAction SilentlyContinue)
            } $name
            $found | Should -BeFalse
        }
    }

    It '已删除的降级轨源文件不应出现在模块目录内' {
        # 基于 (Get-Module ShellPrompt).ModuleBase 推导, 不依赖仓库工作区路径,
        # 因此模块被安装到任意位置时该断言同样成立
        $privateDir = Join-Path $script:mod.ModuleBase 'Private'
        foreach ($file in @(
                'Invoke-AnsiMenu.ps1', 'Invoke-ConsoleMenu.ps1', 'Invoke-MenuMachine.ps1',
                'New-AnsiLayout.ps1', 'Clear-AnsiScreen.ps1', 'Write-MenuItem.ps1',
                'New-MenuItem.ps1', 'New-StatusBadge.ps1', 'Format-StatusBadge.ps1',
                'New-DynamicHelpPanel.ps1', 'Get-TmuxSessionMenuOption.ps1',
                'Get-KeyboardFilter.ps1', 'Show-InputPrompt.ps1')) {
            Test-Path (Join-Path $privateDir $file) | Should -BeFalse
        }
    }

    It 'GridView 主轨实现文件应存在于模块目录内' {
        $privateDir = Join-Path $script:mod.ModuleBase 'Private'
        foreach ($file in @(
                'Invoke-GridViewMenu.ps1', 'Get-GridViewColumnPlan.ps1',
                'Get-GridViewHostRow.ps1', 'Get-GridViewManagerRow.ps1',
                'Get-TmuxSessionGridRow.ps1', 'Get-TmuxSessionStateText.ps1',
                'Get-ConsoleUiBackend.ps1')) {
            Test-Path (Join-Path $privateDir $file) | Should -BeTrue
        }
    }
}
