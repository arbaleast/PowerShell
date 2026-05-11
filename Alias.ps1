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
        # 移除已加载的函数，打破懒加载缓存
        Remove-Item Function:\Start-TmuxSession -ErrorAction SilentlyContinue

        . $PROFILE
        Write-Host " [OK] PowerShell Profile Reloaded" -ForegroundColor Green
    }
}
