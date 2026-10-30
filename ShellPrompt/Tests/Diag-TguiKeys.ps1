# Diag-TguiKeys.ps1 - **真机按键取证**: Esc / Ctrl+C / 任意键在 Terminal.Gui v2 'ansi' 驱动下的到达与处理
#
# 用途 (2026-10-31): 真机报告 sss 仪表盘 Esc/Ctrl+C 无反应, 其它 Shortcut 键正常。
#   无头复现(p73/p74)已排除 "应用级 Esc->Quit 绑定被前序 TG 周期吃掉" —— 绑定层
#   Esc=[Quit] 恒在。本脚本在**用户自己的终端**里取证按键流向:
#     1. Application 实例 KeyDown 事件 —— 每个到达 TG 的键都会触发(即使稍后被视图消费);
#     2. 焦点视图(TableView)的 KeyDown —— 若视图先消费, 会在此出现;
#     3. q-Shortcut —— 验证应用级 Shortcut 分发通路(对照键);
#     4. Run 是否因 Esc 返回 —— Quit 通路的最终判据。
#
# 运行:  在仓库根的交互 pwsh 里:  ./ShellPrompt/Tests/Diag-TguiKeys.ps1
#        按提示按若干键, 按 q 结束(或 Ctrl+C 强杀该进程)。
# 输出:  每个键即时打印一行 "[t] APP/VIEW KeyDown: <KeyCode> Ctrl=<b>"; 结束后打印汇总。
# 判读:  按 Esc 后若 "Run 从事件循环返回" 出现 => Esc->Quit 通路完好, 键已到达 TG;
#        按 Esc 无返回但随后按 q 能退出 => 键能到达应用绑定层而 Esc 专属处理失效
#        (把输出发回); 两条都无(Esc/q 都不返回) => 键没有进入 TG 输入通路(终端/驱动层)。
$ErrorActionPreference = 'Continue'
$repo = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
$dir = Join-Path $repo 'Modules\Terminal.Gui\2.4.10'
if (-not (Test-Path (Join-Path $dir 'Terminal.Gui.dll'))) {
    Write-Warning "未找到 vendored Terminal.Gui ($dir) —— 请在仓库根运行。"
    return
}

$alc = [System.Runtime.Loader.AssemblyLoadContext]::new('Diag-TguiKeys', $true)
$alc.add_Resolving({
        param($ctx, $name)
        $dll = Join-Path $dir ($name.Name + '.dll')
        if (Test-Path $dll) { return $ctx.LoadFromAssemblyPath((Resolve-Path $dll).Path) }
        return $null
    }.GetNewClosure())
$asm = $alc.LoadFromAssemblyPath((Resolve-Path (Join-Path $dir 'Terminal.Gui.dll')).Path)

$static = [System.Reflection.BindingFlags]'Public,Static'
$appT = $asm.GetType('Terminal.Gui.App.Application')
$keyT = $asm.GetType('Terminal.Gui.Input.Key')
$viewT = $asm.GetType('Terminal.Gui.ViewBase.View')
$scT = $asm.GetType('Terminal.Gui.Views.Shortcut')
$cmdT = $asm.GetType('Terminal.Gui.Input.Command')

# ---- 会话级的按键流水(闭包走 global, TG 事件回调跨 runtime 会话) ----
$global:DiagJournal = [System.Collections.Generic.List[string]]::new()

$amProp = $appT.GetProperty('AppModel', $static)
$fsV = $asm.GetType('Terminal.Gui.App.AppModel').GetField('FullScreen').GetValue($null)
$amProp.SetValue($null, $fsV)
try { $initM = $appT.GetMethods($static) | Where-Object { $_.Name -eq 'Init' } | Select-Object -First 1; [void]$initM.Invoke($null, @('ansi')) } catch {
    Write-Warning "TG Init 失败: $($_.Exception.Message) —— 需要交互终端, 请在真窗口运行。"
    return
}
$app = $appT.GetProperty('Instance', $static).GetValue($null)
if ($null -eq $app) { Write-Warning 'Application.Instance 为空 —— Init 语义异常。'; return }
"== INIT OK (driver=$($app.Driver.GetType().Name), TG=$($asm.GetName().Version)); 现在按几个键: 建议顺序 Esc → 任意字母 → Ctrl+C → q(结束) =="

# app **静态** KeyDown 事件在 2.4.10 无法从 PowerShell 订阅(仅 static, 反射 Invoke/事件绑定均拒)。
# 诊断改用三条可观测通路:
#   A. VIEW(TableView) 实例 KeyDown —— 键是否到达焦点视图层(实例事件可订阅);
#   B. q-Shortcut —— 应用级绑定通路对照(用户报告 q 正常);
#   C. Run 是否因 Esc 返回 —— TG 内建 Esc->Quit 的最终判据(到达即返回, 无需 hook)。

# 组件
$win = [System.Activator]::CreateInstance($asm.GetType('Terminal.Gui.Views.Window'))
$win.BorderStyle = $null
# 焦点视图: TableView(与仪表盘同物); 数据源走 EnumerableTableSource<object> 探针产物
$tvT = $asm.GetType('Terminal.Gui.Views.TableView')
$dt = [System.Collections.Generic.Dictionary[ [string], [System.Func[ [object], [object] ] ] ]]::new()
$dt['NAME'] = [System.Func[[object],[object]]]{ param($r) $r.N }
$rowsForSource = [object[]]@([PSCustomObject]@{ N = 'alpha' }, [PSCustomObject]@{ N = 'bravo' })
$srcT = $asm.GetExportedTypes() |
    Where-Object { $_.FullName -match '^Terminal.Gui.Views.EnumerableTableSource' } |
    Select-Object -First 1
$genSrc = $srcT.MakeGenericType([object])
$srcCtor = $genSrc.GetConstructors() |
    Where-Object {
        $p = $_.GetParameters()
        $p.Count -eq 2 -and $p[1].ParameterType.Name -in @('Dictionary`2', 'IDictionary`2')
    } | Select-Object -First 1
$tv = [System.Activator]::CreateInstance($tvT, @($srcCtor.Invoke(@($rowsForSource, $dt))))
$tvT.GetProperty('CollectionNavigator').SetValue($tv, $null)
# TableView 的 KeyDown(焦点视图层记录)
$tv.add_KeyDown({
        # $args = (sender, Key) 两参; 用 $args 避免 PSSA 未用形参告警(Invoke 先例)
        $kDiag = $args[1]
        $line = "VIEW(TableView) KeyDown: $([string]$kDiag.KeyCode)"
        [Console]::Out.WriteLine("  [$line]")
        $global:DiagJournal.Add($line) | Out-Null
    })

# 对照 Shortcut: q -> RequestStop(应用级绑定, 与仪表盘 q 同型)
$notBound = [Enum]::Parse($cmdT, 'NotBound')
$stopAction = [System.Action]([scriptblock]::Create('[Console]::Out.WriteLine("  [q-Shortcut ACTIVATED -> RequestStop]"); $global:DiagJournal.Add("q-Shortcut ACTIVATED") | Out-Null'))
$qKey = $keyT.GetProperty('Q').GetValue($null)
$sc = [System.Activator]::CreateInstance($scT, @($qKey, '结束', $stopAction, ''))
$sc.Command = $notBound
$sc.BindKeyToApplication = $true
[void]$win.Add($sc)
[void]$win.Add($tv)

# 焦点 TableView: 视图自身 0 参 SetFocus()(p26 既有实测: Table.SetFocus 后 HasFocus=True)
$setFocusTv = $viewT.GetMethods('Public,Instance') |
    Where-Object { $_.Name -eq 'SetFocus' -and $_.GetParameters().Count -eq 0 } |
    Select-Object -First 1
[void]$setFocusTv.Invoke($tv, @())
"== FOCUS OK; 现在请按: Esc → 任意字母 → Ctrl+C → q(结束诊断) =="

$runM = $appT.GetMethods($static) |
    Where-Object {
        $_.Name -eq 'Run' -and -not $_.IsGenericMethodDefinition -and
        $_.GetParameters().Count -eq 2 -and
        $_.GetParameters()[0].ParameterType.IsAssignableFrom($win.GetType())
    } | Select-Object -First 1
if ($null -eq $runM) { Write-Warning '缺 Run(IRunnable, Func) 重载。'; return }

$errHandler = [System.Func[[exception], [bool]]]{ param($ex)
    [Console]::Out.WriteLine("  [RUN ERROR: $($ex.GetType().Name): $($ex.Message)]")
    $global:DiagJournal.Add("RUN ERROR: $($ex.Message)") | Out-Null
    return $false
}
$runArgs = [object[]]::CreateInstance([System.Object], 2)
$runArgs[0] = $win
$runArgs[1] = $errHandler
try {
    [void]$runM.Invoke($null, $runArgs)
    "== Run 从事件循环返回 (Esc->Quit 或 q-Shortcut 结束) =="
} finally {
    try { $appT.GetMethod('Shutdown', $static).Invoke($null, @()) } catch { Write-Verbose "[Diag] finally 内 Shutdown 失败: $($_.Exception.Message)" }
}

"== 汇总(按键流水, 逐行) =="
foreach ($l in $global:DiagJournal) { "  $l" }
"== 判读(对照输出) =="
"  · 有 [Run 从事件循环返回] 且此前按过 Esc => Esc->Quit 通路正常(键到达 TG)"
"  · 无返回但 [VIEW(TableView) KeyDown: Esc] 出现 => 键到视图层但 Quit 未触发, 输出发回"
"  · 按 Esc 与 q 均无 [Run 返回] => 键根本没有进入 TG 输入通路(终端/驱动层), 输出发回"
