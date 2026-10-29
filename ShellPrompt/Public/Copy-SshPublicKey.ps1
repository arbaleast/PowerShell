<#
.SYNOPSIS
    将本机 SSH 公钥复制到远程主机 authorized_keys

.DESCRIPTION
    模拟 Linux `ssh-copy-id` 命令，自动按 ed25519 > ecdsa > rsa > dsa 顺序查找
    ~/.ssh 下的公钥文件，支持通过 -IdentityFile 指定自定义公钥路径和 -Port 指定端口。

.PARAMETER RemoteHost
    远程主机地址（必填），格式为 [user@]hostname。

.PARAMETER IdentityFile
    公钥文件路径。未指定时自动按 ed25519 > ecdsa > rsa > dsa 顺序探测。

.PARAMETER Port
    SSH 端口号，默认 22。

.EXAMPLE
    Copy-SshPublicKey -RemoteHost user@example.com

    自动探测公钥并推送到 user@example.com 的 authorized_keys。

.EXAMPLE
    Copy-SshPublicKey -RemoteHost example.com -IdentityFile ~/.ssh/id_ed25519.pub -Port 2222

    使用指定公钥文件通过 2222 端口推送。
#>
# Copy-SshPublicKey.ps1 - 将本机公钥复制到远程主机 authorized_keys
# 模拟 Linux `ssh-copy-id` 命令,支持指定公钥路径/端口
# 默认自动按 ed25519 > ecdsa > rsa > dsa 顺序查找 ~/.ssh 下的公钥
function Copy-SshPublicKey {
    [CmdletBinding()]
    [OutputType([void])]
param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$RemoteHost,
        [string]$IdentityFile,
        [int]$Port = 22
    )

    # 自动探测默认公钥:ed25519 > ecdsa > rsa > dsa (与 OpenSSH ssh-copy-id 行为一致)
    if (-not $IdentityFile) {
        $sshDir = Join-Path $env:USERPROFILE '.ssh'
        $candidates = @('id_ed25519.pub', 'id_ecdsa.pub', 'id_rsa.pub', 'id_dsa.pub')
        foreach ($name in $candidates) {
            $candidate = Join-Path $sshDir $name
            if (Test-Path $candidate) { $IdentityFile = $candidate; break }
        }
        if (-not $IdentityFile) {
            Write-Error "未在 $sshDir 找到任何默认公钥 (id_ed25519.pub / id_ecdsa.pub / id_rsa.pub / id_dsa.pub),请用 -IdentityFile 显式指定"
            return
        }
    } elseif (-not (Test-Path $IdentityFile)) {
        Write-Error "公钥文件不存在: $IdentityFile"; return
    }

    # 使用 ReadAllText 确保始终以 UTF8 无 BOM 读取，避免 Linux 端乱码
    $key = [System.IO.File]::ReadAllText($IdentityFile)
    Write-Host "[ssh-copy-id] 使用公钥: $IdentityFile" -ForegroundColor DarkGray

    # 重要: 公钥内容中的单引号必须转义，否则远程 sh -c 会断引号导致命令注入
    $escapedKey = ConvertTo-SshEscapedString -Value $key.Trim()

    $sshArgs = @(
        '-p', $Port,
        $RemoteHost,
        "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$escapedKey' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && echo DONE"
    )
    & ssh @sshArgs
    # 必须检查退出码: 追加公钥失败时静默返回会让用户以为已配好, 实际登录仍要密码。
    if ($LASTEXITCODE -ne 0) {
        Write-Error "推送公钥失败 (ssh 退出码 $LASTEXITCODE)，请在远端确认 ~/.ssh/authorized_keys 是否已写入。"
        return
    }
    Write-Host " [OK] 公钥已推送到 $RemoteHost" -ForegroundColor Green
}
