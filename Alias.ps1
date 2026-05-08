Set-Alias ll Get-ChildItem
Set-Alias which where.exe

function .. { Set-Location .. }
function ~  { Set-Location ~ }

function reload {
    if (Test-Path $PROFILE) {
        . $PROFILE
        Write-Host " [OK] Hermes G7 Reloaded" -ForegroundColor Green
    }
}
