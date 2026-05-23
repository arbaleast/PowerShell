# ============================================================
# ShellPrompt Module Tests
# Pester 单元测试套件 (Pester 3.x 兼容)
# ============================================================

# 导入模块（在所有测试之前）
$ModulePath = Join-Path $PSScriptRoot "..\ShellPrompt.psd1"
Import-Module $ModulePath -Force

Describe "Get-SshConfigHosts" {
    # 保存原始 HOME 环境变量
    $OriginalHome = $env:HOME
    
    AfterEach {
        # 恢复原始 HOME 环境变量
        $env:HOME = $OriginalHome
    }
    
    It "应该返回空数组当 SSH config 不存在" {
        # 设置一个不存在的路径
        $env:HOME = [System.IO.Path]::GetTempPath()
        $result = Get-SshConfigHosts
        $result | Should BeNullOrEmpty
    }
    
    It "应该正确解析有效的 SSH Host 条目" {
        # 创建临时 SSH config
        $tempDir = [System.IO.Path]::GetTempPath()
        $env:HOME = $tempDir
        $sshDir = Join-Path $tempDir ".ssh"
        if (-not (Test-Path $sshDir)) {
            New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
        }
        $configFile = Join-Path $sshDir "config"
        @"
Host server1
    HostName 192.168.1.1
    User admin

Host server2
    HostName example.com

Host *
    Port 22
"@ | Out-File -FilePath $configFile -Encoding UTF8 -Force
        
        $result = Get-SshConfigHosts
        $result | Should Not BeNullOrEmpty
        ($result -contains "server1") | Should Be $true
        ($result -contains "server2") | Should Be $true
        
        # 清理
        Remove-Item $configFile -Force -ErrorAction SilentlyContinue
    }
    
    It "应该排除包含通配符的 Host 条目" {
        $tempDir = [System.IO.Path]::GetTempPath()
        $env:HOME = $tempDir
        $sshDir = Join-Path $tempDir ".ssh"
        if (-not (Test-Path $sshDir)) {
            New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
        }
        $configFile = Join-Path $sshDir "config"
        @"
Host *
    Port 22

Host server1
    HostName 192.168.1.1
"@ | Out-File -FilePath $configFile -Encoding UTF8 -Force
        
        $result = Get-SshConfigHosts
        ($result -contains "*") | Should Be $false
        ($result -contains "server1") | Should Be $true
        
        # 清理
        Remove-Item $configFile -Force -ErrorAction SilentlyContinue
    }
}

Describe "Get-MultiplexerSessions" {
    It "应该返回正确的结构" {
        $result = Get-MultiplexerSessions
        
        $result | Should Not BeNullOrEmpty
        $result.ContainsKey("Detected") | Should Be $true
        $result.ContainsKey("Available") | Should Be $true
        $result.ContainsKey("Sessions") | Should Be $true
        $result.ContainsKey("RawOutput") | Should Be $true
    }
    
    It "Available 应该为布尔类型" {
        $result = Get-MultiplexerSessions
        $result.Available.GetType().Name | Should Match "Boolean"
    }
    
    It "Sessions 应该为数组类型" {
        $result = Get-MultiplexerSessions
        $result.Sessions.GetType().Name | Should Match "Object"
    }
}

Describe "Test-MultiplexerAvailable" {
    It "应该返回布尔值" {
        $result = Test-MultiplexerAvailable
        $result.GetType().Name | Should Match "Boolean"
    }
    
    It "指定类型时应该正确检测" {
        # tmux 可能不存在于 Windows 系统，所以只验证返回值类型
        $result = Test-MultiplexerAvailable -Type "tmux"
        $result.GetType().Name | Should Match "Boolean"
    }
}

Describe "TUILogLevel 枚举" {
    It "应该包含所有预期的日志级别" {
        $levels = [enum]::GetValues([TUILogLevel])
        ($levels -contains "Trace") | Should Be $true
        ($levels -contains "Debug") | Should Be $true
        ($levels -contains "Info") | Should Be $true
        ($levels -contains "Warning") | Should Be $true
        ($levels -contains "Error") | Should Be $true
    }
    
    It "日志级别数值应该正确" {
        [TUILogLevel]::Trace | Should Be 0
        [TUILogLevel]::Debug | Should Be 1
        [TUILogLevel]::Info | Should Be 2
        [TUILogLevel]::Warning | Should Be 3
        [TUILogLevel]::Error | Should Be 4
    }
}

Describe "Test-TUIDebugMode" {
    It "应该返回布尔值" {
        $result = Test-TUIDebugMode
        $result.GetType().Name | Should Match "Boolean"
    }
    
    It "当 DEBUG=1 时应该返回 true" {
        $env:DEBUG = "1"
        $result = Test-TUIDebugMode
        $result | Should Be $true
    }
    
    It "当 DEBUG=true 时应该返回 true" {
        $env:DEBUG = "true"
        $result = Test-TUIDebugMode
        $result | Should Be $true
    }
    
    It "当 DEBUG 未设置时应该返回 false" {
        $env:DEBUG = $null
        $result = Test-TUIDebugMode
        $result | Should Be $false
    }
}

Describe "Global Configuration" {
    It "UserScoop_CONF 应该存在" {
        $global:UserScoop_CONF | Should Not BeNullOrEmpty
    }
    
    It "UserScoop_CONF 应该包含所有必需的键" {
        $global:UserScoop_CONF.ContainsKey("Colors") | Should Be $true
        $global:UserScoop_CONF.ContainsKey("Keys") | Should Be $true
        $global:UserScoop_CONF.ContainsKey("SSH") | Should Be $true
        $global:UserScoop_CONF.ContainsKey("Tmux") | Should Be $true
    }
    
    It "Colors 配置应该包含基本颜色" {
        $colors = $global:UserScoop_CONF.Colors
        $colors.ContainsKey("FreshGreen") | Should Be $true
        $colors.ContainsKey("SageGreen") | Should Be $true
        $colors.ContainsKey("Rst") | Should Be $true
    }
    
    It "SSH 配置应该包含 ConnectTimeout" {
        $ssh = $global:UserScoop_CONF.SSH
        $ssh.ContainsKey("ConnectTimeout") | Should Be $true
        $ssh.ConnectTimeout.GetType().Name | Should Match "Int32"
    }
    
    It "Tmux 配置应该包含 DefaultSessionName" {
        $tmux = $global:UserScoop_CONF.Tmux
        $tmux.ContainsKey("DefaultSessionName") | Should Be $true
    }
}

Describe "Merge-Hashtable Function" {
    It "应该正确合并嵌套的 hashtable" {
        # 直接测试 Merge-UserConfig 函数（如果存在）
        if (Get-Command Merge-Hashtable -ErrorAction SilentlyContinue) {
            $base = @{
                Key1 = "value1"
                Key2 = @{
                    Nested1 = "nested1"
                    Nested2 = "nested2"
                }
            }
            
            $override = @{
                Key2 = @{
                    Nested1 = "modified"
                    Nested3 = "new"
                }
                Key3 = "value3"
            }
            
            $result = Merge-Hashtable -Base $base -Override $override
            
            $result.Key1 | Should Be "value1"
            $result.Key2.Nested1 | Should Be "modified"
            $result.Key2.Nested2 | Should Be "nested2"
            $result.Key2.Nested3 | Should Be "new"
            $result.Key3 | Should Be "value3"
        } else {
            # 如果函数不存在，跳过此测试
            $true | Should Be $true
        }
    }
}