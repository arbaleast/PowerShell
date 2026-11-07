# ConvertTo-TmuxRelativeTime.ps1 - TGUI 数据层的**纯展示辅助函数**(时间/路径/文本)
#
# 为什么单独成文件(而不是塞进 ConvertTo-TmuxTuiViewModel):
#   这三个函数被 UI 层(右侧详情面板)与数据层共同使用, 且都必须**纯函数**化:
#     - 相对时间: 需要能注入"当前时刻", 否则测试会随时钟漂移变成 flaky;
#     - 路径折叠: 规则(替换 HOME / 兜底启发式)必须能被单独钉死;
#     - ANSI 剥离: 预览快照来自 capture-pane, 可能带转义序列, 必须统一净化。
#   放在一起便于单元测试一次覆盖, 也避免视图模型文件继续膨胀。

function ConvertTo-TmuxRelativeTime {
    <#
    .SYNOPSIS
        把 unix 时间戳(秒)转换为人类可读的相对时间文本。

    .DESCRIPTION
        分档规则(向下取整, 阈值固定, 便于测试钉死):
            <  60 秒   -> 'just now'
            <  60 分   -> '5m ago'   (分钟)
            <  24 小时 -> '2h ago'   (小时)
            <   7 天   -> '2d ago'   (天)
            >= 7 天    -> '3w ago'   (周)
        时间戳 <= 0(未知)时返回 'N/A' —— 老 tmux 不支持 session_created/activity,
        此时**不能**显示假的时间, 只能显式说"未知"。

    .PARAMETER Epoch
        unix 时间戳(秒)。0 / 负数视为未知。

    .PARAMETER Now
        参考时刻(默认 UtcNow)。测试注入固定值以消除时间依赖。

    .OUTPUTS
        [string] 相对时间文本

    .EXAMPLE
        ConvertTo-TmuxRelativeTime -Epoch 1700000000 -Now ([DateTimeOffset]::FromUnixTimeSeconds(1700000300))
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Epoch,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Now
    )

    if ($null -eq $Epoch) { return 'N/A' }
    $seconds = 0
    if (-not [long]::TryParse([string]$Epoch, [ref]$seconds)) { return 'N/A' }
    if ($seconds -le 0) { return 'N/A' }

    $nowValue = [DateTimeOffset]::UtcNow
    if ($null -ne $Now) {
        if ($Now -is [DateTimeOffset]) {
            $nowValue = $Now
        } elseif ($Now -is [DateTime]) {
            $nowValue = [DateTimeOffset]::new($Now.ToUniversalTime())
        } else {
            $parsed = [DateTimeOffset]::MinValue
            if ([DateTimeOffset]::TryParse([string]$Now, [ref]$parsed)) { $nowValue = $parsed }
        }
    }

    $moment = [DateTimeOffset]::FromUnixTimeSeconds($seconds)
    $delta = ($nowValue - $moment).TotalSeconds
    # 远端时钟可能略快于本地, 负差一律按 0 处理(显示 just now), 不显示 "-3s ago"
    if ($delta -lt 0) { $delta = 0 }

    if ($delta -lt 60) { return 'just now' }
    if ($delta -lt 3600) { return ('{0}m ago' -f [int][Math]::Floor($delta / 60)) }
    if ($delta -lt 86400) { return ('{0}h ago' -f [int][Math]::Floor($delta / 3600)) }
    if ($delta -lt 604800) { return ('{0}d ago' -f [int][Math]::Floor($delta / 86400)) }
    return ('{0}w ago' -f [int][Math]::Floor($delta / 604800))
}

function ConvertTo-TmuxShortPath {
    <#
    .SYNOPSIS
        把远端绝对路径折叠成以 '~' 开头的短路径(用于窄面板显示)。

    .DESCRIPTION
        规则:
          1. 已知 HOME(来自同一次 SSH 的 TMUX_HOME 段)时, 用 HOME 前缀替换为 '~';
             HOME 恰好等于路径本身时结果为 '~'。
          2. HOME 缺失时的**兜底启发式**: 剥掉开头的 '/home/<用户名>' 或 '/Users/<用户名>'
             段 —— 这是绝大多数 Linux/macOS 远端的形态, 猜错的代价只是路径短了一点,
             比显示一整条长路径可读性好得多。
          3. 其它路径原样返回(不猜测、不改写)。
        路径为空时返回空串。

    .PARAMETER Path
        原始绝对路径。

    .PARAMETER HomePath
        远端用户 HOME 目录(可为空)。

    .OUTPUTS
        [string] 折叠后的路径

    .EXAMPLE
        ConvertTo-TmuxShortPath -Path '/home/debian/work/hermes' -HomePath '/home/debian'
        # -> '~/work/hermes'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$HomePath
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    $normalized = $Path.Trim()

    if (-not [string]::IsNullOrWhiteSpace($HomePath)) {
        $homeDir = $HomePath.Trim()
        if ($homeDir.Length -gt 0) {
            $homeTrimmed = $homeDir.TrimEnd('/')
            if ($normalized -eq $homeTrimmed) { return '~' }
            if ($normalized.StartsWith($homeTrimmed + '/', [System.StringComparison]::Ordinal)) {
                return '~' + $normalized.Substring($homeTrimmed.Length)
            }
        }
    }

    # 兜底启发式: /home/<name>/... 与 /Users/<name>/...
    if ($normalized -match '^(?<root>/(?:home|Users)/[^/]+)(?<rest>/.*)?$') {
        $rest = $matches['rest']
        if ([string]::IsNullOrEmpty($rest)) { return '~' }
        return '~' + $rest
    }

    return $normalized
}

function ConvertTo-TmuxPlainText {
    <#
    .SYNOPSIS
        剥离文本中的 ANSI 转义序列(返回纯文本)。

    .DESCRIPTION
        预览快照来自 `tmux capture-pane -p`, 默认不带转义序列, 但用户配置了
        escape sequence / RGB 样式或历史内容里含转义时仍可能出现。右面板是纯文本
        渲染, 残留的 ESC 序列会导致**列宽计算错位与乱码**, 因此统一在这里剥离。
        剥离范围: CSI 序列(\e[...m 等)、OSC 序列(\e]...\a / \e]...\e\\)、以及
        两字符转义(\e(B 之类)。纯文本输入原样返回。

    .PARAMETER Text
        待净化的文本。

    .OUTPUTS
        [string] 纯文本

    .EXAMPLE
        ConvertTo-TmuxPlainText -Text "$([char]27)[31mred$([char]27)[0m"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Text
    )

    if ($null -eq $Text) { return '' }
    if ($Text.Length -eq 0) { return '' }

    # 用正则转义写法(\x1B = ESC)而不是插值拼接, 避免 PowerShell 字符串里的
    # 反斜杠/括号转义歧义; .NET 正则原生支持 \xHH。
    $pattern = '\x1B(?:\[[0-?]*[ -/]*[@-~]|\][^\x07\x1B]*(?:\x07|\x1B\\)?|[@-Z\x5C-_])'
    return [regex]::Replace($Text, $pattern, '')
}
