# Get-WttrTitleSuffix.ps1 - 交互菜单标题区单行天气后缀(TGUI 标题行拼接)
#
# 职责:
#   - 走 wttr.in ?format=j1&lang=zh 端点, 客户端字典中文化 weatherDesc,
#     拼成 " - CityName: 中文描述 温度°C" 形式, 由调用方拼到窗标题末尾
#   - HTTP/JSON/字段缺失等任何失败一律返回空串, 由调用方静默降级
#   - 用户扩展由 $script:Config.Weather.ExtraWeatherDescMap 注入
#
# 调用方:
#   - Show-HostSelector
#
# 依赖:
#   - Get-WttrWeather (HTTP + 缓存)
#   - Get-WttrWeatherDescMap (本目录同会话文件, 提供中英映射)

# 标题区天气的端点 URL: 由 Get-WttrTitleSuffix 与 Submit-WttrPrefetch 共用。
# 共用的意义: 后台预取写回缓存时用的 CacheKey 必须与同步路径完全一致,
# 否则预取结果命中不了缓存, 首屏仍然要等一次 HTTP。
$script:_WttrTitleUrl = 'https://wttr.in/?format=j1&lang=zh'

function Get-WttrTitleSuffix {
    <#
    .SYNOPSIS
        获取交互窗标题区使用的单行天气后缀(如 " - Chiuhuahsien: 烟雾 26°C")。

    .DESCRIPTION
        端点选择动机:
          - wttr.in 的 ?format=3 短格式在 IP 定位下会回退到 "lat,lon: 图标  温度"
            (例如 "23.501900,113.253700: ✨  +26°C"), 城市名丢失, R2 上轮的 regex
            清洗只能去掉 lat,lon 段, 无城市名可恢复。
          - ?format=j1 一次性返回 nearest_area(城市名) + current_condition
            (温度/天气描述), 我们自己拼接 "CityName: Desc Temp", 不依赖 wttr.in
            短格式的渲染选择, 行为稳定。
          - URL 追加 &lang=zh 是礼貌性行为(告知后端期望中文); 实测 wttr.in 后端
            weatherDesc/nearest_area 均不接 i18n 文案, 因此中文显示**必须**走客户端
            字典 (Get-WttrWeatherDescMap), 这两层互不冲突。
        失败语义:
          - HTTP/JSON 解析失败 → 返回空串, 标题区不显示天气 (保持现有行为)。
          - 复用 Get-WttrWeather 的 $script:_WttrCache(10 分钟 TTL,缓存键
            "CustomUrl|https://wttr.in/?format=j1&lang=zh"),与 Short 缓存互不污染。
        扩展机制:
          - 用户可在 $script:Config.Weather.ExtraWeatherDescMap 追加/覆盖中英映射
            (例如 @{ 'smoky haze' = '烟霞' }), 由 Get-WttrWeatherDescMap 合并。
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # 功能开关: 仅在 $script:Config.Weather.Enabled 时启用, 缺失配置视为关闭
    if (-not ($script:Config -and $script:Config.Weather -and [bool]$script:Config.Weather.Enabled)) {
        return ''
    }

    # 一次 HTTP 拉 j1, 走 Get-WttrWeather 的缓存 + 错误兜底通道;
    # lang=zh 为礼貌性参数, 真正中文化靠下方客户端字典 (见上方端点选择动机)
    # 2026-10-30: 先收割后台预取(Submit-WttrPrefetch)。预取已完成时结果直接进模块缓存,
    # 这条同步路径随即命中缓存, 不再发 HTTP —— 标题区不因天气请求阻塞首屏。
    $null = Receive-WttrPrefetch
    $raw = Get-WttrWeather -Format CustomUrl -Url $script:_WttrTitleUrl -CacheMinutes 10 -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return ''
    }

    # JSON 解析容错: 远端偶尔返回 HTML/纯文本错误页, 失败时静默跳过
    $payload = $null
    try { $payload = $raw | ConvertFrom-Json -ErrorAction Stop }
    catch { return '' }

    # 城市名: 优先 nearest_area[0].areaName[0].value; 都缺失时回退到空串, 触发整段跳过
    # 注: nearest_area 来自第三方 API, lang 参数不影响, 拼音/英文是上游固有行为
    $city = ''
    if ($payload.nearest_area -and $payload.nearest_area.Count -gt 0 -and
        $payload.nearest_area[0].areaName -and $payload.nearest_area[0].areaName.Count -gt 0) {
        $city = [string]$payload.nearest_area[0].areaName[0].value
    }
    if ([string]::IsNullOrWhiteSpace($city)) {
        return ''
    }

    # 当前温度(°C) 与天气描述: 都从 current_condition[0] 取
    $temp = ''
    $desc = ''
    if ($payload.current_condition -and $payload.current_condition.Count -gt 0) {
        $cur = $payload.current_condition[0]
        if ($cur.PSObject.Properties.Name -contains 'temp_C') {
            $temp = ([string]$cur.temp_C).Trim()
        }
        if ($cur.weatherDesc -and $cur.weatherDesc.Count -gt 0 -and $cur.weatherDesc[0].PSObject.Properties.Name -contains 'value') {
            $desc = ([string]$cur.weatherDesc[0].value).Trim()
        }
    }
    if (-not $temp) {
        return ''
    }

    # 客户端字典翻译 weatherDesc: wttr.in 后端 weatherDesc 不接 i18n, 必须本地化
    $descZh = $desc
    if ($desc) {
        $map = Get-WttrWeatherDescMap
        $key = $desc.ToLower()
        if ($map.Contains($key)) {
            $descZh = [string]$map[$key]
        } else {
            Write-Verbose "[Get-WttrTitleSuffix] 天气描述翻译缺失, 回退英文: '$desc'"
        }
    }

    # 拼接: "<City>: <DescZh> <Temp>°C"; DescZh 缺失时退化为 "<City>: <Temp>°C"
    if ($descZh) {
        $line = "$city`: $descZh $temp°C"
    } else {
        $line = "$city`: $temp°C"
    }
    return ' - ' + $line
}