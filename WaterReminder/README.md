# WaterReminder - 智能喝水提醒模块

独立的 PowerShell 喝水提醒模块，支持天气感知、时段智能提醒、历史记录追踪。

## 目录结构

```
WaterReminder/
├── WaterReminder.psm1   # 核心模块
├── config.ps1           # 配置文件
├── todo.ps1             # 待办事项和 bug 追踪
├── data/                # 数据目录
│   └── water-history.json
└── logs/                # 日志目录
    └── water-reminder.log
```

## 快速开始

```powershell
# 导入模块
Import-Module ./WaterReminder/WaterReminder.psm1

# 发送一次提醒
Invoke-WaterReminder

# 查看状态
Get-WaterReminderStatus

# 查看历史
Get-WaterReminderHistory -Days 7

# 启动后台守护进程
Start-WaterReminderDaemon -Background

# 停止后台守护进程
Stop-WaterReminderDaemon
```

## 核心功能

| 功能 | 说明 |
|------|------|
| 天气感知 | 根据气温动态调整提醒间隔 |
| 时段智能 | 不同时间段使用不同文案 |
| 历史追踪 | 记录每日喝水量 |
| 多通知渠道 | Toast > WinForms > msg.exe |

## 天气调整策略

| 温度范围 | 调整系数 | 说明 |
|----------|----------|------|
| < 15°C | ×1.2 | 低温减少排尿，延长间隔 |
| 15-28°C | ×1.0 | 标准间隔 |
| 28-35°C | ×0.7 | 高温加速出汗，缩短间隔 |
| > 35°C | ×0.5 | 极端高温，大幅缩短 |

## 配置

编辑 `config.ps1` 文件修改以下配置：

```powershell
Enabled = $true              # 功能开关
IntervalMin = 60             # 基础提醒间隔（分钟）
DayGoalMl = 2000             # 每日目标（ml）
QuietHoursStart = 22         # 安静时段开始
QuietHoursEnd = 7            # 安静时段结束
WeatherEnabled = $true       # 天气感知开关
DefaultDrinkMl = 250         # 每次建议喝水量
```

## 待办事项

详见 [todo.ps1](todo.ps1)
