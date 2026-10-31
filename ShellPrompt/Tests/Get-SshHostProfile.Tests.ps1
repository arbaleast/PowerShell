# Get-SshHostProfile.Tests.ps1 - SSH 配置结构化档案解析的契约测试
#
# 覆盖 (2026-10-31 sss 仪表盘数据层):
#   1. 连接字段解析(HostName/Port/User/IdentityFile/ProxyJump)与缺省值;
#   2. 元数据注释(@provider/@region/@tags/@group) —— 云端信息只能来自人写的注释,
#      没有就留空, 解析器不许"猜"云厂商;
#   3. 别名白名单(通配符/注入形态不产生条目)与 Match 块边界;
#   4. Include 展开(相对路径按主配置目录、Group 缺省取文件名、递归限深、防环);
#   5. mtime 缓存命中与失效;
#   6. 分类列表 / 分类过滤(纯函数, 不碰文件);
#   7. 文件缺失返回空数组, 不抛异常。
#
# 测试全部使用临时目录里的配置夹具, 不读真实 ~/.ssh, 不触网。

Describe 'Get-SshHostProfile: 连接字段解析' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'

        $script:fixtureDir = Join-Path $TestDrive 'profile-basic'
        New-Item -ItemType Directory -Force -Path $script:fixtureDir | Out-Null
        $script:cfgPath = Join-Path $script:fixtureDir 'config'
        @(
            'Host web1'
            '    HostName 10.0.0.11'
            '    User ubuntu'
            '    Port 2222'
            '    IdentityFile ~/.ssh/id_web1'
            '    ProxyJump bastion'
            ''
            'Host web2'
            '    HostName=web2.example.com'
            '    port = 2200'
        ) | Set-Content -LiteralPath $script:cfgPath -Encoding UTF8

        $script:profiles = @(& $script:mod {
                param($p)
                @(Get-SshHostProfile -ConfigPath $p -NoCache)
            } $script:cfgPath)
    }

    It '每个 Host 块产出一条档案, 顺序与配置一致' {
        $script:profiles | Should -HaveCount 2
        $script:profiles[0].Name | Should -BeExactly 'web1'
        $script:profiles[1].Name | Should -BeExactly 'web2'
    }

    It 'HostName / User / Port / IdentityFile / ProxyJump 原样解析' {
        $p = $script:profiles[0]
        $p.HostName | Should -BeExactly '10.0.0.11'
        $p.User | Should -BeExactly 'ubuntu'
        $p.Port | Should -Be 2222
        $p.IdentityFile | Should -BeExactly '~/.ssh/id_web1'
        $p.ProxyJump | Should -BeExactly 'bastion'
    }

    It '指令名大小写不敏感, 且支持 "Key=Value" 与 "Key = Value" 两种分隔' {
        $p = $script:profiles[1]
        $p.HostName | Should -BeExactly 'web2.example.com'
        $p.Port | Should -Be 2200
    }

    It '缺省值: Port=22, HostName 回退别名, User/IdentityFile/ProxyJump 为空串' {
        $cfg = Join-Path $TestDrive 'profile-defaults/config'
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $cfg) | Out-Null
        @('Host bare') | Set-Content -LiteralPath $cfg -Encoding UTF8
        $one = @(& $script:mod { param($p) @(Get-SshHostProfile -ConfigPath $p -NoCache) } $cfg)
        $one | Should -HaveCount 1
        $one[0].Port | Should -Be 22
        $one[0].HostName | Should -BeExactly 'bare'
        $one[0].User | Should -BeExactly ''
        $one[0].IdentityFile | Should -BeExactly ''
        $one[0].ProxyJump | Should -BeExactly ''
        $one[0].Tags | Should -HaveCount 0
    }

    It '非法 Port(非数字/越界)回退 22, 不抛异常' {
        $cfg = Join-Path $TestDrive 'profile-badport/config'
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $cfg) | Out-Null
        @(
            'Host bad-port'
            '    Port not-a-number'
            ''
            'Host out-of-range'
            '    Port 70000'
        ) | Set-Content -LiteralPath $cfg -Encoding UTF8
        $two = @(& $script:mod { param($p) @(Get-SshHostProfile -ConfigPath $p -NoCache) } $cfg)
        $two | Should -HaveCount 2
        $two[0].Port | Should -Be 22
        $two[1].Port | Should -Be 22
    }

    It 'IsLocal: localhost / 127.0.0.1 / ::1 判定为本地主机' {
        $cfg = Join-Path $TestDrive 'profile-local/config'
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $cfg) | Out-Null
        @(
            'Host box-a'
            '    HostName localhost'
            ''
            'Host box-b'
            '    HostName 127.0.0.1'
            ''
            'Host box-c'
            '    HostName ::1'
            ''
            'Host box-d'
            '    HostName 10.1.2.3'
        ) | Set-Content -LiteralPath $cfg -Encoding UTF8
        $local = @(& $script:mod { param($p) @(Get-SshHostProfile -ConfigPath $p -NoCache) } $cfg)
        $local | Should -HaveCount 4
        ($local | Where-Object IsLocal | ForEach-Object Name) | Should -Be @('box-a', 'box-b', 'box-c')
        ($local | Where-Object { -not $_.IsLocal } | ForEach-Object Name) | Should -Be @('box-d')
    }
}

Describe 'Get-SshHostProfile: 元数据注释与别名白名单' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'

        $script:cfgPath = Join-Path $TestDrive 'profile-meta/config'
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $script:cfgPath) | Out-Null
        @(
            '# @provider AWS'
            '# @region us-east-1'
            '# @tags prod, web'
            '# @group production'
            'Host aws-web'
            '    HostName ec2-1-2-3-4.compute-1.amazonaws.com   # 行内注释应被剥离'
            ''
            'Host *'
            '    User fallback'
            ''
            'Host *.internal'
            '    User nobody'
            ''
            'Host -oProxyCommand=calc'
            '    User injected'
            ''
            'Host Mixed-Case'
            '    HostName 10.9.9.9'
            '    User deploy'
        ) | Set-Content -LiteralPath $script:cfgPath -Encoding UTF8

        $script:profiles = @(& $script:mod {
                param($p)
                @(Get-SshHostProfile -ConfigPath $p -NoCache)
            } $script:cfgPath)
    }

    It '元数据注释解析为 Provider / Region / Tags / Group' {
        $p = $script:profiles | Where-Object Name -EQ 'aws-web'
        $p.Provider | Should -BeExactly 'AWS'
        $p.Region | Should -BeExactly 'us-east-1'
        $p.Tags | Should -Be @('prod', 'web')
        $p.Group | Should -BeExactly 'production'
    }

    It '行内注释被剥离, HostName 保持干净' {
        ($script:profiles | Where-Object Name -EQ 'aws-web').HostName |
            Should -BeExactly 'ec2-1-2-3-4.compute-1.amazonaws.com'
    }

    It '通配符别名不产生档案条目' {
        $script:profiles | ForEach-Object Name | Should -Not -Contain '*'
        $script:profiles | ForEach-Object Name | Should -Not -Contain '*.internal'
    }

    It '以 - 开头的注入形态别名不产生档案条目' {
        $script:profiles | ForEach-Object Name | Should -Not -Contain '-oProxyCommand=calc'
    }

    It '没有元数据注释的主机 Provider/Region/Tags/Group 为空(不猜云厂商)' {
        $p = $script:profiles | Where-Object Name -EQ 'Mixed-Case'
        $p.Provider | Should -BeExactly ''
        $p.Region | Should -BeExactly ''
        $p.Tags | Should -HaveCount 0
        $p.Group | Should -BeExactly ''
        $p.User | Should -BeExactly 'deploy'
    }

    It 'Match 之后的属性不落到上一个 Host 块' {
        $cfg = Join-Path $TestDrive 'profile-match/config'
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $cfg) | Out-Null
        @(
            'Host before-match'
            '    HostName 10.0.0.1'
            ''
            'Match host internal'
            '    User should-not-leak'
            ''
            'Host after-match'
            '    HostName 10.0.0.2'
        ) | Set-Content -LiteralPath $cfg -Encoding UTF8
        $profiles = @(& $script:mod { param($p) @(Get-SshHostProfile -ConfigPath $p -NoCache) } $cfg)
        $profiles | Should -HaveCount 2
        ($profiles | Where-Object Name -EQ 'before-match').User | Should -BeExactly ''
        ($profiles | Where-Object Name -EQ 'after-match').User | Should -BeExactly ''
    }

    It '同一别名重复定义: 首见为准, 后续块只补空字段' {
        $cfg = Join-Path $TestDrive 'profile-dup/config'
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $cfg) | Out-Null
        @(
            'Host dup'
            '    HostName first.example.com'
            ''
            'Host dup'
            '    HostName second.example.com'
            '    User second-user'
        ) | Set-Content -LiteralPath $cfg -Encoding UTF8
        $profiles = @(& $script:mod { param($p) @(Get-SshHostProfile -ConfigPath $p -NoCache) } $cfg)
        $profiles | Should -HaveCount 1
        $profiles[0].HostName | Should -BeExactly 'first.example.com'
        $profiles[0].User | Should -BeExactly 'second-user'
    }
}

Describe 'Get-SshHostProfile: Include 展开' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'

        $script:root = Join-Path $TestDrive 'profile-include'
        New-Item -ItemType Directory -Force -Path (Join-Path $script:root 'conf.d') | Out-Null
        $script:cfgPath = Join-Path $script:root 'config'
        @(
            'Host main-host'
            '    HostName 10.0.0.10'
            ''
            'Include conf.d/*.conf'
        ) | Set-Content -LiteralPath $script:cfgPath -Encoding UTF8

        @(
            'Host droplet'
            '    HostName 203.0.113.9'
            ''
            'Host droplet-2'
            '    HostName 203.0.113.10'
        ) | Set-Content -LiteralPath (Join-Path $script:root 'conf.d/digitalocean.conf') -Encoding UTF8

        $script:profiles = @(& $script:mod {
                param($p)
                @(Get-SshHostProfile -ConfigPath $p -NoCache)
            } $script:cfgPath)
    }

    It 'Include 的文件按插入点展开, 块顺序为 主配置 -> 包含文件' {
        $script:profiles | ForEach-Object Name | Should -Be @('main-host', 'droplet', 'droplet-2')
    }

    It '被包含文件的 Source 指向该文件本身' {
        $p = $script:profiles | Where-Object Name -EQ 'droplet'
        (Split-Path -Leaf $p.Source) | Should -BeExactly 'digitalocean.conf'
    }

    It '被包含文件的 Group 缺省取文件名(不含扩展名)' {
        ($script:profiles | Where-Object Name -EQ 'droplet').Group | Should -BeExactly 'digitalocean'
    }

    It '显式 @group 优先于文件名缺省' {
        $cfg = Join-Path $TestDrive 'profile-include-group/config'
        $dir = Split-Path -Parent $cfg
        New-Item -ItemType Directory -Force -Path (Join-Path $dir 'conf.d') | Out-Null
        @('Include conf.d/cloud.conf') | Set-Content -LiteralPath $cfg -Encoding UTF8
        @(
            '# @group explicit'
            'Host cloud-host'
            '    HostName 10.5.5.5'
        ) | Set-Content -LiteralPath (Join-Path $dir 'conf.d/cloud.conf') -Encoding UTF8
        $profiles = @(& $script:mod { param($p) @(Get-SshHostProfile -ConfigPath $p -NoCache) } $cfg)
        $profiles | Should -HaveCount 1
        $profiles[0].Group | Should -BeExactly 'explicit'
    }

    It '自引用 Include 不会无限递归(深度上限内终止)' {
        $cfg = Join-Path $TestDrive 'profile-include-cycle/config'
        $dir = Split-Path -Parent $cfg
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        @(
            'Host cycle-host'
            '    HostName 10.1.1.1'
            ''
            'Include config'
        ) | Set-Content -LiteralPath $cfg -Encoding UTF8
        $profiles = @(& $script:mod { param($p) @(Get-SshHostProfile -ConfigPath $p -NoCache) } $cfg)
        $profiles | Should -HaveCount 1
        $profiles[0].Name | Should -BeExactly 'cycle-host'
    }

    It 'Include 指向不存在的路径静默跳过' {
        $cfg = Join-Path $TestDrive 'profile-include-missing/config'
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $cfg) | Out-Null
        @(
            'Host lonely'
            '    HostName 10.2.2.2'
            ''
            'Include does-not-exist.conf'
        ) | Set-Content -LiteralPath $cfg -Encoding UTF8
        $profiles = @(& $script:mod { param($p) @(Get-SshHostProfile -ConfigPath $p -NoCache) } $cfg)
        $profiles | Should -HaveCount 1
        $profiles[0].Name | Should -BeExactly 'lonely'
    }
}

Describe 'Get-SshHostProfile: 缓存与容错' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It '文件缺失时返回空数组, 不抛异常' {
        $missing = Join-Path $TestDrive 'profile-absent/config'
        { & $script:mod { param($p) Get-SshHostProfile -ConfigPath $p -NoCache } $missing } |
            Should -Not -Throw
        $result = @(& $script:mod { param($p) @(Get-SshHostProfile -ConfigPath $p -NoCache) } $missing)
        $result | Should -HaveCount 0
    }

    It 'mtime 缓存: 同文件未变时命中, 内容变化后失效' {
        $cfg = Join-Path $TestDrive 'profile-cache/config'
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $cfg) | Out-Null
        @('Host cache-a') | Set-Content -LiteralPath $cfg -Encoding UTF8

        $first = @(& $script:mod { param($p) @(Get-SshHostProfile -ConfigPath $p) } $cfg)
        $first | Should -HaveCount 1

        $second = @(& $script:mod { param($p) @(Get-SshHostProfile -ConfigPath $p) } $cfg)
        $second | Should -HaveCount 1

        # 改内容并把 mtime 推到未来, 确保 mtime 一定变化(不依赖文件系统时间精度)
        @('Host cache-a', 'Host cache-b') | Set-Content -LiteralPath $cfg -Encoding UTF8
        [System.IO.File]::SetLastWriteTimeUtc($cfg, [datetime]::UtcNow.AddSeconds(30))

        $third = @(& $script:mod { param($p) @(Get-SshHostProfile -ConfigPath $p) } $cfg)
        $third | Should -HaveCount 2
    }

    It '不同配置文件路径互不复用缓存(测试隔离保障)' {
        $cfgA = Join-Path $TestDrive 'profile-iso-a/config'
        $cfgB = Join-Path $TestDrive 'profile-iso-b/config'
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $cfgA) | Out-Null
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $cfgB) | Out-Null
        @('Host only-a') | Set-Content -LiteralPath $cfgA -Encoding UTF8
        @('Host only-b-1', 'Host only-b-2') | Set-Content -LiteralPath $cfgB -Encoding UTF8

        $a = @(& $script:mod { param($p) @(Get-SshHostProfile -ConfigPath $p) } $cfgA)
        $b = @(& $script:mod { param($p) @(Get-SshHostProfile -ConfigPath $p) } $cfgB)
        $a | Should -HaveCount 1
        $b | Should -HaveCount 2
    }
}

Describe 'Get-SshHostCategoryList / Select-SshHostByCategory' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'

        # 分类/过滤是纯函数, 直接用最小字段的档案对象驱动, 不必造 ssh 配置文件
        $script:profiles = @(
            [PSCustomObject]@{ Name = 'aws-a'; HostName = 'aws-a'; Provider = 'AWS'; IsLocal = $false }
            [PSCustomObject]@{ Name = 'do-a'; HostName = 'do-a'; Provider = 'DigitalOcean'; IsLocal = $false }
            [PSCustomObject]@{ Name = 'aws-b'; HostName = 'aws-b'; Provider = 'aws'; IsLocal = $false }
            [PSCustomObject]@{ Name = 'local-box'; HostName = 'localhost'; Provider = ''; IsLocal = $true }
            [PSCustomObject]@{ Name = 'plain-host'; HostName = 'plain-host'; Provider = ''; IsLocal = $false }
        )
    }

    It '分类列表: All 开头 + 实际出现的 Provider(首次出现顺序, 大小写不敏感去重) + Local + Other' {
        $categories = @(& $script:mod { param($p) @(Get-SshHostCategoryList -Profiles $p) } $script:profiles)
        $categories | Should -Be @('All', 'AWS', 'DigitalOcean', 'Local', 'Other')
    }

    It '没有任何主机时只有 All' {
        $categories = @(& $script:mod { @(Get-SshHostCategoryList -Profiles @()) })
        $categories | Should -Be @('All')
    }

    It 'Provider 恰好叫 Local / Other 时不重复追加同名分类' {
        $profiles = @(
            [PSCustomObject]@{ Name = 'x'; HostName = 'x'; Provider = 'Local'; IsLocal = $true }
            [PSCustomObject]@{ Name = 'y'; HostName = 'y'; Provider = ''; IsLocal = $false }
        )
        $categories = @(& $script:mod { param($p) @(Get-SshHostCategoryList -Profiles $p) } $profiles)
        $categories | Should -Be @('All', 'Local', 'Other')
    }

    It 'Select: All 返回全部, Provider 匹配大小写不敏感' {
        $all = @(& $script:mod { param($p) @(Select-SshHostByCategory -Profiles $p -Category 'All') } $script:profiles)
        $all | Should -HaveCount 5

        $aws = @(& $script:mod { param($p) @(Select-SshHostByCategory -Profiles $p -Category 'aws') } $script:profiles)
        $aws | ForEach-Object Name | Should -Be @('aws-a', 'aws-b')
    }

    It 'Select: Local 只返回本地主机, Other 只返回无 Provider 且非本地的主机' {
        $local = @(& $script:mod { param($p) @(Select-SshHostByCategory -Profiles $p -Category 'Local') } $script:profiles)
        $local | ForEach-Object Name | Should -Be @('local-box')

        $other = @(& $script:mod { param($p) @(Select-SshHostByCategory -Profiles $p -Category 'Other') } $script:profiles)
        $other | ForEach-Object Name | Should -Be @('plain-host')
    }

    It 'Select: 未知分类返回空集合而不是抛错' {
        $none = @(& $script:mod { param($p) @(Select-SshHostByCategory -Profiles $p -Category 'NoSuchProvider') } $script:profiles)
        $none | Should -HaveCount 0
    }
}
