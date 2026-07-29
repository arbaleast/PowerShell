@{
    Severity = @('Error', 'Warning', 'Information')

    ExcludeRules = @(
        'PSAvoidUsingWriteHost'  # Invoke-ConsoleMenu 和 Show-UserScoopLogo 需要 Write-Host
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
        PSUseCorrectCasing = @{
            Enable = $true
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
