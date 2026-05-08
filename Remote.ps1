$Global:LastSshHost = ""

function Get-TmuxSessions {
    param([string]$HostName)
    $output = ssh $HostName "tmux ls" 2>$null | Out-String
    $sessionList = @()
    foreach ($line in ($output -split "`n")) {
        if ($line -match '^[^:]+:') {
            $name = ($line -split ':')[0].Trim()
            $status = "鍚庡彴涓?
            if ($line -match "attached") { $status = "宸叉寕杞? }
            $sessionList += @{ Name = $name; Status = $status }
        }
    }
    return @{ Sessions = $sessionList; RawOutput = $output }
}

function Show-TmuxSelector {
    param([string]$HostName, [array]$Sessions)
    $subOptions = @(@{ Name = "杩斿洖涓昏彍鍗? }) + $Sessions
    $idx = 0

    while ($true) {
        Clear-Host
        Write-Host "$($global:HERMES_CONF.Colors.Cyan)馃殌 TMUX MANAGER | $HostName $($global:HERMES_CONF.Colors.Rst)"

        for ($i = 0; $i -lt $subOptions.Count; $i++) {
            $color = "White"; $marker = "    "
            if ($i -eq $idx) { $color = "Cyan"; $marker = "[>] " }
            $prefix = "[$i]"
            if ($i -eq 0) { $prefix = "[Q]" }
            Write-Host "$marker $prefix $($subOptions[$i].Name) $($subOptions[$i].Status)" -ForegroundColor $color
        }

        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        $vK = $key.VirtualKeyCode
        if ($vK -eq $global:HERMES_CONF.Keys.Up) { $idx = ($idx - 1 + $subOptions.Count) % $subOptions.Count; continue }
        if ($vK -eq $global:HERMES_CONF.Keys.Down) { $idx = ($idx + 1) % $subOptions.Count; continue }
        if ($vK -eq $global:HERMES_CONF.Keys.Enter) {
            if ($idx -eq 0) { return "MENU_BACK" }
            return "tmux attach -t '$($Sessions[$idx - 1].Name)'"
        }
        if ($key.Character -eq 'q') { return "MENU_BACK" }
    }
}

function Invoke-TmuxAction {
    param([string]$Key, [string]$HostName)
    switch ($Key) {
        '1' { return "tmux attach -t main || tmux new -s main" }
        '2' { return "tmux attach -t main" }
        '3' {
            $n = Read-Host " > 鏂颁細璇濆悕绉?(鐣欑┖鍥炶溅闅忔満鐢熸垚)"
            if ([string]::IsNullOrWhiteSpace($n)) { 
                $n = "G7-$(Get-Random -Min 1000 -Max 9999)" 
            } else {
                if ($n -notmatch '^[a-zA-Z0-9_-]+$') {
                    Write-Host " [鉁朷 鍚嶇О浠呮敮鎸佸瓧姣嶃€佹暟瀛椼€? 鍜?_" -ForegroundColor Red
                    Start-Sleep -s 1
                    return $null
                }
            }
            return "tmux new -d -s '$n' && tmux attach -t '$n'"
        }
        '4' {
            $data = Get-TmuxSessions -HostName $HostName
            if ($data.Sessions.Count -eq 0) {
                Write-Host " [!] 鏃犳椿璺冧細璇? -ForegroundColor Yellow; Start-Sleep -s 1
                return "MENU_BACK"
            }
            return Show-TmuxSelector -HostName $HostName -Sessions $data.Sessions
        }
        '5' { return "tmux kill-server" }
        'q' { return "INTERNAL_QUIT" }
    }
    return $null
}

function Start-TmuxSession {
    param([Parameter(Position=0)][string]$hostName)
    if (-not $hostName) { $hostName = $Global:LastSshHost }
    if (-not $hostName) { Write-Host " [!] 缂哄皯涓绘満鍚? -ForegroundColor Red; return }

    $Global:LastSshHost = $hostName
    $idx = 0

    $menu = @(
        @{ Name = "RESUME"; Desc = "鎺ュ叆 main 浼氳瘽锛岃嫢涓嶅瓨鍦ㄥ垯鑷姩鏂板缓 (鎺ㄨ崘)" }
        @{ Name = "ATTACH"; Desc = "浠呭皾璇曟帴鍏?main 浼氳瘽 (涓嶅垱寤烘柊浼氳瘽)" }
        @{ Name = "NEW";    Desc = "鍒涘缓鏂颁細璇?(杈撳叆鍚嶇О锛屾垨鐩存帴鐣欑┖鍥炶溅鐢熸垚闅忔満鍚嶇О)" }
        @{ Name = "LIST";   Desc = "鏌ヨ璇ヤ富鏈烘墍鏈夋椿璺冧細璇濓紝骞舵墦寮€閫夋嫨闈㈡澘" }
        @{ Name = "KILL";   Desc = "鍗遍櫓锛氱粓姝㈠綋鍓嶄富鏈轰笂杩愯鐨勬墍鏈?tmux 杩涚▼" }
        @{ Name = "EXIT";   Desc = "閫€鍑哄綋鍓嶉潰鏉匡紝杩斿洖鏈湴缁堢" }
    )

    while ($true) {
        Clear-Host
        if (Get-Command Show-HermesLogo -ErrorAction SilentlyContinue) { Show-HermesLogo }
        Write-Host "$($global:HERMES_CONF.Colors.Cyan)馃殌 REMOTE TMUX | $hostName $($global:HERMES_CONF.Colors.Rst)"
        Write-Host "$($global:HERMES_CONF.Colors.Gray)$("-" * 50)$($global:HERMES_CONF.Colors.Rst)"

        for ($i = 0; $i -lt $menu.Count; $i++) {
            $color = "White"; $marker = "    "
            if ($i -eq $idx) { $color = "Cyan"; $marker = "[>] " }
            Write-Host "$marker[$($i+1)] $($menu[$i].Name)" -ForegroundColor $color
        }

        Write-Host ""
        Write-Host "    $($global:HERMES_CONF.Colors.Gray)鈩?璇存槑: $($menu[$idx].Desc)$($global:HERMES_CONF.Colors.Rst)"
        Write-Host "$($global:HERMES_CONF.Colors.Gray)$("-" * 50)$($global:HERMES_CONF.Colors.Rst)"

        if ($Host.UI.RawUI.KeyAvailable) { $Host.UI.RawUI.FlushInputBuffer() }

        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        $vK = $key.VirtualKeyCode; $char = $key.Character.ToString().ToLower()

        if ($vK -eq $global:HERMES_CONF.Keys.Up) { $idx = ($idx - 1 + $menu.Count) % $menu.Count; continue }
        if ($vK -eq $global:HERMES_CONF.Keys.Down) { $idx = ($idx + 1) % $menu.Count; continue }

        $finalKey = $null
        if ($vK -eq $global:HERMES_CONF.Keys.Enter) { $finalKey = ($idx + 1).ToString() }
        elseif ($char -match "^[1-$($menu.Count)]$") { $finalKey = $char }
        elseif ($char -eq 'q' -or $vK -eq $global:HERMES_CONF.Keys.Esc) { return }

        if ($finalKey -eq "$($menu.Count)") { return }
        if ($null -ne $finalKey) {
            $cmd = Invoke-TmuxAction -Key $finalKey -HostName $hostName
            if ($cmd -eq "INTERNAL_QUIT") { return }
            if ($cmd -eq "MENU_BACK" -or $null -eq $cmd) { continue }

            Write-Host "`n[SSH] 杩炴帴涓?.." -ForegroundColor DarkCyan
            & ssh.exe -tt -o "ConnectTimeout=5" $hostName "$cmd"

            Start-Sleep -Milliseconds 200
            if ($Host.UI.RawUI.KeyAvailable) { $Host.UI.RawUI.FlushInputBuffer() }
        }
    }
}
