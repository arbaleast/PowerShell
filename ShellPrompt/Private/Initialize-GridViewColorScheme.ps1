# Initialize-GridViewColorScheme.ps1 - GridView 弹窗前的 Terminal.Gui 配色初始化
# 职责: 反射调用 Terminal.Gui 静态 API 应用配色方案, 失败时降级为内置主题。
# 抽出来的原因: 配色属于纯视觉增强, 不能阻塞菜单显示, 独立后便于单独处理异常。

function Initialize-GridViewColorScheme {
    <#
    .SYNOPSIS
        尝试应用 Terminal.Gui 配色方案, 失败时告警并继续。

    .DESCRIPTION
        配色属于纯视觉增强: 反射调用 Terminal.Gui 静态 API 在版本升级时随时可能失效,
        绝不能让它阻塞菜单显示, 因此整段包 try/catch, 失败只告警一次并继续弹菜单。

    .OUTPUTS
        无

    .EXAMPLE
        Initialize-GridViewColorScheme
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    try {
        if (-not (Set-TgColorScheme)) {
            Write-Verbose '[GridView] 未启用 TG 配色方案, 沿用 Terminal.Gui 内置主题'
        }
    } catch {
        Write-Warning "[ShellPrompt] 应用 TG 配色方案失败, 使用内置主题: $($_.Exception.Message)"
    }
}
