# Ssh-HostName-Validation.Tests.ps1 - SSH 目标地址白名单校验契约测试
#
# 覆盖 (2026-10-30 SSH 参数注入收口):
#   1. Test-SshHostName 由"否定式黑名单"改为"白名单", 且目标地址不得以 '-' 开头 ——
#      ssh 的 getopt 会把以 '-' 开头的目标地址解析成选项, 于是 -oProxyCommand=... 在**本机**执行命令。
#      (实测: ssh -oProxyCommand="touch /tmp/x" somehost 会在本机创建 /tmp/x)
#   2. -AllowUserPrefix: Copy-SshPublicKey 的 -RemoteHost 文档格式 [user@]hostname
#   3. Get-SshArgs 在参数构建阶段拒绝非法目标地址 (结构保证), 且命令行形状保持不变
#   4. Copy-SshPublicKey 的 -RemoteHost 复用同一校验 (参数绑定阶段即拒绝)
#   5. Get-SshConfigHosts 过滤 ~/.ssh/config 里的非法 Host 别名
#
# 测试环境说明:
#   - 全部为纯逻辑/参数绑定断言, 不触网、不调用真实 ssh、不触碰真实 ~/.ssh。

Describe 'SSH 目标地址白名单校验' {

    BeforeAll {
        # Pester v5/v6: 路径与模块引用必须放在 BeforeAll 内解析
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    Context 'Test-SshHostName: 合法目标地址放行' {

        It '普通域名/主机名/短横线/下划线/点 全部放行' {
            foreach ($h in @('example.com', 'my-server-01', 'host_1', 'my-server.lan', 'a', 'EXAMPLE.COM', '192.168.1.1')) {
                & $script:mod { param($n) Test-SshHostName -HostName $n } $h |
                    Should -BeTrue -Because "'$h' 是合法目标地址"
            }
        }
    }

    Context 'Test-SshHostName: 非法目标地址拒绝' {

        It '拒绝含空白与 shell 元字符的目标地址' {
            foreach ($h in @('bad host', 'host|danger', 'host;danger', 'host&danger', 'host$danger', 'host`danger')) {
                & $script:mod { param($n) Test-SshHostName -HostName $n } $h |
                    Should -BeFalse -Because "'$h' 含非法字符"
            }
        }

        It '拒绝以 - 开头的 ssh 选项形态 (注入载荷)' {
            foreach ($h in @('-oProxyCommand=calc', '-oProxyCommand=calc.exe', '-Fconfig', '-luser', '-')) {
                & $script:mod { param($n) Test-SshHostName -HostName $n } $h |
                    Should -BeFalse -Because "'$h' 会被 ssh 解析成选项"
            }
        }

        It '拒绝含 = : / 等非主机名字符的目标地址' {
            foreach ($h in @('host=1', 'host:22', '192.168.1.1/24', 'host name', 'host>out')) {
                & $script:mod { param($n) Test-SshHostName -HostName $n } $h |
                    Should -BeFalse -Because "'$h' 不是合法主机名"
            }
        }

        It '拒绝纯空白; 空串在参数绑定阶段即被拒绝' {
            & $script:mod { param($n) Test-SshHostName -HostName $n } ' ' |
                Should -BeFalse -Because '纯空白不是合法目标地址'
            # [Parameter(Mandatory)] + [string] 默认不接受空串 —— 空串在绑定阶段就被拒绝,
            # 走不到谓词内部; 三个调用点的参数同样不接受空串, 该路径不会被绕过。
            { & $script:mod { param($n) Test-SshHostName -HostName $n } '' } |
                Should -Throw -ExpectedMessage '*HostName*'
        }
    }

    Context 'Test-SshHostName: user@ 前缀 (仅 -AllowUserPrefix)' {

        It '带前缀开关时放行 [user@]hostname' {
            foreach ($h in @('user@example.com', 'root@192.168.1.1', 'example.com')) {
                & $script:mod { param($n) Test-SshHostName -HostName $n -AllowUserPrefix } $h |
                    Should -BeTrue -Because "'$h' 是合法 [user@]hostname"
            }
        }

        It '不带前缀开关时拒绝含 @ 的目标地址' {
            & $script:mod { Test-SshHostName -HostName 'user@example.com' } | Should -BeFalse
        }

        It '带前缀开关时仍拒绝非法 user 段与空主机段' {
            foreach ($h in @('-oProxyCommand=calc@example.com', '@example.com', 'user@', 'user@host@x')) {
                & $script:mod { param($n) Test-SshHostName -HostName $n -AllowUserPrefix } $h |
                    Should -BeFalse -Because "'$h' 的 user/host 段非法"
            }
        }
    }

    Context 'Get-SshArgs: 目标地址白名单守卫' {

        It '非法主机名在参数构建阶段即抛错 (结构保证)' {
            foreach ($h in @('-oProxyCommand=calc', '-Fconfig', 'host=1', 'bad host')) {
                { & $script:mod { param($n) Get-SshArgs -HostName $n } $h } |
                    Should -Throw -ExpectedMessage '*非法的主机名*'
            }
        }

        It '合法主机名正常构建参数, 目标地址是最后一个元素' {
            $a = & $script:mod { @(Get-SshArgs -HostName 'myhost' -CaptureOutput) }
            $a[-1] | Should -BeExactly 'myhost'
        }

        It '远端命令仍排在目标地址之后, 且不被拆分' {
            $cmd = 'tmux ls'
            $a = & $script:mod { param($c) @(Get-SshArgs -HostName 'myhost' -RemoteCommand $c -CaptureOutput) } $cmd
            $a[-2] | Should -BeExactly 'myhost'
            $a[-1] | Should -BeExactly $cmd
        }

        It '命令行形状保持不变: 选项在前、目标地址在后 (未插入 "--")' {
            # 参数数组直接交给 [array] 参数 (由参数绑定展开), 不套 @() ——
            # Get-SshArgs 用 Write-Output -NoEnumerate 输出, 外面再套 @() 会把 ArrayList
            # 整体当成一个元素, 渲染结果失真。
            $line = & $script:mod { ConvertTo-SshArgumentLine -Argument (Get-SshArgs -HostName 'myhost' -CaptureOutput) }
            $line | Should -Not -Match '(^|\s)--(\s|$)'
            $line | Should -Match ' myhost$'
        }
    }

    Context 'Copy-SshPublicKey: -RemoteHost 复用同一校验' {

        BeforeAll {
            # 让公钥探测走确定性分支 (临时 USERPROFILE 下无 .ssh), 不触碰真实 ~/.ssh
            $script:origUserProfile = $env:USERPROFILE
            $env:USERPROFILE = Join-Path ([System.IO.Path]::GetTempPath()) 'sp-copypubkey-test'
        }

        AfterAll {
            $env:USERPROFILE = $script:origUserProfile
        }

        It '拒绝以 - 开头的选项形态目标地址' {
            { Copy-SshPublicKey -RemoteHost '-oProxyCommand=calc' } |
                Should -Throw -ExpectedMessage '*非法字符*'
        }

        It '放行文档格式 [user@]hostname (不因校验而失败)' {
            $err = $null
            Copy-SshPublicKey -RemoteHost 'user@example.com' -ErrorAction SilentlyContinue -ErrorVariable err
            ($err | Out-String) | Should -Not -Match '非法字符'
        }
    }

    Context 'Get-SshConfigHosts: 过滤非法 Host 别名' {

        BeforeAll {
            $script:fakeHome = Join-Path ([System.IO.Path]::GetTempPath()) ("sp-hosttest-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path $script:fakeHome | Out-Null
            # 与实现同构的路径表达式 (Join-Path $HOME ".ssh\config"), 跨平台均可
            $script:cfgPath = Join-Path $script:fakeHome '.ssh\config'
            $cfgParent = Split-Path -Path $script:cfgPath -Parent
            New-Item -ItemType Directory -Force -Path $cfgParent | Out-Null
            @(
                'Host good-alias'
                'Host -oProxyCommand=calc'
                'Host another.good'
            ) | Set-Content -LiteralPath $script:cfgPath -Encoding UTF8
        }

        AfterAll {
            Remove-Item -LiteralPath $script:fakeHome -Recurse -Force -ErrorAction SilentlyContinue
        }

        It '只保留合法别名, 过滤以 - 开头的选项形态别名' {
            $hosts = & $script:mod {
                param($h)
                $origHome = $HOME
                try {
                    # 用 Set-Variable 覆盖模块作用域的 $HOME (直接赋值 $HOME 会被 PSSA 判为
                    # PSAvoidAssignmentToAutomaticVariable); 全局 $HOME 不受影响。
                    Set-Variable -Name HOME -Value $h -Scope Script
                    $script:SshHostsCache = $null
                    $script:SshHostsCacheMtime = [DateTime]::MinValue
                    Get-SshConfigHosts
                } finally {
                    Set-Variable -Name HOME -Value $origHome -Scope Script
                    $script:SshHostsCache = $null
                    $script:SshHostsCacheMtime = [DateTime]::MinValue
                }
            } $script:fakeHome
            $hosts | Should -Contain 'good-alias'
            $hosts | Should -Contain 'another.good'
            $hosts | Should -Not -Contain '-oProxyCommand=calc'
        }
    }
}
