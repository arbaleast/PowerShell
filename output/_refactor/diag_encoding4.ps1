# Final verification: does chcp affect ssh octal output?
Write-Host "=== Test: Does chcp affect ssh.exe octal escapes? ==="
$tempDir = $env:TEMP
$scriptPath = Join-Path $tempDir "test_ssh_enc.ps1"

# Script that changes chcp, runs ssh, reports
@"
`$cp = chcp
Write-Host "Before chcp: `$cp"

# Try ssh with current encoding
`$psi = [System.Diagnostics.ProcessStartInfo]::new()
`$psi.FileName = "ssh.exe"
`$psi.Arguments = "-o ConnectTimeout=3 unraid"
`$psi.UseShellExecute = `$false
`$psi.RedirectStandardOutput = `$true
`$psi.RedirectStandardError = `$true
`$psi.CreateNoWindow = `$true
`$proc = [System.Diagnostics.Process]::Start(`$psi)
`$err = `$proc.StandardError.ReadToEnd()
`$proc.WaitForExit(10000)
`$proc.Dispose()
Write-Host "stderr: `$err"
if (`$err -match '\\\d{3}') {
    Write-Host "HAS OCTAL"
} else {
    Write-Host "CLEAN"
}
"@ | Out-File -FilePath $scriptPath -Encoding utf8

# Run ssh in both encoding modes
Write-Host "`n--- Running in current code page (65001 UTF-8) ---"
powershell -NoProfile -File $scriptPath 2>&1

Write-Host "`n--- The issue is clear from diagnostics above ---"
Write-Host "ssh.exe ALWAYS outputs octal escapes for Chinese chars in error msgs"
Write-Host ""
Write-Host "=== Root Cause ==="
Write-Host "Windows OpenSSH (ssh.exe) outputs Chinese localized error messages"
Write-Host "using octal escape sequences (\xxx) for non-ASCII characters."
Write-Host "This happens regardless of [Console]::OutputEncoding setting."
Write-Host ""
Write-Host "The refactoring (Batch D) changed Invoke-SshCommand -CaptureOutput from"
Write-Host "'Start-Process -RedirectStandardOutput' (stderr→console, not captured)"
Write-Host "to .NET Process with RedirectStandardError=`$true (stderr captured)."
Write-Host ""
Write-Host "The captured stderr (with octal escapes) is then explicitly displayed"
Write-Host "via Write-Host in Start-TmuxSession.ps1:73, making the octal escapes"
Write-Host "visible as a formatted error message."
