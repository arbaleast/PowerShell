@{
    Severity = @('Error', 'Warning', 'Information')

    ExcludeRules = @(
        'PSAvoidUsingWriteHost'  # Invoke-ConsoleMenu 和 Show-UserScoopLogo 需要 Write-Host
        'PSUseBOMForUnicodeEncodedFile'  # P4-3a: 统一 UTF-8 无 BOM,避免 chcp 65001 + ANSI 转义错位
    )

    Rules = @{
        # P0 级别: 全局变量违规
        PSAvoidUsingGlobalVariables = @{
            Enable = $true
        }

        # Verb-Noun 合规
        PSUseApprovedVerbs = @{
            Enable = $true
        }

        # 正确的大小写
        # 已知上游缺陷: PSScriptAnalyzer 1.25.0 的 PSUseCorrectCasing 在解析"命令参数元数据"
        # 时会实例化 PwshSpectreConsole 的动态 ValidateSet 值生成器
        # (IValidateSetValuesGenerator, 见 Modules/PwshSpectreConsole/2.6.3/PwshSpectreConsole.psm1),
        # 该生成器需要 Runspace, 而 PSSA 在无 Runspace 的线程中调用 ->
        # "There is no Runspace available to run scripts in this thread", 整个文件的扫描结果作废。
        # 触发命令: Write-SpectreHost / Format-SpectreTable / Invoke-SpectreCommandWithStatus 等
        # (仅当被扫描文件调用了这些函数时才会踩到)。
        # 取舍: 关闭"命令名/参数名大小写检查"(CheckCommands), 保留关键字/操作符/别名大小写检查。
        # 恢复命令名大小写检查的方法: 临时把 Modules/PwshSpectreConsole 移出模块搜索路径,
        # 或用 -IncludeRule PSUseCorrectCasing 扫描不调用 Spectre 函数的文件。
        PSUseCorrectCasing = @{
            Enable = $true
            CheckCommands = $false
        }

        # 应包含帮助注释
        PSProvideCommentHelp = @{
            Enable = $true
            ExportedOnly = $true
        }

        # 缺少 OutputType 注解
        PSUseOutputTypeCorrectly = @{
            Enable = $true
        }

        # ShouldProcess 用于状态变更函数
        PSUseShouldProcessForStateChangingFunctions = @{
            Enable = $true
        }

        # 避免使用别名
        PSAvoidUsingCmdletAliases = @{
            Enable = $true
        }
    }
}
