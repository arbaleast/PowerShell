# Test if [Console]::OutputEncoding affects ssh.exe octal output
Write-Host "=== Test: Does setting [Console]::OutputEncoding affect ssh octal output? ==="
Write-Host ""

$hostname = "unraid"
$timeout = 3

# Test A: WITHOUT setting encoding = UTF8 first
Write-Host "--- Test A: Without explicit encoding change ---"
Write-Host ("Current [Console]::OutputEncoding: " + [Console]::OutputEncoding.CodePage)
$psiA = [System.Diagnostics.ProcessStartInfo]::new()
$psiA.FileName = "ssh.exe"
$psiA.Arguments = "-o ConnectTimeout=$timeout $hostname"
$psiA.UseShellExecute = $false
$psiA.RedirectStandardOutput = $true
$psiA.RedirectStandardError = $true
$psiA.CreateNoWindow = $true
# No encoding set
$procA = [System.Diagnostics.Process]::Start($psiA)
$procA.StandardInput.Close()
$errA = $procA.StandardError.ReadToEnd()
$procA.WaitForExit(10000) | Out-Null
$procA.Dispose()
if ($errA -match '\\\d{3}') {
    Write-Host "Test A: Octal escapes PRESENT"
} else {
    Write-Host "Test A: Clean (no octal escapes)"
}

Write-Host ""

# Test B: WITH [Console]::OutputEncoding = UTF8 first
Write-Host "--- Test B: With [Console]::OutputEncoding = UTF8 ---"
$savedEnc = [Console]::OutputEncoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$psiB = [System.Diagnostics.ProcessStartInfo]::new()
$psiB.FileName = "ssh.exe"
$psiB.Arguments = "-o ConnectTimeout=$timeout $hostname"
$psiB.UseShellExecute = $false
$psiB.RedirectStandardOutput = $true
$psiB.RedirectStandardError = $true
$psiB.CreateNoWindow = $true
$procB = [System.Diagnostics.Process]::Start($psiB)
$procB.StandardInput.Close()
$errB = $procB.StandardError.ReadToEnd()
$procB.WaitForExit(10000) | Out-Null
$procB.Dispose()
[Console]::OutputEncoding = $savedEnc
if ($errB -match '\\\d{3}') {
    Write-Host "Test B: Octal escapes PRESENT"
} else {
    Write-Host "Test B: Clean (no octal escapes)"
}

Write-Host ""

# Test C: Set encoding to GBK (936) - can represent Chinese
Write-Host "--- Test C: With [Console]::OutputEncoding = GBK (936) ---"
$savedEnc2 = [Console]::OutputEncoding
[Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(936)
$psiC = [System.Diagnostics.ProcessStartInfo]::new()
$psiC.FileName = "ssh.exe"
$psiC.Arguments = "-o ConnectTimeout=$timeout $hostname"
$psiC.UseShellExecute = $false
$psiC.RedirectStandardOutput = $true
$psiC.RedirectStandardError = $true
$psiC.CreateNoWindow = $true
$procC = [System.Diagnostics.Process]::Start($psiC)
$procC.StandardInput.Close()
$errC = $procC.StandardError.ReadToEnd()
$procC.WaitForExit(10000) | Out-Null
$procC.Dispose()
[Console]::OutputEncoding = $savedEnc2
Write-Host ("stderr length: " + $errC.Length)
if ($errC -match '\\\d{3}') {
    Write-Host "Test C: Octal escapes PRESENT"
} else {
    Write-Host "Test C: CLEAN (no octal escapes, raw Chinese)"
    Write-Host ("stderr: " + $errC)
    # Show hex of first few non-ASCII bytes
    $cBytes = [System.Text.Encoding]::UTF8.GetBytes($errC)
    Write-Host ("UTF8 bytes: " + ($cBytes -join ' '))
}

Write-Host ""
Write-Host "=== Test D: RedirectStandardError = false (stderr goes to console) ==="
$psiD = [System.Diagnostics.ProcessStartInfo]::new()
$psiD.FileName = "ssh.exe"
$psiD.Arguments = "-o ConnectTimeout=$timeout $hostname"
$psiD.UseShellExecute = $false
$psiD.RedirectStandardOutput = $true
$psiD.RedirectStandardError = $false  # stderr goes to console
$psiD.CreateNoWindow = $true
Write-Host "Starting process with stderr NOT redirected..."
$procD = [System.Diagnostics.Process]::Start($psiD)
$outD = $procD.StandardOutput.ReadToEnd()
$procD.WaitForExit(10000) | Out-Null
$procD.Dispose()
Write-Host ("stdout: " + $outD)
Write-Host "stderr went to console (check above for raw output)"

Write-Host ""
Write-Host "=== Summary ==="
Write-Host "Test A (default enc): " + ($errA -match '\\\d{3}' ? 'OCTAL' : 'CLEAN')
Write-Host "Test B (UTF8 enc):    " + ($errB -match '\\\d{3}' ? 'OCTAL' : 'CLEAN')
Write-Host "Test C (GBK enc):     " + ($errC -match '\\\d{3}' ? 'OCTAL' : 'CLEAN')
Write-Host ""
Write-Host "Raw stderr Test A: $errA"
Write-Host "Raw stderr Test B: $errB"
Write-Host "Raw stderr Test C: $errC"
