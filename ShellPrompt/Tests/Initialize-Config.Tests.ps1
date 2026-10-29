# Initialize-Config.Tests.ps1 - 配置读取与颜色常量
# 2026-10-29: 从 Show-ProgressSpinner.Tests.ps1 迁出 (该文件随死代码整体删除)。
# 覆盖: Get-CachedConfig 返回的颜色值必须携带真正的 ESC 字节 (0x1B),
#   否则 Spectre / ANSI 渲染会失效;
#   用户配置(config.ps1)的覆盖必须生效, 且不被预热缓存遮蔽。

Describe 'Get-CachedConfig 颜色常量' {

    BeforeAll {
        # Pester v6: 路径与模块引用必须放在 BeforeAll 内解析
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It '返回的颜色值应包含真正的 ESC 字符 (0x1B)' {
        # 锁定回归: 颜色常量必须携带真实 ESC 字节, 否则 Spectre/ANSI 渲染失效
        $primary = & $script:mod { Get-CachedConfig -Section 'Colors' -Key 'FreshGreen' -Default "`e[38;2;137;209;133m" }
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($primary)
        ($bytes -contains 27) | Should -Be $true
    }

    It 'Rst 重置码应包含 ESC 字符' {
        $rst = & $script:mod { Get-CachedConfig -Section 'Colors' -Key 'Rst' -Default "`e[0m" }
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($rst)
        ($bytes -contains 27) | Should -Be $true
    }
}

Describe '用户配置覆盖与预热缓存' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
        $script:initConfigPath = Join-Path -Path $moduleRoot -ChildPath 'Private\Initialize-Config.ps1'
    }

    It '预热缓存的每个值都必须与 $script:Config 保持一致' {
        # 两者一旦不一致, 说明预热快照比配置旧 —— 用户在 config.ps1 里的覆盖
        # 会被 Get-CachedConfig 优先命中的缓存静默遮蔽。
        $mismatch = & $script:mod {
            $bad = @()
            foreach ($cacheKey in $script:ColorCache.Keys) {
                $parts = $cacheKey -split '\|'
                $configValue = $script:Config[$parts[0]][$parts[1]]
                if ("$($script:ColorCache[$cacheKey])" -ne "$configValue") { $bad += $cacheKey }
            }
            $bad
        }
        $mismatch | Should -BeNullOrEmpty
    }

    It '用户配置(config.ps1)的覆盖必须生效, 且不被预热缓存遮蔽' {
        # 锁定回归(2026-10-29): 用户配置原先在预热缓存**之后**加载, 而
        # Get-CachedConfig 优先命中预热快照 —— 于是 config.ps1 里的颜色/路径
        # 覆盖全部不生效, 用户改了配置却看不到任何变化。
        # 本用例用临时 HOME 重跑一次配置初始化, 直接验证"用户配置 -> Config
        # -> 预热缓存 -> Get-CachedConfig"整条链路。
        $fakeHome = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('sp-home-' + [guid]::NewGuid().ToString('N'))
        $configDir = Join-Path -Path $fakeHome -ChildPath '.ShellPrompt'
        try {
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path -Path $configDir -ChildPath 'config.ps1') `
                -Value '$Config.Colors.FreshGreen = ''SP-SENTINEL-GREEN''' -Encoding utf8

            $initConfig = $script:initConfigPath
            $actual = @(& {
                    # $HOME 只在这个子作用域里被替换, 用户的真实 HOME 不受影响
                    $HOME = $fakeHome
                    . $initConfig
                    Get-CachedConfig -Section 'Colors' -Key 'FreshGreen' -Default 'NO-VALUE'
                })[-1]
            $actual | Should -Be 'SP-SENTINEL-GREEN'
        } finally {
            Remove-Item -LiteralPath $fakeHome -Recurse -Force -ErrorAction SilentlyContinue
            # 本用例会在测试文件作用域留下 $script:Config / $script:ColorCache 等变量, 清掉以免影响其它用例
            Remove-Variable -Name 'Config', 'ColorCache', 'Esc', 'ShellPromptRoot' -Scope Script -ErrorAction SilentlyContinue
        }
    }
}
