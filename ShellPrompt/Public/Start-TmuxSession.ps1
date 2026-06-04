# ============================================================
# Start-TmuxSession.ps1 - 远程 Tmux 会话管理器
# 功能: 主机选择 -> tmux 检测 -> 会话管理 -> SSH 连接
# 安全: 使用 Invoke-SshCommand + ConvertTo-SshEscapedString 防止命令注入
# 关键: 使用 Start-Process -NoNewWindow -Wait ssh.exe 解决 PTY 问题
# ============================================================

function Start-TmuxSession {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$HostName
    )

    # ========================================
    # 内部验证：检查 HostName 是否包含 Shell 注入字符（允许空格和中文）
    # ========================================
    if ($HostName -match '[\t\n|&;`$(){}<>#@!*?\[\]~"]') {
        throw "主机名 [$HostName] 包含非法字符，仅允许字母、数字、空格、点、短横线和下划线"
    }

    # ========================================
    # Phase 1: 主机选择（SSH 配置主机列表）
    # ========================================

    if (-not $HostName) {
        $hosts = Get-SshConfigHosts
        if ($hosts.Count -eq 0) {
            Write-Host "`n [!] SSH 配置中未找到任何主机" -ForegroundColor Red
            Write-Host "     请先在 ~/.ssh/config 中配置主机" -ForegroundColor DarkGray
            return
        }

        # 将上次使用的主机置顶
        if ($Global:LastSshHost -and ($hosts -contains $Global:LastSshHost)) {
            $hosts = @($Global:LastSshHost) + ($hosts | Where-Object { $_ -ne $Global:LastSshHost })
        }

        # 构建主机选择菜单
        # 注意：使用 foreach 循环代替 ForEach-Object 管道输出，避免 PowerShell 管道收集 hashtable 时的索引问题
        $hostOptions = New-Object System.Collections.ArrayList
        foreach ($h in $hosts) {
            $desc = "SSH 远程主机"
            if ($Global:LastSshHost -and $h -eq $Global:LastSshHost) {
                $desc = "上次使用的主机"
            }
            [void]$hostOptions.Add([PSCustomObject]@{ Label = $h; Desc = $desc })
        }

        # 显示主机选择菜单
        $selected = Invoke-ConsoleMenu -Title "SSH 主机选择器" -Options $hostOptions -ExitLabel "退出"
        if ($null -eq $selected) {
            Clear-Host
            return
        }

        $HostName = $selected.Label
    }

    # 记录上次使用的主机
    $Global:LastSshHost = $HostName

    # ========================================
    # 基础配置常量
    # ========================================
    # tmux 随机会话名前缀
    $sessionPrefix = "tmux-"

    # 定义生成随机会话名的内联函数（每次调用生成不同名称，避免循环中名称冲突）
    function New-RandomSessionName {
        "$sessionPrefix$(Get-Random -Minimum 100000 -Maximum 999999)"
    }

    Write-Host "`n [SSH] 目标主机: $HostName" -ForegroundColor Cyan

    # ========================================
    # Phase 2: 检测远程 tmux 是否可用
    # ========================================

    Write-Host " [..] 正在检测远程 tmux..." -ForegroundColor DarkGray
    $hasTmux = Test-TmuxAvailable -HostName $HostName

    if (-not $hasTmux) {
        Write-Host " [!!] 远程主机 $HostName 未安装 tmux" -ForegroundColor Yellow
        Write-Host " [SSH] 直接连接..." -ForegroundColor Green
        # 直接 SSH 登录，不需要远程命令
        Invoke-SshCommand -HostName $HostName -Interactive
        Write-Host "`n [OK] SSH 连接已关闭，回到本地 PowerShell" -ForegroundColor Cyan
        return
    }

    Write-Host " [OK] 远程 tmux 可用" -ForegroundColor Green

    # ========================================
    # Phase 3: 获取远程 tmux 会话列表
    # ========================================

    $sessionData = Get-TmuxSessions -HostName $HostName
    $sessions = $sessionData.Sessions

    # 无会话时自动创建随机会话并附着（使用随机名，避免名称冲突）
    if ($sessions.Count -eq 0) {
        Write-Host " [TMUX] $HostName 上无现有会话" -ForegroundColor Yellow
        $defaultSession = New-RandomSessionName
        Write-Host " [TMUX] 自动创建默认会话 '$defaultSession' ..." -ForegroundColor Green
        # 会话名是内部生成的随机字符串，每次调用不同，会话名由数字和短横线组成，安全无害
        $escapedSession = ConvertTo-SshEscapedString $defaultSession
        Invoke-SshCommand -HostName $HostName -Interactive -RemoteCommand "tmux new-session -A -s $escapedSession 2>/dev/null || exec sh"
        Write-Host "`n [OK] tmux 会话已关闭，回到本地 PowerShell" -ForegroundColor Cyan
        return
    }

    # ========================================
    # Phase 4: 会话管理菜单循环
    # ========================================

    while ($true) {
        # 每次循环刷新会话列表
        $sessionData = Get-TmuxSessions -HostName $HostName
        $sessions = $sessionData.Sessions

        # 会话摘要信息
        $attachedCount = ($sessions | Where-Object { $_.Status -eq "attached" }).Count
        $detachedCount = ($sessions | Where-Object { $_.Status -eq "detached" }).Count
        $sessionSummary = "会话: $($sessions.Count) 个 (已附着=$attachedCount 已分离=$detachedCount)"

        # 操作菜单项
        $actionOptions = @(
            @{ Label = "附着/恢复 tmux 会话"; Desc = "选择并附着到远程 tmux 会话" }
            @{ Label = "创建新 tmux 会话"; Desc = "在远程主机上创建新的 tmux 会话" }
            @{ Label = "删除 tmux 会话"; Desc = "删除远程主机上的 tmux 会话" }
            @{ Label = "直接 SSH 登录"; Desc = "不使用 tmux，直接 SSH 登录" }
            @{ Label = "刷新会话列表"; Desc = "重新获取远程 tmux 会话状态" }
        )

        # 显示管理菜单
        $action = Invoke-ConsoleMenu -Title "TMUX 管理器 [$HostName] | $sessionSummary" -Options $actionOptions -ExitLabel "断开连接"

        # 用户选择断开连接
        if ($null -eq $action) {
            Clear-Host
            # 双重保障：菜单退出时也重置终端状态
            if (Get-Command Reset-TerminalMode -ErrorAction SilentlyContinue) {
                Reset-TerminalMode
            }
            Write-Host " [OK] 已从 $HostName 断开连接" -ForegroundColor Cyan
            return
        }

        # 根据选择执行操作
        switch ($action.Label) {

            # --------------------------------------------------
            # 操作 1: 附着/恢复 tmux 会话
            # --------------------------------------------------
            "附着/恢复 tmux 会话" {
                if ($sessions.Count -eq 0) {
                    Write-Host " [!] 没有可用的 tmux 会话" -ForegroundColor Yellow
                    continue
                }

                # 构建会话选择菜单（带状态图标和原始名称）
                # 注意：使用 ArrayList 代替 ForEach-Object 管道输出，避免 PowerShell 管道收集 hashtable 时的索引问题
                $sessionOptions = New-Object System.Collections.ArrayList
                foreach ($s in $sessions) {
                    $icon = if ($s.Status -eq "attached") { "[A]" } else { "[D]" }
                    [void]$sessionOptions.Add([PSCustomObject]@{
                            # 显示标签：图标 + 名称（用于显示）
                            Label   = "$icon $($s.Name)"
                            # 原始名称（用于命令构建，避免正则提取歧义）
                            RawName = $s.Name
                            Desc    = "状态: $($s.Status)"
                        })
                }

                $selected = Invoke-ConsoleMenu -Title "TMUX 会话列表 [$HostName]" -Options $sessionOptions -ExitLabel "返回"
                if ($null -eq $selected) { continue }

                # 使用 RawName 获取纯会话名称（避免从 Label 中正则提取的歧义问题）
                $sessionName = $selected.RawName
                if (-not $sessionName) {
                    # 防御性回退：从 Label 中提取名称（格式: "[A] tmux-xxxxxx"）
                    $sessionName = $selected.Label -replace '^\[[AD]\]\s+', ''
                }

                Write-Host " [TMUX] 正在连接到会话 '$sessionName' ..." -ForegroundColor Green
                # 安全：使用 ConvertTo-SshEscapedString 转义 $sessionName，防止命令注入
                $escapedName = ConvertTo-SshEscapedString $sessionName
                Invoke-SshCommand -HostName $HostName -Interactive -RemoteCommand "tmux attach -d -t $escapedName 2>/dev/null || tmux new-session -A -s $escapedName"
                # 交互式 SSH 退出后，给 SSH 连接留出清理时间
                Start-Sleep -Seconds 1
                Write-Host "`n [OK] tmux 会话已分离，回到管理菜单" -ForegroundColor Cyan
            }

            # --------------------------------------------------
            # 操作 2: 创建新 tmux 会话
            # --------------------------------------------------
            "创建新 tmux 会话" {
                # 在菜单框内部绘制输入区域，避免显示错位
                # Invoke-ConsoleMenu 布局：1空行 + 3行header + N选项 + 1EXIT + 2分隔 + 1描述 + 1| + 1底边 + 2底部空行
                # 描述行的 ANSI 行号 = 8 + 选项数
                $optCount = $actionOptions.Count
                $descRow = 8 + $optCount  # 描述行在框内的 ANSI 行号（1-based）
                $inputRow = $descRow + 1   # 输入行在描述行下方

                # 获取菜单颜色配置，保持视觉效果一致
                $rst = "`e[0m"
                $cp = $global:UserScoop_CONF.Colors.FreshGreen
                $cm = $global:UserScoop_CONF.Colors.MidGray
                $ca = $global:UserScoop_CONF.Colors.SageGreen

                # 清空从描述行到菜单底部的区域，准备绘制输入界面
                $clearEndRow = $descRow + 6
                for ($r = $descRow; $r -le $clearEndRow; $r++) {
                    [Console]::Write("`e[${r};1H`e[K")
                }

                # 始终提示使用随机名称
                $defaultHint = "直接回车使用随机名称"

                # 在框内绘制输入提示行（保持菜单边框样式）
                [Console]::Write("`e[$($descRow);1H  ${cp}|${rst}  ${cm}-- 输入会话名称（${defaultHint}）${rst}")

                # 绘制输入行（使用 > 符号作为输入指示符）
                [Console]::Write("`e[$($inputRow);1H  ${cp}|${rst}  ${ca}>${rst} ")

                # 定位光标到输入位置（CursorTop 是 0-based，需 ANSI 行号减 1）
                [Console]::CursorTop = $inputRow - 1
                [Console]::CursorLeft = 7

                # 使用 [Console]::ReadLine() 而非 Read-Host，避免额外输出破坏边框布局
                try {
                    $newName = [Console]::ReadLine()
                } catch {
                    # Ctrl+C 或中断时使用默认名称
                    $newName = $null
                }

                # 处理空输入：始终使用随机名称（每次调用生成不同名称，避免冲突）
                if ([string]::IsNullOrWhiteSpace($newName)) {
                    $newName = New-RandomSessionName
                }

                # 输出操作状态（覆盖残留的菜单框区域，避免视觉混乱）
                # 先定位光标到输入行下方，再用 Write-Host 输出
                [Console]::Write("`e[$($inputRow + 1);1H`e[K")
                [Console]::Write("`e[$($inputRow + 2);1H`e[K")
                [Console]::Write("`e[$($inputRow + 1);1H")
                Write-Host " [TMUX] 正在创建并连接到会话 '$newName' ..." -ForegroundColor Green
                # 安全：使用 ConvertTo-SshEscapedString 转义 $newName，防止命令注入
                $escapedName = ConvertTo-SshEscapedString $newName
                Invoke-SshCommand -HostName $HostName -Interactive -RemoteCommand "tmux new-session -A -s $escapedName 2>/dev/null || exec sh"
                # 交互式 SSH 退出后，给 SSH 连接留出清理时间
                Start-Sleep -Seconds 1
                Write-Host "`n [OK] tmux 会话已分离，回到管理菜单" -ForegroundColor Cyan
            }

            # --------------------------------------------------
            # 操作 3: 删除 tmux 会话
            # --------------------------------------------------
            "删除 tmux 会话" {
                if ($sessions.Count -eq 0) {
                    Write-Host " [!] 没有可删除的会话" -ForegroundColor Yellow
                    continue
                }

                # 构建删除选择菜单
                # 注意：使用 foreach 循环代替 ForEach-Object 管道输出，避免 PowerShell 管道收集 hashtable 时的索引问题
                $killOptions = New-Object System.Collections.ArrayList
                foreach ($s in $sessions) {
                    [void]$killOptions.Add([PSCustomObject]@{ Label = $s.Name; Desc = "状态: $($s.Status)" })
                }

                $selected = Invoke-ConsoleMenu -Title "删除 TMUX 会话 [$HostName]" -Options $killOptions -ExitLabel "取消"
                if ($null -eq $selected) { continue }

                # 执行删除（同步 SSH，不需要 Start-Process）
                Write-Host " [..] 正在删除会话 '$($selected.Label)' ..." -ForegroundColor DarkGray
                # 安全：使用 ConvertTo-SshEscapedString 转义 $selected.Label，防止命令注入
                # 删除操作不需要交互式 PTY，使用非交互模式
                $escapedLabel = ConvertTo-SshEscapedString $selected.Label
                Invoke-SshCommand -HostName $HostName -RemoteCommand "tmux kill-session -t $escapedLabel"
                Write-Host " [OK] 会话 '$($selected.Label)' 已删除" -ForegroundColor Green
            }

            # --------------------------------------------------
            # 操作 4: 直接 SSH 登录
            # --------------------------------------------------
            "直接 SSH 登录" {
                Write-Host " [SSH] 直接连接..." -ForegroundColor Green
                # 直接 SSH 登录，不需要远程命令
                Invoke-SshCommand -HostName $HostName -Interactive
                # 交互式 SSH 退出后，给 SSH 连接留出清理时间
                Start-Sleep -Seconds 1
                Write-Host "`n [OK] SSH 连接已关闭，回到管理菜单" -ForegroundColor Cyan
            }

            # --------------------------------------------------
            # 操作 5: 刷新会话列表
            # --------------------------------------------------
            "刷新会话列表" {
                Write-Host " [..] 正在刷新会话列表..." -ForegroundColor DarkGray
                # 下次循环迭代时会自动重新获取
            }
        }
    }
}
