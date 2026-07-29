# New-TmuxSession.ps1 - 在远程主机上创建新的 tmux 会话

function New-TmuxSession {
    <#
    .SYNOPSIS
        在远程主机上创建新的 tmux 会话

    .DESCRIPTION
        提示用户输入会话名称（或直接回车使用随机 6 位数字名称），
        然后通过 SSH 在远程主机上创建并附着到新 tmux 会话。

    .PARAMETER HostName
        远程主机名

    .EXAMPLE
        New-TmuxSession -HostName myserver
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName
    )

    # Invoke-ConsoleMenu 布局：1空行 + 3行header + N选项 + 1EXIT + 2分隔 + 1描述 + 1| + 1底边 + 2底部空行
    $optCount = 5
    $descRow = 8 + $optCount
    $inputRow = $descRow + 1

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
    $escapedName = "'$(ConvertTo-SshEscapedString -Value $newName)'"
    Invoke-SshCommand -HostName $HostName -Interactive -RemoteCommand "tmux new-session -A -s $escapedName 2>/dev/null || exec sh"
    Write-Host "`n [OK] tmux 会话已分离，回到管理菜单" -ForegroundColor Cyan
}
