# Get-SpinnerStyleMapping.Tests.ps1 - ShellPrompt 样式名 -> Spectre spinner 名
# 2026-10-29: 从 Show-ProgressSpinner.Tests.ps1 迁出 (Show-ProgressSpinner 整体删除)。
# 覆盖:
#   - 5 个样式名 + 未知样式 + 默认样式的映射结果
#   - 映射结果必须是 Spectre.Console `Spinner.Known` 的真实成员名
#     (Invoke-SpectreCommandWithStatus -Spinner 带 ValidateSet, 名字不存在会在
#      参数绑定阶段直接报错 —— 2026-10-29 正是这样发现 Blocks -> 'Block1' 的死映射)

Describe 'Get-SpinnerStyleMapping' {

    BeforeAll {
        # Pester v6: 路径与模块引用必须放在 BeforeAll 内解析
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    Context '样式名映射' {

        It 'Dots -> Dots6' {
            & $script:mod { Get-SpinnerStyleMapping -Style 'Dots' } | Should -Be 'Dots6'
        }

        It 'Braille -> Dots3' {
            & $script:mod { Get-SpinnerStyleMapping -Style 'Braille' } | Should -Be 'Dots3'
        }

        It 'Ascii -> Ascii' {
            & $script:mod { Get-SpinnerStyleMapping -Style 'Ascii' } | Should -Be 'Ascii'
        }

        It 'Blocks -> Material (Spectre 没有 Block/Blocks 成员名)' {
            & $script:mod { Get-SpinnerStyleMapping -Style 'Blocks' } | Should -Be 'Material'
        }

        It 'Arrows -> Arrow' {
            & $script:mod { Get-SpinnerStyleMapping -Style 'Arrows' } | Should -Be 'Arrow'
        }

        It '未知样式回退到 Dots6' {
            & $script:mod { Get-SpinnerStyleMapping -Style 'NoSuch' } | Should -Be 'Dots6'
        }

        It '不传 Style 时默认 Braille -> Dots3' {
            & $script:mod { Get-SpinnerStyleMapping } | Should -Be 'Dots3'
        }
    }

    Context '映射结果必须是 Spectre 的合法 spinner 名' {

        It '5 个样式的映射结果都在 Spectre.Spinner.Known 的成员名里' {
            # 退路名单: Spectre.Console 的 Spinner.Known 成员名中确实存在的那几个
            # (取自 Modules/PwshSpectreConsole/2.6.3/lib/Spectre.Console.xml 的枚举文档)。
            # 之所以要有退路: 不能让本用例依赖"能否枚举到 Spectre 类型"这一环境事实,
            # 否则在类型不可见的环境里会静默失去保护力。
            $fallback = @('Ascii', 'Arrow', 'Dots3', 'Dots6', 'Material')

            $known = $null
            try {
                # 与 Modules/PwshSpectreConsole 的 SpectreConsoleSpinner 验证器同一取法
                $known = [Spectre.Console.Spinner+Known] |
                    Get-Member -Static -MemberType Properties |
                    Select-Object -ExpandProperty Name
            } catch {
                $known = $null
            }

            foreach ($style in @('Braille', 'Ascii', 'Blocks', 'Dots', 'Arrows')) {
                $mapped = & $script:mod { param($s) Get-SpinnerStyleMapping -Style $s } $style
                $fallback | Should -Contain $mapped -Because "样式 '$style' 的映射名必须是合法的 Spectre spinner 名"
                if ($known) {
                    $known | Should -Contain $mapped -Because "样式 '$style' 的映射名必须存在于 Spectre.Spinner.Known"
                }
            }
        }
    }
}
