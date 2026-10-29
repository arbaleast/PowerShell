# Write-TmuxWelcomeBanner.ps1 - tmux 管理器入口 banner 输出
# 职责: 解析配色 -> 构造 banner -> 写到控制台(与 Show-UserScoopLogo 样式一致)。

function Write-TmuxWelcomeBanner {
    <#
    .SYNOPSIS
        输出 tmux 远程会话管理器的欢迎 banner。

    .DESCRIPTION
        颜色从配置读取(用户配置优先), 缺省值与 Show-UserScoopLogo 保持一致;
        banner 本体由纯函数 New-WelcomeBanner 构造, 本函数只负责 I/O。

    .OUTPUTS
        void

    .EXAMPLE
        Write-TmuxWelcomeBanner
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    # 颜色预解析: 统一走 Resolve-ColorTable(Border 跟随 Primary, 与 New-WelcomeBanner 语义一致)
    $wbColors = Resolve-ColorTable -Name 'Primary', 'Accent', 'Muted', 'Border'
    $wbQuotesPath = Get-CachedConfig -Section 'Paths' -Key 'Quotes' -Default ''
    $quote = Get-RandomQuote -QuotesPath $wbQuotesPath -Fallback 'SYSTEM READY'
    $bannerLines = New-WelcomeBanner -Title 'TMUX 远程会话' -Subtitle $quote -Width 49 -Colors $wbColors
    $bannerLines | ForEach-Object { [Console]::WriteLine($_) }
}
