# Copy-SshPublicKey.ps1 - 将本机公钥复制到远程主机 authorized_keys
# 模拟 Linux `ssh-copy-id` 命令,支持指定公钥路径/端口
# 默认自动按 ed25519 > ecdsa > rsa > dsa 顺序查找 ~/.ssh 下的公钥
function Copy-SshPublicKey {
    [CmdletBinding()]
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

    $key = Get-Content $IdentityFile -Raw
    Write-Host "[ssh-copy-id] 使用公钥: $IdentityFile" -ForegroundColor DarkGray
    $sshArgs = @('-p', $Port, $RemoteHost, "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$key' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && echo DONE")
    & ssh @sshArgs
}
