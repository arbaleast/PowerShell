# Get-SshHostDashboardRow.Tests.ps1 - SSH 主机仪表盘**行视图模型**的契约测试
#
# 覆盖 (2026-10-31 sss 仪表盘视图层):
#   1. Get-SshHostRelativeTime: '—' / '刚刚' / '5m' / '2h' / '3d' / '2w' 五种形态
#      (注入固定 -Now, 结果与当前时刻无关);
#   2. Get-SshHostStatusPresentation: Online/Offline/Unknown 三态文案 + 角色 + 状态点,
#      未知/脏状态一律退化为 Unknown(不猜"在线");
#   3. Get-SshHostDashboardRow: 排序(上次使用置顶 / 无分组排后面)、文本过滤
#      (名称 / HostName / 标签, 大小写不敏感)、活动历史(有记录取真实值, 无记录
#      **如实留空**, 绝不伪造)、分组缩进标记、状态缺省为 Unknown。
#
# 测试全部使用临时目录里的配置夹具与临时活动记录文件, 不读真实 ~/.ssh,
# 不依赖用户 HOME, 不触网, 每次运行结果确定。

Describe 'Get-SshHostRelativeTime: 相对时间文案' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'

        # 固定参照时间: 所有相对时间都由它推导, 与运行时刻无关
        $script:now = [datetime]'2026-10-31T12:00:00'
    }

    It '没有记录($null)返回 "—"(单列宽占位符)' {
        $result = & $script:mod { param($n) Get-SshHostRelativeTime -Time $null -Now $n } $script:now
        $result | Should -BeExactly ([string][char]0x2014)
    }

    It '未来时间(时钟回拨)返回 "刚刚", 不返回负数形态' {
        $result = & $script:mod {
            param($n) Get-SshHostRelativeTime -Time $n.AddMinutes(5) -Now $n
        } $script:now
        $result | Should -BeExactly '刚刚'
    }

    It '不足 1 分钟返回 "刚刚"' {
        $result = & $script:mod {
            param($n) Get-SshHostRelativeTime -Time $n.AddSeconds(-30) -Now $n
        } $script:now
        $result | Should -BeExactly '刚刚'
    }

    It '分钟级返回 "Nm"(向下取整)' {
        $result = & $script:mod {
            param($n) Get-SshHostRelativeTime -Time $n.AddMinutes(-5) -Now $n
        } $script:now
        $result | Should -BeExactly '5m'
    }

    It '小时级返回 "Nh"' {
        $result = & $script:mod {
            param($n) Get-SshHostRelativeTime -Time $n.AddHours(-2) -Now $n
        } $script:now
        $result | Should -BeExactly '2h'
    }

    It '天级返回 "Nd"' {
        $result = & $script:mod {
            param($n) Get-SshHostRelativeTime -Time $n.AddDays(-3) -Now $n
        } $script:now
        $result | Should -BeExactly '3d'
    }

    It '满 7 天返回 "Nw"(超过 4 周也不输出绝对时间)' {
        $result = & $script:mod {
            param($n) Get-SshHostRelativeTime -Time $n.AddDays(-14) -Now $n
        } $script:now
        $result | Should -BeExactly '2w'
    }
}

Describe 'Get-SshHostStatusPresentation: 状态展示三元组' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    It 'Online => 在线 / Online 角色 / 实心圆点' {
        $p = & $script:mod { Get-SshHostStatusPresentation -Status 'Online' }
        $p.Status | Should -BeExactly 'Online'
        $p.StatusText | Should -BeExactly '在线'
        $p.StatusRole | Should -BeExactly 'Online'
        $p.StatusGlyph | Should -BeExactly ([string][char]0x25CF)
    }

    It 'Offline => 离线 / Offline 角色 / 实心圆点' {
        $p = & $script:mod { Get-SshHostStatusPresentation -Status 'Offline' }
        $p.Status | Should -BeExactly 'Offline'
        $p.StatusText | Should -BeExactly '离线'
        $p.StatusRole | Should -BeExactly 'Offline'
        $p.StatusGlyph | Should -BeExactly ([string][char]0x25CF)
    }

    It 'Unknown => 未知 / Unknown 角色 / 实心圆点' {
        $p = & $script:mod { Get-SshHostStatusPresentation -Status 'Unknown' }
        $p.Status | Should -BeExactly 'Unknown'
        $p.StatusText | Should -BeExactly '未知'
        $p.StatusRole | Should -BeExactly 'Unknown'
        $p.StatusGlyph | Should -BeExactly ([string][char]0x25CF)
    }

    It '脏状态(空串/乱码)一律退化为 Unknown, 绝不猜成在线' {
        foreach ($bad in @('', '???', 'null', 'Offline-ish', '2')) {
            $p = & $script:mod { param($s) Get-SshHostStatusPresentation -Status $s } $bad
            $p.Status | Should -BeExactly 'Unknown' -Because "输入 '$bad' 不是合法状态"
            $p.StatusText | Should -BeExactly '未知'
            $p.StatusRole | Should -BeExactly 'Unknown'
        }
    }
}

Describe 'Get-SshHostDashboardRow: 排序 / 过滤 / 活动历史' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1') -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'

        # ---- 夹具: 临时 ssh config(带 @group/@tags 元数据注释) ----
        $script:fixtureDir = Join-Path $TestDrive 'dash-row'
        New-Item -ItemType Directory -Force -Path $script:fixtureDir | Out-Null
        $script:cfgPath = Join-Path $script:fixtureDir 'config'
        @(
            '# @group dev'
            'Host devbox'
            '    HostName dev.example.com'
            '    User ops'
            ''
            '# @group prod'
            '# @tags web,pub'
            'Host web1'
            '    HostName 10.0.0.11'
            '    Port 2222'
            ''
            '# @group prod'
            '# @tags db'
            'Host db1'
            '    HostName db1.example.com'
            ''
            'Host plain'
            '    HostName plain.example.com'
        ) | Set-Content -LiteralPath $script:cfgPath -Encoding UTF8

        $script:profiles = @(& $script:mod {
                param($p)
                @(Get-SshHostProfile -ConfigPath $p -NoCache)
            } $script:cfgPath)

        # ---- 夹具: 临时活动记录文件(只有 web1 有真实连接记录) ----
        $script:storePath = Join-Path $script:fixtureDir 'host-activity.json'
        $script:activeUtc = [datetime]::SpecifyKind([datetime]'2026-01-02T03:04:05', [System.DateTimeKind]::Utc)
        & $script:mod {
            param($s, $h, $t)
            Add-SshHostActivity -HostName $h -TimeUtc $t -StorePath $s
        } $script:storePath 'web1' $script:activeUtc

        $script:activity = @(& $script:mod {
                param($s)
                @(Get-SshHostActivity -All -StorePath $s)
            } $script:storePath)

        $script:rows = @(& $script:mod {
                param($p, $a)
                @(Get-SshHostDashboardRow -Profile $p -Activity $a)
            } $script:profiles $script:activity)
    }

    It '夹具本身可用: 4 台主机, 只有 web1 有活动记录' {
        $script:profiles | Should -HaveCount 4
        $script:activity | Should -HaveCount 1
        $script:activity[0].Host | Should -BeExactly 'web1'
    }

    It '排序: 有分组的主机在前(按分组名), 无分组的主机排最后' {
        $script:rows | ForEach-Object Name | Should -Be @('devbox', 'db1', 'web1', 'plain')
    }

    It '排序: LastHost 置顶(其余顺序不变)' {
        $rows = @(& $script:mod {
                param($p, $a, $l)
                @(Get-SshHostDashboardRow -Profile $p -Activity $a -LastHost $l)
            } $script:profiles $script:activity 'plain')
        $rows[0].Name | Should -BeExactly 'plain'
        $rows[0].IsLastHost | Should -BeTrue
        ($rows | Select-Object -Skip 1 | ForEach-Object Name) | Should -Be @('devbox', 'db1', 'web1')
    }

    It '过滤: 命中名称(大小写不敏感)' {
        $rows = @(& $script:mod {
                param($p, $a, $f)
                @(Get-SshHostDashboardRow -Profile $p -Activity $a -Filter $f)
            } $script:profiles $script:activity 'WEB')
        $rows | Should -HaveCount 1
        $rows[0].Name | Should -BeExactly 'web1'
    }

    It '过滤: 命中 HostName' {
        $rows = @(& $script:mod {
                param($p, $a, $f)
                @(Get-SshHostDashboardRow -Profile $p -Activity $a -Filter $f)
            } $script:profiles $script:activity 'example')
        $rows | ForEach-Object Name | Should -Be @('devbox', 'db1', 'plain')
    }

    It '过滤: 命中标签(Tags)' {
        $rows = @(& $script:mod {
                param($p, $a, $f)
                @(Get-SshHostDashboardRow -Profile $p -Activity $a -Filter $f)
            } $script:profiles $script:activity 'pub')
        $rows | Should -HaveCount 1
        $rows[0].Name | Should -BeExactly 'web1'
    }

    It '过滤: 无命中时返回空数组(不抛错)' {
        $rows = @(& $script:mod {
                param($p, $a, $f)
                @(Get-SshHostDashboardRow -Profile $p -Activity $a -Filter $f)
            } $script:profiles $script:activity 'no-such-host')
        $rows | Should -HaveCount 0
    }

    It '活动记录: 有记录的主机取真实 LastActive 与 ConnectCount' {
        $row = $script:rows | Where-Object Name -EQ 'web1'
        $row.HasActivity | Should -BeTrue
        $row.LastActive | Should -Not -BeNullOrEmpty
        $row.LastActive.ToUniversalTime() | Should -Be $script:activeUtc
        $row.ConnectCount | Should -Be 1
    }

    It '活动记录: 无记录的主机不伪造数据(HasActivity=false / LastActive 为空 / 文案 "—")' {
        $row = $script:rows | Where-Object Name -EQ 'plain'
        $row.HasActivity | Should -BeFalse
        $row.LastActive | Should -BeNullOrEmpty
        $row.LastActiveText | Should -BeExactly ([string][char]0x2014)
        $row.ConnectCount | Should -Be 0
    }

    It '分组: Indent 仅在 Group 非空时为真' {
        ($script:rows | Where-Object Name -EQ 'web1').Indent | Should -BeTrue
        ($script:rows | Where-Object Name -EQ 'devbox').Indent | Should -BeTrue
        ($script:rows | Where-Object Name -EQ 'plain').Indent | Should -BeFalse
    }

    It '状态: 缺省为 Unknown(没有远端探测结果就不猜在线)' {
        foreach ($row in $script:rows) {
            $row.Status | Should -BeExactly 'Unknown'
            $row.StatusText | Should -BeExactly '未知'
            $row.StatusRole | Should -BeExactly 'Unknown'
        }
    }

    It '行字段: 档案字段原样透传(端口/用户/标签)' {
        $row = $script:rows | Where-Object Name -EQ 'web1'
        $row.HostName | Should -BeExactly '10.0.0.11'
        $row.Port | Should -Be 2222
        $row.Group | Should -BeExactly 'prod'
        $row.Tags | Should -Be @('web', 'pub')
        $row.DisplayName | Should -BeExactly 'web1'
        $row.Value | Should -BeExactly 'web1'
    }

    It '空档案集合返回空数组, 不抛异常' {
        $rows = @(& $script:mod { @(Get-SshHostDashboardRow -Profile @()) })
        $rows | Should -HaveCount 0
    }
}
