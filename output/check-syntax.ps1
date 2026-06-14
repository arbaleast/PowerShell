$ErrorActionPreference = 'Stop'
$files = @(
    'ShellPrompt\Private\Initialize-Config.ps1',
    'ShellPrompt\Public\Initialize-Environment.ps1',
    'ShellPrompt\CHANGELOG.md'
)
foreach ($f in $files) {
    if ($f -like '*.ps1') {
        $errors = $null
        $tokens = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$errors)
        if ($errors -and $errors.Count -gt 0) {
            Write-Host "PARSE FAIL: $f"
            $errors | ForEach-Object { Write-Host "  $($_.Extent.StartLineNumber):$($_.Extent.StartColumnNumber) - $($_.Message)" }
        } else {
            Write-Host "PARSE OK:   $f"
        }
    } else {
        Write-Host "SKIP:       $f"
    }
}
