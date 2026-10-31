# Get-TguiContext.ps1 - Terminal.Gui v2 独立仪表盘的程序集加载器(阶段 A · SSS 迁移)
#
# 背景 (2026-10-30 TGUI 迁移 · 阶段 A):
#   目标: 把 sss 的 tmux 仪表盘迁移到 Terminal.Gui v2 真正的全屏界面,
#   不引第二套自研 ANSI 渲染系统、不对 PSTui 内部反射。
#   载入源: 仓库内 vendored 的 Modules/Terminal.Gui/<ver>/Terminal.Gui.dll
#   (PS 7.6+.NET 10 同家族, 版本钉 2.4.10.0),
#   用独立 AssemblyLoadContext + 路径解析回调加载 TG 及其依赖:
#     Testably.Abstractions.FileSystem.Interface  System.IO.Abstractions
#     Wcwidth  ColorHelper (均与 Terminal.Gui.dll 同目录)
#
# v2.4.10 实测 API 面(与本 Goal 严禁"按示例假定 API"的要求对应,
# 反射实测于 2026-10-30, 全部以本文件验证过的命名空间为准;
# 完整探针报告见 .agent_cache/tgui-probe/REPORT.md):
#   Application: Terminal.Gui.App.Application
#                (静态 Init(System.String) —— **只有一个重载**;
#                 Run[TRunnable](Func<Exception,bool>, String) —— 约束 IRunnable;
#                 Shutdown() —— **无参唯一重载**, 负责还原光标/鼠标/粘贴/备用屏;
#                 RequestStop(IRunnable) / Instance / Screen / AppModel / KeyBindings)
#   View 家族:   Terminal.Gui.Views.{Window,TableView,StatusBar,Label,Shortcut,
#                TableSelection,EnumerableTableSource`1,...}
#                (Window : Terminal.Gui.App.IRunnable, ctor 为空)
#   View 基类:   Terminal.Gui.ViewBase.View (X/Y=Pos, Width/Height=Dim, BorderStyle)
#   键/命令:     Terminal.Gui.Input.{Key,Command,KeyBindings}
#                键码枚举在 **Terminal.Gui.Drivers.KeyCode** —— 只有 'Esc', 没有 'Escape';
#                `Key.KeyCode.ToString()` 才是大写字母('N'), `Key.ToString()` 是小写('n')。
#   驱动名:      DriverRegistry 仅注册 'windows' / 'dotnet' / 'ansi' 三个。
#   状态条:      Terminal.Gui.Views.StatusBar(IEnumerable<Terminal.Gui.Views.Shortcut>)
#   测试注入:    Application.RaiseKeyDownEvent(Key) 是 PowerShell 侧唯一可用的注入口
#                (TestInputSource 需要自写 ComponentFactoryImpl, PowerShell 做不到)。
#
# ★ 实测坑位(改本文件前先读):
#   - `Shortcut.BindKeyToApplication = $true` 时 TG 用 KeyBindings.AddApp 登记到
#     **应用级**键表(真实按键才会到达 Action); 同时 `Shortcut.Command` 必须保持
#     NotBound —— 与 Accept 同时出现会死循环 StackOverflow **崩进程**。
#   - 应用级键表**默认已绑定 Esc -> Quit**; 再登记 Esc 会抛
#     "A binding for Esc exists"。Esc 退出因此走 TG 内建 Quit 路径。
#   - `KeyBindings.Get(key)` 未绑定时抛 InvalidOperationException;
#     查询要用 `GetCommands(key)`。
#   - `GetBindings()` 返回的是底层 ConcurrentDictionary 本体, 遍历它拿不到键值对。
#   - PowerShell 侧调用 `MethodInfo.GetValue(obj, @($i))` 会被**解包**成单参数 ——
#     单元素参数数组必须用 `[object[]]::CreateInstance([object],1)` 手工构造。
#
# 契约: 幂等 —— 首次调用加载并缓存到 $script:TguiContext, 后续直接复用。
# 失败语义: 依赖/程序集缺失或类型探针失败抛可定位的终止错误, 不静默降级
# (调用方是真正的交互前沿, 缺一块就歇菜, 谎称可用只会渲染半屏)。

$script:TguiContext = $null

function Get-TguiContext {
    <#
    .SYNOPSIS
        加载(或复用)仓库内 vendored 的 Terminal.Gui v2 程序集上下文。

    .DESCRIPTION
        从 <仓库根>/Modules/Terminal.Gui/<最高版本目录>/ 载入 Terminal.Gui.dll
        及其同目录依赖, 返回 PSCustomObject:
          .Alc         AssemblyLoadContext(持有解析回调与全部已载程序集)
          .Assembly    Terminal.Gui 程序集对象
          .Version     程序集版本字符串(如 2.4.10.0)
          .Types       核心类型句柄哈希表:
                       Application / Window / TableView / StatusBar /
                       View / Key / Command / TestInputSource
        幂等: 已加载过则直接返回缓存, 不重复建立 ALC。

        依赖解析回调按**同目录文件名**回载 —— 版本升级(vendored 目录换名)
        仅影响版本号, 不需要改代码。

    .PARAMETER RootDirectory
        可选: 自定义 vendored 目录(测试隔离注入)。缺省用仓库根 Modules/Terminal.Gui。

    .OUTPUTS
        [PSCustomObject] .Alc/.Assembly/.Version/.Types

    .EXAMPLE
        $tg = Get-TguiContext
        $tg.Types.Application.GetMethod('Init', [object[]]@([string])) | Out-Null
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$RootDirectory = ''
    )

    if ($script:TguiContext) { return $script:TguiContext }

    # ---- 1. 定位 vendored 目录 (仓库根/Modules/Terminal.Gui/<ver>/Terminal.Gui.dll) ----
    $privateRoot = $PSScriptRoot
    $repoRoot = Split-Path -Path (Split-Path -Path $privateRoot -Parent) -Parent
    if ([string]::IsNullOrWhiteSpace($RootDirectory)) {
        $RootDirectory = Join-Path -Path $repoRoot -ChildPath 'Modules'
    }
    $tguiDir = Join-Path -Path $RootDirectory -ChildPath 'Terminal.Gui'
    if (-not (Test-Path -Path $tguiDir)) {
        throw "TGUI 载入失败: 未找到 vendored Terminal.Gui 目录 ($tguiDir)。交互式 UI 需要仓库内 Modules/Terminal.Gui。"
    }

    # 选最高版本子目录(目录名即版本), 取其一含 Terminal.Gui.dll
    $versionDir = Get-ChildItem -Path $tguiDir -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName 'Terminal.Gui.dll') } |
        Sort-Object { [version]$_.Name } -Descending |
        Select-Object -First 1
    if ($null -eq $versionDir) {
        throw "TGUI 载入失败: $tguiDir 下没有包含 Terminal.Gui.dll 的版本目录。"
    }
    $dllDir = $versionDir.FullName

    # ---- 2. 建立 ALC + 同目录依赖解析回调 ----
    # 注意: 解析回调由 ALC 在"程序集解析阶段"异步触发, 函数的局部变量会随
    # 函数栈退出而消亡 —— 不 GetNewClosure() 的话 $dllDir 在回调里是 $null,
    # 依赖解析静默失败_GetExportedTypes 抛 assembly-missing(实测踩坑)。
    #
    # ★ isCollectible = $false(2026-10-31 由 $true 改正, 勿改回):
    #   本 ALC 的生命周期就是进程 —— 全仓没有任何 Unload 调用, context 缓存到
    #   $script:TguiContext 供整个会话复用, "可回收"只会引入 GC 卸载竞态:
    #   每个测试文件的 BeforeAll 都 Import-Module -Force(旧模块实例被替换),
    #   旧 ALC 一旦被 GC 回收, .NET 之后在**新的** ALC 上解析 TG 依赖时会命中
    #   "AssemblyLoadContext is unloading or was already unloaded"(实测:
    #   Onigwrap / Microsoft.Extensions.DependencyInjection.Abstractions 的
    #   LoadFromAssemblyPath 落回已卸载的旧 ALC), 表现为成套 TGUI 用例集体
    #   失败。用独立脚本在纯净 HEAD 上同样可复现(与业务代码无关, 是
    #   collectible ALC + GC 的既有 .NET 限制), 只有"不可回收"能根除。
    #   代价: 每次模块重导入多驻留约 2 MB 托管 / 6 MB 工作集(实测), 进程退出即释放。
    $alc = [System.Runtime.Loader.AssemblyLoadContext]::new('ShellPrompt-Tgui', $false)
    $alc.add_Resolving({
        param($context, $assemblyName)
        # 按"文件名 = 程序集名 + .dll"在同目录回载; 不存在返回 $null 走默认解析
        $probe = Join-Path -Path $dllDir -ChildPath ($assemblyName.Name + '.dll')
        if (Test-Path -Path $probe) {
            return $context.LoadFromAssemblyPath((Resolve-Path -Path $probe).Path)
        }
        return $null
    }.GetNewClosure())

    # ---- 3. 载入 Terminal.Gui (依赖按需由回调拉齐, 亦可显式预热) ----
    $dllPath = Join-Path -Path $dllDir -ChildPath 'Terminal.Gui.dll'
    $validPath = (Resolve-Path -Path $dllPath).Path
    $assembly = $alc.LoadFromAssemblyPath($validPath)

    # ---- 4. 核心类型探针(反射实测, 不容"лайkly"命名) ----
    $types = @{}
    foreach ($t in @(
            @{ key = 'Application';     fullName = 'Terminal.Gui.App.Application' },
            @{ key = 'Window';          fullName = 'Terminal.Gui.Views.Window' },
            @{ key = 'TableView';       fullName = 'Terminal.Gui.Views.TableView' },
            @{ key = 'StatusBar';       fullName = 'Terminal.Gui.Views.StatusBar' },
            @{ key = 'View';            fullName = 'Terminal.Gui.ViewBase.View' },
            @{ key = 'Key';             fullName = 'Terminal.Gui.Input.Key' },
            @{ key = 'Command';         fullName = 'Terminal.Gui.Input.Command' },
            @{ key = 'TestInputSource'; fullName = 'Terminal.Gui.Drivers.TestInputSource' },
            @{ key = 'Label';           fullName = 'Terminal.Gui.Views.Label' },
            @{ key = 'FrameView';       fullName = 'Terminal.Gui.Views.FrameView' },
            @{ key = 'Dim';             fullName = 'Terminal.Gui.ViewBase.Dim' },
            @{ key = 'Pos';             fullName = 'Terminal.Gui.ViewBase.Pos' },
            @{ key = 'Shortcut';        fullName = 'Terminal.Gui.Views.Shortcut' },
            @{ key = 'TableSelection';  fullName = 'Terminal.Gui.Views.TableSelection' },
            @{ key = 'AppModel';        fullName = 'Terminal.Gui.App.AppModel' },
            # 配色链路(TGUI 自带主题装配, 不再借 Add-Type 的默认上下文副本):
            #   SchemeManager = 方案字典; Scheme = 单个方案(10 槽位); Color/Attribute = 结构体。
            # ★ 2026-10-30 真机教训: 同名类型跨程序集(Add-Type 默认上下文 vs 本 ALC)
            #   互不兼容 —— TGUI 的视图与 scheme 必须同源本 ALC。
            @{ key = 'SchemeManager';   fullName = 'Terminal.Gui.Configuration.SchemeManager' },
            @{ key = 'Scheme';          fullName = 'Terminal.Gui.Drawing.Scheme' },
            @{ key = 'Color';           fullName = 'Terminal.Gui.Drawing.Color' },
            @{ key = 'Attribute';       fullName = 'Terminal.Gui.Drawing.Attribute' }
        )) {
        $known = $assembly.GetType($t.fullName)
        if ($null -eq $known) {
            throw "TGUI 载入失败: Terminal.Gui 中缺少核心类型 $($t.fullName)。vendored 版本可能已变更, 请核对 Get-TguiContext.ps1 头部的 API 面记录。"
        }
        $types[$t.key] = $known
    }

    $context = [PSCustomObject]@{
        Alc        = $alc
        Assembly   = $assembly
        Version    = $assembly.GetName().Version.ToString()
        Types      = $types
        SourceDir  = $dllDir
    }
    $script:TguiContext = $context
    return $context
}
