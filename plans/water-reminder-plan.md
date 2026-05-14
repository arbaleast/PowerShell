# 喝水提醒功能实现计划

## 功能概述

智能喝水提醒系统，基于科学饮水规律，通过 Windows 通知中心定时提醒，并形成用户反馈闭环。

## 核心功能

| 功能 | 说明 |
|------|------|
| 智能提醒 | 定时推送喝水提醒，用户确认后自动延后下次提醒 |
| 每日历史 | 记录每日喝水量，形成历史趋势 |
| 天气感知 | 根据气温/湿度动态调整提醒策略 |

## 系统架构

```
ShellPrompt 模块
├── Public/
│   └── Start-WaterReminder.ps1     # 后台任务入口
├── Private/
│   ├── Initialize-Config.ps1       # 配置管理
│   └── Invoke-WaterReminder.ps1    # 核心提醒逻辑
└── 数据存储
    └── water-history.json          # 每日喝水记录
```

## 智能闭环机制

```
┌──────────┐    提醒    ┌──────────┐    确认    ┌──────────┐
│  系统    │ ────────▶ │  用户    │ ────────▶ │  延后    │
│  提醒    │            │  喝水    │            │  下次    │
└──────────┘            └──────────┘            └──────────┘
     │                                              │
     │  15分钟内确认                                │  延后30分钟
     ▼                                              │
┌──────────┐                                        │
│  达标    │                                        │
│  跳过    │                                        ▼
└──────────┘                                 ┌──────────┐
                                            │  正常    │
                                            │  间隔    │
                                            └──────────┘
```

## 智能提醒规则

| 时段 | 基础间隔 | 文案风格 |
|------|----------|----------|
| 07:00-11:00 | 60分钟 | 晨间问候 · 激活状态 |
| 11:00-17:00 | 45分钟 | 午后工作 · 高效补水 |
| 17:00-22:00 | 60分钟 | 傍晚放松 · 维持平衡 |
| 22:00-07:00 | 不提醒 | 夜间休眠 |

## 天气感知策略

| 温度范围 | 调整系数 | 说明 |
|----------|----------|------|
| < 15°C | ×1.2 | 低温减少排尿，延长间隔 |
| 15-28°C | ×1.0 | 标准间隔 |
| 28-35°C | ×0.7 | 高温加速出汗，缩短间隔 |
| > 35°C | ×0.5 | 极端高温，大幅缩短 |

数据来源：使用 wttr.in 获取当地天气

## 每日目标

- 总量: 2000ml
- 每次提醒建议: ~250ml
- 用户确认后记录实际摄入量

## 数据存储

历史数据存储于 `ShellPrompt/data/water-history.json`:

```json
{
  "2024-01-15": {
    "total": 1800,
    "records": [
      { "time": "08:30", "ml": 250 },
      { "time": "10:15", "ml": 300 }
    ]
  }
}
```

## 实现步骤

### 1. 修改 `Initialize-Config.ps1`

添加 `WaterReminder` 配置:

```powershell
WaterReminder = @{
    Enabled     = $true
    IntervalMin = 60
    DayGoalMl   = 2000
    QuietHours  = @(22, 7)
    WeatherEnabled = $true
}
```

### 2. 新建 `Private/Invoke-WaterReminder.ps1`

核心逻辑:
- 获取当前温度 → 计算调整后间隔
- 生成时段感知文案
- 调用 Windows 通知 `[Windows.UI.Notifications]`
- 写入历史记录

### 3. 新建 `Public/Start-WaterReminder.ps1`

后台任务:
- 主循环 `while ($true)`
- 计算下次提醒时间
- 检测安静时段 → 跳过
- 支持 `[Ctrl+C]` 中断

### 4. 更新 `ShellPrompt.psm1`

导出 `Start-WaterReminder` 函数

### 5. 更新 `README_zh.md`

---

## 文件变更清单

| 文件 | 操作 |
|------|------|
| `ShellPrompt/Private/Initialize-Config.ps1` | 修改 |
| `ShellPrompt/Private/Invoke-WaterReminder.ps1` | 新建 |
| `ShellPrompt/Public/Start-WaterReminder.ps1` | 新建 |
| `ShellPrompt/ShellPrompt.psm1` | 修改 |
| `README_zh.md` | 修改 |