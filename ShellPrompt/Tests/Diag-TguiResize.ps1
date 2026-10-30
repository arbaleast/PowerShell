# Diag-TguiResize.ps1 - 真机 TGUI "取数重复风暴" 诊断(一次性工具, 不进产品链路)
#
# 现象(2026-10-30 真机复验): `sss debian` 进入 TGUI 分支后, "获取远程 tmux 会话"
#   进度动画反复出现, 仪表盘从未上屏 —— 编排层里**唯一的**自驱动 continue 路径是
#   "ScreenChanged 报告值 != Post-Init 记录值 -> RequestStop -> resized && 无按键 -> continue"
#   (Show-TmuxTuiDashboard)。Post-Init Screen 读到 0/失败时产线按默认 120x35 记账,
#   真实终端上报尺寸与之不符就会每轮错位触发 —— 即为风暴。
# 本脚本复刻产线全部参数(AppModel=FullScreen / 'ansi' 驱动 / 非泛型 Run /
#   ScreenChanged 订阅 / 40x10 下限夹取), 连跑 3 轮 Init->Run, 采集:
#   Post-Init Screen 原始值 / 每个 ScreenChanged 尺寸与时刻 / Run 实际驻留时长 /
#   关键信号(resizeDetected / pendingAction / errorHandler 异常)。
#
# 用法: pwsh -NoProfile -File .\ShellPrompt\Tests\Diag-TguiResize.ps1
#   (必须在真实交互终端运行; 重定向环境直接退出)
#   若某轮画面真实上屏(未自动返回), 按 Esc 退出该轮即可(healthy), 脚本会标记 elapsed。
# TG 事件回调跨会话执行, 状态统一放一个 $global:Tdiag 哈希表(与产线同理由)。

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

# ---- 宿主环境证据(TG 外侧) ----
$hostOut = [System.Collections.Generic.List[string]]::new()
$hostOut.Add("version=$($PSVersionTable.PSVersion) edition=$($PSVersionTable.PSEdition)")
$hostOut.Add("ioRedirected: IsInputRedirected=$([Console]::IsInputRedirected) IsOutputRedirected=$([Console]::IsOutputRedirected)")
try {
    $cw = $Host.UI.RawUI.WindowSize
    $hostOut.Add("host.RawUI.WindowSize=$($cw.Width) x $($cw.Height)")
} catch {
    $hostOut.Add("host.RawUI.WindowSize=n/a($($_.Exception.Message))")
}
try {
    $hostOut.Add("host.Console.BufferWidth=$([Console]::BufferWidth) BufferHeight=$([Console]::BufferHeight) WindowWidth=$([Console]::WindowWidth) WindowHeight=$([Console]::WindowHeight)")
} catch {
    $hostOut.Add("host.Console=n/a($($_.Exception.Message))")
}
$guardValue = '?'
try { $guardValue = [string][bool](Test-TmuxTuiInteractive) } catch {
    $guardValue = 'throw: ' + $_.Exception.Message
}
$hostOut.Add("interactiveGuard(Test-TmuxTuiInteractive)=$guardValue")
$hostOut.Add("env.WT_SESSION=$(if ($env:WT_SESSION) { $env:WT_SESSION } else { '(未设置 - 可能不是 Windows Terminal)' })")
$hostOut.Add("env.TERM_PROGRAM=$(if ($env:TERM_PROGRAM) { $env:TERM_PROGRAM } else { '(未设置)' })")

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
    $stopM = $appType.GetMethods($static) | Where-Object { $_.Name -eq 'RequestStop' } | Select-Object -First 1
    if ($null -eq $runInstance -or $null -eq $stopM) {
        $missing = [System.Collections.Generic.List[string]]::new()
        $missing.Add('diag.error=缺少 Run(IRunnable, Func) / RequestStop 反射句柄')
        return $missing
    }
    $instP = $appType.GetProperty('Instance', $static)
    $screenP = $appType.GetProperty('Screen', $static)
    $out = [System.Collections.Generic.List[string]]::new()

    # 产线一致: AppModel=FullScreen + Init('ansi')
    try {
        $amProp = $appType.GetProperty('AppModel', $static)
        $amProp.SetValue($null, $tg.Types.AppModel.GetProperty('FullScreen').GetValue($null))
    } catch {
        $out.Add("appmodel.error=$($_.Exception.Message)")
    }

    # 模拟数据(不连 SSH, 与 Diag-TguiRender 同源)
    $mockState = Get-TmuxSessionState -SessionData @{
        Available = $true
        Sessions  = @(
            [PSCustomObject]@{ Name = 'work'; Status = 'detached'; Windows = 3 }
            [PSCustomObject]@{ Name = 'ci';   Status = 'attached'; Windows = 1 }
        )
    }

    for ($cycle = 1; $cycle -le 3; $cycle++) {
        $out.Add("---- cycle $cycle ----")
        # 每轮重置诊断状态(TG 线程回调也读它)
        $global:Tdiag = @{
            Events        = [System.Collections.Generic.List[string]]::new()
            ResizeDetected = $false
            Pending       = $null
            Error         = $null
            LayoutW       = 0
            LayoutH       = 0
            AppInstance   = $null
            WindowRef     = $null
            StopMethod    = $stopM
        }

        # ---- Init ----
        try {
            [void]$initM.Invoke($null, @('ansi'))
        } catch {
            $out.Add("init.error=$($_.Exception.Message)")
            break
        }
        try {
            $global:Tdiag.AppInstance = $instP.GetValue($null)
        } catch {
            $out.Add("instance.error=$($_.Exception.Message)")
            break
        }

        # ---- Post-Init Screen 原始值 + 产线记账(默认 120x35, 下限 40x10) ----
        $rawW = 0; $rawH = 0; $screenOk = $false
        try {
            $sc = $screenP.GetValue($null)
            if ($null -ne $sc) { $rawW = [int]$sc.Width; $rawH = [int]$sc.Height; $screenOk = $true }
        } catch {
            $out.Add("screen.postInit.error=$($_.Exception.Message)")
        }
        $rawText = 'n/a'
        if ($screenOk) { $rawText = "${rawW}x${rawH}" }
        $layoutW = 120; $layoutH = 35
        if ($screenOk) {
            $layoutW = [Math]::Max($rawW, 40)
            $layoutH = [Math]::Max($rawH, 10)
        }
        $global:Tdiag.LayoutW = $layoutW
        $global:Tdiag.LayoutH = $layoutH
        $out.Add("screen.postInit ok=$screenOk raw=$rawText layout=${layoutW}x${layoutH}")

        # ---- 组装窗口(与产线同源) ----
        $vm = ConvertTo-TmuxTuiViewModel -State $mockState
        $dispatch = { param($a)
            $global:Tdiag.Pending = [string]$a
            if ($null -ne $global:Tdiag.WindowRef) {
                [void]($global:Tdiag.StopMethod.Invoke($null, @($global:Tdiag.WindowRef)))
            }
        }
        try {
            $result = New-TmuxTuiDashboardWindow -ViewModel $vm -HostName 'diag-host' `
                -ConnectionState '已进入诊断' -HasSessions $true -Dispatch $dispatch `
                -WindowWidth $layoutW -WindowHeight $layoutH -SelectedIndex 0
        } catch {
            $out.Add("build.error=$($_.Exception.GetType().Name): $($_.Exception.Message)")
            try { [void]$shutM.Invoke($null, @()) } catch { Write-Verbose "diag: shutdown 失败: $($_.Exception.Message)" }
            break
        }
        $global:Tdiag.WindowRef = $result.Window

        # ---- 订阅 ScreenChanged(复刻产线回调 + 记录证据) ----
        try {
            $global:Tdiag.AppInstance.add_ScreenChanged({
                    try {
                        $evApp = $global:Tdiag.AppInstance
                        if ($null -eq $evApp) { return }
                        $cur = $evApp.Screen
                        $evW = [int]$cur.Width
                        $evH = [int]$cur.Height
                        $stamp = [DateTime]::Now.ToString('HH:mm:ss.fff')
                        if ($evW -le 0 -or $evH -le 0) {
                            $global:Tdiag.Events.Add("$stamp size=${evW}x${evH} (零尺寸, 产线守卫静默)")
                            return
                        }
                        $mismatch = ($evW -ne $global:Tdiag.LayoutW) -or ($evH -ne $global:Tdiag.LayoutH)
                        $global:Tdiag.Events.Add("$stamp size=${evW}x${evH} layout=$($global:Tdiag.LayoutW)x$($global:Tdiag.LayoutH) mismatch=$mismatch")
                        if ($mismatch) {
                            $global:Tdiag.ResizeDetected = $true
                            if ($null -ne $global:Tdiag.WindowRef) {
                                [void]($global:Tdiag.StopMethod.Invoke($null, @($global:Tdiag.WindowRef)))
                            }
                        }
                    } catch {
                        Write-Verbose "diag: ScreenChanged 回调异常: $($_.Exception.Message)"
                    }
                })
            $out.Add('subscribe.ScreenChanged=ok')
        } catch {
            $out.Add("subscribe.error=$($_.Exception.Message)")
        }

        # ---- Run(记录驻留时长; 若画面上屏, 按 Esc 退出该轮) ----
        $out.Add("run=cycle $cycle 即将进入(若画面停留, 按 Esc 退出)")
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $errHandler = [System.Func[[exception], [bool]]]{
                param($ex2)
                $global:Tdiag.Error = $ex2
                return $false
            }
            $runArgs = [object[]]::CreateInstance([System.Object], 2)
            $runArgs[0] = $result.Window
            $runArgs[1] = $errHandler
            [void]$runInstance.Invoke($null, $runArgs)
        } catch {
            $out.Add("run.error=$($_.Exception.GetType().Name): $($_.Exception.Message)")
        } finally {
            $sw.Stop()
            try { [void]$shutM.Invoke($null, @()) } catch {
                Write-Verbose "diag: cycle $cycle shutdown 失败: $($_.Exception.Message)"
            }
            $out.Add("run.elapsedMs=$($sw.ElapsedMilliseconds)")
        }

        $pendingText = '<null>'
        if ($null -ne $global:Tdiag.Pending) { $pendingText = $global:Tdiag.Pending }
        $errorText = '<null>'
        if ($null -ne $global:Tdiag.Error) {
            $errorText = $global:Tdiag.Error.GetType().Name + ': ' + $global:Tdiag.Error.Message
        }
        $out.Add("run.signal resizeDetected=$($global:Tdiag.ResizeDetected) pendingAction=$pendingText runError=$errorText")
        foreach ($ev in $global:Tdiag.Events) { $out.Add("screenChanged $ev") }
        if ($global:Tdiag.Events.Count -eq 0) { $out.Add('screenChanged (本轮无事件)') }

        # 立即返回判定: <500ms 且无按键分发 —— 风暴签名
        if ($sw.ElapsedMilliseconds -lt 500 -and $null -eq $global:Tdiag.Pending) {
            $out.Add('verdict.run=立即返回(<500ms 且无按键) —— 疑似取数重复风暴(与产线现象一致)')
        } else {
            $out.Add('verdict.run=该轮驻留(用户按键退出或正常上屏) —— 该轮健康')
        }

        # 产线在 Shutdown 后清订阅标记(回调侧引用一并清)
        $global:Tdiag.WindowRef = $null
    }

    return $out
}

Write-Host ''
Write-Host '==================== TGUI 取数重复风暴诊断报告 ====================' -ForegroundColor Cyan
Write-Host '--- 宿主环境 ---' -ForegroundColor DarkGray
foreach ($line in $hostOut) { Write-Host $line }
Write-Host '--- TG 循环(3 轮) ---' -ForegroundColor DarkGray
foreach ($line in $diag) { Write-Host $line }
Write-Host '==================================================================' -ForegroundColor Cyan
Write-Host '请复制上方全部行回传会话。' -ForegroundColor Yellow
