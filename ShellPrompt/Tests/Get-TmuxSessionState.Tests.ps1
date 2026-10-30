# Get-TmuxSessionState.Tests.ps1 - tmux 探测结果状态化归一契约回归测试
# 覆盖:
#   1. Get-TmuxErrorCode: 探测结果 -> 稳定错误码的判定顺序
#      (超时 / 网络不可达 / 认证失败 / SSH 失败 / 未安装 tmux / 未知)
#   2. Get-TmuxSessionState: Status / Context / Sessions / ErrorCode / ErrorMessage / Hint / Version
#      - "查询成功但确实没有会话"(Empty)与"查询失败"(Error)严格区分
#      - -Sessions 参数优先于 SessionData.Sessions(行序重排场景)
#      - SessionData=$null 的兜底行为
# 说明: 全部为纯函数, 不触碰真实 ssh / tmux / 控制台。

Describe 'tmux 探测结果状态化归一契约' {

    BeforeAll {
        # Pester v6: 路径与模块引用必须放在 BeforeAll 内解析
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ShellPrompt.psd1'
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
        $script:mod = Get-Module -Name 'ShellPrompt'
    }

    Context 'Get-TmuxErrorCode: 探测结果 -> 稳定错误码' {

        It '探测成功(Available=$true)时错误码为空串' {
            $code = & $script:mod {
                Get-TmuxErrorCode -SessionData @{ Available = $true; Sessions = @(); Error = ''; ExitCode = 0 }
            }

            $code | Should -BeExactly ''
        }

        It 'SSH 超时(TimedOut=$true)判定为 E_SSH_TIMEOUT' {
            $code = & $script:mod {
                Get-TmuxErrorCode -SessionData @{
                    Available = $false; TimedOut = $true; NetworkError = $false
                    Error = 'ssh timed out'; ExitCode = 255
                }
            }

            $code | Should -BeExactly 'E_SSH_TIMEOUT'
        }

        It '网络不可达(NetworkError=$true)判定为 E_SSH_UNREACHABLE' {
            $code = & $script:mod {
                Get-TmuxErrorCode -SessionData @{
                    Available = $false; TimedOut = $false; NetworkError = $true
                    Error = 'ssh: connect to host h port 22: Connection refused'; ExitCode = 255
                }
            }

            $code | Should -BeExactly 'E_SSH_UNREACHABLE'
        }

        It '公钥认证失败判定为 E_SSH_AUTH' {
            $code = & $script:mod {
                Get-TmuxErrorCode -SessionData @{
                    Available = $false; TimedOut = $false; NetworkError = $false
                    Error = 'user@host: Permission denied (publickey).'; ExitCode = 255
                }
            }

            $code | Should -BeExactly 'E_SSH_AUTH'
        }

        It '主机密钥校验失败判定为 E_SSH_AUTH' {
            $code = & $script:mod {
                Get-TmuxErrorCode -SessionData @{
                    Available = $false; TimedOut = $false; NetworkError = $false
                    Error = 'Host key verification failed.'; ExitCode = 255
                }
            }

            $code | Should -BeExactly 'E_SSH_AUTH'
        }

        It '退出码非 0 且无特征错误时判定为 E_SSH_FAILED' {
            $code = & $script:mod {
                Get-TmuxErrorCode -SessionData @{
                    Available = $false; TimedOut = $false; NetworkError = $false
                    Error = ''; ExitCode = 255
                }
            }

            $code | Should -BeExactly 'E_SSH_FAILED'
        }

        It '命令跑通(退出码 0)但拿不到 tmux 时判定为 E_NO_TMUX' {
            $code = & $script:mod {
                Get-TmuxErrorCode -SessionData @{
                    Available = $false; TimedOut = $false; NetworkError = $false
                    Error = ''; ExitCode = 0
                }
            }

            $code | Should -BeExactly 'E_NO_TMUX'
        }

        It 'SessionData 为 $null 时兜底为 E_UNKNOWN' {
            $code = & $script:mod { Get-TmuxErrorCode -SessionData $null }

            $code | Should -BeExactly 'E_UNKNOWN'
        }
    }

    Context 'Get-TmuxSessionState: 有会话 (Status = Ok)' {

        It 'Available=$true 且存在 2 个会话时状态为 Ok 且上下文为 Normal' {
            $sessions = @(
                [PSCustomObject]@{ Name = 'alpha'; Status = 'attached' }
                [PSCustomObject]@{ Name = 'beta'; Status = 'detached' }
            )
            $data = @{ Available = $true; Sessions = $sessions; Version = '3.4' }

            $state = & $script:mod { param($d) Get-TmuxSessionState -SessionData $d } $data

            $state.Status | Should -BeExactly 'Ok'
            $state.Context | Should -BeExactly 'Normal'
            $state.ErrorCode | Should -BeExactly ''
            $state.Version | Should -BeExactly '3.4'
        }

        It 'Available=$true 且存在 2 个会话时会话数组原样透传(Count = 2)' {
            $sessions = @(
                [PSCustomObject]@{ Name = 'alpha'; Status = 'attached' }
                [PSCustomObject]@{ Name = 'beta'; Status = 'detached' }
            )
            $data = @{ Available = $true; Sessions = $sessions; Version = '3.4' }

            $state = & $script:mod { param($d) Get-TmuxSessionState -SessionData $d } $data

            $state.Sessions.Count | Should -Be 2
        }
    }

    Context 'Get-TmuxSessionState: 查询成功但没有会话 (Status = Empty)' {

        It 'Available=$true 且 0 个会话时状态为 Empty 且无错误码' {
            $data = @{ Available = $true; Sessions = @(); Version = '3.4' }

            $state = & $script:mod { param($d) Get-TmuxSessionState -SessionData $d } $data

            $state.Status | Should -BeExactly 'Empty'
            $state.Context | Should -BeExactly 'Normal'
            $state.ErrorCode | Should -BeExactly ''
        }

        It '空会话态的降级指引非空(提示新建/刷新/直连)' {
            $data = @{ Available = $true; Sessions = @(); Version = '3.4' }

            $state = & $script:mod { param($d) Get-TmuxSessionState -SessionData $d } $data

            $state.Hint | Should -Not -BeNullOrEmpty
            $state.Hint | Should -Match '按 n 新建会话'
            $state.Hint | Should -Match '按 r 刷新'
        }
    }

    Context 'Get-TmuxSessionState: 查询失败 (Status = Error)' {

        It 'Available=$false 时状态为 Error 且错误码与说明均非空' {
            $data = @{
                Available = $false; TimedOut = $true; NetworkError = $false
                Error = 'ssh timed out'; ExitCode = 255
            }

            $state = & $script:mod { param($d) Get-TmuxSessionState -SessionData $d } $data

            $state.Status | Should -BeExactly 'Error'
            $state.Context | Should -BeExactly 'Error'
            $state.ErrorCode | Should -Not -BeNullOrEmpty
            $state.ErrorMessage | Should -Not -BeNullOrEmpty
        }

        It '失败态的降级指引包含 r(重试)与 s(直连)' {
            $data = @{
                Available = $false; TimedOut = $true; NetworkError = $false
                Error = 'ssh timed out'; ExitCode = 255
            }

            $state = & $script:mod { param($d) Get-TmuxSessionState -SessionData $d } $data

            $state.Hint | Should -Match '按 r 重试'
            $state.Hint | Should -Match '按 s 直连'
        }
    }

    Context 'Get-TmuxSessionState: -Sessions 参数优先(行序重排场景)' {

        It '-Sessions 传入 2 个会话时会话数为 2' {
            $ordered = @(
                [PSCustomObject]@{ Name = 'zulu'; Status = 'detached' }
                [PSCustomObject]@{ Name = 'yankee'; Status = 'attached' }
            )
            $data = @{ Available = $true; Sessions = @([PSCustomObject]@{ Name = 'alpha' }) }

            $state = & $script:mod {
                param($d, $s)
                Get-TmuxSessionState -SessionData $d -Sessions $s
            } $data $ordered

            $state.Sessions.Count | Should -Be 2
        }

        It '-Sessions 传入的会话名称按传入顺序排列' {
            $ordered = @(
                [PSCustomObject]@{ Name = 'zulu'; Status = 'detached' }
                [PSCustomObject]@{ Name = 'yankee'; Status = 'attached' }
            )
            $data = @{ Available = $true; Sessions = @([PSCustomObject]@{ Name = 'alpha' }) }

            $state = & $script:mod {
                param($d, $s)
                Get-TmuxSessionState -SessionData $d -Sessions $s
            } $data $ordered

            @($state.Sessions | ForEach-Object { $_.Name }) | Should -Be @('zulu', 'yankee')
        }
    }

    Context 'Get-TmuxSessionState: SessionData 为 $null 的兜底' {

        It 'SessionData=$null 时状态为 Error 且错误码为 E_UNKNOWN' {
            $state = & $script:mod { param($d) Get-TmuxSessionState -SessionData $d } $null

            $state.Status | Should -BeExactly 'Error'
            $state.ErrorCode | Should -BeExactly 'E_UNKNOWN'
        }
    }
}
