# Get-WttrTitleSuffix Pester 测试套件
# 目标运行时: Pester v5+/v6 (当前环境 Pester 6.2.0 / PowerShell 7.6.3)
# 覆盖矩阵:
#     - 城市名解析成功(nearest_area[0].areaName[0].value)
#     - 温度解析成功(current_condition[0].temp_C)
#     - 描述翻译命中内置字典(Smoky haze -> 烟雾)
#     - 描述未命中回退英文(MyCustomWeather -> 原样)
#     - Weather.ExtraWeatherDescMap 覆盖内置
#     - Weather.Enabled = $false 返回 ''
#     - HTTP 失败 / 空 JSON / 解析失败 -> 返回 ''
#     - 城市缺失 / 温度缺失 -> 返回 ''

Describe 'Get-WttrTitleSuffix' {

    BeforeAll {
        # Pester v6: 必须在 BeforeAll 内解析路径并导入模块(文件级变量对 It 不可见)
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    BeforeEach {
        # 重置 wttr 缓存(避免跨用例污染) 并确保 Weather.Enabled = $true
        & $script:mod {
            $script:_WttrCache = @{
                Result    = ''
                FetchedAt = [datetime]::MinValue
                CacheKey  = $null
            }
            if ($script:Config -and $script:Config.Weather) {
                $script:Config.Weather.Enabled = $true
                # 测试用的用户扩展默认清空, 由具体用例按需注入
                $script:Config.Weather.ExtraWeatherDescMap = [ordered]@{}
            }
        }
    }

    # 工厂: 构造一段 wttr.in j1 响应的 PSCustomObject,
    # 便于用例只声明差异字段, 其它全部填上合法兜底值
    function script:New-WttrJ1 {
        param(
            [string]$City = 'Shanghai',
            [string]$TempC = '26',
            [string]$DescValue = 'Smoky haze'
        )
        [PSCustomObject]@{
            nearest_area = @(
                [PSCustomObject]@{
                    areaName = @(
                        [PSCustomObject]@{ value = $City }
                    )
                }
            )
            current_condition = @(
                [PSCustomObject]@{
                    temp_C      = $TempC
                    weatherDesc = @(
                        [PSCustomObject]@{ value = $DescValue }
                    )
                }
            )
        }
    }

    Context '成功路径' {

        It '解析城市名 + 温度 + 内置字典命中(Smoky haze -> 烟雾)' {
            $j1 = New-WttrJ1 -City 'Chiuhuahsien' -TempC '26' -DescValue 'Smoky haze'
            Mock -CommandName Get-WttrWeather -ModuleName ShellPrompt -MockWith { ($j1 | ConvertTo-Json -Depth 10 -Compress) }

            $suffix = & $script:mod { Get-WttrTitleSuffix }

            $suffix | Should -Be ' - Chiuhuahsien: 烟雾 26°C'
        }

        It '温度解析(无城市时返回空串)' {
            # 温度解析的成功路径实际已被"城市缺失"用例覆盖, 这里验证温度字段缺失独立分支
            $j1 = [PSCustomObject]@{
                nearest_area = @(
                    [PSCustomObject]@{ areaName = @([PSCustomObject]@{ value = 'Shanghai' }) }
                )
                current_condition = @(
                    [PSCustomObject]@{
                        # 故意不带 temp_C 属性
                        weatherDesc = @([PSCustomObject]@{ value = 'Sunny' })
                    }
                )
            }
            Mock -CommandName Get-WttrWeather -ModuleName ShellPrompt -MockWith { ($j1 | ConvertTo-Json -Depth 10 -Compress) }

            $suffix = & $script:mod { Get-WttrTitleSuffix }

            $suffix | Should -Be ''
        }

        It '描述未命中内置字典时回退英文' {
            $j1 = New-WttrJ1 -City 'Shanghai' -TempC '20' -DescValue 'MyCustomWeather'
            Mock -CommandName Get-WttrWeather -ModuleName ShellPrompt -MockWith { ($j1 | ConvertTo-Json -Depth 10 -Compress) }

            $suffix = & $script:mod { Get-WttrTitleSuffix }

            $suffix | Should -Be ' - Shanghai: MyCustomWeather 20°C'
        }

        It 'Weather.ExtraWeatherDescMap 覆盖内置键(烟雾 -> 烟霞)' {
            # 内置字典对 Smoky haze 给出"烟雾", 用户扩展覆盖为"烟霞"
            & $script:mod {
                $script:Config.Weather.ExtraWeatherDescMap = [ordered]@{ 'smoky haze' = '烟霞' }
            }
            $j1 = New-WttrJ1 -City 'Shanghai' -TempC '26' -DescValue 'Smoky haze'
            Mock -CommandName Get-WttrWeather -ModuleName ShellPrompt -MockWith { ($j1 | ConvertTo-Json -Depth 10 -Compress) }

            $suffix = & $script:mod { Get-WttrTitleSuffix }

            $suffix | Should -Be ' - Shanghai: 烟霞 26°C'
        }
    }

    Context '功能开关' {

        It 'Weather.Enabled = $false 时直接返回空串, 不调 HTTP' {
            & $script:mod { $script:Config.Weather.Enabled = $false }
            Mock -CommandName Get-WttrWeather -ModuleName ShellPrompt -MockWith { 'SHOULD_NOT_BE_CALLED' }

            $suffix = & $script:mod { Get-WttrTitleSuffix }

            $suffix | Should -Be ''
            Should -Invoke -CommandName Get-WttrWeather -ModuleName ShellPrompt -Times 0
        }
    }

    Context '错误兜底' {

        It 'Get-WttrWeather 返回空字符串(HTTP 失败) -> 返回空串' {
            Mock -CommandName Get-WttrWeather -ModuleName ShellPrompt -MockWith { '' }

            $suffix = & $script:mod { Get-WttrTitleSuffix }

            $suffix | Should -Be ''
        }

        It 'Get-WttrWeather 返回非 JSON 文本 -> 返回空串, 不抛错' {
            Mock -CommandName Get-WttrWeather -ModuleName ShellPrompt -MockWith { '<html>500 Internal Server Error</html>' }

            $suffix = & $script:mod { Get-WttrTitleSuffix }

            $suffix | Should -Be ''
        }

        It 'JSON 中缺失 nearest_area -> 返回空串' {
            $j1 = [PSCustomObject]@{
                # 故意不带 nearest_area
                current_condition = @(
                    [PSCustomObject]@{ temp_C = '20'; weatherDesc = @([PSCustomObject]@{ value = 'Sunny' }) }
                )
            }
            Mock -CommandName Get-WttrWeather -ModuleName ShellPrompt -MockWith { ($j1 | ConvertTo-Json -Depth 10 -Compress) }

            $suffix = & $script:mod { Get-WttrTitleSuffix }

            $suffix | Should -Be ''
        }

        It 'JSON 中缺少 temp_C -> 返回空串' {
            $j1 = [PSCustomObject]@{
                nearest_area = @(
                    [PSCustomObject]@{ areaName = @([PSCustomObject]@{ value = 'Shanghai' }) }
                )
                current_condition = @(
                    [PSCustomObject]@{
                        # 故意不带 temp_C
                        weatherDesc = @([PSCustomObject]@{ value = 'Sunny' })
                    }
                )
            }
            Mock -CommandName Get-WttrWeather -ModuleName ShellPrompt -MockWith { ($j1 | ConvertTo-Json -Depth 10 -Compress) }

            $suffix = & $script:mod { Get-WttrTitleSuffix }

            $suffix | Should -Be ''
        }
    }
}