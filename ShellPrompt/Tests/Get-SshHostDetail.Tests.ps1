# Get-SshHostDetail.Tests.ps1 - 远端主机详情服务契约测试
# 覆盖 (2026-10-31 sss 仪表盘重构 · 远端详情服务):
#   1. 标记行输出解析: HOSTNAME / UPTIME / LOAD / TMUX 各自命中与缺失;
#   2. TmuxSessionCount 的 $null vs 0 语义 (unknown ≠ 0 —— 不允许伪造"没有会话");
#   3. 错误码映射: 超时 / 认证 / 网络 / 远端非 0 退出 / 探测无法执行;
#   4. -ProbeScript 注入路径: 完全不触网地覆盖解析与错误码, 并断言 -p/-l 插在
#      destination 之前(ssh 只接受前置选项);
#   5. 非法主机名 / 非法用户名抛终止错误 (与"探测失败"区分);
#   6. 返回字段形状: ElapsedMs / CheckedAt / StatusText / ErrorMessage 归一;
#   7. Start/Receive-SshHostDetailTask: 非阻塞收割(未完成 $null)、完成归一、
#      失败归一、消费即清理作业。
#
# 测试环境说明 (诚实声明):
#   - 全部用例**不触网**: 真实 SSH 路径由 -ProbeScript 注入点替代; 后台任务用例
#     把同一个注入脚本块透传进作业, 作业里也不执行 ssh。
#   - 因此本文件可在无 ssh.exe 的容器与 CI 上稳定运行; 真实网络行为需真机验证。

Describe 'Get-SshHostDetail / 远端详情探测契约' {

    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'

        # 统一在模块作用域内调用: 探针脚本块经 param 传入, 不依赖闭包捕获
        $script:InvokeDetail = {
            param($Probe, [string]$HostName, [int]$Port = 0, [string]$User = '', [int]$TimeoutSec = 6)
            & $script:mod {
                param($p, $h, $po, $u, $t)
                Get-SshHostDetail -HostName $h -Port $po -User $u -TimeoutSec $t -ProbeScript $p
            } $Probe $HostName $Port $User $TimeoutSec
        }

    }

    # ============================================================
    # 1/2. 标记行解析与 TmuxSessionCount 语义
    # ============================================================
    Context '标记行解析' {

        It '完整标记行: 主机名 / uptime / 负载 / tmux 会话数全部解析' {
            $probe = {
                [PSCustomObject]@{
                    Output   = "HOSTNAME=deb-box`nUPTIME=up 3 days, 2 hours`nLOAD=0.12 0.34 0.56`nTMUX=3`n"
                    Error    = ''
                    ExitCode = 0
                    TimedOut = $false
                }
            }
            $r = & $script:InvokeDetail $probe 'deb'
            $r.Status | Should -Be 'Online'
            $r.StatusText | Should -Be '在线'
            $r.ErrorCode | Should -Be ''
            $r.RemoteHostname | Should -BeExactly 'deb-box'
            $r.Uptime | Should -BeExactly 'up 3 days, 2 hours'
            $r.Load | Should -BeExactly '0.12 0.34 0.56'
            $r.TmuxSessionCount | Should -Be 3
            $r.Host | Should -BeExactly 'deb'
        }

        It 'TMUX=unknown (远端没有 tmux) ⇒ TmuxSessionCount 为 $null, 不填 0' {
            $probe = {
                [PSCustomObject]@{
                    Output   = "HOSTNAME=deb`nUPTIME=up 1 hour`nLOAD=0.00 0.01 0.05`nTMUX=unknown`n"
                    Error    = ''
                    ExitCode = 0
                    TimedOut = $false
                }
            }
            $r = & $script:InvokeDetail $probe 'deb'
            $null -eq $r.TmuxSessionCount | Should -BeTrue
        }

        It 'TMUX=0 (远端有 tmux 且确实 0 个会话) ⇒ 0, 与 unknown 严格区分' {
            $probe = {
                [PSCustomObject]@{ Output = "TMUX=      0`n"; Error = ''; ExitCode = 0; TimedOut = $false }
            }
            $r = & $script:InvokeDetail $probe 'deb'
            $null -ne $r.TmuxSessionCount | Should -BeTrue
            $r.TmuxSessionCount | Should -Be 0
        }

        It '空输出 + 退出码 0: 连接成功但拿不到字段 ⇒ 全部空值, 不编造内容' {
            $probe = {
                [PSCustomObject]@{ Output = ''; Error = ''; ExitCode = 0; TimedOut = $false }
            }
            $r = & $script:InvokeDetail $probe 'deb'
            $r.Status | Should -Be 'Online'
            $r.RemoteHostname | Should -BeExactly ''
            $r.Uptime | Should -BeExactly ''
            $r.Load | Should -BeExactly ''
            $null -eq $r.TmuxSessionCount | Should -BeTrue
        }

        It '标记行之外的杂输出不会污染字段 (只认行首标记)' {
            $probe = {
                [PSCustomObject]@{
                    Output   = "Welcome to deb`nHOSTNAME=deb`nsome UPTIME=noise`nLOAD=1.00 2.00 3.00`n"
                    Error    = ''
                    ExitCode = 0
                    TimedOut = $false
                }
            }
            $r = & $script:InvokeDetail $probe 'deb'
            $r.RemoteHostname | Should -BeExactly 'deb'
            $r.Uptime | Should -BeExactly ''
            $r.Load | Should -BeExactly '1.00 2.00 3.00'
        }
    }

    # ============================================================
    # 3. 错误码映射
    # ============================================================
    Context '错误码映射' {

        It '等待超时 ⇒ Offline / E_SSH_TIMEOUT' {
            $probe = {
                [PSCustomObject]@{ Output = ''; Error = ''; ExitCode = -1; TimedOut = $true }
            }
            $r = & $script:InvokeDetail $probe 'deb' 0 '' 3
            $r.Status | Should -Be 'Offline'
            $r.StatusText | Should -Be '离线'
            $r.ErrorCode | Should -Be 'E_SSH_TIMEOUT'
            $r.ErrorMessage | Should -Match '超时'
        }

        It '认证失败 (Permission denied) ⇒ E_SSH_AUTH' {
            $probe = {
                [PSCustomObject]@{ Output = ''; Error = 'user@deb: Permission denied (publickey).'; ExitCode = 255; TimedOut = $false }
            }
            $r = & $script:InvokeDetail $probe 'deb'
            $r.Status | Should -Be 'Offline'
            $r.ErrorCode | Should -Be 'E_SSH_AUTH'
        }

        It '主机密钥校验失败 ⇒ E_SSH_AUTH' {
            $probe = {
                [PSCustomObject]@{ Output = ''; Error = 'Host key verification failed.'; ExitCode = 255; TimedOut = $false }
            }
            $r = & $script:InvokeDetail $probe 'deb'
            $r.ErrorCode | Should -Be 'E_SSH_AUTH'
        }

        It '网络不可达 (Connection refused) ⇒ E_SSH_UNREACHABLE' {
            $probe = {
                [PSCustomObject]@{ Output = ''; Error = 'ssh: connect to host deb port 22: Connection refused'; ExitCode = 255; TimedOut = $false }
            }
            $r = & $script:InvokeDetail $probe 'deb'
            $r.ErrorCode | Should -Be 'E_SSH_UNREACHABLE'
        }

        It 'DNS 解析失败 ⇒ E_SSH_UNREACHABLE' {
            $probe = {
                [PSCustomObject]@{ Output = ''; Error = 'ssh: Could not resolve hostname deb: Name or service not known'; ExitCode = 255; TimedOut = $false }
            }
            $r = & $script:InvokeDetail $probe 'deb'
            $r.ErrorCode | Should -Be 'E_SSH_UNREACHABLE'
        }

        It '远端命令非 0 退出且无特征关键字 ⇒ E_SSH_FAILED' {
            $probe = {
                [PSCustomObject]@{ Output = ''; Error = 'sh: line 1: something: not found'; ExitCode = 127; TimedOut = $false }
            }
            $r = & $script:InvokeDetail $probe 'deb'
            $r.Status | Should -Be 'Offline'
            $r.ErrorCode | Should -Be 'E_SSH_FAILED'
        }

        It '探测无法执行 (注入脚本抛错 / ssh.exe 缺失) ⇒ Unknown / E_UNKNOWN, 不伪装成离线' {
            $probe = { throw '启动 ssh.exe 失败 (进程未能创建)' }
            $r = & $script:InvokeDetail $probe 'deb'
            $r.Status | Should -Be 'Unknown'
            $r.StatusText | Should -Be '未知'
            $r.ErrorCode | Should -Be 'E_UNKNOWN'
            $r.ErrorMessage | Should -Match '启动 ssh.exe'
        }

        It 'ErrorMessage 折叠换行并截断到 200 字符 (单行展示位不撕布局)' {
            # 探针经 $script: 取长文本(与参数构造用例同一机制, 不依赖闭包捕获)
            $script:longError = ('x' * 300) + "`nsecond line"
            $probe = {
                [PSCustomObject]@{ Output = ''; Error = $script:longError; ExitCode = 1; TimedOut = $false }
            }
            $r = & $script:InvokeDetail $probe 'deb'
            $r.Status | Should -Be 'Offline'
            $r.ErrorMessage.Length | Should -BeLessOrEqual 200
            $r.ErrorMessage | Should -Not -Match "`n"
        }
    }

    # ============================================================
    # 4. 参数透传: -p / -l 必须在 destination 之前
    # ============================================================
    Context 'SSH 参数构造' {

        It '未指定 Port/User 时不插入 -p/-l (沿用 ssh config 语义)' {
            $script:capturedArgs = $null
            $probe = {
                $script:capturedArgs = @($args[0].ArgumentList)
                [PSCustomObject]@{ Output = 'HOSTNAME=x'; Error = ''; ExitCode = 0; TimedOut = $false }
            }
            $null = & $script:InvokeDetail $probe 'deb'
            $script:capturedArgs | Should -Not -Contain '-p'
            $script:capturedArgs | Should -Not -Contain '-l'
        }

        It '指定 Port/User 时 -p/-l 插在 destination(主机名) 之前' {
            $script:capturedArgs = $null
            $probe = {
                $script:capturedArgs = @($args[0].ArgumentList)
                [PSCustomObject]@{ Output = 'HOSTNAME=x'; Error = ''; ExitCode = 0; TimedOut = $false }
            }
            $null = & $script:InvokeDetail $probe 'deb' 2222 'ops'
            $args0 = @($script:capturedArgs)
            $destIndex = [Array]::IndexOf($args0, 'deb')
            $destIndex | Should -BeGreaterThan 0
            $pIndex = [Array]::IndexOf($args0, '-p')
            $lIndex = [Array]::IndexOf($args0, '-l')
            $pIndex | Should -BeGreaterThan 0
            $lIndex | Should -BeGreaterThan 0
            $pIndex | Should -BeLessThan $destIndex
            $lIndex | Should -BeLessThan $destIndex
            $args0[$pIndex + 1] | Should -BeExactly '2222'
            $args0[$lIndex + 1] | Should -BeExactly 'ops'
        }
    }

    # ============================================================
    # 5. 入参护栏
    # ============================================================
    Context '入参护栏' {

        It '非法主机名 (选项注入形态) 抛终止错误' {
            { & $script:InvokeDetail { $null } '-oProxyCommand=calc' } |
                Should -Throw -ExpectedMessage '*非法主机名*'
        }

        It '非法用户名 (以 - 开头) 抛终止错误' {
            { & $script:InvokeDetail { $null } 'deb' 0 '-oProxyCommand=calc' } |
                Should -Throw -ExpectedMessage '*非法用户名*'
        }
    }

    # ============================================================
    # 6. 返回字段形状
    # ============================================================
    Context '返回字段形状' {

        It '成功结果包含 ElapsedMs / CheckedAt 且类型正确' {
            $probe = {
                [PSCustomObject]@{ Output = "HOSTNAME=deb`nTMUX=1"; Error = ''; ExitCode = 0; TimedOut = $false }
            }
            $r = & $script:InvokeDetail $probe 'deb'
            $r.ElapsedMs | Should -BeOfType [int]
            $r.ElapsedMs | Should -BeGreaterOrEqual 0
            $r.CheckedAt | Should -BeOfType [datetime]
            # 契约字段一个都不能少(UI 层按固定字段名取值)
            foreach ($name in @('Host', 'Status', 'StatusText', 'ErrorCode', 'ErrorMessage',
                    'RemoteHostname', 'Uptime', 'Load', 'TmuxSessionCount', 'ElapsedMs', 'CheckedAt')) {
                $null -ne $r.PSObject.Properties[$name] | Should -BeTrue -Because "缺少契约字段 $name"
            }
        }
    }

    # ============================================================
    # 7. 后台任务: 提交 / 非阻塞收割
    # ============================================================
    Context 'Start/Receive-SshHostDetailTask' {

        It '提交返回句柄且回填 RequestId / HostName / StartedAt' {
            $job = & $script:mod {
                Start-SshHostDetailTask -HostName 'deb' -RequestId 'deb#1' -ProbeScript {
                    [PSCustomObject]@{ Output = 'HOSTNAME=deb'; Error = ''; ExitCode = 0; TimedOut = $false }
                }
            }
            try {
                $null -ne $job.Task | Should -BeTrue
                $job.RequestId | Should -BeExactly 'deb#1'
                $job.HostName | Should -BeExactly 'deb'
                $job.StartedAt | Should -BeOfType [datetime]
            }
            finally {
                & $script:mod { param($j) if ($j) { Stop-Job -Job $j -ErrorAction SilentlyContinue; Remove-Job -Job $j -Force -ErrorAction SilentlyContinue } } $job.Task
            }
        }

        It '作业完成 ⇒ Receive 返回与 Get-SshHostDetail 同形状的详情 (不触网)' {
            $job = & $script:mod {
                Start-SshHostDetailTask -HostName 'deb' -RequestId 'deb#2' -ProbeScript {
                    [PSCustomObject]@{
                        Output   = "HOSTNAME=deb-remote`nUPTIME=up 2 days`nLOAD=0.10 0.20 0.30`nTMUX=2`n"
                        Error    = ''
                        ExitCode = 0
                        TimedOut = $false
                    }
                }
            }
            try {
                # 非阻塞: 最多等 20 秒让作业自然完成(仅测试等待, 生产路径不这么做)
                $detail = $null
                for ($i = 0; $i -lt 40 -and $null -eq $detail; $i++) {
                    $detail = & $script:mod { param($j) Receive-SshHostDetailTask -Task $j } $job
                    if ($null -eq $detail) { Start-Sleep -Milliseconds 250 }
                }
                $null -ne $detail | Should -BeTrue
                $detail.Status | Should -Be 'Online'
                $detail.RemoteHostname | Should -BeExactly 'deb-remote'
                $detail.TmuxSessionCount | Should -Be 2
                $detail.Host | Should -BeExactly 'deb'
            }
            finally {
                & $script:mod { param($j) if ($j) { Stop-Job -Job $j -ErrorAction SilentlyContinue; Remove-Job -Job $j -Force -ErrorAction SilentlyContinue } } $job.Task
            }
        }

        It '作业未完成 ⇒ Receive 立即返回 $null (非阻塞, 不 Wait)' {
            $job = & $script:mod {
                Start-SshHostDetailTask -HostName 'deb' -RequestId 'deb#3' -ProbeScript {
                    Start-Sleep -Seconds 5
                    [PSCustomObject]@{ Output = 'HOSTNAME=deb'; Error = ''; ExitCode = 0; TimedOut = $false }
                }
            }
            try {
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                $detail = & $script:mod { param($j) Receive-SshHostDetailTask -Task $j } $job
                $sw.Stop()
                $null -eq $detail | Should -BeTrue
                # 非阻塞判据: 远小于作业自身的 5 秒
                $sw.ElapsedMilliseconds | Should -BeLessThan 2000
            }
            finally {
                & $script:mod { param($j) if ($j) { Stop-Job -Job $j -ErrorAction SilentlyContinue; Remove-Job -Job $j -Force -ErrorAction SilentlyContinue } } $job.Task
            }
        }

        It '作业失败 ⇒ Receive 归一成 Unknown / E_UNKNOWN, 不抛异常' {
            $job = & $script:mod {
                Start-SshHostDetailTask -HostName 'deb' -RequestId 'deb#4' -ProbeScript {
                    throw 'probe-exploded'
                }
            }
            try {
                $detail = $null
                for ($i = 0; $i -lt 40 -and $null -eq $detail; $i++) {
                    $detail = & $script:mod { param($j) Receive-SshHostDetailTask -Task $j } $job
                    if ($null -eq $detail) { Start-Sleep -Milliseconds 250 }
                }
                $null -ne $detail | Should -BeTrue
                $detail.Status | Should -Be 'Unknown'
                $detail.ErrorCode | Should -Be 'E_UNKNOWN'
                $detail.ErrorMessage | Should -Not -BeExactly ''
            }
            finally {
                & $script:mod { param($j) if ($j) { Stop-Job -Job $j -ErrorAction SilentlyContinue; Remove-Job -Job $j -Force -ErrorAction SilentlyContinue } } $job.Task
            }
        }

        It 'Task 为 $null ⇒ 返回 $null' {
            $r = & $script:mod { Receive-SshHostDetailTask -Task $null }
            $null -eq $r | Should -BeTrue
        }
    }

    # ============================================================
    # 8. 真实 SSH 执行路径 (假 ssh.exe, 仅 POSIX)
    #    与 Invoke-SshCaptureOutput.Tests.ps1 同一套路: 容器内用 POSIX sh 脚本假冒
    #    ssh.exe, 完全不触网 —— 但走的是**真实**的参数构造/转义/子进程/输出解析链路。
    # ============================================================
    Context '真实 SSH 执行路径 (假 ssh, 仅 POSIX)' -Skip:$IsWindows {

        BeforeAll {
            $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
            $script:fakeSshDir = Join-Path -Path $repoRoot -ChildPath '.agent_cache/pester-sshbin-detail'
            New-Item -ItemType Directory -Force -Path $script:fakeSshDir | Out-Null
            $fakeSsh = Join-Path -Path $script:fakeSshDir -ChildPath 'ssh.exe'
            @'
#!/bin/sh
# 测试假 ssh.exe: destination 之后的参数按空格拼回远端命令交给 sh -c, 退出码原样透传。
# FAKE_SSH_EXIT / FAKE_SSH_ERR 用于注入失败场景。
dest=""; seen_dest=0; cmd=""
for a in "$@"; do
  if [ "$seen_dest" -eq 0 ]; then
    case "$a" in
      -o|-t|-tt|-p|-l) continue ;;
      ConnectTimeout=*|BatchMode=*|PreferredAuthentications=*|NumberOfPasswordPrompts=*|StrictHostKeyChecking=*|UserKnownHostsFile=*) continue ;;
    esac
    dest="$a"; seen_dest=1; continue
  fi
  if [ -z "$cmd" ]; then cmd="$a"; else cmd="$cmd $a"; fi
done
if [ -n "$FAKE_SSH_ERR" ]; then printf '%s\n' "$FAKE_SSH_ERR" >&2; fi
if [ -n "$cmd" ]; then sh -c "$cmd"; fi
if [ -n "$FAKE_SSH_EXIT" ]; then exit "$FAKE_SSH_EXIT"; fi
exit 0
'@ | Set-Content -Path $fakeSsh -NoNewline
            & chmod +x $fakeSsh
            $script:origPathDetail = $env:PATH
        }

        BeforeEach {
            $env:PATH = $script:fakeSshDir + [IO.Path]::PathSeparator + $script:origPathDetail
            $env:FAKE_SSH_EXIT = ''
            $env:FAKE_SSH_ERR = ''
        }

        AfterEach {
            $env:PATH = $script:origPathDetail
            Remove-Item Env:FAKE_SSH_EXIT -ErrorAction SilentlyContinue
            Remove-Item Env:FAKE_SSH_ERR -ErrorAction SilentlyContinue
        }

        It '真实链路: 标记行命令在远端 shell 上执行并解析回 Online' {
            $r = & $script:mod { Get-SshHostDetail -HostName 'fakehost' -TimeoutSec 5 }
            $r.Status | Should -Be 'Online'
            $r.ErrorCode | Should -Be ''
            # hostname / /proc/loadavg 在 POSIX 测试机上必然存在
            $r.RemoteHostname | Should -Not -BeExactly ''
            $r.ElapsedMs | Should -BeGreaterOrEqual 0
        }

        It '真实链路: 远端认证失败经 stderr 映射到 E_SSH_AUTH' {
            $env:FAKE_SSH_EXIT = '255'
            $env:FAKE_SSH_ERR = 'fakehost: Permission denied (publickey).'
            # stderr 会被 Invoke-SshCaptureOutput 转发到 [Console]::Error, 测试期间换成空写入器
            $savedErr = [Console]::Error
            try {
                [Console]::SetError([System.IO.TextWriter]::Null)
                $r = & $script:mod { Get-SshHostDetail -HostName 'fakehost' -TimeoutSec 5 }
            } finally {
                [Console]::SetError($savedErr)
            }
            $r.Status | Should -Be 'Offline'
            $r.ErrorCode | Should -Be 'E_SSH_AUTH'
        }
    }
}
