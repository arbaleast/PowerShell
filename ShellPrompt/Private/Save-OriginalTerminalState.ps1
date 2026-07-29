# Save-OriginalTerminalState.ps1 - 保存当前终端编码 / TERM 状态
# 搭配 Reset-TerminalMode 成对使用: try { Save-OriginalTerminalState; ... } finally { Reset-TerminalMode }

function Save-OriginalTerminalState {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    # 保存原始控制台状态到 $script:Original*, Reset-TerminalMode finally 读取并恢复
    $script:OriginalOutputEncoding = [System.Console]::OutputEncoding
    $script:OriginalInputEncoding  = [System.Console]::InputEncoding
    $script:OriginalTerm           = $env:TERM

    # 设置 UTF-8 编码和 xterm-256color TERM, 确保远程 tmux 正确渲染 Unicode
    $env:TERM = 'xterm-256color'
    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
    try { [Console]::InputEncoding  = [System.Text.Encoding]::UTF8 } catch {}
}
