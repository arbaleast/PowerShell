# Start-TmuxSession.ps1 - 远程 tmux 会话管理器
# 流程: 主机选择 -> tmux 检测 -> 会话管理 -> SSH 连接
# 优化: 提升 $actionOptions 跳出 while 循环(每轮迭代不再重建 5 元素数组);
#       消除"创建新 tmux 会话"分支中的 3 段三层回退颜色 -> Get-CachedConfig;
#       强制刷新"刷新会话列表"分支(避免再走 cache 显示过期数据);
#       选项集合 ArrayList -> Generic.List[PSCustomObject]::new($count) 真预分配;
#       提升常量"会话列表描述"为静态字符串,避免每次迭代插值。

$script:TmuxSessionPrefix = "tmux-"

function New-RandomSessionName {
    "$script:TmuxSessionPrefix$(Get-Random -Minimum 100000 -Maximum 999999)"
}

function Start-TmuxSession {

    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$HostName
    )

    # 内部验证：禁止 Shell 注入字符（允许空格、中文）
    if ($HostName -match '[\t\n|&;`$(){}<>#@!*?\[\]~"]') {
        throw "主机名 [$HostName] 包含非法字符，仅允许字母、数字、空格、点、短横线和下划线"
    }

    if (-not $HostName) {
        $hosts = Get-SshConfigHosts
        if ($hosts.Count -eq 0) {
            Write-Host "`n [!] SSH 配置中未找到任何主机" -ForegroundColor Red
            Write-Host "     请先在 ~/.ssh/config 中配置主机" -ForegroundColor DarkGray
            return
        }

        if ($Global:LastSshHost -and ($hosts -contains $Global:LastSshHost)) {
            $hosts = @($Global:LastSshHost) + ($hosts | Where-Object { $_ -ne $Global:LastSshHost })
        }

        $hostOptions = [System.Collections.Generic.List[PSCustomObject]]::new($hosts.Count)
        foreach ($h in $hosts) {
            $desc = "SSH 远程主机"
            if ($Global:LastSshHost -and $h -eq $Global:LastSshHost) {
                $desc = "上次使用的主机"
            }
            $hostOptions.Add([PSCustomObject]@{ Label = $h; Desc = $desc })
        }

        $selected = Invoke-ConsoleMenu -Title "SSH 主机选择器" -Options $hostOptions -ExitLabel "退出"
        if ($null -eq $selected) {
            Clear-Host
            return
        }

        $HostName = $selected.Label
    }

    $Global:LastSshHost = $HostName

    Write-Host "`n [SSH] 目标主机: $HostName" -ForegroundColor Cyan

    Write-Host " [..] 正在检测远程 tmux..." -ForegroundColor DarkGray
    # 拿回 ExitCode/Error 便于误判时打印调试线索
    $availInfo = Get-TmuxAvailability -HostName $HostName
    $hasTmux = $availInfo.Available

    if (-not $hasTmux) {
        Write-Host " [!!] 远程主机 $HostName 未安装 tmux(或探测失败)" -ForegroundColor Yellow
        # 打印 stderr 片段,便于用户判断是真没装还是 PATH 问题
        $rawErr = $availInfo.Error
        if ($rawErr) {
            Write-Host "     远程错误: $($rawErr.Trim())" -ForegroundColor DarkGray
        }
        Write-Host "     排查: 手动跑 `ssh $HostName 'command -v tmux; tmux -V'` 看输出" -ForegroundColor DarkGray
        Write-Host " [SSH] 直接连接..." -ForegroundColor Green
        Invoke-SshCommand -HostName $HostName -Interactive
        Write-Host "`n [OK] SSH 连接已关闭，回到本地 PowerShell" -ForegroundColor Cyan
        return
    }

    Write-Host " [OK] 远程 tmux 可用 (版本: $($availInfo.Version))" -ForegroundColor Green

    $sessionData = Get-TmuxSessions -HostName $HostName
    $sessions = $sessionData.Sessions

    if ($sessions.Count -eq 0) {
        Write-Host " [TMUX] $HostName 上暂无现有会话" -ForegroundColor Yellow
    }

    # ===== 提升常量出循环: 5 个动作的描述在循环中保持稳定,无需每轮重建 =====
    $actionOptions = @(
        [PSCustomObject]@{ Label = "附着/恢复 tmux 会话"; Desc = "选择并附着到远程 tmux 会话" }
        [PSCustomObject]@{ Label = "创建新 tmux 会话"; Desc = "在远程主机上创建新的 tmux 会话" }
        [PSCustomObject]@{ Label = "删除 tmux 会话"; Desc = "删除远程主机上的 tmux 会话" }
        [PSCustomObject]@{ Label = "直接 SSH 登录"; Desc = "不使用 tmux，直接 SSH 登录" }
        [PSCustomObject]@{ Label = "刷新会话列表"; Desc = "重新获取远程 tmux 会话状态" }
    )

    while ($true) {
        # 默认走缓存: 仅在进入菜单时探测 1 次 SSH,避免每次用户操作都触发
        # 短连接消耗 sshd MaxStartups/MaxSessions 配额导致掉线
        # 用户可主动按"刷新会话列表"强制重拉
        $sessionData = Get-TmuxSessions -HostName $HostName
        $sessions = $sessionData.Sessions

        $attachedCount = ($sessions | Where-Object { $_.Status -eq "attached" }).Count
        $detachedCount = ($sessions | Where-Object { $_.Status -eq "detached" }).Count
        $sessionSummary = "会话: $($sessions.Count) 个 (已附着=$attachedCount 已分离=$detachedCount)"

        $action = Invoke-ConsoleMenu -Title "TMUX 管理器 [$HostName] | $sessionSummary" -Options $actionOptions -ExitLabel "断开连接"

        if ($null -eq $action) {
            Clear-Host
            Write-Host " [OK] 已从 $HostName 断开连接" -ForegroundColor Cyan
            return
        }

        switch ($action.Label) {

            "附着/恢复 tmux 会话" {
                if ($sessions.Count -eq 0) {
                    Write-Host " [!] 没有可用的 tmux 会话" -ForegroundColor Yellow
                    continue
                }

                $sessionOptions = [System.Collections.Generic.List[PSCustomObject]]::new($sessions.Count)
                foreach ($s in $sessions) {
                    $icon = if ($s.Status -eq "attached") { "[A]" } else { "[D]" }
                    $sessionOptions.Add([PSCustomObject]@{
                            Label   = "$icon $($s.Name)"
                            RawName = $s.Name
                            Desc    = "状态: $($s.Status)"
                        })
                }

                $selected = Invoke-ConsoleMenu -Title "TMUX 会话列表 [$HostName]" -Options $sessionOptions -ExitLabel "返回"
                if ($null -eq $selected) { continue }

                $sessionName = $selected.RawName
                if (-not $sessionName) {
                    $sessionName = $selected.Label -replace '^\[[AD]\]\s+', ''
                }

                $escapedName = "'" + ($sessionName -replace "'", "'\''") + "'"
                Invoke-SshCommand -HostName $HostName -Interactive -RemoteCommand "tmux attach -d -t $escapedName 2>/dev/null || tmux new-session -A -s $escapedName"
                Write-Host "`n [OK] tmux 会话已分离，回到管理菜单" -ForegroundColor Cyan
            }

            "创建新 tmux 会话" {
                # Invoke-ConsoleMenu 布局：1空行 + 3行header + N选项 + 1EXIT + 2分隔 + 1描述 + 1| + 1底边 + 2底部空行
                $optCount = $actionOptions.Count
                $descRow = 8 + $optCount
                $inputRow = $descRow + 1

                # 走预热缓存: 1 次 hashtable 查询替代 3 段三层回退
                $cp = Get-CachedConfig -Section 'Colors' -Key 'FreshGreen' -Default "`e[38;2;137;209;133m"
                $cm = Get-CachedConfig -Section 'Colors' -Key 'MidGray'    -Default "`e[38;2;100;100;100m"
                $ca = Get-CachedConfig -Section 'Colors' -Key 'SageGreen'  -Default "`e[38;2;159;177;159m"
                $rst = Get-CachedConfig -Section 'Colors' -Key 'Rst'        -Default "`e[0m"

                $clearEndRow = $descRow + 6
                for ($r = $descRow; $r -le $clearEndRow; $r++) {
                    [Console]::Write("`e[${r};1H`e[K")
                }

                [Console]::Write("`e[$($descRow);1H  ${cp}|${rst}  ${cm}-- 输入会话名称（直接回车使用随机名称）${rst}")
                [Console]::Write("`e[$($inputRow);1H  ${cp}|${rst}  ${ca}>${rst} ")

                [Console]::CursorTop = $inputRow - 1
                [Console]::CursorLeft = 7

                try {
                    $newName = [Console]::ReadLine()
                } catch {
                    $newName = $null
                }

                if ([string]::IsNullOrWhiteSpace($newName)) {
                    $newName = New-RandomSessionName
                }

                [Console]::Write("`e[$($inputRow + 1);1H`r`e[K")
                $escapedName = "'" + ($newName -replace "'", "'\''") + "'"
                Invoke-SshCommand -HostName $HostName -Interactive -RemoteCommand "tmux new-session -A -s $escapedName 2>/dev/null || exec sh"
                Write-Host "`n [OK] tmux 会话已分离，回到管理菜单" -ForegroundColor Cyan
            }

            "删除 tmux 会话" {
                if ($sessions.Count -eq 0) {
                    Write-Host " [!] 没有可删除的会话" -ForegroundColor Yellow
                    continue
                }

                $killOptions = [System.Collections.Generic.List[PSCustomObject]]::new($sessions.Count)
                foreach ($s in $sessions) {
                    $killOptions.Add([PSCustomObject]@{ Label = $s.Name; Desc = "状态: $($s.Status)" })
                }

                $selected = Invoke-ConsoleMenu -Title "删除 TMUX 会话 [$HostName]" -Options $killOptions -ExitLabel "取消"
                if ($null -eq $selected) { continue }

                Write-Host " [..] 正在删除会话 '$($selected.Label)' ..." -ForegroundColor DarkGray
                $escapedLabel = "'" + ($selected.Label -replace "'", "'\''") + "'"
                Invoke-SshCommand -HostName $HostName -RemoteCommand "tmux kill-session -t $escapedLabel"
                Write-Host " [OK] 会话 '$($selected.Label)' 已删除" -ForegroundColor Green
            }

            "直接 SSH 登录" {
                Write-Host " [SSH] 直接连接..." -ForegroundColor Green
                Invoke-SshCommand -HostName $HostName -Interactive
                Write-Host "`n [OK] SSH 连接已关闭，回到管理菜单" -ForegroundColor Cyan
            }

            "刷新会话列表" {
                Write-Host " [..] 正在刷新会话列表..." -ForegroundColor DarkGray
                # 显式带 -Force 绕过缓存,真正发起一次 SSH 探测获取最新会话状态
                $sessionData = Get-TmuxSessions -HostName $HostName -Force
                $sessions = $sessionData.Sessions
                $attachedCount = ($sessions | Where-Object { $_.Status -eq "attached" }).Count
                $detachedCount = ($sessions | Where-Object { $_.Status -eq "detached" }).Count
                Write-Host " [OK] 会话列表已刷新: $($sessions.Count) 个 (已附着=$attachedCount 已分离=$detachedCount)" -ForegroundColor Green
            }
        }
    }
}
