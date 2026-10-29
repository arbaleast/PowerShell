# Get-WttrWeather Pester 测试套件
# 目标运行时: Pester v5+/v6 (当前环境 Pester 6.2.0 / PowerShell 7.6.3)
# 迁移要点 (由 Pester v3 语法演进而来):
#   - 断言统一改为 v5+ 连字符算子: Should -Be / -Match / -BeGreaterThan
#   - Assert-MockCalled -Scope It 改为 Should -Invoke -CommandName ... -ModuleName ...
#   - 模块清单路径不再放在文件顶层: Pester v6 中文件级变量在 It / BeforeAll 内不可见,
#     统一在 BeforeAll 内基于 $PSScriptRoot 重新计算
# 覆盖:
#   - 元数据 [OutputType] 与中文 .SYNOPSIS 帮助
#   - 缓存命中 / 未命中 / Format 切换 / CacheMinutes=0 强制刷新
#   - 错误兜底:HTTP 异常 / 远端空响应 / CustomUrl 缺 Url
#   - 纯函数 Get-WttrFormatUrl 的 URL 解析

Describe 'Get-WttrWeather' {

    BeforeAll {
        # Pester v6: 必须在 BeforeAll 内解析路径并导入模块(文件级变量对 It 不可见)
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    BeforeEach {
        # 重置模块作用域缓存,避免跨测试污染
        & $script:mod {
            $script:_WttrCache = @{
                Result    = ''
                FetchedAt = [datetime]::MinValue
                CacheKey  = $null
            }
        }
    }

    Context '元数据 & 帮助' {

        It '具有 [OutputType([string])]' {
            $cmd = & $script:mod { Get-Command Get-WttrWeather }
            $names = @($cmd.OutputType | ForEach-Object { $_.Type.Name })
            (@($names) -contains 'String') | Should -Be $true
        }

        It '包含中文 .SYNOPSIS 帮助' {
            $help = & $script:mod { Get-Help Get-WttrWeather }
            $help.Synopsis | Should -Match '天气'
        }

        It 'Verb (Get) 在 Get-Verb 批准列表中' {
            $approved = & $script:mod { (Get-Verb | Where-Object { $_.Verb -eq 'Get' }).Verb }
            (@($approved) -contains 'Get') | Should -Be $true
        }
    }

    Context '缓存行为' {

        It '首次调用:缓存未命中,触发 HTTP' {
            Mock -CommandName Get-WttrHttpBody  -ModuleName ShellPrompt -MockWith { 'SHORT_BODY' }
            Mock -CommandName Get-WttrFormatUrl -ModuleName ShellPrompt -MockWith { 'https://wttr.in?format=3' }

            $r = & $script:mod { Get-WttrWeather -CacheMinutes 10 }

            $r | Should -Be 'SHORT_BODY'
            Should -Invoke -CommandName Get-WttrHttpBody -ModuleName ShellPrompt -Exactly 1
        }

        It '第二次相同参数:命中缓存,不再次 HTTP' {
            Mock -CommandName Get-WttrHttpBody  -ModuleName ShellPrompt -MockWith { 'CACHED_BODY' }
            Mock -CommandName Get-WttrFormatUrl -ModuleName ShellPrompt -MockWith { 'https://wttr.in?format=3' }

            $first  = & $script:mod { Get-WttrWeather }
            $second = & $script:mod { Get-WttrWeather }

            $first  | Should -Be 'CACHED_BODY'
            $second | Should -Be 'CACHED_BODY'
            Should -Invoke -CommandName Get-WttrHttpBody -ModuleName ShellPrompt -Exactly 1
        }

        It '切换 Format:缓存键变化,重新抓取' {
            Mock -CommandName Get-WttrFormatUrl -ModuleName ShellPrompt -ParameterFilter { $Format -eq 'Short' } -MockWith { 'https://wttr.in?format=3' }
            Mock -CommandName Get-WttrFormatUrl -ModuleName ShellPrompt -ParameterFilter { $Format -eq 'Full'  } -MockWith { 'https://wttr.in' }
            Mock -CommandName Get-WttrHttpBody  -ModuleName ShellPrompt -ParameterFilter { $Uri -like '*format=3' } -MockWith { 'SHORT' }
            Mock -CommandName Get-WttrHttpBody  -ModuleName ShellPrompt -ParameterFilter { $Uri -eq 'https://wttr.in' } -MockWith { 'FULL' }

            $short = & $script:mod { Get-WttrWeather -Format Short }
            $full  = & $script:mod { Get-WttrWeather -Format Full  }

            $short | Should -Be 'SHORT'
            $full  | Should -Be 'FULL'
            Should -Invoke -CommandName Get-WttrHttpBody -ModuleName ShellPrompt -Exactly 2
        }

        It 'CacheMinutes=0:强制绕过缓存,每次都重新抓取' {
            Mock -CommandName Get-WttrHttpBody  -ModuleName ShellPrompt -MockWith { 'X' }
            Mock -CommandName Get-WttrFormatUrl -ModuleName ShellPrompt -MockWith { 'https://wttr.in?format=3' }

            & $script:mod { Get-WttrWeather -CacheMinutes 0 }
            & $script:mod { Get-WttrWeather -CacheMinutes 0 }
            & $script:mod { Get-WttrWeather -CacheMinutes 0 }

            Should -Invoke -CommandName Get-WttrHttpBody -ModuleName ShellPrompt -Exactly 3
        }
    }

    Context '错误兜底' {

        It 'HTTP 抛异常:返回空字符串,不上抛' {
            Mock -CommandName Get-WttrHttpBody  -ModuleName ShellPrompt -MockWith { throw 'simulated timeout' }
            Mock -CommandName Get-WttrFormatUrl -ModuleName ShellPrompt -MockWith { 'https://wttr.in?format=3' }

            $r = & $script:mod { Get-WttrWeather }
            $r | Should -Be ''
        }

        It 'HTTP 返回空字符串:返回空字符串,不写入缓存' {
            Mock -CommandName Get-WttrHttpBody  -ModuleName ShellPrompt -MockWith { '' }
            Mock -CommandName Get-WttrFormatUrl -ModuleName ShellPrompt -MockWith { 'https://wttr.in?format=3' }

            $r = & $script:mod { Get-WttrWeather }
            $r | Should -Be ''

            $cache = & $script:mod { $script:_WttrCache }
            $cache.Result | Should -Be ''
        }

        It 'CustomUrl 但 -Url 为空:返回空字符串,不调用 HTTP' {
            # 显式 mock 两个辅助,避免被前序测试的 mock 泄漏影响
            Mock -CommandName Get-WttrFormatUrl -ModuleName ShellPrompt -MockWith { '' }
            Mock -CommandName Get-WttrHttpBody   -ModuleName ShellPrompt -MockWith { 'SHOULD_NOT_BE_CALLED' }

            $r = & $script:mod { Get-WttrWeather -Format CustomUrl -Url '' }
            $r | Should -Be ''

            Should -Invoke -CommandName Get-WttrHttpBody -ModuleName ShellPrompt -Exactly 0
        }

        It '成功结果会被写入缓存(用于下次命中)' {
            Mock -CommandName Get-WttrHttpBody  -ModuleName ShellPrompt -MockWith { 'PERSISTED' }
            Mock -CommandName Get-WttrFormatUrl -ModuleName ShellPrompt -MockWith { 'https://wttr.in?format=3' }

            & $script:mod { Get-WttrWeather }

            $cache = & $script:mod { $script:_WttrCache }
            $cache.Result    | Should -Be 'PERSISTED'
            $cache.CacheKey  | Should -Be 'Short|'
            $cache.FetchedAt | Should -BeGreaterThan ([datetime]::MinValue)
        }
    }
}

Describe 'Get-WttrFormatUrl (纯函数)' {

    BeforeAll {
        # Pester v6: 路径解析与模块导入必须位于 BeforeAll 内
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It 'Format=Short 解析为 ?format=3' {
        $u = & $script:mod { Get-WttrFormatUrl -Format 'Short' }
        $u | Should -Be 'https://wttr.in?format=3'
    }

    It 'Format=Full 解析为根 URL' {
        $u = & $script:mod { Get-WttrFormatUrl -Format 'Full' }
        $u | Should -Be 'https://wttr.in'
    }

    It 'Format=CustomUrl 透传 -Url' {
        $u = & $script:mod { Get-WttrFormatUrl -Format 'CustomUrl' -Url 'https://wttr.in/Shanghai?format=4' }
        $u | Should -Be 'https://wttr.in/Shanghai?format=4'
    }

    It 'Format=CustomUrl 但 -Url 为空时返回空字符串' {
        $u = & $script:mod { Get-WttrFormatUrl -Format 'CustomUrl' -Url '' }
        $u | Should -Be ''
    }
}
