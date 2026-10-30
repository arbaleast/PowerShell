# New-TmuxSession.ps1 - 在远程主机上创建新的 tmux 会话


function New-TmuxSession {
    <#
    .SYNOPSIS
        在远程主机上创建新的 tmux 会话

    .DESCRIPTION
        提示用户输入会话名称（或直接回车使用随机 6 位数字名称），
        然后通过 SSH 在远程主机上创建并附着到新 tmux 会话。

        输入区的渲染按"谁持有备用屏"分流(2026-10-30 TGUI 迁移):
          - Legacy(管理器持有全屏备用屏): 绝对坐标 HUD(标题/提示/输入行/底栏);
          - Plain(TGUI 仪表盘路径, 普通屏): 单行内联提示 + 就地重绘,
            读完即换行, 不发任何绝对定位序列, 不在屏幕上留残影。

    .PARAMETER HostName
        远程主机名

    .EXAMPLE
        New-TmuxSession -HostName myserver
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    [OutputType([void])]
param(
        [Parameter(Mandatory = $true)]
        [string]$HostName
    )
    if ($PSCmdlet.ShouldProcess("tmux session on $HostName", "Perform New-TmuxSession")) { } else { return  }

    # ---- 渲染模式分流(2026-10-30 TGUI 迁移) ----
    # 两种模式按"谁持有备用屏"分流:
    #   Legacy($script:TmuxAltScreenActive -eq $true): 管理器自己持有全屏备用屏,
    #     画面是独立的全屏缓冲区 -> 沿用绝对坐标 HUD(逐字节与迁移前一致)。
    #   Plain(其余情况, 即 TGUI 仪表盘路径): 终端是普通屏(TG 自己管备用屏),
    #     绝对坐标写入会落在屏幕任意位置并留下残影 -> 改用一次性内联提示 +
    #     就地重绘, 读完即换行, 不做任何定位。
    $height = 0
    try { $height = [Console]::WindowHeight } catch { $height = 0 }
    if ($height -lt 12) { $height = 40 }   # 重定向控制台取不到高度: 保守回退
    $descRow  = $height - 6
    $inputRow = $height - 5
    $inputBarRow = $height - 1

    if ($script:TmuxAltScreenActive -eq $true) {
        # ---- 绝对坐标布局(2026-10-30 第五轮修复) ----
        # 主循环每次迭代开头已 Clear-TmuxScreen(\e[2J\e[H), 此处屏幕是干净的,
        # 全部渲染走 [Console]::WindowHeight 推导的绝对坐标, 不基于旧光标位置:
        #   Y = $h - 6  提示语(输入会话名称...)
        #   Y = $h - 5  "> <输入缓冲区>"
        #   Y = $h - 1  Input 态底栏 [Enter] 确认  [Esc] 取消
        # (旧实现用 8 + optCount 的固定行号, 屏幕上半部分随上游内容漂移。)
        # 颜色预解析: 统一走 Resolve-ColorTable(预热缓存 -> 配置层默认值)
        $colorTable = Resolve-ColorTable -Name 'Primary', 'Muted', 'Accent', 'Rst'
        $cp  = $colorTable.Primary
        $cm  = $colorTable.Muted
        $ca  = $colorTable.Accent
        $rst = $colorTable.Rst

        [Console]::Write("`e[2;1H  ${cm}TMUX 管理器 - 新建会话 - 主机 ${cp}${HostName}${rst}")
        [Console]::Write("`e[$($descRow);1H  ${cp}|${rst}  ${cm}-- 输入会话名称（直接回车使用随机名称）${rst}")
        [Console]::Write("`e[$($inputRow);1H  ${cp}|${rst}  ${ca}>${rst} ")
        # Input 态底栏(状态机渲染分支): 与 Normal 态动作条互斥, 键位提示只呈现本模式可用的键
        [Console]::Write("`e[$($inputBarRow);1H`e[K  ${cm}[Enter] 确认  [Esc] 取消${rst}")

        # Input 态(2026-10-30 第三轮 TUI 修复): 不再用 [Console]::ReadLine —— 行编辑
        # 行为不受我们控制, 且旁边的键位循环会把打字过程刷成 "未识别的按键 ''"。
        # Read-TmuxConsoleLine 是状态机 Input 态: Enter 提交 / Esc 取消($null) /
        # Backspace 删字符 / 可见字符入缓冲 / 其余控制键**静默忽略**。
        try {
            $newName = Read-TmuxConsoleLine -Row $inputRow -Column 7
        } catch {
            $newName = $null
        }

        # 提交/取消都清掉输入区与 Input 底栏(含 "> n" 残留), 交还主循环重绘
        [Console]::Write("`e[$($descRow);1H`e[J")
    }
    else {
        # ---- 内联提示(TGUI 仪表盘路径: 普通屏, 不允许绝对定位) ----
        # 提示语独占一行, 输入缓冲落在下一行的行首: 内联重绘用 \r 回行首,
        # 若提示语与输入同行, \r 会把提示语覆盖掉。
        [Console]::Write("新建 tmux 会话 (直接回车使用随机名称, Esc 取消): `n")
        try {
            # -Inline: 就地重绘(\r + 缓冲 + \e[K), 不发任何绝对定位序列
            $newName = Read-TmuxConsoleLine -Row $inputRow -Inline
        } catch {
            $newName = $null
        }
        # 读完补一个换行: 让 shell 提示符从新行开始, 不与输入残留在同一行
        [Console]::Write("`n")
    }

    if ($null -eq $newName) {
        # Esc = 取消创建: 回到主循环, 下一轮迭代 Clear-TmuxScreen + 绝对重绘恢复画面
        return
    }
    if ([string]::IsNullOrWhiteSpace($newName)) {
        $newName = New-RandomSessionName
    }
    $escapedName = "'$(ConvertTo-SshEscapedString -Value $newName)'"
    # fix(2026-10-07): 显式分两步, 不吞 stderr, 也不依赖 `-A` 隐式 attach 语义
    #   1) has-session: 若会话已存在则 attach;  2) 否则 new-session 再 attach。
    # 全屏交接只发生在**真正进入 SSH/tmux** 的时刻(2026-10-30 第六轮修复):
    # 此前由调用方无条件 Exit/Enter 包裹 —— Esc 取消输入也会白翻一次屏幕,
    # 用户被抖到主屏闪现 Shell 历史(detached 输出)再拉回来。
    # 现在: Esc 取消直接 return, 全程零屏幕翻转; ssh 启动才暂停管理器屏。
    [string]$remoteCmd = "tmux has-session -t $escapedName 2>/dev/null && tmux attach -t $escapedName || (tmux new-session -d -s $escapedName && tmux attach -t $escapedName)"
    # DoubleTty: Win OpenSSH 下 `ssh -t` 的 PTY 不会回 tmux 期望的 u6/u7 响应,
    # tmux 走 "软启动后立刻 detach" 闪退路径。加 -tt -t 可强制 ssh 把 PTY 当作
    # tty 传给远端, 绕过 isatty 检测。raw 探针 2026-10-07 验证可修。
    # ssh 启动失败(未安装 OpenSSH 客户端 / ssh.exe 不在 PATH 等)时 Invoke-SshCommand 会抛异常。
    # 这里降级为警告并返回, 让管理器回到主循环由用户重试, 而不是让整个 SSS 流程带异常中断。
    Exit-TmuxAlternateScreen
    try {
        $result = Invoke-SshCommand -HostName $HostName -Interactive -DoubleTty -RemoteCommand $remoteCmd -PassThru
    } catch {
        # 无论如何先回到管理器备用屏再报错, 异常降级为警告并回主循环
        Enter-TmuxAlternateScreen
        Write-Warning "无法执行 ssh: $($_.Exception.Message)"
        return
    }
    Enter-TmuxAlternateScreen
    if ($null -ne $result -and $result.ExitCode -ne 0) {
        Write-Warning "tmux 新建/附加会话未成功结束 (ssh 退出码: $($result.ExitCode))，请到远端确认会话状态。"
        return
    }
    Write-Host "`n [OK] tmux 会话已分离，回到管理菜单" -ForegroundColor Cyan
}
