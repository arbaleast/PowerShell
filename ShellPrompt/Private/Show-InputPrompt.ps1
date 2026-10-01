# Show-InputPrompt.ps1 - 输入提示组件
# P2-3: 支持默认值/校验/取消的交互式输入
# 设计原则:
# 1. 纯函数 Update-InputBuffer + Test-InputValidation 可被 Pester 单元测试
# 2. Show-InputPrompt 真实交互, 自动降级 Read-Host (ReadKey 失败时)
# 3. 不在 try/finally 之外改变 Console state; 调用方负责保存/恢复
# 4. 输出是结构化对象: { Value, Cancelled, Valid, ValidationMessage } 便于调用方判断

# 缓冲区状态机: 每次按键后计算下一个状态
#   Continue  = 继续接收输入
#   Submit    = Enter 提交
#   Cancel    = Esc/Ctrl+C 取消
$script:InputStateValues = @('Continue', 'Submit', 'Cancel')


function Update-InputBuffer {
    <#
    .SYNOPSIS
        根据按键事件计算输入缓冲区下一个状态(纯函数)

    .DESCRIPTION
        按键类型:
          - 'Char':      普通字符,追加到 Buffer(经 MaxLength 截断)
          - 'Backspace': 删除 Buffer 末尾字符
          - 'Ctrl+U':    清空整个 Buffer
          - 'Enter':     提交(不修改 Buffer)
          - 'Escape':    取消
          - 'Ctrl+C':    取消

    .PARAMETER Buffer
        当前缓冲区内容

    .PARAMETER Key
        按键类型(见上)

    .PARAMETER Char
        当 Key='Char' 时要追加的字符

    .PARAMETER MaxLength
        缓冲区最大长度(默认 256); 'Char' 时若 Buffer.Length >= MaxLength 则丢弃字符

    .OUTPUTS
        [PSCustomObject]@{ Buffer=string; State=string; Key=string }
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    [OutputType([PSCustomObject])]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '')]
param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Buffer = '',

        [Parameter(Mandatory = $true)]
        [ValidateSet('Char', 'Backspace', 'Ctrl+U', 'Enter', 'Escape', 'Ctrl+C')]
        [string]$Key,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Char = '',

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 4096)]
        [int]$MaxLength = 256
    )

    switch ($Key) {
        'Char' {
            $newBuf = $Buffer + $Char
            if ($newBuf.Length -gt $MaxLength) {
                # 超出长度: 丢弃该字符, 保持 Buffer 不变
                $newBuf = $Buffer
            }
            return [PSCustomObject]@{
                Buffer = $newBuf
                State  = 'Continue'
                Key    = $Key
            }
        }
        'Backspace' {
            if ($Buffer.Length -gt 0) {
                $newBuf = $Buffer.Substring(0, $Buffer.Length - 1)
            } else {
                $newBuf = $Buffer
            }
            return [PSCustomObject]@{
                Buffer = $newBuf
                State  = 'Continue'
                Key    = $Key
            }
        }
        'Ctrl+U' {
            return [PSCustomObject]@{
                Buffer = ''
                State  = 'Continue'
                Key    = $Key
            }
        }
        'Enter' {
            return [PSCustomObject]@{
                Buffer = $Buffer
                State  = 'Submit'
                Key    = $Key
            }
        }
        default {
            # 'Escape' / 'Ctrl+C'
            return [PSCustomObject]@{
                Buffer = $Buffer
                State  = 'Cancel'
                Key    = $Key
            }
        }
    }
}

function Test-InputValidation {
    <#
    .SYNOPSIS
        对输入值执行校验(纯函数, 调用方提供 validator 脚本块)

    .DESCRIPTION
        校验器签名为: param($value) 返回 $true / $false / 带 Message 的 hashtable
        简化返回: 返回 hashtable @{ Valid=$true/$false; Message=string }
        - Valid=$true 时 Message 可空
        - Valid=$false 时 Message 必填, 用于回显给用户

    .PARAMETER Value
        待校验的输入值

    .PARAMETER Validator
        校验脚本块; 不传时返回 Valid=$true (无校验)
        脚本块可以返回:
          - $true / $false (无 message)
          - @{ Valid=$true/$false; Message='...' }

    .OUTPUTS
        [PSCustomObject]@{ Valid=[bool]; Message=[string] }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value = '',

        [Parameter(Mandatory = $false)]
        [scriptblock]$Validator
    )

    if (-not $Validator) {
        return [PSCustomObject]@{ Valid = $true; Message = '' }
    }

    try {
        $result = & $Validator $Value
    } catch {
        # 校验器自身抛异常: 视为校验失败, 把异常信息作为 Message
        return [PSCustomObject]@{
            Valid   = $false
            Message = "校验器错误: $($_.Exception.Message)"
        }
    }

    if ($result -is [bool]) {
        return [PSCustomObject]@{
            Valid   = $result
            Message = ''
        }
    }
    if ($result -is [hashtable] -or $result -is [System.Collections.IDictionary]) {
        $valid = [bool]$result['Valid']
        $msg   = if ($result.ContainsKey('Message')) { [string]$result['Message'] } else { '' }
        return [PSCustomObject]@{
            Valid   = $valid
            Message = $msg
        }
    }
    # 其他返回: 隐式 True(真值), 无 message
    return [PSCustomObject]@{
        Valid   = [bool]$result
        Message = ''
    }
}

function Show-InputPrompt {
    <#
    .SYNOPSIS
        交互式输入提示(支持默认值/实时校验/取消)

    .DESCRIPTION
        真实 I/O: 主路径用 [Console]::ReadKey() 逐字符读取(支持 Backspace/Esc 实时反馈),
        ReadKey 失败(非交互式终端/Pester redirect)时自动降级到 Read-Host。

        返回对象:
          [PSCustomObject]@{
              Value              = [string]  最终输入值
              Cancelled          = [bool]    用户是否按了 Esc/Ctrl+C
              Valid              = [bool]    是否通过校验(取消时为 $false)
              ValidationMessage  = [string]  校验失败信息
          }

    .PARAMETER Prompt
        提示前缀文本(显示在输入前, e.g. "请输入主机名: ")

    .PARAMETER Default
        默认值; 用户未输入直接回车时使用

    .PARAMETER Validator
        校验脚本块(签名见 Test-InputValidation)

    .PARAMETER MaxLength
        输入最大长度(默认 256)

    .PARAMETER Secret
        安全输入模式: 屏幕显示 * 替代实际字符(用于密码/Token 输入)

    .OUTPUTS
        [PSCustomObject]@{ Value, Cancelled, Valid, ValidationMessage }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [Parameter(Mandatory = $false)]
        [string]$Default = '',

        [Parameter(Mandatory = $false)]
        [scriptblock]$Validator,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 4096)]
        [int]$MaxLength = 256,

        [Parameter(Mandatory = $false)]
        [switch]$Secret
    )

    $primary = Get-CachedConfig -Section 'Colors' -Key 'FreshGreen' -Default "`e[38;2;137;209;133m"
    $muted   = Get-CachedConfig -Section 'Colors' -Key 'MidGray'    -Default "`e[38;2;100;100;100m"
    $errorC  = "`e[38;2;220;80;80m"
    $rst     = Get-CachedConfig -Section 'Colors' -Key 'Rst'        -Default "`e[0m"

    $buffer = ''

    # 主路径: 尝试 [Console]::ReadKey 逐字符
    $useReadKey = $true
    try {
        # 测试 console 是否可用
        $null = [Console]::CursorLeft
    } catch {
        $useReadKey = $false
    }

    if ($useReadKey) {
        # 打印 prompt 前缀(换行保留可读性)
        [Console]::Write("${primary}${Prompt}${rst}")
        $state = 'Continue'
        try {
            while ($state -eq 'Continue') {
                $key = [Console]::ReadKey($true)  # $true = 不回显
                $keyKind = 'Char'
                $ch = ''
                switch ($key.Key) {
                    'Enter'        { $keyKind = 'Enter' }
                    'Escape'       { $keyKind = 'Escape' }
                    'Backspace'    { $keyKind = 'Backspace' }
                    'C' {
                        # Ctrl+C
                        if (($key.Modifiers -band [ConsoleModifiers]::Control) -ne 0) {
                            $keyKind = 'Ctrl+C'
                        } else {
                            $keyKind = 'Char'; $ch = 'c'
                        }
                    }
                    'U' {
                        if (($key.Modifiers -band [ConsoleModifiers]::Control) -ne 0) {
                            $keyKind = 'Ctrl+U'
                        } else {
                            $keyKind = 'Char'; $ch = 'u'
                        }
                    }
                    default {
                        $keyKind = 'Char'
                        $ch = [string]$key.KeyChar
                        # 过滤控制字符(ASCII < 32 且非已处理键)
                        if ([int]$ch[0] -lt 32) { continue }
                    }
                }
                $result = Update-InputBuffer -Buffer $buffer -Key $keyKind -Char $ch -MaxLength $MaxLength
                $buffer = $result.Buffer
                $state  = $result.State

                # 回显: 普通模式原字符, Secret 模式 *
                if ($keyKind -eq 'Backspace') {
                    [Console]::Write("`b `b")  # 退格+空格+退格, 抹除末字符
                } elseif ($keyKind -eq 'Char' -and $ch) {
                    if ($Secret) {
                        [Console]::Write('*')
                    } else {
                        [Console]::Write($ch)
                    }
                } elseif ($keyKind -eq 'Ctrl+U') {
                    # 清行: \r 回行首 + \e[K 清行尾
                    [Console]::Write("`r${primary}${Prompt}${rst}`e[K")
                }
            }
        } catch {
            # ReadKey 失败: 切换到降级路径
            $useReadKey = $false
            $buffer = ''
        }
    }

    if (-not $useReadKey) {
        # 降级路径: Read-Host
        $defaultSuffix = if ($Default) { " [默认: $Default]" } else { '' }
        $read = Read-Host "${Prompt}${muted}${defaultSuffix}${rst}"
        if ([string]::IsNullOrEmpty($read)) {
            $buffer = $Default
        } else {
            $buffer = $read
        }
    } else {
        # 主路径提交后换行
        [Console]::WriteLine('')
    }

    # 处理 Cancel
    if ($state -eq 'Cancel') {
        [Console]::WriteLine("${muted}(已取消)${rst}")
        return [PSCustomObject]@{
            Value             = $buffer
            Cancelled         = $true
            Valid             = $false
            ValidationMessage = ''
        }
    }

    # Enter 提交: 若为空且有 Default, 用 Default
    if ([string]::IsNullOrEmpty($buffer) -and $Default) {
        $buffer = $Default
    }

    # 校验
    $check = Test-InputValidation -Value $buffer -Validator $Validator
    if (-not $check.Valid) {
        [Console]::WriteLine("${errorC}✗ 校验失败: $($check.Message)${rst}")
    }

    return [PSCustomObject]@{
        Value             = $buffer
        Cancelled         = $false
        Valid             = $check.Valid
        ValidationMessage = $check.Message
    }
}
