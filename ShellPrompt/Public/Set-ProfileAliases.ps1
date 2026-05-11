# ============================================================
# Set-ProfileAliases.ps1 — 命令行别名
# ============================================================

Set-Alias ll Get-ChildItem
Set-Alias which where.exe

function ..
{ Set-Location .. 
}
function ~
{ Set-Location ~ 
}
