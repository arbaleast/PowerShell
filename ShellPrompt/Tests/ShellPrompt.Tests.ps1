<#
.SYNOPSIS
    ShellPrompt 模块 Pester v3/v5 兼容测试套件
#>

# 模块路径：相对于测试目录的父目录
$moduleRoot = (Resolve-Path "$PSScriptRoot\..").Path
$manifestPath = Join-Path $moduleRoot 'ShellPrompt.psd1'

Describe 'Module Import' {

    It '应能成功导入模块' {
        { Import-Module $manifestPath -Force -ErrorAction Stop } | Should Not Throw
    }

    It '导入后模块应可用' {
        Import-Module $manifestPath -Force
        $module = Get-Module ShellPrompt
        $module | Should Not BeNullOrEmpty
        $module.Name | Should Be 'ShellPrompt'
    }
}

Describe 'Command Export' {

    It '应导出 Invoke-Reload' {
        Import-Module $manifestPath -Force
        Get-Command -Module ShellPrompt -Name 'Invoke-Reload' -ErrorAction SilentlyContinue |
            Should Not BeNullOrEmpty
    }

    It '应导出 Show-UserScoopLogo' {
        Import-Module $manifestPath -Force
        Get-Command -Module ShellPrompt -Name 'Show-UserScoopLogo' -ErrorAction SilentlyContinue |
            Should Not BeNullOrEmpty
    }

    It '应导出 Start-TmuxSession' {
        Import-Module $manifestPath -Force
        Get-Command -Module ShellPrompt -Name 'Start-TmuxSession' -ErrorAction SilentlyContinue |
            Should Not BeNullOrEmpty
    }

    It '应导出 Copy-SshPublicKey' {
        Import-Module $manifestPath -Force
        Get-Command -Module ShellPrompt -Name 'Copy-SshPublicKey' -ErrorAction SilentlyContinue |
            Should Not BeNullOrEmpty
    }

    It '不应导出旧命令 reload' {
        Import-Module $manifestPath -Force
        Get-Command -Module ShellPrompt -Name 'reload' -ErrorAction SilentlyContinue |
            Should BeNullOrEmpty
    }

    It '不应导出内部辅助函数' {
        Import-Module $manifestPath -Force
        $privateNames = @(
            'Get-CachedConfig', 'Get-SshConfigHosts', 'Get-TmuxAvailability',
            'Get-TmuxSessions', 'Invoke-ConsoleMenu', 'Invoke-SshCommand',
            'New-RandomSessionName', 'Reset-TerminalMode', 'Start-SshInteractive'
        )
        $exported = @(Get-Command -Module ShellPrompt | Select-Object -ExpandProperty Name)
        foreach ($name in $privateNames) {
            ($exported -notcontains $name) | Should Be $true
        }
    }
}

Describe 'Verb-Noun Compliance' {

    It '所有导出命令的动词应在 Get-Verb 批准列表中' {
        Import-Module $manifestPath -Force
        $approvedVerbs = @(Get-Verb | Select-Object -ExpandProperty Verb)
        $exported = @(Get-Command -Module ShellPrompt)
        foreach ($cmd in $exported) {
            $verb = $cmd.Name -split '-' | Select-Object -First 1
            ($approvedVerbs -contains $verb) | Should Be $true
        }
    }
}

Describe 'Config Access' {

    It '$script:Config 应包含所有域' {
        Import-Module $manifestPath -Force
        $config = & (Get-Module ShellPrompt) { $script:Config }
        $config | Should Not BeNullOrEmpty
        $config.Contains('Colors') | Should Be $true
        $config.Contains('Keys') | Should Be $true
        $config.Contains('Paths') | Should Be $true
        $config.Contains('SSH') | Should Be $true
    }
}
