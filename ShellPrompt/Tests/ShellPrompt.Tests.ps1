<#
.SYNOPSIS
    ShellPrompt 模块 Pester v3/v5 兼容测试套件
#>

# 模块路径：相对于测试目录的父目录
$moduleRoot = (Resolve-Path "$PSScriptRoot\..").Path
$manifestPath = Join-Path $moduleRoot 'ShellPrompt.psd1'

Describe 'Module Import' {

    It '应能成功导入模块' {
        { Import-Module $manifestPath -Force -ErrorAction Stop } | Should Not Throw
    }

    It '导入后模块应可用' {
        Import-Module $manifestPath -Force
        $module = Get-Module ShellPrompt
        $module | Should Not BeNullOrEmpty
        $module.Name | Should Be 'ShellPrompt'
    }
}

Describe 'Command Export' {

    It '应导出 Invoke-Reload' {
        Import-Module $manifestPath -Force
        Get-Command -Module ShellPrompt -Name 'Invoke-Reload' -ErrorAction SilentlyContinue |
            Should Not BeNullOrEmpty
    }

    It '应导出 Show-UserScoopLogo' {
        Import-Module $manifestPath -Force
        Get-Command -Module ShellPrompt -Name 'Show-UserScoopLogo' -ErrorAction SilentlyContinue |
            Should Not BeNullOrEmpty
    }

    It '应导出 Start-TmuxSession' {
        Import-Module $manifestPath -Force
        Get-Command -Module ShellPrompt -Name 'Start-TmuxSession' -ErrorAction SilentlyContinue |
            Should Not BeNullOrEmpty
    }

    It '应导出 Copy-SshPublicKey' {
        Import-Module $manifestPath -Force
        Get-Command -Module ShellPrompt -Name 'Copy-SshPublicKey' -ErrorAction SilentlyContinue |
            Should Not BeNullOrEmpty
    }

    It '不应导出旧命令 reload' {
        Import-Module $manifestPath -Force
        Get-Command -Module ShellPrompt -Name 'reload' -ErrorAction SilentlyContinue |
            Should BeNullOrEmpty
    }

    It '不应导出内部辅助函数' {
        Import-Module $manifestPath -Force
        $privateNames = @(
            'Get-CachedConfig', 'Get-SshConfigHosts', 'Get-TmuxAvailability',
            'Get-TmuxSessions', 'Invoke-ConsoleMenu', 'Invoke-SshCommand',
            'Invoke-SshCaptureOutput', 'New-RandomSessionName', 'Reset-TerminalMode',
            'Start-SshInteractive', 'Get-SshArgs', 'Connect-TmuxSession',
            'New-TmuxSession', 'Remove-TmuxSession', 'ConvertTo-SshEscapedString',
            'Test-SshHostName', 'Save-OriginalTerminalState'
        )
        $exported = @(Get-Command -Module ShellPrompt | Select-Object -ExpandProperty Name)
        foreach ($name in $privateNames) {
            ($exported -notcontains $name) | Should Be $true
        }
    }
}

Describe 'Verb-Noun Compliance' {

    It '所有导出命令的动词应在 Get-Verb 批准列表中' {
        Import-Module $manifestPath -Force
        $approvedVerbs = @(Get-Verb | Select-Object -ExpandProperty Verb)
        $exported = @(Get-Command -Module ShellPrompt)
        foreach ($cmd in $exported) {
            $verb = $cmd.Name -split '-' | Select-Object -First 1
            ($approvedVerbs -contains $verb) | Should Be $true
        }
    }
}

Describe 'Config Access' {

    It '$script:Config 应包含所有域' {
        Import-Module $manifestPath -Force
        $config = & (Get-Module ShellPrompt) { $script:Config }
        $config | Should Not BeNullOrEmpty
        $config.Contains('Colors') | Should Be $true
        $config.Contains('Keys') | Should Be $true
        $config.Contains('Paths') | Should Be $true
        $config.Contains('SSH') | Should Be $true
    }
}

Describe 'ConvertTo-SshEscapedString' {

    It '应正确处理普通字符' {
        $result = & (Get-Module ShellPrompt) { ConvertTo-SshEscapedString -Value 'hello' }
        $result | Should Be 'hello'
    }

    It '应转义单引号' {
        $result = & (Get-Module ShellPrompt) { ConvertTo-SshEscapedString -Value "it's a test" }
        $result | Should Be "it'\''s a test"
    }

    It '应通过管道处理输入' {
        $result = "don't stop" | & (Get-Module ShellPrompt) { $input | ConvertTo-SshEscapedString }
        $result | Should Be "don'\''t stop"
    }
}

Describe 'Test-SshHostName' {

    It '合法主机名应返回 $true' {
        & (Get-Module ShellPrompt) { Test-SshHostName -HostName 'example.com' } | Should Be $true
    }

    It '带短横线的合法主机名应返回 $true' {
        & (Get-Module ShellPrompt) { Test-SshHostName -HostName 'my-server-01' } | Should Be $true
    }

    It '含空格的主机名应返回 $false' {
        & (Get-Module ShellPrompt) { Test-SshHostName -HostName 'bad host' } | Should Be $false
    }

    It '含管道符的主机名应返回 $false' {
        & (Get-Module ShellPrompt) { Test-SshHostName -HostName 'host|danger' } | Should Be $false
    }
}

Describe 'Test-FilterCharacter' {

    It '应接受小写字母' {
        & (Get-Module ShellPrompt) { Test-FilterCharacter -Character 'a' } | Should Be $true
    }

    It '应接受大写字母' {
        & (Get-Module ShellPrompt) { Test-FilterCharacter -Character 'Z' } | Should Be $true
    }

    It '应接受数字' {
        & (Get-Module ShellPrompt) { Test-FilterCharacter -Character '7' } | Should Be $true
    }

    It '应接受点号' {
        & (Get-Module ShellPrompt) { Test-FilterCharacter -Character '.' } | Should Be $true
    }

    It '应接受下划线和短横线' {
        & (Get-Module ShellPrompt) { Test-FilterCharacter -Character '_' } | Should Be $true
        & (Get-Module ShellPrompt) { Test-FilterCharacter -Character '-' } | Should Be $true
    }

    It '应拒绝空格' {
        & (Get-Module ShellPrompt) { Test-FilterCharacter -Character ' ' } | Should Be $false
    }

    It '应拒绝空字符串' {
        & (Get-Module ShellPrompt) { Test-FilterCharacter -Character '' } | Should Be $false
    }

    It '应拒绝控制字符' {
        & (Get-Module ShellPrompt) { Test-FilterCharacter -Character ([char]27) } | Should Be $false
    }

    It '应拒绝斜杠和管道符' {
        & (Get-Module ShellPrompt) { Test-FilterCharacter -Character '/' } | Should Be $false
        & (Get-Module ShellPrompt) { Test-FilterCharacter -Character '|' } | Should Be $false
    }
}

Describe 'Get-FilteredItems' {

    It '空 Filter 应返回全部 Items' {
        $result = & (Get-Module ShellPrompt) { Get-FilteredItems -Items @('debian', 'ubuntu', 'arch') -Filter '' }
        @($result).Count | Should Be 3
    }

    It '应按 Contains 方式大小写不敏感匹配' {
        $result = & (Get-Module ShellPrompt) { Get-FilteredItems -Items @('Debian-Server', 'Ubuntu-Cloud', 'ArchLinux') -Filter 'UBUNTU' }
        @($result).Count | Should Be 1
        @($result)[0] | Should Be 'Ubuntu-Cloud'
    }

    It '支持多结果匹配' {
        $result = & (Get-Module ShellPrompt) { Get-FilteredItems -Items @('dev-01', 'dev-02', 'prod-01') -Filter 'dev' }
        @($result).Count | Should Be 2
    }

    It '应支持 PSCustomObject 候选项' {
        $result = & (Get-Module ShellPrompt) {
            Get-FilteredItems -Items @(
                [PSCustomObject]@{ Label = 'alpha'; Value = 1 }
                [PSCustomObject]@{ Label = 'beta';  Value = 2 }
            ) -Filter 'bet'
        }
        @($result).Count | Should Be 1
        @($result)[0].Value | Should Be 2
    }

    It '应支持 AlwaysInclude 始终保留项' {
        $result = & (Get-Module ShellPrompt) { Get-FilteredItems -Items @('debian', 'ubuntu') -Filter 'notexist' -AlwaysInclude 'EXIT' }
        @($result).Count | Should Be 1
        @($result)[0] | Should Be 'EXIT'
    }

    It '无匹配时返回空数组' {
        $result = & (Get-Module ShellPrompt) { Get-FilteredItems -Items @('debian') -Filter 'xyz' }
        @($result).Count | Should Be 0
    }
}

Describe 'Update-FilterString' {

    It '应追加可打印字符' {
        $result = & (Get-Module ShellPrompt) {
            Update-FilterString -Filter 'deb' -Key ([PSCustomObject]@{ VirtualKeyCode = 65; Character = '1' })
        }
        $result | Should Be 'deb1'
    }

    It '应处理 Backspace 删除末尾字符' {
        $result = & (Get-Module ShellPrompt) {
            Update-FilterString -Filter 'debian' -Key ([PSCustomObject]@{ VirtualKeyCode = 8; Character = ([char]8) })
        }
        $result | Should Be 'debia'
    }

    It '空 Filter 时 Backspace 应保持空' {
        $result = & (Get-Module ShellPrompt) {
            Update-FilterString -Filter '' -Key ([PSCustomObject]@{ VirtualKeyCode = 8; Character = ([char]8) })
        }
        $result | Should Be ''
    }

    It '应处理 Ctrl+U 清空' {
        $result = & (Get-Module ShellPrompt) {
            Update-FilterString -Filter 'whatever' -Key ([PSCustomObject]@{ VirtualKeyCode = 17; Character = ([char]21) })
        }
        $result | Should Be ''
    }

    It '应拒绝非法字符(空格)' {
        $result = & (Get-Module ShellPrompt) {
            Update-FilterString -Filter 'deb' -Key ([PSCustomObject]@{ VirtualKeyCode = 32; Character = ' ' })
        }
        $result | Should Be 'deb'
    }
}

Describe 'New-StatusBadge' {

    It 'Online 状态应使用绿色圆点' {
        $b = & (Get-Module ShellPrompt) { New-StatusBadge -Status Online }
        $b.Status | Should Be 'Online'
        $b.Glyph  | Should Be '●'
    }

    It 'Attached 状态应使用蓝色圆点' {
        $b = & (Get-Module ShellPrompt) { New-StatusBadge -Status Attached }
        $b.Status | Should Be 'Attached'
        $b.Glyph  | Should Be '●'
    }

    It 'Detached 状态应使用灰色空心圆' {
        $b = & (Get-Module ShellPrompt) { New-StatusBadge -Status Detached }
        $b.Glyph | Should Be '○'
    }

    It 'NetworkError 状态应使用红色叉号' {
        $b = & (Get-Module ShellPrompt) { New-StatusBadge -Status NetworkError }
        $b.Glyph | Should Be '✗'
    }

    It 'Pending 状态应使用黄色半圆' {
        $b = & (Get-Module ShellPrompt) { New-StatusBadge -Status Pending }
        $b.Glyph | Should Be '◐'
    }

    It 'Disabled 状态应使用暗灰叉号' {
        $b = & (Get-Module ShellPrompt) { New-StatusBadge -Status Disabled }
        $b.Glyph | Should Be '×'
    }

    It 'Warning 状态应使用黄色感叹号' {
        $b = & (Get-Module ShellPrompt) { New-StatusBadge -Status Warning }
        $b.Glyph | Should Be '!'
    }

    It '未指定 Text 时应使用默认说明' {
        $b = & (Get-Module ShellPrompt) { New-StatusBadge -Status Online }
        $b.Text | Should Be 'ready'
    }

    It '指定 Text 时应使用自定义说明' {
        $b = & (Get-Module ShellPrompt) { New-StatusBadge -Status NetworkError -Text '连接超时' }
        $b.Text | Should Be '连接超时'
    }

    It '应返回包含 Rst 重置码的对象' {
        $b = & (Get-Module ShellPrompt) { New-StatusBadge -Status Online }
        $b.Rst | Should Not BeNullOrEmpty
        $b.Rst | Should Match '\[0m'
    }
}

Describe 'Format-StatusBadge' {

    It '应返回包含 Glyph + Text 的单行字符串' {
        $script:badgeObj = & (Get-Module ShellPrompt) { New-StatusBadge -Status Online -Text 'ok' }
        $s = & (Get-Module ShellPrompt) { param($bg) Format-StatusBadge -Badge $bg } -bg $script:badgeObj
        $s | Should Match '●'
        $s | Should Match 'ok'
    }

    It '应包含 ANSI 颜色转义' {
        $script:badgeObj = & (Get-Module ShellPrompt) { New-StatusBadge -Status Detached }
        $s = & (Get-Module ShellPrompt) { param($bg) Format-StatusBadge -Badge $bg } -bg $script:badgeObj
        $s | Should Match '\[38;2;\d+;\d+;\d+m'
    }

    It '应包含重置码' {
        $script:badgeObj = & (Get-Module ShellPrompt) { New-StatusBadge -Status Online }
        $s = & (Get-Module ShellPrompt) { param($bg) Format-StatusBadge -Badge $bg } -bg $script:badgeObj
        $s | Should Match '\[0m'
    }
}

Describe 'New-MenuItem' {

    It '未指定 Value 时应默认等于 Label' {
        $item = & (Get-Module ShellPrompt) { New-MenuItem -Label 'debian' }
        $item.Label | Should Be 'debian'
        $item.Value | Should Be 'debian'
    }

    It '指定 Value 时应使用自定义值' {
        $item = & (Get-Module ShellPrompt) { New-MenuItem -Label 'debian' -Value ([PSCustomObject]@{ Name = 'srv' }) }
        $item.Value.Name | Should Be 'srv'
    }

    It '默认 Disabled 应为 false' {
        $item = & (Get-Module ShellPrompt) { New-MenuItem -Label 'a' }
        $item.Disabled | Should Be $false
    }

    It '指定 Disabled 时应正确记录' {
        $item = & (Get-Module ShellPrompt) { New-MenuItem -Label 'a' -Disabled $true }
        $item.Disabled | Should Be $true
    }

    It '应保留 Desc 描述' {
        $item = & (Get-Module ShellPrompt) { New-MenuItem -Label 'a' -Desc 'desc' }
        $item.Desc | Should Be 'desc'
    }
}

Describe 'Write-MenuItem' {

    $script:itemNormal   = & (Get-Module ShellPrompt) { New-MenuItem -Label 'debian' -Desc 'SSH 远程' }
    $script:itemDisabled = & (Get-Module ShellPrompt) { New-MenuItem -Label 'nope' -Disabled $true }
    $script:itemSelected = & (Get-Module ShellPrompt) { New-MenuItem -Label 'ubuntu' }

    It '未选中态应输出 [01] 序号' {
        $s = & (Get-Module ShellPrompt) { param($it) Write-MenuItem -Item $it -Index 0 -IsSelected $false } -it $script:itemNormal
        $s | Should Match '\[01\]'
    }

    It '选中态应包含 `>` 焦点箭头' {
        $s = & (Get-Module ShellPrompt) { param($it) Write-MenuItem -Item $it -Index 0 -IsSelected $true } -it $script:itemSelected
        $s | Should Match '>'
        $s | Should Match '\[01\]'
    }

    It '禁用态应包含 `/` 斜杠前缀' {
        $s = & (Get-Module ShellPrompt) { param($it) Write-MenuItem -Item $it -Index 0 -IsSelected $false } -it $script:itemDisabled
        $s | Should Match '/'
    }

    It '禁用态应包含序号' {
        $s = & (Get-Module ShellPrompt) { param($it) Write-MenuItem -Item $it -Index 0 -IsSelected $false } -it $script:itemDisabled
        $s | Should Match '\[01\]'
    }

    It '应包含 Label 主显示文本' {
        $s = & (Get-Module ShellPrompt) { param($it) Write-MenuItem -Item $it -Index 0 -IsSelected $false } -it $script:itemNormal
        $s | Should Match 'debian'
    }

    It '选中态且有 Desc 时应输出描述' {
        $script:itemWithDesc = & (Get-Module ShellPrompt) { New-MenuItem -Label 'srv' -Desc 'note here' }
        $s = & (Get-Module ShellPrompt) { param($it) Write-MenuItem -Item $it -Index 2 -IsSelected $true } -it $script:itemWithDesc
        $s | Should Match 'srv'
        $s | Should Match 'note here'
    }

    It '不同 Index 应输出不同序号' {
        $s1 = & (Get-Module ShellPrompt) { param($it) Write-MenuItem -Item $it -Index 0 -IsSelected $false } -it $script:itemNormal
        $s5 = & (Get-Module ShellPrompt) { param($it) Write-MenuItem -Item $it -Index 4 -IsSelected $false } -it $script:itemNormal
        $s1 | Should Match '\[01\]'
        $s5 | Should Match '\[05\]'
    }
}

Describe 'New-DynamicHelpPanel' {

    It '空 Entries 应返回空字符串' {
        $s = & (Get-Module ShellPrompt) { New-DynamicHelpPanel -Entries @() }
        $s | Should Be ''
    }

    It '应拼接多个条目' {
        $s = & (Get-Module ShellPrompt) {
            New-DynamicHelpPanel -Entries @(
                @{ Keys = 'Enter'; Action = '附着' }
                @{ Keys = 'Del';   Action = '删除' }
            )
        }
        $s | Should Match 'Enter'
        $s | Should Match '附着'
        $s | Should Match 'Del'
        $s | Should Match '删除'
    }

    It '多个条目应以 │ 分隔' {
        $s = & (Get-Module ShellPrompt) {
            New-DynamicHelpPanel -Entries @(
                @{ Keys = 'Enter'; Action = 'A' }
                @{ Keys = 'R';     Action = 'B' }
            )
        }
        $s | Should Match '│'
    }

    It 'Keys 或 Action 为空时跳过该条目' {
        $s = & (Get-Module ShellPrompt) {
            New-DynamicHelpPanel -Entries @(
                @{ Keys = 'Enter'; Action = 'OK' }
                @{ Keys = '';      Action = 'skip' }
                @{ Keys = 'R';     Action = '' }
            )
        }
        $s | Should Match 'Enter'
        $s | Should Match 'R'
        ($s -notmatch 'skip') | Should Be $true
    }
}

Describe 'Get-SessionActionHelp' {

    It '附着/恢复动作应返回含 Enter+R 的条目' {
        $result = @( & (Get-Module ShellPrompt) { Get-SessionActionHelp -ActionLabel '附着/恢复 tmux 会话' } )
        $result.Count | Should BeGreaterThan 0
        $joined = ($result | ConvertTo-Json -Compress)
        $joined | Should Match 'Enter'
        $joined | Should Match 'R'
    }

    It '删除动作应包含二次确认提示' {
        $result = @( & (Get-Module ShellPrompt) { Get-SessionActionHelp -ActionLabel '删除 tmux 会话' } )
        $joined = ($result | ConvertTo-Json -Compress)
        $joined | Should Match '二次确认'
    }

    It '刷新动作应包含 Enter 条目' {
        $result = @( & (Get-Module ShellPrompt) { Get-SessionActionHelp -ActionLabel '刷新会话列表' } )
        $joined = ($result | ConvertTo-Json -Compress)
        $joined | Should Match 'Enter'
    }

    It '所有动作都应包含退出提示(Esc/Q)' {
        $labels = @('附着/恢复 tmux 会话', '删除 tmux 会话', '刷新会话列表', '其他动作')
        foreach ($lbl in $labels) {
            $result = @( & (Get-Module ShellPrompt) { param($l) Get-SessionActionHelp -ActionLabel $l } -l $lbl )
            $joined = ($result | ConvertTo-Json -Compress)
            $joined | Should Match 'Esc'
            $joined | Should Match 'Q'
        }
    }
}

Describe 'New-AnsiLayout' {

    It '应返回含 Header/Main/Footer 三个集合的布局对象' {
        $l = & (Get-Module ShellPrompt) { New-AnsiLayout -Title '测试' -Width 80 }
        $l.Header.Count | Should BeGreaterThan 0
        $l.Main.Count   | Should Be 0
        $l.Footer.Count | Should BeGreaterThan 0
        # Header 必须包含至少 1 行非空内容(标题行/装饰行/分隔线)
        ($l.Header | Where-Object { $_ -and $_.Length -gt 0 }).Count | Should BeGreaterThan 0
    }

    It '应暴露颜色调色板字段' {
        $l = & (Get-Module ShellPrompt) { New-AnsiLayout -Title 'x' -Width 80 }
        $l.Primary | Should Not BeNullOrEmpty
        $l.Accent  | Should Not BeNullOrEmpty
        $l.Muted   | Should Not BeNullOrEmpty
        $l.Rst     | Should Not BeNullOrEmpty
    }

    It 'Header 应至少 3 行(标题/分隔/边框)' {
        $l = & (Get-Module ShellPrompt) { New-AnsiLayout -Title 'x' -Width 80 }
        $l.Header.Count | Should BeGreaterThan 2
    }

    It 'Width 指定为 80 时应记录 Width=80' {
        $l = & (Get-Module ShellPrompt) { New-AnsiLayout -Title 'x' -Width 80 }
        $l.Width | Should Be 80
    }

    It 'Title 应出现在 Header 中' {
        $l = & (Get-Module ShellPrompt) { New-AnsiLayout -Title 'MyTitle' -Width 80 }
        $joined = ($l.Header -join "`n")
        $joined | Should Match 'MyTitle'
    }

    It 'HeaderBadges 应嵌入 Header 行' {
        $script:badges = @('badge-text-1', 'badge-text-2')
        $l = & (Get-Module ShellPrompt) { param($b) New-AnsiLayout -Title 'x' -Width 80 -HeaderBadges $b } -b $script:badges
        $joined = ($l.Header -join "`n")
        $joined | Should Match 'badge-text-1'
        $joined | Should Match 'badge-text-2'
    }
}

Describe 'Add-MainLine / Set-FooterLine' {

    It 'Add-MainLine 应向 Main 区域追加行' {
        $script:layout = & (Get-Module ShellPrompt) { New-AnsiLayout -Title 'x' -Width 80 }
        $before = $script:layout.Main.Count
        & (Get-Module ShellPrompt) { param($ly) Add-MainLine -Layout $ly -Text 'hello' } -ly $script:layout
        $script:layout.Main.Count | Should Be ($before + 1)
        $script:layout.Main[$script:layout.Main.Count - 1] | Should Be 'hello'
    }

    It 'Set-FooterLine 应修改指定索引处的 Footer 行' {
        $script:layout = & (Get-Module ShellPrompt) { New-AnsiLayout -Title 'x' -Width 80 }
        & (Get-Module ShellPrompt) { param($ly) Set-FooterLine -Layout $ly -Index 0 -Text 'replaced' } -ly $script:layout
        $script:layout.Footer[0] | Should Be 'replaced'
    }

    It 'Set-FooterLine 越界 Index 不应崩溃' {
        $script:layout = & (Get-Module ShellPrompt) { New-AnsiLayout -Title 'x' -Width 80 }
        { & (Get-Module ShellPrompt) { param($ly) Set-FooterLine -Layout $ly -Index 999 -Text 'x' } -ly $script:layout } | Should Not Throw
    }

    It 'Set-FooterLine 负数 Index 不应崩溃' {
        $script:layout = & (Get-Module ShellPrompt) { New-AnsiLayout -Title 'x' -Width 80 }
        { & (Get-Module ShellPrompt) { param($ly) Set-FooterLine -Layout $ly -Index -1 -Text 'x' } -ly $script:layout } | Should Not Throw
    }
}

Describe 'Write-AnsiLine' {

    It 'Write-AnsiLine 应为已注册的内部函数' {
        # 验证函数定义存在(需先 dot-source)
        $moduleRoot = (Resolve-Path "$PSScriptRoot\..").Path
        $src = Join-Path $moduleRoot 'Private\New-AnsiLayout.ps1'
        Test-Path $src | Should Be $true
        $content = Get-Content $src -Raw
        $content | Should Match 'function Write-AnsiLine'
    }
}

Describe 'P2-1 Get-SpinnerFrame (纯函数)' {

    It '默认样式 (Braille) Frame=0 应返回首帧' {
        $glyph = & (Get-Module ShellPrompt) { Get-SpinnerFrame -Frame 0 -Style 'Braille' }
        $glyph | Should Be '⠋'
    }

    It 'Braille 样式第 5 帧应为 ⠴' {
        $glyph = & (Get-Module ShellPrompt) { Get-SpinnerFrame -Frame 5 -Style 'Braille' }
        $glyph | Should Be '⠴'
    }

    It 'Ascii 样式 Frame=2 应为 |' {
        $glyph = & (Get-Module ShellPrompt) { Get-SpinnerFrame -Frame 2 -Style 'Ascii' }
        $glyph | Should Be '|'
    }

    It 'Arrows 样式 Frame=4 应为 →' {
        $glyph = & (Get-Module ShellPrompt) { Get-SpinnerFrame -Frame 4 -Style 'Arrows' }
        $glyph | Should Be '→'
    }

    It '超出范围的 Frame 索引应正确回绕' {
        $mod = Get-Module ShellPrompt
        # Ascii 4 帧: '-','\','|','/'。 Frame=4 应回绕到 Frame=0 = '-'
        $glyph = & $mod { Get-SpinnerFrame -Frame 4 -Style 'Ascii' }
        $glyph | Should Be '-'
        # Frame=8 (8 mod 4 = 0) 也应回绕到 '-'
        $glyph2 = & $mod { Get-SpinnerFrame -Frame 8 -Style 'Ascii' }
        $glyph2 | Should Be '-'
    }

    It '负数 Frame 索引应正确回绕 (negative-safe modulo)' {
        $mod = Get-Module ShellPrompt
        # -1 在 Ascii (4 帧) 中应映射到 index 3 ('/')
        $glyph = & $mod { Get-SpinnerFrame -Frame (-1) -Style 'Ascii' }
        $glyph | Should Be '/'
    }

    It '未知样式应回退到 Braille' {
        $glyph = & (Get-Module ShellPrompt) { Get-SpinnerFrame -Frame 0 -Style 'NonExistentStyle' }
        $glyph | Should Be '⠋'
    }
}

Describe 'P2-1 Get-SpinnerSequence' {

    It '默认应返回 10 个 Braille 帧' {
        $seq = & (Get-Module ShellPrompt) { Get-SpinnerSequence -Style 'Braille' }
        $seq.Count | Should Be 10
    }

    It 'Blocks 样式应返回 14 帧' {
        $seq = & (Get-Module ShellPrompt) { Get-SpinnerSequence -Style 'Blocks' }
        $seq.Count | Should Be 14
    }

    It 'Dots 样式所有帧应为 3 字符宽 (幂等总宽度)' {
        $seq = & (Get-Module ShellPrompt) { Get-SpinnerSequence -Style 'Dots' }
        foreach ($frame in $seq) {
            $frame.Length | Should Be 3
        }
    }
}

Describe 'P2-4 Invoke-WithProgress (同步模式)' {

    It '同步 ScriptBlock 返回值应传递给 Result' {
        $r = & (Get-Module ShellPrompt) {
            Invoke-WithProgress -Message '测试' -ScriptBlock { 'ok' } -SuppressConsole
        }
        $r.Status | Should Be 'Success'
        $r.Result | Should Be 'ok'
    }

    It 'ScriptBlock 拋异常时函数应拋出原始异常' {
        $mod = Get-Module ShellPrompt
        $threw = $false
        try {
            & $mod {
                Invoke-WithProgress -Message '测试' -ScriptBlock { throw 'boom' } -SuppressConsole
            }
        } catch {
            $threw = $true
        }
        $threw | Should Be $true
    }

    It '轮询模式 PollScript=true 立即完成' {
        $r = & (Get-Module ShellPrompt) {
            Invoke-WithProgress -Message '测试' -ScriptBlock { } `
                                -PollScript { $true } -IntervalMs 50 -TimeoutSeconds 5 `
                                -SuppressConsole
        }
        $r.Status | Should Be 'Success'
        $r.ElapsedMs | Should BeLessThan 500
    }

    It '轮询模式超时应拋 TimeoutException' {
        $mod = Get-Module ShellPrompt
        $threw = $false
        $typeName = ''
        try {
            & $mod {
                Invoke-WithProgress -Message '测试' -ScriptBlock { } `
                                    -PollScript { $false } -IntervalMs 80 -TimeoutSeconds 1 `
                                    -SuppressConsole
            }
        } catch {
            $threw = $true
            $typeName = $_.Exception.GetType().Name
        }
        $threw | Should Be $true
        $typeName | Should Be 'TimeoutException'
    }

    It 'PollScript 拋异常时应结束拋出原异常' {
        $mod = Get-Module ShellPrompt
        $threw = $false
        try {
            & $mod {
                Invoke-WithProgress -Message '测试' -ScriptBlock { } `
                                    -PollScript { throw 'poll-fail' } -IntervalMs 50 -TimeoutSeconds 5 `
                                    -SuppressConsole
            }
        } catch {
            $threw = $true
        }
        $threw | Should Be $true
    }

    It 'Frames 数组应记录展示过的帧索引' {
        $r = & (Get-Module ShellPrompt) {
            Invoke-WithProgress -Message '测试' -ScriptBlock { return 1 } -SuppressConsole
        }
        $r.Frames.Count | Should BeGreaterThan 0
        $r.Frames[0] | Should Be 0
    }
}

Describe 'P2-2 New-WelcomeBanner (纯函数)' {

    It '默认应返回 10 行' {
        $lines = & (Get-Module ShellPrompt) { New-WelcomeBanner -Title 'TEST' }
        $lines.Count | Should Be 10
    }

    It '首行与末行应为空行' {
        $lines = & (Get-Module ShellPrompt) { New-WelcomeBanner -Title 'TEST' }
        $lines[0] | Should Be ''
        $lines[9] | Should Be ''
    }

    It 'Title 应出现在第 2 行' {
        $lines = & (Get-Module ShellPrompt) { New-WelcomeBanner -Title 'MYTEST' }
        $lines[1] | Should Match 'MYTEST'
    }

    It 'Subtitle 应出现在第 5 行' {
        $lines = & (Get-Module ShellPrompt) { New-WelcomeBanner -Subtitle 'HELLOTEST' }
        $lines[4] | Should Match 'HELLOTEST'
    }

    It 'Width=60 时 HLine 应有 56 个 =' {
        $lines = & (Get-Module ShellPrompt) { New-WelcomeBanner -Title 'X' -Width 60 }
        # 第 9 行形如 '  +<hLine>---'
        $line9 = $lines[8]
        $eqCount = ([regex]::Matches($line9, '=')).Count
        $eqCount | Should Be 56
    }

    It 'Width 小于 40 应拋 ValidationRange 错误' {
        $mod = Get-Module ShellPrompt
        $threw = $false
        try {
            & $mod { New-WelcomeBanner -Title 'X' -Width 10 }
        } catch {
            $threw = $true
        }
        $threw | Should Be $true
    }
}

Describe 'P2-2 Get-RandomQuote' {

    It '空 QuotesPath 应返回 Fallback' {
        $q = & (Get-Module ShellPrompt) { Get-RandomQuote -QuotesPath '' -Fallback 'FB' }
        $q | Should Be 'FB'
    }

    It '不存在的文件应返回 Fallback' {
        $q = & (Get-Module ShellPrompt) {
            Get-RandomQuote -QuotesPath 'C:\nonexistent\file.txt' -Fallback 'FB'
        }
        $q | Should Be 'FB'
    }

    It '存在且非空的文件应返回非空 Trim 后的语录' {
        $tmp = [System.IO.Path]::GetTempFileName()
        try {
            Set-Content -LiteralPath $tmp -Value "line one`nline two`nline three" -Encoding UTF8
            $q = & (Get-Module ShellPrompt) {
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '')]                param($p) Get-RandomQuote -QuotesPath $p -Fallback 'FB'
            } -p $tmp
            $q | Should Match 'line (one|two|three)'
        } finally {
            Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
        }
    }

    It '多文件调用应使用 mtime 缓存' {
        $tmp = [System.IO.Path]::GetTempFileName()
        try {
            Set-Content -LiteralPath $tmp -Value 'cached' -Encoding UTF8
            $mod = Get-Module ShellPrompt
            $q1 = & $mod { param($p) Get-RandomQuote -QuotesPath $p } -p $tmp
            $q2 = & $mod { param($p) Get-RandomQuote -QuotesPath $p } -p $tmp
            $q1 | Should Be $q2
            # 验证 cache 存在
            $hasCache = & $mod { param($p) $script:QuotesCache -ne $null -and $script:QuotesCache.Path -eq $p } -p $tmp
            $hasCache | Should Be $true
        } finally {
            Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
        }
    }
}

Describe 'P2-3 Update-InputBuffer (纯函数)' {

    It 'Char 应追加字符并保持 Continue' {
        $r = & (Get-Module ShellPrompt) { Update-InputBuffer -Buffer 'ab' -Key 'Char' -Char 'c' }
        $r.Buffer | Should Be 'abc'
        $r.State  | Should Be 'Continue'
    }

    It 'Backspace 应删除末尾字符' {
        $r = & (Get-Module ShellPrompt) { Update-InputBuffer -Buffer 'abc' -Key 'Backspace' }
        $r.Buffer | Should Be 'ab'
        $r.State  | Should Be 'Continue'
    }

    It '空 Buffer Backspace 应保持空' {
        $r = & (Get-Module ShellPrompt) { Update-InputBuffer -Buffer '' -Key 'Backspace' }
        $r.Buffer | Should Be ''
        $r.State  | Should Be 'Continue'
    }

    It 'MaxLength 超过时 Char 应被丢弃' {
        $r = & (Get-Module ShellPrompt) {
            Update-InputBuffer -Buffer 'abc' -Key 'Char' -Char 'd' -MaxLength 3
        }
        $r.Buffer | Should Be 'abc'
    }

    It 'Enter 应提交当前 Buffer' {
        $r = & (Get-Module ShellPrompt) { Update-InputBuffer -Buffer 'done' -Key 'Enter' }
        $r.Buffer | Should Be 'done'
        $r.State  | Should Be 'Submit'
    }

    It 'Escape 应取消并保留 Buffer' {
        $r = & (Get-Module ShellPrompt) { Update-InputBuffer -Buffer 'partial' -Key 'Escape' }
        $r.Buffer | Should Be 'partial'
        $r.State  | Should Be 'Cancel'
    }

    It 'Ctrl+C 应取消' {
        $r = & (Get-Module ShellPrompt) { Update-InputBuffer -Buffer 'x' -Key 'Ctrl+C' }
        $r.State | Should Be 'Cancel'
    }

    It 'Ctrl+U 应清空 Buffer' {
        $r = & (Get-Module ShellPrompt) { Update-InputBuffer -Buffer 'clear me' -Key 'Ctrl+U' }
        $r.Buffer | Should Be ''
        $r.State  | Should Be 'Continue'
    }
}

Describe 'P2-3 Test-InputValidation (纯函数)' {

    It '无 Validator 应返回 Valid=true' {
        $r = & (Get-Module ShellPrompt) { Test-InputValidation -Value 'anything' }
        $r.Valid   | Should Be $true
        $r.Message | Should Be ''
    }

    It 'Validator 返回 $true 应为 Valid=true' {
        $r = & (Get-Module ShellPrompt) {
            Test-InputValidation -Value 'foo' -Validator { param($v) $true }
        }
        $r.Valid | Should Be $true
    }

    It 'Validator 返回 $false 应为 Valid=false' {
        $r = & (Get-Module ShellPrompt) {
            Test-InputValidation -Value 'foo' -Validator { param($v) $false }
        }
        $r.Valid | Should Be $false
    }

    It 'Validator 返回 hashtable Valid=false 应提取 Message' {
        $r = & (Get-Module ShellPrompt) {
            Test-InputValidation -Value 'x' -Validator { @{ Valid=$false; Message='自定义错误' } }
        }
        $r.Valid   | Should Be $false
        $r.Message | Should Be '自定义错误'
    }

    It 'Validator 返回 hashtable Valid=true 应提取 Message' {
        $r = & (Get-Module ShellPrompt) {
            Test-InputValidation -Value 'x' -Validator { @{ Valid=$true; Message='passed' } }
        }
        $r.Valid   | Should Be $true
        $r.Message | Should Be 'passed'
    }

    It 'Validator 拋异常应被捕获并转为 Valid=false' {
        $r = & (Get-Module ShellPrompt) {
            Test-InputValidation -Value 'x' -Validator { throw 'validator-boom' }
        }
        $r.Valid   | Should Be $false
        $r.Message | Should Match 'validator-boom'
    }

    It '非空校验场景应按预期工作' {
        $mod = Get-Module ShellPrompt
        $r1 = & $mod {
            Test-InputValidation -Value '' -Validator {
                param($v) if ([string]::IsNullOrWhiteSpace($v)) { @{ Valid=$false; Message='不能为空' } } else { $true }
            }
        }
        $r1.Valid   | Should Be $false
        $r1.Message | Should Be '不能为空'

        $r2 = & $mod {
            Test-InputValidation -Value 'hi' -Validator {
                param($v) if ([string]::IsNullOrWhiteSpace($v)) { @{ Valid=$false; Message='不能为空' } } else { $true }
            }
        }
        $r2.Valid | Should Be $true
    }
}
