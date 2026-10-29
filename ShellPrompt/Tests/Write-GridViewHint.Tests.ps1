# Write-GridViewHint Pester 测试套件
# 目标运行时: Pester v5+/v6 (当前环境 Pester 6.2.0 / PowerShell 7.6.3)
# 覆盖 (2026-10-18 重构, 单行天气已迁至 PSTui -Title 区):
#   - Weather.Enabled=$true: 提示行不再包含 wttr 片段(天气在窗口标题)
#   - Weather.Enabled=$false: 提示行同样不包含 wttr 片段(短路保护)
#   - Write-GridViewHint 不调 Get-WttrWeather(单行天气拼接逻辑已彻底迁出)
# 注: 草案 A.2 已撤回(2026-10-19): 3 个 Invoke-GridView* 菜单不再调用 Write-GridViewHint /
#     Show-GridViewMenuBanner / Get-GridViewMenuTitleSuffix; 后两个函数及对应 Pester 文件已删除.
#     Write-GridViewHint 保留(本文件 2 个 Context 共 2 个用例), 作为内部函数可被未来调用点复用.
# 注: Write-GridViewHint 是 dot-source 到模块作用域的内部函数;
#     Mock Write-SpectreHost 把 message 写入模块作用域 script 变量,
#     断言时通过 & $script:mod { ... } 读取该变量以跨 scope 同步.
#     Pester v6 上下文外层的 $script: 仍属 Pester runspace 自身的 script scope,
#     与模块内 $script: 隔离 — 因此必须用模块自身的 script scope.

Describe 'Write-GridViewHint' {

    BeforeAll {
        # Pester v6: 路径解析与模块导入必须位于 BeforeAll 内
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    BeforeEach {
        # 重置模块作用域捕获变量, 避免跨测试污染
        & $script:mod {
            $script:_LastSpectreMessage = $null
        }
    }

    Context '天气已迁出提示行(方案 R2)' {

        It 'Weather.Enabled=$true: 提示行不包含 wttr 片段, Get-WttrWeather 不被调用' {
            $message = & $script:mod {
                $origEn = $script:Config.Weather.Enabled
                try {
                    $script:Config.Weather.Enabled = $true

                    Mock -CommandName Get-WttrWeather  -ModuleName ShellPrompt -MockWith { 'SHOULD_NOT_BE_CALLED' }
                    Mock -CommandName Write-SpectreHost -ModuleName ShellPrompt -MockWith {
                        param($Message)
                        $script:_LastSpectreMessage = [string]$Message
                    }

                    Write-GridViewHint -Text 'BASE_HINT'
                    $script:_LastSpectreMessage
                } finally {
                    $script:Config.Weather.Enabled = $origEn
                }
            }

            # 1. 重构后, Write-GridViewHint 不再触达天气, Get-WttrWeather 不应被调用
            Should -Invoke -CommandName Get-WttrWeather -ModuleName ShellPrompt -Exactly 0
            # 2. 提示行应原样包含 BASE_HINT, 不含 wttr 也不含分隔符
            $message | Should -Match 'BASE_HINT'
            $message | Should -Not -Match 'SHOULD_NOT_BE_CALLED'
            $message | Should -Not -Match '\|'
        }
    }

    Context '配置禁用' {

        It 'Weather.Enabled=$false: 提示行同样不包含 wttr 片段' {
            $message = & $script:mod {
                $origEn = $script:Config.Weather.Enabled
                try {
                    $script:Config.Weather.Enabled = $false

                    Mock -CommandName Get-WttrWeather  -ModuleName ShellPrompt -MockWith { 'SHOULD_NOT_BE_CALLED' }
                    Mock -CommandName Write-SpectreHost -ModuleName ShellPrompt -MockWith {
                        param($Message)
                        $script:_LastSpectreMessage = [string]$Message
                    }

                    Write-GridViewHint -Text 'BASE_HINT'
                    $script:_LastSpectreMessage
                } finally {
                    $script:Config.Weather.Enabled = $origEn
                }
            }

            Should -Invoke -CommandName Get-WttrWeather -ModuleName ShellPrompt -Exactly 0
            $message | Should -Match 'BASE_HINT'
            $message | Should -Not -Match 'SHOULD_NOT_BE_CALLED'
            $message | Should -Not -Match '\|'
        }
    }
}
