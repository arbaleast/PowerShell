# Test-TmuxTuiInteractive.ps1 - TGUI 仪表盘的非交互终端护栏(可 Mock 的独立判定)
#
# 背景 (2026-10-30 阶段 B 收口):
#   护栏原本内联在 Show-TmuxTuiDashboard 里(读重定向状态), 导致"视图组装异常
#   向上传播"用例在重定向的 Pester 环境下被短路 —— Run 之前就 return 'Exit',
#   mock 的 throw 根本没机会触发, Should -Throw 必失败。
#   抽成独立私有函数后: 编排层可测, 测试也可对本函数打桩(不暴露公共命令)。
#
# 依据(探针 .agent_cache/tgui-probe/REPORT.md): 无 TTY 容器里 TG 的
#   Init('windows'/'dotnet'/'ansi') **全部成功不抛异常**, 随后 Run() 的
#   事件循环会永久阻塞 —— 必须在触碰 TG 之前用重定向状态提前护栏。

function Test-TmuxTuiInteractive {
    <#
    .SYNOPSIS
        判断当前终端是否可安全启动 TGUI 事件循环(非交互护栏)。

    .DESCRIPTION
        输入或输出被重定向(Pester/CI/管道)时返回 $false —— TG 的 Init 在
        无 TTY 环境不抛异常但事件循环会永久阻塞, 编排层据此直接返回 'Exit'。

    .OUTPUTS
        [bool] $true = 交互式终端, 可启动 TGUI。

    .EXAMPLE
        if (-not (Test-TmuxTuiInteractive)) { return }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    -not ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected)
}
