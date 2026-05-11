Set-Alias ll Get-ChildItem
Set-Alias which where.exe

function ..
{ Set-Location ..
}
function ~
{ Set-Location ~
}

function reload
{
    if (Test-Path $PROFILE)
    {
        # 卸载整个模块，打破模块缓存
        Remove-Module ShellPrompt -Force -ErrorAction SilentlyContinue

        . $PROFILE
        Write-Host " [OK] PowerShell Profile Reloaded" -ForegroundColor Green
    }
}
