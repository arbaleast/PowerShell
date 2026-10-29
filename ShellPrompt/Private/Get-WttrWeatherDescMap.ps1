# Get-WttrWeatherDescMap.ps1 - wttr.in weatherDesc 英文 → 中文映射字典(模块内置 + 用户扩展)
#
# 职责:
#   - 提供 wttr.in weatherDesc 英文短语到中文文案的翻译映射
#   - 内置 42 条常见描述(雾/霾/晴/多云/阴/雨/雪/雷暴)
#   - 与 $script:Config.Weather.ExtraWeatherDescMap 合并: 同名键覆盖, 新键追加
#   - 用户配置为 null / 非字典 / 空 / 含 null 条目 时静默跳过, 不抛错
#
# 调用方:
#   - Get-WttrTitleSuffix
# 匹配规则:
#   - 键已统一小写, 由 Get-WttrTitleSuffix 对输入做 .ToLower() 后查表
#   - 命中返回中文文案, 未命中由调用方走原文回退 + Write-Verbose 提示

function Get-WttrWeatherDescMap {
    <#
    .SYNOPSIS
        返回 wttr.in weatherDesc 英文描述 → 中文文案 的有序字典(模块内置,用户可在
        $script:Config.Weather.ExtraWeatherDescMap 追加自定义条目覆盖)。

    .DESCRIPTION
        wttr.in 后端没有接入 i18n 文案: ?format=j1&lang=zh 实测 weatherDesc 字段
        仍是英文("Smoky haze" / "Partly Cloudy" 等), nearest_area 也是拼音。
        因此标题区中文化**必须**走客户端字典方案, 没法依赖 URL 参数。

        字典匹配规则(由 Get-WttrTitleSuffix 调用):
          1) Trim 后按完整英文短语查表(忽略大小写);
          2) 未命中则回退原英文描述, 同时 Write-Verbose 提示"翻译缺失";
          3) 用户可在 $script:Config.Weather.ExtraWeatherDescMap 追加/覆盖条目,
             键 = 英文短语(小写), 值 = 自定义中文; 模块内置条目可被覆盖。

        字典条目按 wttr.in 实际 weatherCode/weatherDesc 常见值选取(覆盖 113/116/
        119/122/143/248/260/263/266/281/284/293/296/299/302/305/308/311/314/317/
        320/323/326/329/332/335/338/350/353/356/359/362/365/368/371/374/377/386/
        389/392/395), 用户实机在 IP 定位下最常见的是 Smoky haze / Mist / Haze /
        Sunny / Clear / Cloudy / Partly Cloudy, 因此排在前部。
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()

    # 内置字典(键已统一为小写, 匹配时对输入做 .ToLower().Trim())
    $base = [ordered]@{
        # 雾/霾/烟 (实机 IP 定位最常见, 排前)
        'smoky haze'         = '烟雾'
        'mist'               = '薄雾'
        'fog'                = '雾'
        'haze'               = '霾'
        'freezing fog'       = '冻雾'
        'shallow fog'        = '浅雾'
        'patchy fog'         = '零星雾'
        # 晴/少云/多云/阴
        'sunny'              = '晴'
        'clear'              = '晴'
        'partly cloudy'      = '局部多云'
        'cloudy'             = '多云'
        'overcast'           = '阴'
        # 雨 (按强度)
        'patchy rain possible'      = '可能零星小雨'
        'patchy light drizzle'      = '零星小雨'
        'light drizzle'             = '小雨'
        'freezing drizzle'          = '冻雨'
        'heavy freezing drizzle'    = '强冻雨'
        'patchy light rain'         = '零星小雨'
        'light rain'                = '小雨'
        'moderate rain at times'    = '时有中雨'
        'moderate rain'             = '中雨'
        'heavy rain at times'       = '时有大雨'
        'heavy rain'                = '大雨'
        'light freezing rain'       = '冻小雨'
        'moderate or heavy freezing rain' = '中到大冻雨'
        'torrential rain'           = '暴雨'
        # 雪
        'patchy snow possible'      = '可能零星降雪'
        'patchy light snow'         = '零星小雪'
        'light snow'                = '小雪'
        'patchy moderate snow'      = '零星中雪'
        'moderate snow'             = '中雪'
        'patchy heavy snow'         = '零星大雪'
        'heavy snow'                = '大雪'
        'ice pellets'               = '冰粒'
        'light sleet'               = '小雨夹雪'
        'moderate or heavy sleet'   = '中到大雨夹雪'
        'blizzard'                  = '暴雪'
        # 雷暴
        'thundery outbreaks possible' = '可能有雷暴'
        'patchy light rain with thunder' = '零星雷阵雨'
        'moderate or heavy rain with thunder' = '中到大雷阵雨'
        'patchy light snow with thunder' = '零星雷阵雪'
        'moderate or heavy snow with thunder' = '中到大雷阵雪'
    }

    # 用户扩展: 任何同名键会覆盖内置值; 缺失/空/非字典/非 IEnumerable 则忽略
    $extra = $null
    if ($script:Config -and $script:Config.Weather) {
        $extra = $script:Config.Weather.ExtraWeatherDescMap
    }
    if ($null -ne $extra -and ($extra -is [System.Collections.IDictionary] -or $extra -is [System.Collections.IEnumerable]) -and $extra.Count -gt 0) {
        try {
            foreach ($entry in $extra.GetEnumerator()) {
                if ($null -eq $entry.Key -or $null -eq $entry.Value) { continue }
                $base[[string]$entry.Key] = [string]$entry.Value
            }
        } catch {
            Write-Verbose "[Get-WttrWeatherDescMap] 用户扩展映射合并失败: $($_.Exception.Message)"
        }
    }
    return $base
}