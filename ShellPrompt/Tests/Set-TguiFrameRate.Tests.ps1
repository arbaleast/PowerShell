# Set-TguiFrameRate.Tests.ps1 - 主循环帧率上限调整的契约测试
#
# 背景 (2026-11-01 实测): Terminal.Gui 2.4.10 的
# `Application.DefaultMaximumIterationsPerSecond` = **25** ⇒ 相邻两帧之间有
# 40ms 的**硬地板**, 而按键必须等下一帧才能出画面。这解释了"把重绘面积缩小
# 5~12 倍之后延迟几乎没变"—— 延迟不在"画多少", 而在"多久画一次"。
#
# 覆盖:
#   - 默认值确实被读成 25(把"25"这个事实钉住, 免得 TG 升级后地板变了没人知道)
#   - 只调高不调低; 已达标时不动; 能继续往上调
#   - 设置真的落到 Application.MaximumIterationsPerSecond 上

Describe 'Set-TguiFrameRate (主循环帧率上限)' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It 'Terminal.Gui 2.4.10 的默认帧率上限是 25 fps(即 40ms 的帧周期地板)' {
        $default = & $script:mod {
            $tg = Get-TguiContext
            $static = [System.Reflection.BindingFlags]'Public,Static'
            [int]$tg.Types.Application.GetProperty('DefaultMaximumIterationsPerSecond', $static).GetValue($null)
        }
        # 这个数字是"按键延迟地板"的来源: 1000/25 = 40ms。
        # TG 若升级导致它变化, 这条断言会失败并提醒我们重新评估延迟地板。
        $default | Should -Be 25
    }

    It '把帧率抬到 100fps, 并确实落到 Application.MaximumIterationsPerSecond 上' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $static = [System.Reflection.BindingFlags]'Public,Static'
            $prop = $tg.Types.Application.GetProperty('MaximumIterationsPerSecond', $static)
            $before = [int]$prop.GetValue($null)
            $r = Set-TguiFrameRate -Tgui $tg -MinimumIps 100
            [PSCustomObject]@{
                Before   = $before
                Applied  = $r.Applied
                Current  = $r.Current
                Actual   = [int]$prop.GetValue($null)
            }
        }
        $result.Applied | Should -BeTrue
        $result.Current | Should -Be 100
        $result.Actual | Should -Be 100
    }

    It '已经达标时**不动**(不把用户/环境调高过的帧率降回去)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $static = [System.Reflection.BindingFlags]'Public,Static'
            $prop = $tg.Types.Application.GetProperty('MaximumIterationsPerSecond', $static)
            [void]$prop.SetValue($null, [uint16]150)
            $r = Set-TguiFrameRate -Tgui $tg -MinimumIps 100
            [PSCustomObject]@{
                Applied = $r.Applied
                Current = $r.Current
                Actual  = [int]$prop.GetValue($null)
            }
        }
        $result.Applied | Should -BeFalse
        $result.Current | Should -Be 150
        $result.Actual | Should -Be 150
    }

    It '可以继续往上调(上限只设地板, 不封顶)' {
        $result = & $script:mod {
            $tg = Get-TguiContext
            $static = [System.Reflection.BindingFlags]'Public,Static'
            $prop = $tg.Types.Application.GetProperty('MaximumIterationsPerSecond', $static)
            [void]$prop.SetValue($null, [uint16]100)
            $r = Set-TguiFrameRate -Tgui $tg -MinimumIps 200
            [PSCustomObject]@{ Applied = $r.Applied; Actual = [int]$prop.GetValue($null) }
        }
        $result.Applied | Should -BeTrue
        $result.Actual | Should -Be 200
    }
}
