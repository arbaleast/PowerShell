# Get-TguiContext.Tests.ps1 - Terminal.Gui v2 程序集加载器契约测试(阶段 A)
# 覆盖:
#   1. 幂等: 首次加载后二次调用返回同一上下文(不重复建 ALC);
#   2. 核心 API 面存在(反射实测,Goal 严禁"按示例假定 API"): Application 的
#      Init/Run/Shutdown 静态成员与 Window/TableView/StatusBar/View/FTypes;
#   3. Window : Terminal.Gui.App.IRunnable (Run[TRunnable] 运行模型的前提);
#   4. 文案不匹配/目录缺失时抛可定位错误(不静默降级)。
# 说明: 纯反射级验证, 不触发 Application.Init(无头/无 TTY 环境安全)。

Describe 'Terminal.Gui v2 上下文加载器 (Get-TguiContext)' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It '首次调用加载 vendored Terminal.Gui 2.4.10 并缓存幂等' {
        $first = & $script:mod { Get-TguiContext }
        $second = & $script:mod { Get-TguiContext }

        $first | Should -Not -BeNullOrEmpty
        $second | Should -BeExactly $first
        $first.Version | Should -Not -BeNullOrEmpty
        # PSTui 1.0.5 同源钉版 (vendored 2.4.10.0)
        $first.Assembly.GetName().Version.Major | Should -Be 2
    }

    It '核心类型句柄齐全且命名空间与 2.4.10 实测 API 面一致' {
        $ctx = & $script:mod { Get-TguiContext }

        foreach ($key in @('Application', 'Window', 'TableView', 'StatusBar', 'View', 'Key', 'Command', 'TestInputSource')) {
            $ctx.Types.ContainsKey($key) | Should -BeTrue
            $ctx.Types[$key] | Should -Not -BeNullOrEmpty
        }
        ($ctx.Types.Application.FullName -eq 'Terminal.Gui.App.Application') | Should -BeTrue
        ($ctx.Types.View.FullName -eq 'Terminal.Gui.ViewBase.View') | Should -BeTrue
    }

    It 'Application 具备 Init/Shutdown/Run 静态方法与 Instance 属性' {
        $ctx = & $script:mod { Get-TguiContext }
        $app = $ctx.Types.Application
        $staticFlags = [System.Reflection.BindingFlags]'Public,Static'

        ($app.GetMethod('Init', [System.Type[]]@([string]), $staticFlags) -or
            $app.GetMethod('Init', $staticFlags)) | Should -Not -BeNullOrEmpty
        $app.GetMethod('Shutdown', $staticFlags) | Should -Not -BeNullOrEmpty
        ($app.GetMethods($staticFlags) | Where-Object { $_.Name -eq 'Run' }) | Should -Not -BeNullOrEmpty
        $app.GetProperty('Instance', $staticFlags) | Should -Not -BeNullOrEmpty
    }

    It 'Window 实现 Terminal.Gui.App.IRunnable (可被 Run[TRunnable] 运行)' {
        $ctx = & $script:mod { Get-TguiContext }
        $runnable = $ctx.Assembly.GetType('Terminal.Gui.App.IRunnable')

        $runnable | Should -Not -BeNullOrEmpty
        $runnable.IsAssignableFrom($ctx.Types.Window) | Should -BeTrue
    }

    It '缺失依赖时抛可定位错误(不静默降级)' {
        # 幂等缓存会让非法目录"啥也不检查"就命中命中 —— 先清缓存再探针
        & $script:mod { $script:TguiContext = $null }

        # 注入不存在的目录: 必须抛"TGUI 载入失败" 而不是返回空壳。
        # 注意: 路径不要带 'X:\' 盘符假写 —— Linux 上 Test-Path 会抛
        # "Cannot find drive", 与"目录缺失"是两种错误。
        { & $script:mod { param($d) Get-TguiContext -RootDirectory $d } '/definitely/not/tui-here' } |
            Should -Throw '*TGUI 载入失败*'
    }
}
