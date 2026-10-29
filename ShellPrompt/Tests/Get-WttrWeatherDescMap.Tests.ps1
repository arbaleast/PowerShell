# Get-WttrWeatherDescMap Pester 测试套件
# 目标运行时: Pester v5+/v6 (当前环境 Pester 6.2.0 / PowerShell 7.6.3)
# 覆盖矩阵:
#     - 内置字典完整性(至少 10 条关键短语的中文映射)
#     - 用户 ExtraWeatherDescMap 同名键覆盖内置
#     - 用户 ExtraWeatherDescMap 追加新键
#     - 用户 ExtraWeatherDescMap 为 null / 非字典 / Count=0 时静默跳过
#     - 用户 ExtraWeatherDescMap 含 null Key / null Value 时跳过该条

Describe 'Get-WttrWeatherDescMap' {

    BeforeAll {
        # Pester v6: 必须在 BeforeAll 内解析路径并导入模块
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    BeforeEach {
        # 重置用户扩展映射, 避免跨用例污染
        & $script:mod {
            if ($script:Config -and $script:Config.Weather) {
                $script:Config.Weather.ExtraWeatherDescMap = [ordered]@{}
            }
        }
    }

    Context '内置字典' {

        It '内置字典应至少包含 42 条常见描述映射' {
            $map = & $script:mod { Get-WttrWeatherDescMap }
            $map.Count | Should -BeGreaterOrEqual 42
        }

        It '关键英文短语到中文的映射应正确(至少 10 条)' {
            $map = & $script:mod { Get-WttrWeatherDescMap }
            $map.Contains('smoky haze')       | Should -BeTrue
            $map['smoky haze']                | Should -Be '烟雾'
            $map.Contains('sunny')            | Should -BeTrue
            $map['sunny']                     | Should -Be '晴'
            $map.Contains('clear')            | Should -BeTrue
            $map['clear']                     | Should -Be '晴'
            $map.Contains('partly cloudy')    | Should -BeTrue
            $map['partly cloudy']             | Should -Be '局部多云'
            $map.Contains('cloudy')           | Should -BeTrue
            $map['cloudy']                    | Should -Be '多云'
            $map.Contains('overcast')         | Should -BeTrue
            $map['overcast']                  | Should -Be '阴'
            $map.Contains('mist')             | Should -BeTrue
            $map['mist']                      | Should -Be '薄雾'
            $map.Contains('fog')              | Should -BeTrue
            $map['fog']                       | Should -Be '雾'
            $map.Contains('haze')             | Should -BeTrue
            $map['haze']                      | Should -Be '霾'
            $map.Contains('heavy rain')       | Should -BeTrue
            $map['heavy rain']                | Should -Be '大雨'
            $map.Contains('blizzard')         | Should -BeTrue
            $map['blizzard']                  | Should -Be '暴雪'
            # 返回类型必须是 OrderedDictionary, 保留插入顺序
            $map | Should -BeOfType ([System.Collections.Specialized.OrderedDictionary])
        }
    }

    Context '用户扩展合并' {

        It '用户 ExtraWeatherDescMap 同名键应覆盖内置值' {
            & $script:mod {
                $script:Config.Weather.ExtraWeatherDescMap = [ordered]@{
                    'smoky haze' = '烟霞'
                }
            }
            $map = & $script:mod { Get-WttrWeatherDescMap }

            $map['smoky haze'] | Should -Be '烟霞'
            # 未被覆盖的内置条目应原样保留
            $map['sunny']      | Should -Be '晴'
        }

        It '用户 ExtraWeatherDescMap 追加新键应进入字典' {
            & $script:mod {
                $script:Config.Weather.ExtraWeatherDescMap = [ordered]@{
                    'my custom' = '自定义天气'
                }
            }
            $map = & $script:mod { Get-WttrWeatherDescMap }

            $map.Contains('my custom') | Should -BeTrue
            $map['my custom']          | Should -Be '自定义天气'
            # 内置条目数应保持原样(>= 42)
            $map.Count | Should -BeGreaterOrEqual 43
        }
    }

    Context '用户扩展健壮性' {

        It '用户 ExtraWeatherDescMap 为 null 时应静默跳过, 只返回内置字典' {
            & $script:mod { $script:Config.Weather.ExtraWeatherDescMap = $null }
            $map = & $script:mod { Get-WttrWeatherDescMap }

            $map.Contains('sunny') | Should -BeTrue
            $map.Count | Should -BeGreaterOrEqual 42
        }

        It '用户 ExtraWeatherDescMap 为非字典(字符串)时应静默跳过' {
            & $script:mod { $script:Config.Weather.ExtraWeatherDescMap = 'not-a-dict' }
            $map = & $script:mod { Get-WttrWeatherDescMap }

            $map.Contains('sunny') | Should -BeTrue
            $map.Count | Should -BeGreaterOrEqual 42
        }

        It '用户 ExtraWeatherDescMap 为空字典时跳过合并循环' {
            & $script:mod { $script:Config.Weather.ExtraWeatherDescMap = [ordered]@{} }
            $map = & $script:mod { Get-WttrWeatherDescMap }

            $map.Count | Should -BeGreaterOrEqual 42
        }

        It '用户条目含 null Key / null Value 时跳过该条, 其它条目正常合并' {
            # 构造一个会触发跳过逻辑的字典:
            #   - good_key / another_good: 正常条目
            #   - null_value = $null: 走 entry.Value 为 null 分支, 应跳过
            # 验证含 null value 的条目不会被写入, 其它正常条目照常合并
            & $script:mod {
                $script:Config.Weather.ExtraWeatherDescMap = [ordered]@{
                    'good_key'     = '好的'
                    'null_value'   = $null
                    'another_good' = '另一个好的'
                }
            }
            $map = & $script:mod { Get-WttrWeatherDescMap }

            $map['good_key']              | Should -Be '好的'
            $map['another_good']          | Should -Be '另一个好的'
            $map.Contains('null_value')   | Should -BeFalse
            $map.Contains('good_key')     | Should -BeTrue
            $map.Contains('another_good') | Should -BeTrue
        }
    }
}