# ConvertTo-TmuxRefreshSelection.ps1 - "刷新会话列表" 这一特殊选择项的构造器
#
# 背景: 会话列表层的刷新是"用户触发"语义(菜单打开期间不做定时轮询),
#       因此需要一个可被两条 UI 轨识别的特殊选择对象。
# 方案: 用固定哨兵值 $script:TmuxRefreshSignalValue 作为 Value,
#       由 Show-TmuxSessionList 统一识别并重新拉取会话后原地重绘。

$script:TmuxRefreshSignalValue = '__tmux_refresh__'

function ConvertTo-TmuxRefreshSelection {
    <#
    .SYNOPSIS
        构造"刷新会话列表"特殊选择项。

    .DESCRIPTION
        返回对象的 Value 为哨兵值 $script:TmuxRefreshSignalValue,
        调用方据此判定"用户请求刷新"而不是"用户选中了某个会话"。
        形状与 ConvertTo-TmuxSessionSelection 保持一致(都带 Value/RawName/
        Label/Desc/Status/IsRefresh), 因此两条 UI 轨可以共用同一套判断逻辑。

    .OUTPUTS
        PSCustomObject(.Value/.RawName/.Label/.Desc/.Status/.IsRefresh)

    .EXAMPLE
        $refresh = ConvertTo-TmuxRefreshSelection
        $refresh.IsRefresh
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    return [PSCustomObject]@{
        Value     = $script:TmuxRefreshSignalValue
        RawName   = ''
        Label     = '⟳ 刷新会话列表'
        Desc      = '重新获取远程 tmux 会话列表'
        Status    = ''
        IsRefresh = $true
    }
}
