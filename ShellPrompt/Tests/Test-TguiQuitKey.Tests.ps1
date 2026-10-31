<#
.SYNOPSIS
    Test-TguiQuitKey (TGUI 退出键纯判定) 的 Pester 测试

.DESCRIPTION
    2026-10-31 真机 Ctrl+C 修复: KeyCode.ToString() 对带修饰键是 'C, CtrlMask'
    形态(真机取证 Diag-TguiKeys: "VIEW KeyDown: C, CtrlMask"), 整串与 'C'
    等值比较必失败(91b4280 首版真机无效的根因)。

    本测试用**形态桩**(PSCustomObject 携带 KeyCode 文本 + IsCtrl 标志)锁定
    判定逻辑本身; 形态常量取自真机取证输出, 不用真实 Key 对象 —— 全套件中
    每个 *.Tests 都会 Import-Module -Force(各自新建 ALC 载 Terminal.Gui.dll),
    实测塞到第 30 个文件时 Key 静态属性的 <Module> 初始化在某进程级状态下
    崩("type initializer for '<Module>' threw"), 与本 ALC 无关且不可从
    测试文件规避; Test-TguiQuitKey 本体只读 Key.KeyCode/Key.IsCtrl 两组
    成员, 行为级契约按上述形态常量锁定, Key 真实形态漂移由 Diag-TguiKeys
    真机取证兜底(见 tui-dashboard.md 验收清单)。
#>

Describe 'Test-TguiQuitKey (TGUI 退出键纯判定)' {

    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..\ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module ShellPrompt

        # 形态桩: 与真实 Key 的反射访问面一致(KeyCode 文本 / IsCtrl 布尔)
        $script:newShapeKey = {
            param([string]$KeyCodeText, [bool]$IsCtrl = $false)
            [PSCustomObject]@{ KeyCode = $KeyCodeText; IsCtrl = $IsCtrl }
        }
    }

    It 'Esc 文本形态应判定为退出键' {
        $isQuit = & $script:mod { param($kQuitKey) Test-TguiQuitKey -Key $kQuitKey } (& $script:newShapeKey 'Esc')
        $isQuit | Should -BeTrue
    }

    It '真机 Ctrl+C 形态 "C, CtrlMask" 应判定为退出键(91b4280 首版回归锁)' {
        $isQuit = & $script:mod { param($kQuitKey) Test-TguiQuitKey -Key $kQuitKey } (& $script:newShapeKey 'C, CtrlMask' $true)
        $isQuit | Should -BeTrue
    }

    It 'IsCtrl 属性为真、KeyCode 无后缀的 C(另一驱动形态)也应判定为退出键' {
        $isQuit = & $script:mod { param($kQuitKey) Test-TguiQuitKey -Key $kQuitKey } (& $script:newShapeKey 'C' $true)
        $isQuit | Should -BeTrue
    }

    It '无修饰 C 不应判定为退出键' {
        $isQuit = & $script:mod { param($kQuitKey) Test-TguiQuitKey -Key $kQuitKey } (& $script:newShapeKey 'C')
        $isQuit | Should -BeFalse
    }

    It '普通字母(Q)不应判定为退出键' {
        $isQuit = & $script:mod { param($kQuitKey) Test-TguiQuitKey -Key $kQuitKey } (& $script:newShapeKey 'Q')
        $isQuit | Should -BeFalse
    }

    It 'Ctrl 修饰的其它字母(如 Z)不应判定为退出键(只放行 C)' {
        $isQuit = & $script:mod { param($kQuitKey) Test-TguiQuitKey -Key $kQuitKey } (& $script:newShapeKey 'Z, CtrlMask' $true)
        $isQuit | Should -BeFalse
    }

    It '$null 应判定为非退出键(异常路径兜底)' {
        $isQuit = & $script:mod { param($kQuitKey) Test-TguiQuitKey -Key $kQuitKey } $null
        $isQuit | Should -BeFalse
    }
}
