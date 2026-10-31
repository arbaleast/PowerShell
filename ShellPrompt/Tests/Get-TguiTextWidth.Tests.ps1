# Get-TguiTextWidth.Tests.ps1 - 终端显示宽度测量(纯函数)契约测试
# 覆盖:
#   1. ASCII 半角 = 1 列;
#   2. 东亚全角(CJK 汉字/假名/全角标点) = 2 列;
#   3. 零宽字符(组合记号/变体选择符) = 0 列;
#   4. 代理对(增补平面)按**一个**宽字符计 2 列(不拆成两个代理项);
#   5. 空串/空值 = 0 列。
# 说明: 该函数是底部快捷键栏"按宽度取舍"的预算依据(见 New-TmuxTuiShortcutList),
#       口径必须与 Terminal.Gui 的 Wcwidth 一致, 否则窄屏会算错可容纳项数。

Describe '终端显示宽度测量 (Get-TguiTextWidth)' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It 'ASCII 半角字符按 1 列计' {
        & $script:mod { Get-TguiTextWidth -Text 'Attached' } | Should -Be 8
        & $script:mod { Get-TguiTextWidth -Text 'Enter' } | Should -Be 5
        & $script:mod { Get-TguiTextWidth -Text 'SSH' } | Should -Be 3
    }

    It '东亚全角字符按 2 列计(汉字/假名/全角标点)' {
        & $script:mod { Get-TguiTextWidth -Text '附着' } | Should -Be 4
        & $script:mod { Get-TguiTextWidth -Text '新建' } | Should -Be 4
        & $script:mod { Get-TguiTextWidth -Text '错误' } | Should -Be 4
        # 全角冒号/间隔号也算 2 列
        & $script:mod { Get-TguiTextWidth -Text '：' } | Should -Be 2
    }

    It '中英混排按实际宽度累加(与底栏宽度预算口径一致)' {
        & $script:mod { Get-TguiTextWidth -Text '会话: 3' } | Should -Be 7
        & $script:mod { Get-TguiTextWidth -Text '连接失败' } | Should -Be 8
        & $script:mod { Get-TguiTextWidth -Text 'n 新建' } | Should -Be 6
    }

    It '零宽字符(组合记号/变体选择符)按 0 列计' {
        # U+0301 组合尖音符(零宽) + 'e'
        & $script:mod { Get-TguiTextWidth -Text ([string][char]0x0301 + 'e') } | Should -Be 1
        # U+FE0F 变体选择符(零宽) + 'A'
        & $script:mod { Get-TguiTextWidth -Text ([string][char]0xFE0F + 'A') } | Should -Be 1
    }

    It '代理对(增补平面)按一个宽字符计 2 列, 不拆成两个代理项' {
        # U+1F600  grinning face = 代理对 D83D DE00
        & $script:mod { Get-TguiTextWidth -Text ([string][char]0xD83D + [string][char]0xDE00) } | Should -Be 2
    }

    It '空串与空值返回 0' {
        & $script:mod { Get-TguiTextWidth -Text '' } | Should -Be 0
        & $script:mod { Get-TguiTextWidth -Text $null } | Should -Be 0
    }
}
