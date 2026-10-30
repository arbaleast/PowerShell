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
    $runGeneric = $appType.GetMethods($static) |
        Where-Object { $_.Name -eq 'Run' -and $_.IsGenericMethod } | Select-Object -First 1
    $runTyped = $runGeneric.MakeGenericMethod($tg.Types.Window)
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
                $cs = $v.ColorScheme
                if ($null -ne $cs) {
                    $f = $cs.Normal.Foreground
                    $b = $cs.Normal.Background
                    $csInfo = "fg=$($f.R),$($f.G),$($f.B) bg=$($b.R),$($b.G),$($b.B)"
                }
            } catch {
                $csInfo = "配色读取异常: $($_.Exception.Message)"
            }
            $out.Add("child $($v.GetType().Name) frame=$($v.Frame) $csInfo '$t'")
        }
    } catch {
        $out.Add("children.error=$($_.Exception.Message)")
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

    # ---- Scheme 全 slot 配色 ----
    try {
        $appSchemeP = $appType.GetProperty('Scheme', $static)
        $s = if ($appSchemeP) { $appSchemeP.GetValue($null) } else { $null }
        if ($s) {
            foreach ($slotName in @('Normal', 'Focus', 'HotNormal', 'HotFocus')) {
                $sl = $s.GetType().GetProperty($slotName)
                if ($null -ne $sl) {
                    $sc2 = $sl.GetValue($s)
                    if ($null -ne $sc2) {
                        $f = $sc2.Normal.Foreground
                        $b = $sc2.Normal.Background
                        $out.Add("scheme.$slotName fg=$($f.R),$($f.G),$($f.B) bg=$($b.R),$($b.G),$($b.B)")
                    }
                }
            }
        } else {
            $out.Add('scheme=不可达(无静态 Scheme 属性)')
        }
    } catch {
        $out.Add("scheme.error=$($_.Exception.Message)")
    }

    # ---- Run(画面停留阶段; Esc/Q 退出) ----
    $out.Add('run=即将进入(此段画面为待检查仪表盘; 按 Esc 或 Q 退出)')
    try {
        [void]$runTyped.Invoke($null, @($errHandler, 'ansi'))
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
