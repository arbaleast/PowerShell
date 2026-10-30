# Invoke-SshCaptureOutput.Tests.ps1 - SSH 捕获执行层与参数转义契约测试
# 覆盖 (2026-10-29 SSH 可靠性审计):
#   1. ConvertTo-SshArgumentLine 共享转义函数的钉死用例 (重构前后逐字节一致的守护证据)
#   2. 远端命令在 Get-SshArgs 中保持单个数组元素, 生成的命令行不把远端命令拆成多个 argv
#   3. 非捕获路径交给 Start-Process 的是"单元素已转义命令行" (修复双引号被本地解析器吃掉)
#   4. 捕获路径: 退出码透传 (0 / 非 0 / 255)、stdout/stderr 分离、空输出、TimedOut=$false
#   5. 启动失败 (ssh.exe 无法启动): 抛出含 ssh.exe 的异常, 不返回对象;
#      Invoke-TmuxProbe 把该异常降级为 ExitCode=-1 (调用方不被阻断)
#   6. 超时: TimedOut=$true 且 ExitCode=-1 (不使用 Kill 后的信号退出码)
#
# 测试环境说明 (诚实声明):
#   - 4/6 需要真实子进程: 容器内由"测试自建的假 ssh.exe (POSIX sh 脚本)"提供, 完全不触网、
#     不碰真实主机; 该假实现只在 POSIX 平台可用, 且 Windows 上 System32 自带 ssh.exe 会让
#     "启动失败"用例失效, 故相关 Context 统一 -Skip:$IsWindows。
#   - 转义正确性只断言"本地生成的命令行字符串" (按 lead 钦定口径), 不依赖平台参数解析差异。
#   - 被 Skip 的用例 (Windows CI) 结论需 Windows 真机复核, 见交付报告。

Describe 'Invoke-SshCaptureOutput / SSH 参数转义与返回契约' {

    BeforeAll {
        # Pester v5/v6: 路径与模块引用必须放在 BeforeAll 内解析
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
        $repoRoot = Split-Path -Path $moduleRoot -Parent

        # 捕获路径调用辅助: 在模块作用域内构建参数并执行 (参数经 param 传入, 不依赖闭包)
        $script:InvokeCapture = {
            param([string]$RemoteCommand, [int]$ConnectTimeout = 5)
            & $script:mod {
                param($cmd, $ct)
                $a = Get-SshArgs -HostName 'fakehost' -RemoteCommand $cmd -CaptureOutput
                Invoke-SshCaptureOutput -ArgumentList $a -ConnectTimeout $ct -PassThru
            } $RemoteCommand $ConnectTimeout
        }

        # 假 ssh.exe: 与真 ssh 一致地把 destination 之后的 argv 用空格拼回远端命令, 交给 sh -c。
        # 仅 POSIX 需要; 放进 gitignored 的 .agent_cache (测试运行时生成, 不进仓库)。
        $script:fakeBin = Join-Path -Path $repoRoot -ChildPath '.agent_cache/pester-sshbin'
        if (-not $IsWindows) {
            New-Item -ItemType Directory -Force -Path $script:fakeBin | Out-Null
            $fakeSsh = Join-Path -Path $script:fakeBin -ChildPath 'ssh.exe'
            @'
#!/bin/sh
# 测试假 ssh.exe: destination 之后的参数按空格拼回远端命令后交给 sh -c, 退出码原样透传
dest=""
seen_dest=0
cmd=""
for a in "$@"; do
  if [ "$seen_dest" -eq 0 ]; then
    case "$a" in
      -o|-t|-tt) continue ;;
      ConnectTimeout=*|BatchMode=*|PreferredAuthentications=*|NumberOfPasswordPrompts=*) continue ;;
    esac
    dest="$a"
    seen_dest=1
    continue
  fi
  if [ -z "$cmd" ]; then cmd="$a"; else cmd="$cmd $a"; fi
done
if [ -n "$cmd" ]; then
  exec sh -c "$cmd"
fi
exit 0
'@ | Set-Content -Path $fakeSsh -NoNewline
            & chmod +x $fakeSsh
            $script:origPath = $env:PATH
        }
    }

    # ============================================================
    # 1. 共享转义函数: 输出钉死 (算法逐字节不变的守护证据)
    # ============================================================
    Context 'ConvertTo-SshArgumentLine 转义契约 (钉死用例)' {

        It '不含空白与双引号的元素原样保留' {
            & $script:mod { ConvertTo-SshArgumentLine -Argument @('simple', 'back\slash', 'trail\') } |
                Should -BeExactly 'simple back\slash trail\'
        }

        It '含空白的元素整体加引号, 远端命令不会被拆成多个 argv' {
            $line = & $script:mod { ConvertTo-SshArgumentLine -Argument @('echo hi there') }
            $line | Should -BeExactly '"echo hi there"'
        }

        It '元素内双引号转义为 \" (生成的命令行保留双引号证据)' {
            $line = & $script:mod { ConvertTo-SshArgumentLine -Argument @('quote"a') }
            $line | Should -BeExactly '"quote\"a"'
            # 双引号必须以 \" 形式出现在命令行里, 否则本地参数解析器会把它当分隔符吃掉
            $line | Should -Match ([regex]::Escape('\"'))
        }

        It 'kill-session 远端命令 (空格+双引号) 生成单个整体, 双引号被转义保住' {
            $line = & $script:mod { ConvertTo-SshArgumentLine -Argument @('tmux kill-session -t ''a"b c''') }
            # 期望内容: "tmux kill-session -t 'a\"b c'"
            $line | Should -BeExactly '"tmux kill-session -t ''a\"b c''"'
        }

        It '含空白时反斜杠翻倍 (既有算法, tmux 探测命令依赖)' {
            $line = & $script:mod { ConvertTo-SshArgumentLine -Argument @('a\ path') }
            $line | Should -BeExactly '"a\\ path"'
        }

        It 'tmux 探测命令的引号包裹输出钉死 (重构前后逐字节一致)' {
            $probe = 'printf "TMUX_VERSION=%s\n" "${TMUX_V:-}"'
            $line = & $script:mod { param($c) ConvertTo-SshArgumentLine -Argument @($c) } $probe
            $line | Should -BeExactly '"printf \"TMUX_VERSION=%s\\n\" \"${TMUX_V:-}\""'
        }

        It '混合特征输入的完整钉死用例' {
            $mixed = 'mixed "q" and \n and ''s'''
            $line = & $script:mod { param($c) ConvertTo-SshArgumentLine -Argument @($c) } $mixed
            $line | Should -BeExactly '"mixed \"q\" and \\n and ''s''"'
        }

        It '多参数用单个空格连接, 选项部分不加引号' {
            $line = & $script:mod { ConvertTo-SshArgumentLine -Argument @('-o', 'BatchMode=yes', 'host', 'tmux ls') }
            $line | Should -BeExactly '-o BatchMode=yes host "tmux ls"'
        }
    }

    # ============================================================
    # 2. Get-SshArgs: 远端命令保持单个数组元素 (退出码传播的前提)
    # ============================================================
    Context 'Get-SshArgs: 远端命令作为单个参数' {

        It '含空格/引号/反斜杠的远端命令整体作为一个数组元素, 不被拆分' {
            $cmd = 'tmux kill-session -t ''a"b c'''
            $a = & $script:mod { param($c) @(Get-SshArgs -HostName 'myhost' -RemoteCommand $c -CaptureOutput) } $cmd
            @($a | Where-Object { $_ -eq $cmd }).Count | Should -Be 1
            $a[-1] | Should -BeExactly $cmd
        }

        It '不提供远端命令时不附加远端命令参数 (仅选项+主机名)' {
            $a = & $script:mod { @(Get-SshArgs -HostName 'myhost' -CaptureOutput) }
            $a.Count | Should -BeGreaterThan 1
            # 最后一个元素必须是主机名, 其后没有任何远端命令片段
            $a[-1] | Should -BeExactly 'myhost'
        }
    }

    # ============================================================
    # 3. 非捕获路径: Start-Process 收到单元素已转义命令行
    #    (修复: 原裸数组拼接会把远端命令里的双引号吃掉 -> 打到别的会话)
    # ============================================================
    Context 'Invoke-SshCommand 非捕获路径的命令行形状' {

        BeforeEach {
            Mock -CommandName Save-OriginalTerminalState -ModuleName ShellPrompt -MockWith { }
            Mock -CommandName Reset-TerminalMode -ModuleName ShellPrompt -MockWith { }
            Mock -CommandName Start-Process -ModuleName ShellPrompt -MockWith {
                [PSCustomObject]@{ ExitCode = 0 }
            }
        }

        It '含双引号的 kill-session 命令以单个已转义元素传给 Start-Process' {
            $cmd = 'tmux kill-session -t ''a"b'''
            $r = & $script:mod { param($c) Invoke-SshCommand -HostName 'myhost' -RemoteCommand $c -PassThru } $cmd

            Should -Invoke -CommandName Start-Process -ModuleName ShellPrompt -Exactly 1 `
                -ParameterFilter {
                    # 期望整条命令行: -o ConnectTimeout=5 myhost "tmux kill-session -t 'a\"b'"
                    $ArgumentList.Count -eq 1 -and
                    $ArgumentList[0] -eq '-o ConnectTimeout=5 myhost "tmux kill-session -t ''a\"b''"'
                }
            # 返回对象形状: 非捕获路径无超时概念, TimedOut 恒为 false
            $r.TimedOut | Should -BeFalse
            $r.ExitCode | Should -Be 0
            $r.Output | Should -Be ''
            $r.Error | Should -Be ''
        }

        It '直连 SSH (无远端命令) 同样以单元素命令行传递' {
            $null = & $script:mod { Invoke-SshCommand -HostName 'myhost' -PassThru }

            Should -Invoke -CommandName Start-Process -ModuleName ShellPrompt -Exactly 1 `
                -ParameterFilter { $ArgumentList.Count -eq 1 -and $ArgumentList[0] -like '*myhost*' }
        }

        It 'PassThru 透传 Start-Process 的退出码' {
            Mock -CommandName Start-Process -ModuleName ShellPrompt -MockWith {
                [PSCustomObject]@{ ExitCode = 7 }
            }
            $r = & $script:mod { Invoke-SshCommand -HostName 'myhost' -PassThru }
            $r.ExitCode | Should -Be 7
        }
    }

    # ============================================================
    # 4/5/6. 捕获路径真实进程行为 (假 ssh, 仅 POSIX)
    # ============================================================
    Context '捕获路径真实子进程行为 (假 ssh, 仅 POSIX)' -Skip:$IsWindows {

        BeforeEach {
            $env:PATH = $script:fakeBin + [IO.Path]::PathSeparator + $script:origPath
        }

        AfterEach {
            $env:PATH = $script:origPath
        }

        It '远端退出码 0 透传, 且 TimedOut=$false' {
            $r = & $script:InvokeCapture 'echo OK-CAPTURE'
            $r.ExitCode | Should -Be 0
            $r.TimedOut | Should -BeFalse
            $r.Output | Should -Match 'OK-CAPTURE'
        }

        It '远端退出码非 0 (7) 原样透传' {
            $r = & $script:InvokeCapture 'exit 7'
            $r.ExitCode | Should -Be 7
            $r.TimedOut | Should -BeFalse
        }

        It '远端退出码 255 原样透传 (与 ssh 自身失败码 255 语义不可区分, 属 ssh 协议固有)' {
            $r = & $script:InvokeCapture 'exit 255'
            $r.ExitCode | Should -Be 255
        }

        It 'stdout 与 stderr 分离到 Output / Error 两个字段' {
            $savedErr = [Console]::Error
            try {
                # stderr 内容会被函数写入 [Console]::Error, 测试期间换成空写入器避免污染测试输出
                [Console]::SetError([System.IO.TextWriter]::Null)
                $r = & $script:InvokeCapture 'echo OUT-123; echo ERR-456 >&2'
            } finally {
                [Console]::SetError($savedErr)
            }
            $r.Output | Should -Match 'OUT-123'
            $r.Output | Should -Not -Match 'ERR-456'
            $r.Error | Should -Match 'ERR-456'
            $r.Error | Should -Not -Match 'OUT-123'
        }

        It '远端无输出时 Output 为空字符串, 不抛异常' {
            $r = & $script:InvokeCapture 'true'
            $r.Output | Should -Be ''
            $r.ExitCode | Should -Be 0
            $r.TimedOut | Should -BeFalse
        }

        It '不带 -PassThru 时仍返回纯输出字符串 (兼容旧调用方式)' {
            $out = & $script:mod {
                $a = Get-SshArgs -HostName 'fakehost' -RemoteCommand 'echo RAW-OUT' -CaptureOutput
                Invoke-SshCaptureOutput -ArgumentList $a -ConnectTimeout 5
            }
            $out | Should -Match 'RAW-OUT'
        }

        It 'ssh.exe 无法启动时抛出含 ssh.exe 的可定位异常, 不返回对象' {
            $emptyDir = Join-Path -Path $TestDrive -ChildPath 'emptybin'
            New-Item -ItemType Directory -Force -Path $emptyDir | Out-Null
            $savedPath = $env:PATH
            $env:PATH = $emptyDir
            try {
                { & $script:InvokeCapture 'echo hi' } |
                    Should -Throw -ExpectedMessage '*ssh.exe*'
            } finally {
                $env:PATH = $savedPath
            }
        }

        It 'Invoke-TmuxProbe 把启动失败异常降级为 ExitCode=-1 (调用方不被阻断)' {
            $emptyDir = Join-Path -Path $TestDrive -ChildPath 'emptybin2'
            New-Item -ItemType Directory -Force -Path $emptyDir | Out-Null
            $savedPath = $env:PATH
            $env:PATH = $emptyDir
            try {
                $r = & $script:mod { Invoke-TmuxProbe -HostName 'fakehost' -ConnectTimeout 5 }
            } finally {
                $env:PATH = $savedPath
            }
            $r.ExitCode | Should -Be -1
            $r.Error | Should -Match 'ssh.exe'
        }

        It '等待超时后 Kill ssh: TimedOut=$true 且 ExitCode=-1 (约 11 秒)' {
            # ConnectTimeout=1 -> waitMs=11000; 远端命令 sleep 30 必然超时
            $r = & $script:InvokeCapture 'sleep 30' 1
            $r.TimedOut | Should -BeTrue
            $r.ExitCode | Should -Be -1
        }
    }
}
