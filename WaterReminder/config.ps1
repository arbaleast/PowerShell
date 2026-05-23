# ============================================================
# WaterReminder 配置
# 独立喝水提醒模块配置
# ============================================================

@{
    # 模块基本信息
    ModuleName      = 'WaterReminder'
    Version         = '1.0.0'
    
    # 功能开关
    Enabled         = $true
    
    # 提醒间隔（分钟）
    IntervalMin     = 60
    
    # 每日目标（ml）
    DayGoalMl       = 2000
    
    # 安静时段（小时，24小时制）
    # 例如：22 到 7 点不提醒
    QuietHoursStart = 22
    QuietHoursEnd   = 7
    
    # 天气感知功能
    WeatherEnabled  = $true
    
    # 数据路径
    DataDir         = '$PSScriptRoot\..\WaterReminder\data'
    HistoryFile     = 'water-history.json'
    
    # 日志路径
    LogDir          = '$PSScriptRoot\..\WaterReminder\logs'
    LogFile         = 'water-reminder.log'
    
    # 每次提醒建议喝水量（ml）
    DefaultDrinkMl  = 250
}