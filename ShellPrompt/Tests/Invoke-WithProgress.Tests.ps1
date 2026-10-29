# Invoke-WithProgress.Tests.ps1 - 进度封装 (生产链路的唯一走法)
# 2026-10-29: 轮询封装 Invoke-WithProgressPolling 整体删除后, 本文件改为覆盖
#   生产链路真正使用的那条路径 —— ScriptBlock 透传给 Spectre 的
#   Invoke-SpectreCommandWithStatus。
# 关键约束: Invoke-SpectreCommandWithStatus 的 -Spinner 带 ValidateSet,
#   传入不存在的成员名会在参数绑定阶段直接报错, 因此样式名翻译必须被断言。

Describe 'Invoke-WithProgress' {

    BeforeAll {
        # Pester v6: 路径与模块引用必须放在 BeforeAll 内解析
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    BeforeEach {
        # 替身: 真正执行 ScriptBlock 并回传其返回值, 只是不渲染动画
        Mock -CommandName Invoke-SpectreCommandWithStatus -ModuleName ShellPrompt -MockWith {
            & $ScriptBlock
        }
    }

    It 'ScriptBlock 的返回值应原样透传' {
        $r = & $script:mod { Invoke-WithProgress -Message '测试' -ScriptBlock { 'ok' } }
        $r | Should -Be 'ok'
    }

    It 'Title 应取自 -Message' {
        & $script:mod { Invoke-WithProgress -Message '加载主机列表' -ScriptBlock { 1 } } | Out-Null
        Should -Invoke -CommandName Invoke-SpectreCommandWithStatus -ModuleName ShellPrompt -Exactly 1 `
            -ParameterFilter { $Title -eq '加载主机列表' }
    }

    It 'Spinner 名应来自 Get-SpinnerStyleMapping (默认 Braille -> Dots3)' {
        & $script:mod { Invoke-WithProgress -Message '测试' -ScriptBlock { 1 } } | Out-Null
        Should -Invoke -CommandName Invoke-SpectreCommandWithStatus -ModuleName ShellPrompt -Exactly 1 `
            -ParameterFilter { $Spinner -eq 'Dots3' }
    }

    It '-Style 应影响传给 Spectre 的 spinner 名 (Blocks -> Material)' {
        & $script:mod { Invoke-WithProgress -Message '测试' -ScriptBlock { 1 } -Style 'Blocks' } | Out-Null
        Should -Invoke -CommandName Invoke-SpectreCommandWithStatus -ModuleName ShellPrompt -Exactly 1 `
            -ParameterFilter { $Spinner -eq 'Material' }
    }

    It 'ScriptBlock 抛出的异常应原样抛出' {
        $threw = $false
        $message = ''
        try {
            & $script:mod {
                Invoke-WithProgress -Message '测试' -ScriptBlock { throw 'boom' }
            }
        } catch {
            $threw = $true
            $message = $_.Exception.Message
        }
        $threw | Should -BeTrue
        $message | Should -BeLike '*boom*'
    }
}
