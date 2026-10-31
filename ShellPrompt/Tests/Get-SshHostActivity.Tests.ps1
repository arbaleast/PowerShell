# Get-SshHostActivity.Tests.ps1 - 主机本地连接活动(读/写)的契约测试
#
# 覆盖 (2026-10-31 sss 仪表盘数据层):
#   1. 无记录时 HasData=$false / LastSeen=$null / DayBuckets 全 0(不伪造数据);
#   2. 写入 -> 读回: Count 累加、Recent 升序、LastSeen 取最新;
#   3. 按天分桶(固定日期注入, 不依赖运行时的"今天");
#   4. Recent 截断 20 条、主机数上限 200 按最后活跃淘汰;
#   5. JSON 损坏 / 空文件 / 缺字段的容错(降级为空历史, 不抛异常);
#   6. -PassThru 返回写入后的视图; -All 列出全部并按最后活跃倒序;
#   7. 时间口径归一(本地时区入参 -> 落盘 UTC); 写入目录自动创建; 无 .tmp 残留;
#   8. 主机名大小写不敏感。
#
# 测试全部使用 -StorePath 指向临时文件, 不碰真实 ~/.ShellPrompt。

Describe 'Get-SshHostActivity: 无记录时的空态' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
        $script:store = Join-Path $TestDrive 'empty/activity.json'
    }

    It '记录文件不存在时返回空态, 不抛异常' {
        $view = & $script:mod { param($p) Get-SshHostActivity -HostName 'nope' -StorePath $p } $script:store
        $view.HasData | Should -BeFalse
        $view.Count | Should -Be 0
        $view.LastSeen | Should -BeNullOrEmpty
        $view.Recent | Should -HaveCount 0
        $view.DayBuckets | Should -HaveCount 7
        ($view.DayBuckets | Measure-Object -Sum).Sum | Should -Be 0
    }
}

Describe 'Add-SshHostActivity: 写入与读回' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
        $script:store = Join-Path $TestDrive 'write/activity.json'
    }

    It '连续两次记录: Count=2, Recent 升序, LastSeen 取最新' {
        $older = [datetime]::new(2026, 10, 29, 12, 0, 0, [System.DateTimeKind]::Utc)
        $newer = [datetime]::new(2026, 10, 30, 12, 0, 0, [System.DateTimeKind]::Utc)

        & $script:mod { param($p, $t) Add-SshHostActivity -HostName 'deb' -TimeUtc $t -StorePath $p } $script:store $newer
        & $script:mod { param($p, $t) Add-SshHostActivity -HostName 'deb' -TimeUtc $t -StorePath $p } $script:store $older

        $view = & $script:mod { param($p) Get-SshHostActivity -HostName 'deb' -StorePath $p } $script:store
        $view.HasData | Should -BeTrue
        $view.Count | Should -Be 2
        $view.Recent | Should -HaveCount 2
        # 升序: 即使先写新后写旧, 读回仍按时间升序
        $view.Recent[0] | Should -BeLessThan $view.Recent[1]
        $view.LastSeen.ToUniversalTime() | Should -Be $newer
    }

    It '二次写入后 Recent 仍是 ISO 8601 串(防 ConvertFrom-Json 自动转 DateTime 的区域格式回归)' {
        # 回归背景: PowerShell 7.5+ 的 ConvertFrom-Json 默认把 ISO 串反序列化成 [datetime],
        # 旧实现再用 [string] 强转就会按区域格式写回(如 "10/30/2026 12:00:00"),
        # 与既有 ISO 串混排后字典序排序失效、LastSeen 倒退。这里钉死落盘格式。
        $store = Join-Path $TestDrive 'write/iso-format.json'
        $t1 = [datetime]::new(2026, 10, 30, 12, 0, 0, [System.DateTimeKind]::Utc)
        $t2 = [datetime]::new(2026, 10, 29, 12, 0, 0, [System.DateTimeKind]::Utc)
        & $script:mod { param($p, $t) Add-SshHostActivity -HostName 'iso-host' -TimeUtc $t -StorePath $p } $store $t1
        & $script:mod { param($p, $t) Add-SshHostActivity -HostName 'iso-host' -TimeUtc $t -StorePath $p } $store $t2

        $json = Get-Content -LiteralPath $store -Raw -Encoding UTF8
        $json | Should -Not -Match '\d{1,2}/\d{1,2}/\d{4}'
        # LastSeenUtc(1) + Recent(2) 都必须是 ISO 形态
        ([regex]::Matches($json, '2026-10-\d\dT\d{2}:\d{2}:\d{2}')).Count | Should -BeGreaterOrEqual 3
    }

    It 'PassThru 返回写入后的活动视图' {
        $store = Join-Path $TestDrive 'write/passthru.json'
        $view = & $script:mod { param($p) Add-SshHostActivity -HostName 'web' -StorePath $p -PassThru } $store
        $view.Host | Should -BeExactly 'web'
        $view.Count | Should -Be 1
        $view.HasData | Should -BeTrue
    }

    It '主机名大小写不敏感(deb 与 DEB 是同一条记录)' {
        $store = Join-Path $TestDrive 'write/case.json'
        & $script:mod { param($p) Add-SshHostActivity -HostName 'deb' -StorePath $p } $store
        & $script:mod { param($p) Add-SshHostActivity -HostName 'DEB' -StorePath $p } $store
        $view = & $script:mod { param($p) Get-SshHostActivity -HostName 'Deb' -StorePath $p } $store
        $view.Count | Should -Be 2
        @(& $script:mod { param($p) @(Get-SshHostActivity -All -StorePath $p) } $store) | Should -HaveCount 1
    }

    It '目录不存在时自动创建; 写完后不留下 .tmp 半成品' {
        $store = Join-Path $TestDrive 'nested/deeper/activity.json'
        & $script:mod { param($p) Add-SshHostActivity -HostName 'auto-dir' -StorePath $p } $store
        $store | Should -Exist
        (Join-Path $TestDrive 'nested/deeper/activity.json.tmp') | Should -Not -Exist
    }

    It '本地时区入参归一为 UTC 落盘, 读回仍是同一时刻' {
        $store = Join-Path $TestDrive 'write/tz.json'
        $localTime = [datetime]::new(2026, 10, 31, 9, 30, 0, [System.DateTimeKind]::Local)
        & $script:mod {
            param($p, $t)
            Add-SshHostActivity -HostName 'tz-host' -TimeUtc $t -StorePath $p
        } $store $localTime

        $json = Get-Content -LiteralPath $store -Raw -Encoding UTF8
        $json | Should -Match '\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}'

        $view = & $script:mod { param($p) Get-SshHostActivity -HostName 'tz-host' -StorePath $p } $store
        $view.LastSeen.ToUniversalTime() | Should -Be $localTime.ToUniversalTime()
    }
}

Describe 'Add-SshHostActivity: 容量上限' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It 'Recent 只保留最近 20 条, Count 仍然累加' {
        $store = Join-Path $TestDrive 'cap/recent.json'
        $base = [datetime]::new(2026, 10, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
        & $script:mod {
            param($p, $base)
            for ($i = 0; $i -lt 25; $i++) {
                Add-SshHostActivity -HostName 'frequent' -TimeUtc $base.AddMinutes($i) -StorePath $p
            }
        } $store $base

        $view = & $script:mod { param($p) Get-SshHostActivity -HostName 'frequent' -StorePath $p } $store
        $view.Count | Should -Be 25
        $view.Recent | Should -HaveCount 20
        # 最新一条是 base+24min, 最旧保留的是 base+5min(前 5 条被裁掉)
        $view.Recent[19].ToUniversalTime() | Should -Be $base.AddMinutes(24)
        $view.Recent[0].ToUniversalTime() | Should -Be $base.AddMinutes(5)
    }

    It '主机数超过 200 时按最后活跃最旧淘汰' {
        $store = Join-Path $TestDrive 'cap/hosts.json'
        $hosts = @{}
        $base = [datetime]::new(2026, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
        for ($i = 0; $i -lt 200; $i++) {
            $hosts["h$i"] = @{
                LastSeenUtc = $base.AddMinutes($i).ToString('o')
                Count       = 1
                Recent      = @()
            }
        }
        $document = @{ Version = 1; Hosts = $hosts } | ConvertTo-Json -Depth 6
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $store) | Out-Null
        Set-Content -LiteralPath $store -Value $document -Encoding utf8

        & $script:mod { param($p) Add-SshHostActivity -HostName 'brand-new' -StorePath $p } $store

        $all = @(& $script:mod { param($p) @(Get-SshHostActivity -All -StorePath $p) } $store)
        $all | Should -HaveCount 200
        $all.Host | Should -Contain 'brand-new'
        $all.Host | Should -Not -Contain 'h0'      # 最旧
        $all.Host | Should -Contain 'h199'         # 最新一批仍在
    }
}

Describe 'Get-SshHostActivity: 按天分桶与容错' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It 'DayBuckets: 索引 6 = 今天, 索引 0 = 6 天前(固定日期注入, 不依赖运行时)' {
        # 用 12:00Z 造时间戳: 在任何常见时区偏移下, 本地日期都与 UTC 日期同日,
        # 因此这个用例不会因为容器时区而抖动。
        $entry = @{
            LastSeenUtc = '2026-10-31T12:00:00.0000000Z'
            Count       = 3
            Recent      = @(
                '2026-10-31T12:00:00.0000000Z'   # 今天   -> 索引 6
                '2026-10-29T12:00:00.0000000Z'   # 2 天前 -> 索引 4
                '2026-10-29T13:00:00.0000000Z'   # 2 天前 -> 索引 4
                '2026-10-10T12:00:00.0000000Z'   # 超窗   -> 不计数
            )
        }
        $today = [datetime]::new(2026, 10, 31)

        $view = & $script:mod {
            param($e, $t)
            ConvertTo-SshHostActivityView -HostName 'bucketed' -Entry $e -Today $t
        } $entry $today

        $view.DayBuckets[6] | Should -Be 1
        $view.DayBuckets[4] | Should -Be 2
        $view.DayBuckets[0] | Should -Be 0
        $view.DayBuckets[5] | Should -Be 0
        ($view.DayBuckets | Measure-Object -Sum).Sum | Should -Be 3
    }

    It '公开 API 写入后能看到今天的计数(真实时钟路径)' {
        $store = Join-Path $TestDrive 'bucket/today.json'
        & $script:mod { param($p) Add-SshHostActivity -HostName 'now-host' -StorePath $p } $store
        $view = & $script:mod { param($p) Get-SshHostActivity -HostName 'now-host' -StorePath $p } $store
        ($view.DayBuckets | Measure-Object -Sum).Sum | Should -Be 1
        $view.DayBuckets[6] | Should -Be 1
    }

    It 'JSON 损坏时按空历史处理, 不抛异常, 后续写入仍可用' {
        $store = Join-Path $TestDrive 'corrupt/activity.json'
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $store) | Out-Null
        Set-Content -LiteralPath $store -Value '{ this is not valid json' -Encoding utf8

        { & $script:mod { param($p) Get-SshHostActivity -HostName 'x' -StorePath $p } $store } |
            Should -Not -Throw
        $broken = & $script:mod { param($p) Get-SshHostActivity -HostName 'x' -StorePath $p } $store
        $broken.HasData | Should -BeFalse

        & $script:mod { param($p) Add-SshHostActivity -HostName 'x' -StorePath $p } $store
        $after = & $script:mod { param($p) Get-SshHostActivity -HostName 'x' -StorePath $p } $store
        $after.Count | Should -Be 1
    }

    It '空文件与缺字段的条目按空历史处理' {
        $store = Join-Path $TestDrive 'corrupt/partial.json'
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $store) | Out-Null
        Set-Content -LiteralPath $store -Value '' -Encoding utf8
        $empty = & $script:mod { param($p) Get-SshHostActivity -HostName 'y' -StorePath $p } $store
        $empty.HasData | Should -BeFalse

        @{ Version = 1; Hosts = @{ 'partial' = @{ Count = 2 } } } | ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath $store -Encoding utf8
        $partial = & $script:mod { param($p) Get-SshHostActivity -HostName 'partial' -StorePath $p } $store
        $partial.Count | Should -Be 2
        $partial.LastSeen | Should -BeNullOrEmpty
        $partial.Recent | Should -HaveCount 0
        $partial.HasData | Should -BeTrue
    }

    It '-All 按最后活跃倒序返回, 无记录的主机不出现' {
        $store = Join-Path $TestDrive 'all/activity.json'
        $base = [datetime]::new(2026, 10, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
        & $script:mod {
            param($p, $base)
            Add-SshHostActivity -HostName 'old' -TimeUtc $base -StorePath $p
            Add-SshHostActivity -HostName 'new' -TimeUtc $base.AddHours(5) -StorePath $p
            Add-SshHostActivity -HostName 'mid' -TimeUtc $base.AddHours(2) -StorePath $p
        } $store $base

        $all = @(& $script:mod { param($p) @(Get-SshHostActivity -All -StorePath $p) } $store)
        $all | Should -HaveCount 3
        $all.Host | Should -Be @('new', 'mid', 'old')
    }
}
