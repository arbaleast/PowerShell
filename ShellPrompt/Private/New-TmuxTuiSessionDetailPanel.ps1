# New-TmuxTuiSessionDetailPanel.ps1 - tmux 会话仪表盘的**右侧会话详情卡**
#
# 背景 (2026-10-31 sss 仪表盘重构 · tmux 侧并入):
#   Goal 要求"列表与详细信息形成清晰的信息层级"。SSH 主机侧是四张卡
#   (Connection/Activity/Tags/Infrastructure); tmux 侧的真实字段远少 ——
#   Get-TmuxSessions 只给出会话名 / attached 状态 / 窗口数 —— 所以这里只做
#   **一张**卡, 字段全部来自真实数据:
#     Session  会话名
#     Status   Attached / Detached
#     Windows  窗口数
#     No       行号
#   **没有数据就显示 '—'**, 绝不为了填满卡片而伪造(远端没有更多字段可取,
#   也不该编造 "运行时长 / 客户端数"这类我们根本没有的数据源)。
#
# 契约: 组装(无头可测) + 就地更新(改 Label.Text 只重画该标签)。

function New-TmuxTuiSessionDetailPanel {
    <#
    .SYNOPSIS
        组装 tmux 会话详情卡(单个 FrameView + 键值 Label)。

    .DESCRIPTION
        返回对象里带全部**值 Label** 的句柄, 供 Set-TmuxTuiSessionDetail
        就地更新文本(改 Label.Text 只重画该标签, 不重建视图)。

    .PARAMETER Width
        卡片宽度(列)。

    .PARAMETER Height
        卡片高度(行)。

    .PARAMETER Theme
        Get-TuiDashboardTheme 产物(与 SSH 主机仪表盘共用同一套语义 Scheme)。

    .PARAMETER Tgui
        Get-TguiContext 产物。

    .OUTPUTS
        [PSCustomObject] View/Card/Labels(哈希表)/Width/Height/Theme/Tgui

    .EXAMPLE
        $panel = New-TmuxTuiSessionDetailPanel -Width 30 -Height 10 -Theme $theme -Tgui $tg
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(20, 500)]
        [int]$Width,

        [Parameter(Mandatory = $true)]
        [ValidateRange(4, 200)]
        [int]$Height,

        [Parameter(Mandatory = $true)]
        [object]$Theme,

        [Parameter(Mandatory = $true)]
        [object]$Tgui
    )

    if ($PSCmdlet.ShouldProcess('tmux 会话详情卡', 'Construct')) { } else { return $null }

    $static = [System.Reflection.BindingFlags]'Public,Static'
    $posAbsolute = $Tgui.Types.Pos.GetMethods($static) |
        Where-Object { $_.Name -eq 'Absolute' -and $_.GetParameters().Count -eq 1 } |
        Select-Object -First 1
    $dimAbsolute = $Tgui.Types.Dim.GetMethods($static) |
        Where-Object { $_.Name -eq 'Absolute' -and $_.GetParameters().Count -eq 1 } |
        Select-Object -First 1
    $labelType = $Tgui.Types.Label
    $frameType = $Tgui.Types.FrameView

    $card = [System.Activator]::CreateInstance($frameType)
    $card.X = $posAbsolute.Invoke($null, @(0))
    $card.Y = $posAbsolute.Invoke($null, @(0))
    $card.Width = $dimAbsolute.Invoke($null, @($Width))
    $card.Height = $dimAbsolute.Invoke($null, @($Height))
    try { $card.Title = ' Session ' } catch {
        Write-Verbose "[New-TmuxTuiSessionDetailPanel] 卡片标题设置失败: $($_.Exception.Message)"
    }
    [void]$card.SetScheme($Theme.CardBorder)

    # 键列宽 10 + 1 空格; 值列吃满剩余(减去左右边框各 1 与内缩 1)
    $keyX = 2
    $keyWidth = 10
    $valueX = $keyX + $keyWidth + 1
    $valueWidth = [Math]::Max(6, $Width - $valueX - 2)

    $labels = @{}
    $keys = @('Session', 'Status', 'Windows', 'No')
    for ($i = 0; $i -lt $keys.Count; $i++) {
        if ($i + 2 -gt $Height) { break }
        $k = [System.Activator]::CreateInstance($labelType)
        $k.Text = $keys[$i]
        $k.X = $posAbsolute.Invoke($null, @($keyX))
        $k.Y = $posAbsolute.Invoke($null, @(1 + $i))
        $k.Width = $dimAbsolute.Invoke($null, @($keyWidth))
        $k.Height = $dimAbsolute.Invoke($null, @(1))
        [void]$k.SetScheme($Theme.Dim)

        $v = [System.Activator]::CreateInstance($labelType)
        $v.Text = ''
        $v.X = $posAbsolute.Invoke($null, @($valueX))
        $v.Y = $posAbsolute.Invoke($null, @(1 + $i))
        $v.Width = $dimAbsolute.Invoke($null, @($valueWidth))
        $v.Height = $dimAbsolute.Invoke($null, @(1))
        [void]$v.SetScheme($Theme.Card)

        [void]$card.Add($k)
        [void]$card.Add($v)
        $labels[$keys[$i]] = $v
    }

    return [PSCustomObject]@{
        View   = $card
        Card   = $card
        Labels = $labels
        # 已应用方案登记(SetScheme 不是幂等 no-op, 等值跳过能缩小脏区)
        AppliedSchemes = @{}
        # 原值登记: 详情卡有 4 个字段, 上下移动时大部分字段的**原值**与上一行
        # 完全相同。截断要逐字符测宽, 先比原值再裁剪可以把按键路径上的
        # 裁剪开销降到 0(与 SSH 详情面板的 RawValues 守卫同构)。
        RawValues = @{}
        # 值列宽登记在此, 更新时按**同一个值**裁剪 —— 两处各算一遍会漂移:
        # 裁剪比值 Label 自身宽时 TG 只能硬切, 长会话名末尾被生硬截断(无省略号)。
        ValueWidth = $valueWidth
        Width  = $Width
        Height = $Height
        Theme  = $Theme
        Tgui   = $Tgui
    }
}

function Set-TmuxTuiSessionDetail {
    <#
    .SYNOPSIS
        把选中会话的真实字段落到详情卡(无数据即 '—')。

    .PARAMETER Panel
        New-TmuxTuiSessionDetailPanel 产物。

    .PARAMETER Row
        会话行视图模型(ConvertTo-TmuxTuiViewModel 的 .SessionRows 元素);
        $null = 没有选中会话(全部字段写 '—')。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Panel,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Row
    )

    $theme = $Panel.Theme
    # 裁剪宽度取**面板登记的值列宽**(与值 Label 自身宽度同源) —— 两处各算一遍
    # 会漂移: 裁剪比标签宽 2 列时, TG 只能硬切, 长会话名末尾被生硬截断。
    $valueWidth = [Math]::Max(6, [int]$Panel.ValueWidth)

    function Set-DetailValue {
        param([string]$Key, [string]$Text)
        $lbl = $Panel.Labels[$Key]
        if ($null -eq $lbl) { return }
        # ★ 原值未变 -> 连截断都不用算(2026-11 性能审计修复):
        #   裁剪走 Get-SshHostListClip -> Get-TguiTextWidth 逐字符测宽,
        #   是按键路径上最贵的一步; 上下移动时 4 个字段里通常只有 1~2 个
        #   真的变了。改成"先比原值, 变了才裁剪", 与 SSH 详情面板的
        #   RawValues 守卫(New-SshHostDetailPanel.ps1)同构。
        if ($Panel.RawValues.ContainsKey($Key) -and $Panel.RawValues[$Key] -ceq $Text) { return }
        $Panel.RawValues[$Key] = $Text
        $clipped = Get-SshHostListClip -Text $Text -Width $valueWidth
        if ([string]$lbl.Text -ceq $clipped) { return }
        $lbl.Text = $clipped
    }

    if ($null -eq $Row) {
        foreach ($k in @('Session', 'Status', 'Windows', 'No')) { Set-DetailValue -Key $k -Text '—' }
        return
    }

    Set-DetailValue -Key 'Session' -Text ([string]$Row.Session)
    Set-DetailValue -Key 'Status' -Text ([string]$Row.Status)
    $windows = '—'
    try { $windows = [string][int]$Row.Windows } catch { $windows = '—' }
    Set-DetailValue -Key 'Windows' -Text $windows
    $no = '—'
    try { $no = [string][int]$Row.No } catch { $no = '—' }
    Set-DetailValue -Key 'No' -Text $no

    # 状态列按语义着色(Attached 亮绿 / Detached 暗灰)
    $statusLabel = $Panel.Labels['Status']
    if ($null -ne $statusLabel) {
        $scheme = if ([string]$Row.Status -eq 'Attached') { $theme.Attached } else { $theme.Detached }
        if (-not $Panel.AppliedSchemes.ContainsKey('Status') -or $Panel.AppliedSchemes['Status'] -ne $scheme) {
            [void]$statusLabel.SetScheme($scheme)
            $Panel.AppliedSchemes['Status'] = $scheme
        }
    }
}
