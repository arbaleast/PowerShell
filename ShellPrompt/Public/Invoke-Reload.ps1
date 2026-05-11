# ============================================================
# Invoke-Reload.ps1 — 重载 PowerShell 配置
# ============================================================

function reload
{
    if (Test-Path $PROFILE)
    {
        Remove-Module ShellPrompt -Force -ErrorAction SilentlyContinue
        . $PROFILE
        Write-Host " [OK] PowerShell Profile Reloaded" -ForegroundColor Green
    }
}
