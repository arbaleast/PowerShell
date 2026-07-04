# Detailed encoding trace: where do octal escapes come from?
Write-Host "=== Detailed Encoding Trace ==="
Write-Host ""

# Test 1: Direct ssh.exe call with 2>&1 - reproduce octal
Write-Host "=== Test 1: ssh 2>&1 capture ==="
$result = ssh -o ConnectTimeout=3 unraid 2>&1
Write-Host ("Type of result: " + $result.GetType().FullName)
Write-Host ("Result count: " + $result.Count)
if ($result -is [array]) {
    for ($i = 0; $i -lt $result.Count; $i++) {
        $item = $result[$i]
        Write-Host ("[$i] Type: " + $item.GetType().FullName)
        Write-Host ("[$i] ToString: " + $item.ToString())
        if ($item -is [System.Management.Automation.ErrorRecord]) {
            Write-Host ("[$i] Exception: " + $item.Exception.Message)
            Write-Host ("[$i] TargetObject: " + ($item.TargetObject -join ' '))
        }
    }
}

Write-Host ""
Write-Host "=== Test 2: .NET Process capture (same as Invoke-SshCommand -CaptureOutput) ==="
$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.FileName = "ssh.exe"
$psi.Arguments = "-o ConnectTimeout=3 unraid"
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$psi.StandardErrorEncoding = [System.Text.Encoding]::Default
$psi.StandardOutputEncoding = [System.Text.Encoding]::Default

$proc = [System.Diagnostics.Process]::Start($psi)
$proc.StandardInput.Close()
$outTask = $proc.StandardOutput.ReadToEndAsync()
$errTask = $proc.StandardError.ReadToEndAsync()

if (-not $proc.WaitForExit(15000)) {
    try { $proc.Kill() } catch {}
    $proc.WaitForExit(2000) | Out-Null
}

$drainMs = 2000
if (-not $outTask.Wait($drainMs)) { $outTask = $null }
if (-not $errTask.Wait($drainMs)) { $errTask = $null }
$output = if ($outTask) { $outTask.Result } else { '' }
$errOut = if ($errTask) { $errTask.Result } else { '' }
$exitCode = $proc.ExitCode
$proc.Dispose()

Write-Host ("ExitCode: " + $exitCode)
Write-Host ("stdout length: " + $output.Length)
Write-Host ("stderr length: " + $errOut.Length)
Write-Host ("stderr: " + $errOut)

# Check if stderr contains octal escapes
if ($errOut -match '\\\d{3}') {
    Write-Host "STDERR CONTAINS OCTAL ESCAPES via .NET Process!"
} else {
    Write-Host "stderr is CLEAN (no octal escapes) via .NET Process"
    Write-Host "stderr hex bytes: "
    $stderrBytes = [System.Text.Encoding]::Unicode.GetBytes($errOut)
    for ($i = 0; $i -lt [Math]::Min($stderrBytes.Length, 200); $i += 2) {
        $charCode = [BitConverter]::ToUInt16($stderrBytes, $i)
        Write-Host ("  U+{0:X4} ({1})" -f $charCode, [char]$charCode)
    }
}

Write-Host ""
Write-Host "=== Test 3: .NET Process with explicit UTF8 encoding for stderr ==="
$psi2 = [System.Diagnostics.ProcessStartInfo]::new()
$psi2.FileName = "ssh.exe"
$psi2.Arguments = "-o ConnectTimeout=3 unraid"
$psi2.UseShellExecute = $false
$psi2.RedirectStandardOutput = $true
$psi2.RedirectStandardError = $true
$psi2.CreateNoWindow = $true
$psi2.StandardErrorEncoding = [System.Text.Encoding]::UTF8
$psi2.StandardOutputEncoding = [System.Text.Encoding]::UTF8

$proc2 = [System.Diagnostics.Process]::Start($psi2)
$proc2.StandardInput.Close()
$outTask2 = $proc2.StandardOutput.ReadToEndAsync()
$errTask2 = $proc2.StandardError.ReadToEndAsync()

if (-not $proc2.WaitForExit(15000)) {
    try { $proc2.Kill() } catch {}
    $proc2.WaitForExit(2000) | Out-Null
}

$drainMs2 = 2000
if (-not $outTask2.Wait($drainMs2)) { $outTask2 = $null }
if (-not $errTask2.Wait($drainMs2)) { $errTask2 = $null }
$output2 = if ($outTask2) { $outTask2.Result } else { '' }
$errOut2 = if ($errTask2) { $errTask2.Result } else { '' }
$proc2.Dispose()

Write-Host ("stderr with UTF8: " + $errOut2)
if ($errOut2 -match '\\\d{3}') {
    Write-Host "UTF8 stderr CONTAINS OCTAL ESCAPES"
} else {
    Write-Host "UTF8 stderr is CLEAN"
}

Write-Host ""
Write-Host "=== Test 4: Raw bytes of ssh stderr ==="
$psi3 = [System.Diagnostics.ProcessStartInfo]::new()
$psi3.FileName = "ssh.exe"
$psi3.Arguments = "-o ConnectTimeout=3 unraid"
$psi3.UseShellExecute = $false
$psi3.RedirectStandardOutput = $true
$psi3.RedirectStandardError = $true
$psi3.CreateNoWindow = $true
# Don't set StandardErrorEncoding - read raw bytes directly

$proc3 = [System.Diagnostics.Process]::Start($psi3)
$proc3.StandardInput.Close()
# Read raw bytes from stderr
$rawStream = $proc3.StandardError.BaseStream
$rawBytes = New-Object byte[] 4096
$bytesRead = $rawStream.Read($rawBytes, 0, $rawBytes.Length)
$proc3.WaitForExit(5000) | Out-Null
$proc3.Dispose()

if ($bytesRead -gt 0) {
    Write-Host ("Raw bytes read: " + $bytesRead)
    Write-Host ("Raw bytes (hex): " + (($rawBytes[0..($bytesRead-1)] | ForEach-Object { '{0:X2}' -f $_ }) -join ' '))
    Write-Host ("Raw bytes (decimal): " + (($rawBytes[0..($bytesRead-1)]) -join ' '))
    
    # Try decoding as UTF-8
    $utf8Decoded = [System.Text.Encoding]::UTF8.GetString($rawBytes, 0, $bytesRead)
    Write-Host ("Decoded as UTF-8: " + $utf8Decoded)
    
    # Try decoding as GBK (CP936)
    try {
        $gbkDecoded = [System.Text.Encoding]::GetEncoding(936).GetString($rawBytes, 0, $bytesRead)
        Write-Host ("Decoded as GBK: " + $gbkDecoded)
    } catch {
        Write-Host ("GBK decode error: " + $_.Exception.Message)
    }
} else {
    Write-Host "No raw bytes read from stderr"
}
