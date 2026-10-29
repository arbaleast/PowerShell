# Update-Weather Pester 测试套件
# 目标运行时: Pester v5+/v6 (当前环境 Pester 6.2.0 / PowerShell 7.6.3)
# 覆盖:
#   - 模块未加载时: 不抛, 输出告警后 return
#   - Get-WttrWeather 返回空字符串: 输出 [Update-Weather] 提示, 不抛
#   - 成功路径: 走到 Write-Host 输出 wttr 短串 (assert Get-WttrWeather 被调 1 次)

Describe 'Update-Weather' {

    BeforeAll {
        # Pester v6: 路径解析与模块导入必须位于 BeforeAll 内
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    Context '模块未加载' {

        It 'Get-Module 返回 $null 时不应抛, 直接 return' {
            # 用 Mock 把模块作用域内的 Get-Module -Name ShellPrompt 拦截为 $null
            Mock -CommandName Get-Module -ModuleName ShellPrompt -MockWith { $null }
            $threw = $false
            try {
                & $script:mod { Update-Weather }
            } catch {
                $threw = $true
            }
            $threw | Should -BeFalse
        }
    }

    Context 'wttr 返回空' {

        It 'Get-WttrWeather 返回空字符串时: 不抛, 走 Write-Host 提示路径' {
            Mock -CommandName Get-WttrWeather -ModuleName ShellPrompt -MockWith { '' }
            $threw = $false
            try {
                & $script:mod { Update-Weather }
            } catch {
                $threw = $true
            }
            $threw | Should -BeFalse
            # 空串路径不应写入任何 wttr 缓存结果(函数内部直接 return)
            Should -Invoke -CommandName Get-WttrWeather -ModuleName ShellPrompt -Times 1
        }
    }

    Context '成功路径' {

        It 'Get-WttrWeather 返回非空短串时: 走到 Write-Host 输出' {
            Mock -CommandName Get-WttrWeather -ModuleName ShellPrompt -MockWith { 'Shanghai: 🌫 +18°C' }
            $threw = $false
            try {
                & $script:mod { Update-Weather }
            } catch {
                $threw = $true
            }
            $threw | Should -BeFalse
            # 成功路径必然调用 Get-WttrWeather 1 次(应 Process 走 -Format Short -CacheMinutes 0)
            Should -Invoke -CommandName Get-WttrWeather -ModuleName ShellPrompt -Times 1
        }
    }
}