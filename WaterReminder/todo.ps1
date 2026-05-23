# ============================================================
# WaterReminder Todo 项目
# 用于跟踪喝水提醒功能的待办事项和 bug 修复
# ============================================================

@{
    # 项目信息
    ProjectName = 'WaterReminder'
    Version     = '1.0.0'
    CreatedDate = '2026-05-22'
    
    # 待办事项
    Todos       = @(
        @{
            Id          = 1
            Title       = '天气 API 错误处理优化'
            Description = '增强天气获取失败时的错误处理，避免网络超时阻塞主流程'
            Priority    = 'high'
            Status      = 'pending'
            Notes       = '当前实现在网络超时时会在 WaitOne 中卡住 5 秒'
        }
        @{
            Id          = 2
            Title       = '历史记录并发写入保护'
            Description = 'Mutex 命名空间回退逻辑在某些环境下可能失败，需要更健壮的处理'
            Priority    = 'high'
            Status      = 'pending'
            Notes       = '观察到在非管理员权限下 Global 命名空间可能创建失败'
        }
        @{
            Id          = 3
            Title       = '通知窗口在后台运行时丢失'
            Description = '当 PowerShell 在后台运行时，Toast 通知可能不会显示'
            Priority    = 'medium'
            Status      = 'pending'
            Notes       = '考虑使用 Task Scheduler 在用户桌面会话中弹出通知'
        }
        @{
            Id          = 4
            Title       = '添加单元测试'
            Description = '为核心函数添加 Pester 测试用例'
            Priority    = 'low'
            Status      = 'pending'
            Notes       = '特别关注历史记录和并发场景'
        }
        @{
            Id          = 5
            Title       = '支持自定义每次喝水量'
            Description = '在提醒确认时可以输入实际喝水量而不是固定 250ml'
            Priority    = 'medium'
            Status      = 'pending'
            Notes       = '需要设计交互式输入界面'
        }
        @{
            Id          = 6
            Title       = '静默时段精确控制'
            Description = '当前安静时段检测在某些边界情况下可能不准确'
            Priority    = 'medium'
            Status      = 'pending'
            Notes       = '特别是跨午夜时段 (如 22:00-07:00) 的处理'
        }
        @{
            Id          = 7
            Title       = '历史数据压缩'
            Description = '自动清理超过 30 天的历史数据，避免 JSON 文件无限增长'
            Priority    = 'low'
            Status      = 'pending'
            Notes       = '在 Add-WaterRecord 中添加清理逻辑'
        }
    )
    
    # 已识别的 Bug
    Bugs        = @(
        @{
            Id          = 'BUG-001'
            Title       = 'ConvertFrom-Json -AsHashtable 在旧版 PowerShell 不兼容'
            Description = 'PowerShell 5.1 不支持 -AsHashtable 参数，导致历史记录解析失败'
            Severity    = 'critical'
            Status      = 'fixed'
            FixedIn     = '1.0.0'
            Workaround  = '使用自定义 ConvertFromJsonCompat 函数兼容旧版'
        }
        @{
            Id          = 'BUG-002'
            Title       = '后台模式下 PID 文件未正确写入'
            Description = '在某些情况下 PID 文件可能包含空值或错误内容'
            Severity    = 'high'
            Status      = 'fixed'
            FixedIn     = '1.0.0'
            Notes       = '已修复，在后台启动前先检查 $PID 可用性'
        }
        @{
            Id          = 'BUG-003'
            Title       = '夜间休眠时间计算错误'
            Description = '当安静时段跨越午夜时，Get-NextActiveTime 计算的下次活跃时间可能偏差'
            Severity    = 'medium'
            Status      = 'pending'
            Notes       = '需要验证 AddDays(1) 在跨午夜场景下的行为'
        }
    )
    
    # 已知限制
    Limitations = @(
        @{
            Title       = '非 Windows 平台支持受限'
            Description = 'Toast 通知和 WinForms NotifyIcon 仅在 Windows 上可用'
            Workaround  = '使用 msg.exe 作为兜底方案'
        }
        @{
            Title       = '网络依赖'
            Description = '天气感知功能依赖 wttr.in API，离线时无法获取'
            Workaround  = '离线时使用默认天气系数 1.0'
        }
        @{
            Title       = '会话隔离'
            Description = '后台运行时无法弹出交互式对话框'
            Workaround  = '使用系统通知代替弹窗'
        }
    )
}