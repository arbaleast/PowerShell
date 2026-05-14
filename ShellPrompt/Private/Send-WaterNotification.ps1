# Send-WaterNotification.ps1 - 喝水提醒通知发送（独立脚本）
# 被 Invoke-WaterReminder 调用，在后台静默发送通知
# 优先级: WinForms NotifyIcon BalloonTip > msg.exe (兜底)

param(
    [string]$Title = "💧 喝水提醒",
    [string]$Body = "该喝水了！",
    [int]$Interval = 60
)

# ─────────────────────────────────────────────────────────
# 方案 1: WinForms NotifyIcon BalloonTip（优先 — 无模块依赖）
# ─────────────────────────────────────────────────────────
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop

    $notify = New-Object System.Windows.Forms.NotifyIcon
    $notify.Icon = [System.Drawing.SystemIcons]::Information
    $notify.Visible = $true
    $notify.ShowBalloonTip(5000, $Title, $Body, [System.Windows.Forms.ToolTipIcon]::Info)

    # 等待气泡显示足够时间后自动清理
    Start-Sleep -Seconds 6
    $notify.Visible = $false
    $notify.Dispose()
    exit 0
} catch {
    # 继续降级
}

# ─────────────────────────────────────────────────────────
# 方案 2: msg.exe 系统消息（最可靠的兜底方案）
# ─────────────────────────────────────────────────────────
try {
    $cleanTitle = $Title -replace '[^\x20-\x7E\u4e00-\u9fff]', ''  # 移除 emoji
    $cleanBody = $Body -replace '[^\x20-\x7E\u4e00-\u9fff]', ''
    $message = "$cleanTitle`r`n$cleanBody`r`n下次提醒: $Interval 分钟后"
    Start-Process msg -ArgumentList "$env:USERNAME", $message -WindowStyle Hidden -ErrorAction SilentlyContinue
    exit 0
} catch {
    # 所有方案均失败，静默退出
}

exit 0
