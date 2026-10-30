# Format-TmuxToolbarText.Tests.ps1 - tmux 管理器单行工具条文案契约回归测试
# 覆盖:
#   1. 有/无会话时的默认渲染(两个空格分隔)的精确文案
#   2. Error 上下文下的文案切换(重试/直连)
#   3. 自定义分隔符(-Separator)的渲染与动作顺序
#   4. -HighlightDanger 的危险色着色(内联 ANSI)与未着色时的对比
#   5. 输出恒为单行(不含换行符)

Describe 'tmux 管理器单行工具条文案契约' {

    BeforeAll {
        # Pester v6: 路径与模块引用必须放在 BeforeAll 内解析
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    Context '默认渲染 (Normal, 两个空格分隔)' {

        It '有会话时渲染 [a]附着 [n]新建 [r]刷新 [s]SSH [x]删除 [q]退出' {
            $text = & $script:mod { Format-TmuxToolbarText -HasSessions $true }

            $text | Should -BeExactly '[a]附着  [n]新建  [r]刷新  [s]SSH  [x]删除  [q]退出'
        }

        It '无会话时不渲染附着与删除' {
            $text = & $script:mod { Format-TmuxToolbarText -HasSessions $false }

            $text | Should -BeExactly '[n]新建  [r]刷新  [s]SSH  [q]退出'
        }

        It '输出恒为单行(不含换行符)' {
            $text = & $script:mod { Format-TmuxToolbarText -HasSessions $true }

            $text | Should -Not -Match '[\r\n]'
        }
    }

    Context '错误上下文 (Context = Error)' {

        It '无会话且错误上下文时渲染 重试/直连' {
            $text = & $script:mod { Format-TmuxToolbarText -HasSessions $false -Context 'Error' }

            $text | Should -BeExactly '[n]新建  [r]重试  [s]直连  [q]退出'
        }

        It '有会话且错误上下文时只切换刷新/SSH 的文案' {
            $text = & $script:mod { Format-TmuxToolbarText -HasSessions $true -Context 'Error' }

            $text | Should -BeExactly '[a]附着  [n]新建  [r]重试  [s]直连  [x]删除  [q]退出'
        }
    }

    Context '自定义分隔符' {

        It '使用 " | " 连接各动作片段' {
            $text = & $script:mod { Format-TmuxToolbarText -HasSessions $true -Separator ' | ' }

            $text | Should -BeExactly '[a]附着 | [n]新建 | [r]刷新 | [s]SSH | [x]删除 | [q]退出'
        }

        It '各动作片段均出现且顺序正确' {
            $text = & $script:mod { Format-TmuxToolbarText -HasSessions $true -Separator ' | ' }

            # Pester 6 的 -Contain 是"集合里存在相等元素", 不做子串匹配;
            # 单串包含判断用 -Match (子串, 元字符需转义)
            $text | Should -Match ([regex]::Escape('[a]附着'))
            $text | Should -Match ([regex]::Escape('[n]新建'))
            $text | Should -Match ([regex]::Escape('[r]刷新'))
            $text | Should -Match ([regex]::Escape('[s]SSH'))
            $text | Should -Match ([regex]::Escape('[x]删除'))
            $text | Should -Match ([regex]::Escape('[q]退出'))

            $text.IndexOf('[a]附着') | Should -BeLessThan $text.IndexOf('[n]新建')
            $text.IndexOf('[n]新建') | Should -BeLessThan $text.IndexOf('[r]刷新')
            $text.IndexOf('[r]刷新') | Should -BeLessThan $text.IndexOf('[s]SSH')
            $text.IndexOf('[s]SSH') | Should -BeLessThan $text.IndexOf('[x]删除')
            $text.IndexOf('[x]删除') | Should -BeLessThan $text.IndexOf('[q]退出')
        }
    }

    Context '危险动作着色 (-HighlightDanger)' {

        It '开启后删除项段落含 ANSI 转义(ESC 字符)' {
            $text = & $script:mod { Format-TmuxToolbarText -HasSessions $true -HighlightDanger }

            $text.Contains([char]27) | Should -BeTrue
        }

        It '开启后仍保留字面量 [x]删除(着色不吞文案)' {
            $text = & $script:mod { Format-TmuxToolbarText -HasSessions $true -HighlightDanger }

            $text | Should -Match ([regex]::Escape('[x]删除'))
        }

        It '未开启时不含 ESC 字符(纯文本)' {
            $text = & $script:mod { Format-TmuxToolbarText -HasSessions $true }

            $text.Contains([char]27) | Should -BeFalse
        }
    }
}
