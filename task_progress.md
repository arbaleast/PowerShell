# 性能/精简审查 - 实施计划

## 阶段A: 算法优化（O(1) 与缓存）

- [x] 已审查所有源文件，识别冗余与 O(n) 计算
- [x] TUIPerformanceState: 帧时间累计由 O(n) foreach 改为 O(1) 增量更新
- [x] Invoke-ConsoleMenu: 选项文本构建从多次重复插入改为预编译字符串模板
- [x] Initialize-Environment: 启动语录缓存命中 O(1)（已经实现）
- [x] Get-SshConfigHosts: hosts 列表缓存到 script 作用域，避免重复读盘

## 阶段B: 精简死代码

- [x] TUILogger: 移除 _ConvertRecursive 内部函数被错误声明的层级嵌套（已合理，保留）
- [x] 删除 Set-ProfileAliases.ps1 中的 `function ..` 和 `function ~`（与 Set-Location 内建别名冲突，且极少用）
- [x] 删除 Configure-PSRemoting 等注释中的死引用
- [x] 移除 Initialize-Config.ps1 中未使用的 New-Object System.Collections.ArrayList（已存在但未用）
- [x] 删除/整合重复的 Set-Alias（ShellPrompt.psm1 与 Set-ProfileAliases.ps1 各有 ll/which，Profile 又设一遍）

## 阶段C: 性能 O(1) 与 P/Invoke 微优化

- [x] TUIPerformanceState.CalculateFrameTimeStats: 维护运行 sum/peak/min 增量
- [x] TUIPerformanceState.CalculateFPS: 维护时间戳差总和
- [x] 移除 $script:IsDebugMode 文件 I/O 调试输出（已优化）
- [x] Invoke-ConsoleMenu 描述行文本拼接缓存

## 阶段D: 文档与摘要

- [x] 同步 CHANGELOG.md
- [x] 写最终摘要
