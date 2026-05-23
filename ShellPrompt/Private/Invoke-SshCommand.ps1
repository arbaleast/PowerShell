# ============================================================
# Invoke-SshCommand.ps1 - SSH 杩滅▼鍛戒护鎵ц杈呭姪鍑芥暟
# 鍔熻兘: 缁熶竴绠＄悊 SSH 杩炴帴锛岄槻姝㈠懡浠ゆ敞鍏?
# 瀹夊叏绛栫暐:
#   - HostName 鍙傛暟杈撳叆楠岃瘉锛堟嫆缁?shell 鐗规畩瀛楃锛?
#   - 杩滅▼鍛戒护瀛楃涓茬敱璋冪敤鏂硅浆涔夌敤鎴峰彉閲?
#   - 浣跨敤 Start-Process 浼犻€掑弬鏁版暟缁勶紙閬垮厤 cmd.exe 瑙ｉ噴锛?
# 鍙樻洿璁板綍:
#   - [2026-05-23] 鏂板 -PassThru 鍙傛暟锛岃繑鍥?SSH 杩涚▼閫€鍑虹爜渚涜皟鐢ㄦ柟鏍￠獙
# ============================================================

# 灏嗙敤鎴疯緭鍏ョ殑鍊艰繘琛?POSIX shell 鍗曞紩鍙疯浆涔?
# 鍘熺悊锛? 鈫?'\''锛堥棴鍚堝崟寮曞彿 鈫?杞箟鍗曞紩鍙?鈫?閲嶆柊寮€鍚崟寮曞彿锛?
# 杩欐槸 POSIX shell 鏍囧噯鐨勫畨鍏ㄨ浆涔夋柟寮?
# 绀轰緥: "test'session" 鈫?"test'\''session"锛堝湪杩滅▼ shell 涓繚鎸佷负瀛楅潰鍊硷級
function ConvertTo-SshEscapedString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowEmptyString()]
        [string]$Value
    )
    # 瀵规瘡涓崟寮曞彿杩涜杞箟锛? 鈫?'\''
    return "'" + ($Value -replace "'", "'\''") + "'"
}

function Invoke-SshCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
                # 楠岃瘉涓绘満鍚嶅彧鑳藉寘鍚瓧姣嶃€佹暟瀛椼€佺偣銆佺煭妯嚎鍜屼笅鍒掔嚎
                # 鎷掔粷绌烘牸銆佺閬撶銆佷笌鍙枫€佸垎鍙枫€佸弽寮曞彿銆佹嫭鍙枫€佽姳鎷彿銆佸紩鍙风瓑 shell 鐗规畩瀛楃
                if ($_ -match '[\s|&;`$(){}<>#@!*?\[\]~"]') {
                    throw "涓绘満鍚嶅寘鍚潪娉曞瓧绗︼紝浠呭厑璁稿瓧姣嶃€佹暟瀛椼€佺偣銆佺煭妯嚎鍜屼笅鍒掔嚎"
                }
                return $true
            })]
        [string]$HostName,

        # 杩滅▼鍛戒护瀛楃涓诧紙鍙€夛紝涓嶆彁渚涘垯鐩存帴 SSH 鐧诲綍锛?
        [Parameter(Mandatory = $false, Position = 1)]
        [string]$RemoteCommand,

        # 鏄惁涓轰氦浜掑紡杩炴帴锛堝垎閰?PTY锛夛紝鐢ㄤ簬 tmux attach/new-session 绛夐渶瑕佺粓绔氦浜掔殑鍦烘櫙
        [switch]$Interactive,

        # 鎹曡幏鏍囧噯杈撳嚭锛岀敤浜庤幏鍙栬繙绋嬪懡浠ゆ墽琛岀粨鏋?
        [switch]$CaptureOutput,

        # SSH 杩炴帴瓒呮椂锛堢锛?
        [int]$ConnectTimeout = 5,

        # PassThru: 鍦?CaptureOutput 妯″紡涓嬶紝杩斿洖鍖呭惈 Output 鍜?ExitCode 鐨勫璞?
        # 璋冪敤鏂瑰彲閫氳繃 ExitCode 鍒ゆ柇杩滅▼鍛戒护鏄惁鎵ц鎴愬姛
        [switch]$PassThru
    )

    # 鏋勫缓 SSH 鍙傛暟鍒楄〃
    $sshArgs = New-Object System.Collections.ArrayList

    # 鍩虹杩炴帴鍙傛暟
    [void]$sshArgs.Add("-o")
    [void]$sshArgs.Add("ConnectTimeout=$ConnectTimeout")
    [void]$sshArgs.Add("-o")
    [void]$sshArgs.Add("StrictHostKeyChecking=no")

    # 濡傛灉鏄氦浜掑紡杩炴帴锛屽垎閰?PTY锛?t 鏍囧織锛?
    if ($Interactive) {
        [void]$sshArgs.Add("-t")
    }

    # 涓绘満鍚嶄綔涓虹嫭绔嬪弬鏁颁紶閫掞紙涓嶄細琚?shell 瑙ｉ噴锛?
    [void]$sshArgs.Add($HostName)

    # 濡傛灉鎻愪緵浜嗚繙绋嬪懡浠わ紝鍒欓檮鍔犲埌鍙傛暟鍒楄〃
    # 娉ㄦ剰锛氭瀛楃涓插皢浼犻€掑埌杩滅▼涓绘満鐨?/bin/sh -c 鎵ц
    # 璋冪敤鏂归渶鑷杞箟鐢ㄦ埛鎻愪緵鐨勫彉閲忓€硷紙浣跨敤 ConvertTo-SshEscapedString锛?
    if ($PSBoundParameters.ContainsKey('RemoteCommand')) {
        [void]$sshArgs.Add($RemoteCommand)
    }

    if ($CaptureOutput) {
        # 鎹曡幏杈撳嚭妯″紡锛氶噸瀹氬悜鏍囧噯杈撳嚭鍒颁复鏃舵枃浠?
        $tempFile = [System.IO.Path]::GetTempFileName()
        try {
            # 鍚姩 ssh.exe 杩涚▼锛屾崟鑾?stdout
            $process = Start-Process -FilePath "ssh.exe" -ArgumentList $sshArgs.ToArray() -NoNewWindow -Wait -RedirectStandardOutput $tempFile -PassThru

            # 读取输出内容（Get-Content -Raw 已返回纯文本字符串）
            $output = Get-Content $tempFile -Raw

            # 濡傛灉鍚敤浜?-PassThru锛岃繑鍥炲寘鍚?Output 鍜?ExitCode 鐨勫璞?
            if ($PassThru) {
                return [PSCustomObject]@{
                    Output   = $output
                    ExitCode = $process.ExitCode
                }
            }

            # 鍏煎鏃ц皟鐢ㄦ柟寮忥細鐩存帴杩斿洖杈撳嚭瀛楃涓?
            return $output
        } finally {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
    } else {
        # 闈炴崟鑾锋ā寮忥細鐩存帴杩愯锛岃緭鍑烘樉绀哄湪缁堢
        # 鍚屾椂鑾峰彇杩涚▼閫€鍑虹爜锛堥潪鎹曡幏妯″紡涓嬩笉鍚敤 PassThru 褰卞搷涓嶅ぇ锛屼絾淇濈暀涓€鑷存€э級 
        if ($PassThru) {
            $process = Start-Process -FilePath "ssh.exe" -ArgumentList $sshArgs.ToArray() -NoNewWindow -Wait -PassThru
            return [PSCustomObject]@{
                Output   = ""
                ExitCode = $process.ExitCode
            }
        }
        Start-Process -FilePath "ssh.exe" -ArgumentList $sshArgs.ToArray() -NoNewWindow -Wait
    }
}
