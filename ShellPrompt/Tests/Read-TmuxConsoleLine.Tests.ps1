# Read-TmuxConsoleLine.Tests.ps1 - Input 态单行输入读取器(状态机)契约测试
# 覆盖:
#   1. 可见字符进入缓冲区, Enter 提交;
#   2. Backspace 删除末字符(空缓冲退格静默忽略);
#   3. Esc 取消返回 $null; 输入流结束($null)同样返回 $null;
#   4. 控制字符 / 无 KeyChar 功能键被静默忽略 —— 缓冲区不变, 也不抛错误。
# 说明: 全部按键通过 -KeyReader 注入, 不触碰真实控制台。

Describe 'Input 态单行输入读取器 (Read-TmuxConsoleLine)' {

    BeforeAll {
        # Pester v6: 路径与模块引用必须放在 BeforeAll 内解析
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'

        # 注入键 walker: 每次调用消费一个按键, 取尽后返回 $null(输入流结束)
        function Get-KeyWalker {
            param([object[]]$Keys)
            $queue = [System.Collections.Generic.Queue[object]]::new()
            foreach ($k in $Keys) { $queue.Enqueue($k) }
            return {
                if ($queue.Count -gt 0) { $queue.Dequeue() } else { $null }
            }.GetNewClosure()
        }

        # 注入键 stub: 与 [ConsoleKeyInfo] 同形状的最小对象(.Key/.KeyChar)
        function Get-StubKey {
            param(
                [ConsoleKey]$Key = [ConsoleKey]::A,
                [char]$KeyChar = [char]0
            )
            [PSCustomObject]@{ Key = $Key; KeyChar = $KeyChar }
        }
    }

    It '可见字符进缓冲, Enter 提交返回输入内容' {
        $keys = Get-KeyWalker -Keys @(
            (Get-StubKey -KeyChar ([char]'a'))
            (Get-StubKey -KeyChar ([char]'b'))
            (Get-StubKey -KeyChar ([char]'c'))
            (Get-StubKey -Key ([ConsoleKey]::Enter) -KeyChar ([char]13))
        )
        $result = & $script:mod { param($r) Read-TmuxConsoleLine -Row 14 -Column 7 -KeyReader $r } $keys

        $result | Should -BeExactly 'abc'
    }

    It 'Backspace 删除末字符; 空缓冲的退格静默忽略' {
        $keys = Get-KeyWalker -Keys @(
            (Get-StubKey -KeyChar ([char]'x'))          # x
            (Get-StubKey -KeyChar ([char]'y'))          # xy
            (Get-StubKey -Key ([ConsoleKey]::Backspace))  # x
            (Get-StubKey -Key ([ConsoleKey]::Backspace))  # ""
            (Get-StubKey -Key ([ConsoleKey]::Backspace))  # "" (静默忽略, 不抛错)
            (Get-StubKey -KeyChar ([char]'z'))          # z
            (Get-StubKey -Key ([ConsoleKey]::Enter) -KeyChar ([char]13))
        )
        $result = & $script:mod { param($r) Read-TmuxConsoleLine -Row 14 -Column 7 -KeyReader $r } $keys

        $result | Should -BeExactly 'z'
    }

    It 'Esc 取消返回 $null' {
        $keys = Get-KeyWalker -Keys @(
            (Get-StubKey -KeyChar ([char]'a'))
            (Get-StubKey -Key ([ConsoleKey]::Escape))
        )
        $result = & $script:mod { param($r) Read-TmuxConsoleLine -Row 14 -Column 7 -KeyReader $r } $keys

        $result | Should -BeNullOrEmpty
    }

    It '输入流结束($null)按取消处理返回 $null' {
        $keys = Get-KeyWalker -Keys @()

        $result = & $script:mod { param($r) Read-TmuxConsoleLine -Row 14 -Column 7 -KeyReader $r } $keys

        $result | Should -BeNullOrEmpty
    }

    It '控制字符与功能键静默忽略: 缓冲区保持不变且不抛错' {
        $keys = Get-KeyWalker -Keys @(
            (Get-StubKey -KeyChar ([char]'h'))
            (Get-StubKey -KeyChar ([char]3))                       # Ctrl-C 字符
            (Get-StubKey -KeyChar ([char]4))                       # EOT
            (Get-StubKey -Key ([ConsoleKey]::F5))                    # 无 KeyChar 功能键
            (Get-StubKey -Key ([ConsoleKey]::Delete) -KeyChar ([char]27)) # 不可见码值
            (Get-StubKey -Key ([ConsoleKey]::LeftArrow) -KeyChar ([char]0))
            (Get-StubKey -Key ([ConsoleKey]::Enter) -KeyChar ([char]13))
        )
        $result = & $script:mod { param($r) Read-TmuxConsoleLine -Row 14 -Column 7 -KeyReader $r } $keys

        # 所有不可见按键被忽略, 只有 'h' 进入缓冲区
        $result | Should -BeExactly 'h'
    }

    It '回车空提交返回空串(上层按"随机名称"处理)' {
        $keys = Get-KeyWalker -Keys @(
            (Get-StubKey -Key ([ConsoleKey]::Enter) -KeyChar ([char]13))
        )
        $result = & $script:mod { param($r) Read-TmuxConsoleLine -Row 14 -Column 7 -KeyReader $r } $keys

        $result | Should -BeExactly ''
    }
}
