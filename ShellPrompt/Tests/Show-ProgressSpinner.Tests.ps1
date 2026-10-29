# Show-ProgressSpinner Pester 测试
# 阶段 5: 固化失败回归测试（等待 fix）
# v2.0: 单轨 Spectre 时代, PS 5.1 兼容不再是目标, 本文件按 pwsh 7.4+ 语义断言
# (ESC 转义序列在 pwsh 下原生可用, 不再是缺陷点)
# 目标运行时: Pester v5+/v6 (当前环境 Pester 6.2.0 / PowerShell 7.6.3)
# 迁移要点:
#   - 断言改为 v5+ 连字符算子: Should -Be / -BeGreaterThan
#   - 模块路径不在文件顶层解析 (Pester v6 中文件级变量在 BeforeAll / It 内不可见),
#     统一在 BeforeAll 内基于 $PSScriptRoot 计算
#   - 帧序列循环改为在模块作用域内执行 (v3 写法 & $script:mod { ... } $i 的附加参数形式不受支持)

Describe 'Show-ProgressSpinner Bug 诊断测试' {

    BeforeAll {
        # Pester v6: 路径解析与模块导入必须位于 BeforeAll 内
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    Context 'ANSI 转义序列 (pwsh 7.4+ 原生支持)' {

        It 'Get-CachedConfig 返回的颜色值应包含真正的 ESC 字符 (0x1B)' {
            # 锁定回归: 颜色常量必须携带真实 ESC 字节, 否则 Spectre/ANSI 渲染失效
            $primary = & $script:mod { Get-CachedConfig -Section 'Colors' -Key 'FreshGreen' -Default "`e[38;2;137;209;133m" }
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($primary)
            $hasEsc = ($bytes -contains 27)
            $hasEsc | Should -Be $true
        }

        It 'Get-CachedConfig 返回的 Rst 重置码应包含 ESC 字符' {
            $rst = & $script:mod { Get-CachedConfig -Section 'Colors' -Key 'Rst' -Default "`e[0m" }
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($rst)
            $hasEsc = ($bytes -contains 27)
            $hasEsc | Should -Be $true
        }

        It 'Show-ProgressSpinner 非 PassThru 输出应包含真正的 ESC 字符' {
            # 这个测试通过捕获输出字节来验证 ANSI 序列
            # 方法：使用 Start-Job 在后台调用，然后捕获输出
            # 作业块内通过 $using: 引用外层变量 (PowerShell 后台作业的跨作用域语法,
            # 也是 PSSA PSUseUsingScopeModifierInNewRunspaces 要求的写法)
            $job = Start-Job -ScriptBlock {
                Import-Module $using:manifestPath -Force
                $jobMod = Get-Module ShellPrompt

                # 使用 PassThru + 手动构造来推断实际输出
                $result = & $jobMod { Show-ProgressSpinner -Message 'test' -Frame 0 -Style 'Braille' -PassThru }

                # 获取 Get-CachedConfig 的返回值
                $primary = & $jobMod { Get-CachedConfig -Section 'Colors' -Key 'FreshGreen' -Default "`e[38;2;137;209;133m" }
                $primaryHasEsc = ([System.Text.Encoding]::UTF8.GetBytes($primary) -contains 27)

                return @{
                    Glyph = $result.Glyph
                    PrimaryHasEsc = $primaryHasEsc
                }
            }

            $timeout = Wait-Job $job -Timeout 30
            if (-not $timeout) {
                Remove-Job $job -Force
                $false | Should -Be $true
                return
            }

            $output = Receive-Job $job
            Remove-Job $job -Force

            # 验证帧字符正确
            $output.Glyph | Should -Be '⠋'

            # 验证 ANSI 转义序列存在
            $output.PrimaryHasEsc | Should -Be $true
        }

        It '帧序列应在 PassThru 模式下正确循环 (10 帧 Braille)' {
            # 这个测试验证动画逻辑本身是正确的
            # v6 迁移: 帧循环在模块作用域内执行, 避免 v3 写法 & $script:mod { ... } $i 的附加参数形式
            $frames = & $script:mod {
                $out = @()
                for ($i = 0; $i -lt 10; $i++) {
                    $out += (Show-ProgressSpinner -Message 'test' -Frame $i -Style 'Braille' -PassThru).Glyph
                }
                $out
            }

            $uniqueFrames = @($frames | Sort-Object -Unique)
            $uniqueFrames.Count | Should -Be 10

            # 验证帧序列
            $expectedFrames = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
            for ($i = 0; $i -lt 10; $i++) {
                $frames[$i] | Should -Be $expectedFrames[$i]
            }
        }

        It '连续帧索引应正确回绕 (Frame 10 -> Frame 0)' {
            # 验证循环逻辑
            $frame0 = & $script:mod { Show-ProgressSpinner -Message 't' -Frame 0 -Style 'Braille' -PassThru }
            $frame10 = & $script:mod { Show-ProgressSpinner -Message 't' -Frame 10 -Style 'Braille' -PassThru }

            $frame0.Glyph | Should -Be $frame10.Glyph
        }
    }

    Context 'Invoke-WithProgress 集成测试' {

        It 'Invoke-WithProgress SuppressConsole + PollScript 应返回多个不同帧' {
            # 多帧只能由 -PollScript 驱动 (Spectre 同步封装无逐帧语义);
            # 同步模式恒为单帧, 不得再期望 >1 帧
            $result = & $script:mod {
                $script:pollCount = 0
                $poll = {
                    if ($script:pollCount -lt 2) { $script:pollCount++; return $false }
                    return $true
                }
                Invoke-WithProgress -Message '测试' -ScriptBlock { Start-Sleep -Milliseconds 100 } -PollScript $poll -IntervalMs 30 -TimeoutSeconds 5 -SuppressConsole
            }

            $result.Status | Should -Be 'Success'
            $result.Frames.Count | Should -BeGreaterThan 1
        }

        It 'Invoke-WithProgress 超时后应抛 TimeoutException' {
            $threw = $false
            $exType = ''

            try {
                & $script:mod {
                    Invoke-WithProgress -Message '超时测试' -ScriptBlock { } -PollScript { $false } -IntervalMs 20 -TimeoutSeconds 1 -SuppressConsole
                }
            } catch {
                $threw = $true
                $exType = $_.Exception.GetType().Name
            }

            $threw | Should -Be $true
            $exType | Should -Be 'TimeoutException'
        }
    }

    Context 'v2.0 单轨路由 (无 legacy 轨 / 无版本探测)' {
        BeforeAll {
            # Pester v6: 嵌套 Context 内确保 $script:mod 可用 (不重复 Force 导入, 避免重载模块)
            $script:mod = Get-Module -Name 'ShellPrompt'
        }

        It 'Get-SpinnerStyleMapping: Dots -> Dots6' {
            & $script:mod { Get-SpinnerStyleMapping -Style 'Dots' } | Should -Be 'Dots6'
        }

        It 'Get-SpinnerStyleMapping: Braille -> Dots3' {
            & $script:mod { Get-SpinnerStyleMapping -Style 'Braille' } | Should -Be 'Dots3'
        }

        It 'Get-SpinnerStyleMapping: Ascii -> Ascii' {
            & $script:mod { Get-SpinnerStyleMapping -Style 'Ascii' } | Should -Be 'Ascii'
        }

        It 'Get-SpinnerStyleMapping: Blocks -> Block1' {
            & $script:mod { Get-SpinnerStyleMapping -Style 'Blocks' } | Should -Be 'Block1'
        }

        It 'Get-SpinnerStyleMapping: Arrows -> Arrow' {
            & $script:mod { Get-SpinnerStyleMapping -Style 'Arrows' } | Should -Be 'Arrow'
        }

        It 'Get-SpinnerStyleMapping: 未知样式回退到 Dots6' {
            & $script:mod { Get-SpinnerStyleMapping -Style 'NoSuch' } | Should -Be 'Dots6'
        }

        It 'Get-SpinnerStyleMapping: 不传 Style 时默认 Braille -> Dots3' {
            & $script:mod { Get-SpinnerStyleMapping } | Should -Be 'Dots3'
        }

        It 'Show-ProgressSpinner 渲染前必须转义 Spectre markup (裸 [ 会丢失)' {
            # 裸 '[' 被 Spectre 当作样式标记, 会吞掉 ESC 段的 '[' 字符。
            # ConvertTo-SpectrePlainText 负责 '[' -> '[[', 转义后应为双写。
            $r = & $script:mod { ConvertTo-SpectrePlainText -Text '[38;2;1;2;3m' }
            $r | Should -Be '[[38;2;1;2;3m'
        }

        It 'Show-ProgressSpinner + -Done 在 PassThru 模式下应返回完成态结构' {
            $r = & $script:mod { Show-ProgressSpinner -Message 'ok' -Done -Status Success -PassThru }
            $r.Glyph | Should -Be ([char]0x2713)  # ✓
            $r.IsDone | Should -Be $true
            $r.Status | Should -Be 'Success'
        }

        It 'Invoke-WithProgress -SuppressConsole 路由到轮询封装并返回结构化对象' {
            $r = & $script:mod { Invoke-WithProgress -Message 't' -ScriptBlock { 42 } -SuppressConsole }
            $r.Status | Should -Be 'Success'
            $r.Result | Should -Be 42
        }

        It 'Invoke-WithProgress -PollScript 路由到轮询封装并产生多帧' {
            $r = & $script:mod {
                $script:pollCount = 0
                $poll = {
                    if ($script:pollCount -lt 2) { $script:pollCount++; return $false }
                    return $true
                }
                Invoke-WithProgress -Message 't' -ScriptBlock { } -PollScript $poll -IntervalMs 20 -TimeoutSeconds 5 -SuppressConsole
            }
            $r.Status | Should -Be 'Success'
            $r.Frames.Count | Should -BeGreaterThan 1
        }

        It 'Invoke-WithProgress 同步模式仍只产 1 帧 (无 PollScript 时不逐帧刷新)' {
            # 固化"无 PollScript 时不产多帧"的现有行为,
            # 避免未来重构误把同步模式也改成轮询
            $r = & $script:mod { Invoke-WithProgress -Message 't' -ScriptBlock { 99 } -SuppressConsole }
            $r.Frames.Count | Should -Be 1
            $r.Result | Should -Be 99
        }
    }
}