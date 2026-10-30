# Diag-TguiRender.ps1 - 真机 TGUI 渲染诊断(一次性工具, 不进产品链路)
#
# 用途: 在真实 Windows Terminal 里复现 sss 仪表盘的组装流程, 进入 Run
#       (用户看到待检查画面), 按 Esc 或 Q 退出后, 把渲染层全部关键证据
#       (驱动/Screen 尺寸/子视图帧与配色/表数据/派发次数)打印出来。
# 用法: pwsh -NoProfile -File .\ShellPrompt\Tests\Diag-TguiRender.ps1
#       (必须在真实交互终端运行; 重定向环境会直接退出并说明原因)
#
# 现场(2026-10-30 真机验收): 仪表盘只剩边框、内容全无, Esc 能退出 —— 本脚本
#   用于在真机上区分五类实因: 驱动选型 / Screen 尺寸 / 子视图布局 / 表数据 / 配色。

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
    Write-Host '本脚本必须在交互式终端直接运行(重定向环境退出)。'
    exit 2
}

$repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ShellPrompt/ShellPrompt.psd1') -Force -ErrorAction Stop
$mod = Get-Module -Name 'ShellPrompt'

$diag = & $mod {
    $tg = Get-TguiContext
    $static = [System.Reflection.BindingFlags]'Public,Static'
    $appType = $tg.Types.Application
    $initM = $appType.GetMethods($static) | Where-Object { $_.Name -eq 'Init' } | Select-Object -First 1
    $shutM = $appType.GetMethod('Shutdown', $static)
    $runInstance = $appType.GetMethods($static) |
        Where-Object { $_.Name -eq 'Run' -and -not $_.IsGenericMethodDefinition -and
                       $_.GetParameters().Count -eq 2 -and
                       $_.GetParameters()[0].ParameterType.IsAssignableFrom($tg.Types.Window) } |
        Select-Object -First 1
    if ($null -eq $runInstance) {
        $out.Add('run.error=缺少 Run(IRunnable, Func) 重载')
        return $out
    }
    $instP = $appType.GetProperty('Instance', $static)
    $screenP = $appType.GetProperty('Screen', $static)
    $errHandler = [System.Func[[exception], [bool]]]{ param($ex2) Write-Host "diag-error: $($ex2.Message)"; return $false }
    $hits = [System.Collections.Generic.List[string]]::new()
    $out = [System.Collections.Generic.List[string]]::new()

    # ---- AppModel=FullScreen(与产线一致) + Init('ansi') ----
    try {
        $amProp = $appType.GetProperty('AppModel', $static)
        $amFs = $tg.Types.AppModel.GetProperty('FullScreen').GetValue($null)
        $amProp.SetValue($null, $amFs)
    } catch {
        $out.Add("appmodel.error=$($_.Exception.Message)")
    }
    try {
        [void]$initM.Invoke($null, @('ansi'))
        $out.Add('init=ok(ansi)')
    } catch {
        $out.Add("init.error=$($_.Exception.Message)")
        return $out
    }
    $app = $instP.GetValue($null)

    # ---- 环境: 驱动 / Screen / AppModel / 宿主尺寸 ----
    try {
        $out.Add("driver=$($app.Driver.GetType().FullName)")
    } catch {
        $out.Add("driver=n/a($($_.Exception.Message))")
    }
    try {
        $sc = $screenP.GetValue($app)
        $out.Add("screen=$($sc.Width) x $($sc.Height)")
    } catch {
        $out.Add("screen=n/a($($_.Exception.Message))")
    }
    $hostUi = $Host.UI.RawUI.WindowSize
    $out.Add("host.RawUI=$($hostUi.Width) x $($hostUi.Height)")

    # ---- 窗口组装(与产线一致) ----
    $state = Get-TmuxSessionState -SessionData @{
        Available = $true
        Sessions  = @(
            [PSCustomObject]@{ Name = 'work'; Status = 'detached'; Windows = 3 }
            [PSCustomObject]@{ Name = 'ci';   Status = 'attached'; Windows = 1 }
        )
    }
    $vm = ConvertTo-TmuxTuiViewModel -State $state
    $dispatch = { param($a) $hits.Add([string]$a); $null }

    try {
        $result = New-TmuxTuiDashboardWindow -ViewModel $vm -HostName 'diag-host' `
            -ConnectionState '已进入诊断' -HasSessions $true -Dispatch $dispatch `
            -SelectedIndex 0
    } catch {
        $out.Add("build.error=$($_.Exception.GetType().Name): $($_.Exception.Message)")
        try { [void]$shutM.Invoke($null, @()) } catch { Write-Verbose "diag: shutdown 在 finally 里失败: $($_.Exception.Message)" }
        $out.Add('hits=[]')
        return $out
    }

    # ---- 子视图帧 + 各子视图配色(关键: fg==bg 则内容隐形) ----
    # ★ TG 2.4.10 没有 ColorScheme 属性(实测), 取色只能用 GetScheme();
    #   旧写法 $v.ColorScheme 恒抛异常 → 配色证据整段不可读。
    $w = $result.Window
    $out.Add("window.BorderStyle=$($w.BorderStyle)")
    try {
        foreach ($v in $w.SubViews) {
            $t = ''
            try {
                $tv = $v.Text
                if ($tv -is [string]) { $t = ($tv -split "`n")[0] }
            } catch {
                $t = '(无Text属性)'
            }
            if ($t.Length -gt 60) { $t = $t.Substring(0, 60) + '...' }
            $csInfo = '配色不可读'
            try {
                $has = $v.HasScheme
                $cs = $v.GetScheme()
                if ($null -ne $cs) {
                    $f = $cs.Normal.Foreground
                    $b = $cs.Normal.Background
                    $visible = -not ($f.R -eq $b.R -and $f.G -eq $b.G -and $f.B -eq $b.B)
                    $csInfo = "hasScheme=$has fg=$($f.R),$($f.G),$($f.B) bg=$($b.R),$($b.G),$($b.B) 可见=$visible"
                }
            } catch {
                $csInfo = "配色读取异常: $($_.Exception.Message)"
            }
            $out.Add("child $($v.GetType().Name) frame=$($v.Frame) $csInfo '$t'")
        }
    } catch {
        $out.Add("children.error=$($_.Exception.Message)")
    }

    # ---- 主题装配状态(ALC 方案实例) ----
    try {
        $applied = Set-TguiTheme -Tgui $tg
        $out.Add("theme.applied=$applied")
        $getSchemeM = $tg.Types.SchemeManager.GetMethod('GetScheme', [type[]]@([string]))
        foreach ($sn in @('Base', 'Menu')) {
            $sc3 = $getSchemeM.Invoke($null, @($sn))
            $f = $sc3.Normal.Foreground
            $b = $sc3.Normal.Background
            $out.Add("theme.$sn Normal fg=$($f.R),$($f.G),$($f.B) bg=$($b.R),$($b.G),$($b.B) 可见=$(-not ($f.R -eq $b.R -and $f.G -eq $b.G -and $f.B -eq $b.B))")
        }
        $body = Resolve-TguiScheme -Tgui $tg -Names @('Base', 'Menu', 'Dialog')
        $bf = $body.Normal.Foreground
        $bb = $body.Normal.Background
        $out.Add("theme.bound fg=$($bf.R),$($bf.G),$($bf.B) bg=$($bb.R),$($bb.G),$($bb.B)")
    } catch {
        $out.Add("theme.error=$($_.Exception.Message)")
    }

    try {
        $cols = @($result.Source.Columns)
        $out.Add("table.Rows=$($result.Source.Rows) Columns=[$($cols -join ',')]")
        $firstRow = $result.Source.Table[0]
        $rowText = ($firstRow | Out-String -NoNewline).Trim()
        $out.Add("table.Row[0]=$rowText")
    } catch {
        $out.Add("table.error=$($_.Exception.Message)")
    }

    # ---- ALC 方案各槽位配色(选中行取 Focus/Active, 列头取 Focus/Normal) ----
    try {
        $getSchemeM2 = $tg.Types.SchemeManager.GetMethod('GetScheme', [type[]]@([string]))
        $baseScheme = $getSchemeM2.Invoke($null, @('Base'))
        foreach ($slotName in @('Normal', 'Focus', 'Active', 'Highlight', 'Disabled')) {
            $sl = $tg.Types.Scheme.GetProperty($slotName)
            if ($null -ne $sl) {
                $sc2 = $sl.GetValue($baseScheme, $null)
                if ($null -ne $sc2) {
                    $f = $sc2.Foreground
                    $b = $sc2.Background
                    $out.Add("scheme.Base.$slotName fg=$($f.R),$($f.G),$($f.B) bg=$($b.R),$($b.G),$($b.B)")
                }
            }
        }
    } catch {
        $out.Add("scheme.error=$($_.Exception.Message)")
    }

    # ---- Run(画面停留阶段; Esc/Q 退出) ----
    $out.Add('run=即将进入(此段画面为待检查仪表盘; 按 Esc 或 Q 退出)')
    try {
        # 非泛型 Run(IRunnable, Func): 传**组装好的**窗口。
        # 泛型 Run<T> 会内部 new 一个全新空 T(IL 实测), 组装内容从不上屏。
        $runArgs = [object[]]::CreateInstance([System.Object], 2)
        $runArgs[0] = $result.Window
        $runArgs[1] = $errHandler
        [void]$runInstance.Invoke($null, $runArgs)
    } catch {
        $out.Add("run.error=$($_.Exception.Message)")
    } finally {
        try { [void]$shutM.Invoke($null, @()) } catch {
            Write-Host "shutdown.error=$($_.Exception.Message)"
        }
    }

    $out.Add("hits=[$($hits -join ',')]")
    return $out
}

Write-Host ''
Write-Host '==================== TGUI 渲染诊断报告 ====================' -ForegroundColor Cyan
foreach ($line in $diag) { Write-Host $line }
Write-Host '==========================================================' -ForegroundColor Cyan
Write-Host '请截图/复制上方全部行回传。' -ForegroundColor Yellow
