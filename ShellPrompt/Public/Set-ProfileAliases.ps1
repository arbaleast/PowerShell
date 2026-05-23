# ============================================================
# Set-ProfileAliases.ps1 — 命令行别名
# ============================================================

# 模块级别名注册（从 psm1 移至此统一管理，避免重复注册冲突）
Set-Alias ll Get-ChildItem -ErrorAction SilentlyContinue
Set-Alias which where.exe -ErrorAction SilentlyContinue

function .. {
    Set-Location .. 
}
function ~ {
    Set-Location ~ 
}
