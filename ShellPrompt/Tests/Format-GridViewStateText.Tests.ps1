# Format-GridViewStateText Pester 测试套件
# 目标运行时: Pester v5+ (当前环境 Pester 6.2.0 / PowerShell 7.6.3)
# 覆盖矩阵:
#   1. Danger 键 + 文字  -> 含 ANSI 颜色码 + 文字 + 重置码
#   2. Warning 键 + 文字 -> 同上但用 Warning 色
#   3. Colors 域未设置   -> 静默回退到纯文本
#   4. Colors.Danger 为 null/空 -> 静默回退
#   5. 颜色码无尾重置码 -> 自动追加 0m
#   6. 颜色码已有尾重置码 -> 不重复追加
#   7. 非 danger/warning 键 -> 静默回退到纯文本
#   8. 大小写不敏感(danger/DANGER/Danger 均识别)

Describe 'Format-GridViewStateText' {

    BeforeAll {
        # Pester v6: 路径与模块引用必须放在 BeforeAll 内解析
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    BeforeEach {
        # 每个用例前重置 Colors 域的标准值, 避免被其它用例污染
        & $script:mod {
            $script:Config.Colors.Danger = "$script:Esc[38;2;220;90;90m"
            $script:Config.Colors.Warning = "$script:Esc[38;2;220;180;80m"
            $script:Config.Colors.Rst = "$script:Esc[0m"
        }
    }

    Context 'Danger / Warning 主路径(Colors 域正常)' {

        It 'Danger 键应包裹 ⚠ 危险 + Colors.Danger + 重置码' {
            $out = & $script:mod { Format-GridViewStateText -Text '⚠ 危险' -ColorKey 'Danger' }
            # 完整输出结构: ESC[38;2;220;90;90m + 文字 + ESC[0m, 按 IndexOf 严格等价校验
            $expected = ([char]27) + '[38;2;220;90;90m⚠ 危险' + ([char]27) + '[0m'
            $out | Should -Be $expected
        }

        It 'Warning 键应包裹 ⚠ 备选 + Colors.Warning + 重置码' {
            $out = & $script:mod { Format-GridViewStateText -Text '⚠ 备选' -ColorKey 'Warning' }
            $expected = ([char]27) + '[38;2;220;180;80m⚠ 备选' + ([char]27) + '[0m'
            $out | Should -Be $expected
        }

        It '大小写不敏感: danger 应识别为 Danger 语义' {
            $out = & $script:mod { Format-GridViewStateText -Text '⚠ 危险' -ColorKey 'danger' }
            $out | Should -Match '\[38;2;220;90;90m'

            $out2 = & $script:mod { Format-GridViewStateText -Text '⚠ 危险' -ColorKey 'DANGER' }
            $out2 | Should -Match '\[38;2;220;90;90m'
        }
    }

    Context 'Colors 域缺失 / 异常回退' {

        It 'Colors 域未设置(整段被清空)时应静默回退到纯文本' {
            & $script:mod {
                $script:Config.Colors.Danger = $null
                $script:Config.Colors.Warning = $null
            }
            $out = & $script:mod { Format-GridViewStateText -Text '⚠ 危险' -ColorKey 'Danger' }
            $out | Should -Be '⚠ 危险'
        }

        It 'Colors.Danger 为空字符串时应静默回退到纯文本' {
            & $script:mod {
                $script:Config.Colors.Danger = ''
            }
            $out = & $script:mod { Format-GridViewStateText -Text '⚠ 危险' -ColorKey 'Danger' }
            $out | Should -Be '⚠ 危险'
        }

        It '非 Danger/Warning 键(如 SelectedBg/Primary/Muted)应原样返回文字' {
            foreach ($k in @('SelectedBg', 'Primary', 'Muted', 'Cyan', 'Bold', 'Rst', 'totally-unknown')) {
                $out = & $script:mod { param($text, $key) Format-GridViewStateText -Text $text -ColorKey $key } '⚠ 任意' $k
                $out | Should -Be '⚠ 任意'
            }
        }
    }

    Context '颜色码尾重置码自追加' {

        It '颜色码无尾重置码时应自动追加 0m' {
            # Colors.Danger 用无尾巴 SGR 形态(模拟用户自定义 24bit 颜色)
            & $script:mod {
                $script:Config.Colors.Danger = "$script:Esc[38;2;1;2;3m"
            }
            $out = & $script:mod { Format-GridViewStateText -Text '⚠ 危险' -ColorKey 'Danger' }
            $expected = ([char]27) + '[38;2;1;2;3m⚠ 危险' + ([char]27) + '[0m'
            $out | Should -Be $expected
        }

        It '颜色码已有尾重置码时不应重复叠加重置码' {
            # 用户 / 旧配置里 Colors.Danger 可能本来就以 Rst 结尾;
            # helper 必须先剥除冗余尾巴再统一追加到文字后, 确保输出只有一处 [0m。
            & $script:mod {
                $script:Config.Colors.Danger = "$script:Esc[38;2;220;90;90m$script:Esc[0m"
                $script:Config.Colors.Rst = "$script:Esc[0m"
            }
            $out = & $script:mod { Format-GridViewStateText -Text '⚠ 危险' -ColorKey 'Danger' }
            $expected = ([char]27) + '[38;2;220;90;90m⚠ 危险' + ([char]27) + '[0m'
            $out | Should -Be $expected
        }
    }

    Context 'ANSI 注入防御' {

        It 'Text 包含 ANSI 片段时应原样拼接,不二次解释' {
            # payload 内容含有 ESC 字符, helper 仅做"前后包裹", 不重解析颜色语义
            $payload = 'A' + ([char]27) + '[31mfoo' + ([char]27) + '[0mB'
            $out = & $script:mod { param($t) Format-GridViewStateText -Text $t -ColorKey 'Danger' } $payload
            $expected = ([char]27) + '[38;2;220;90;90m' + $payload + ([char]27) + '[0m'
            $out | Should -Be $expected
            # 关键: payload 中的 [31m 不能被剥除
            $out.Contains([char]27 + '[31m') | Should -BeTrue
        }
    }
}
