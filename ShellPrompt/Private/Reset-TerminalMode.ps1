# Reset-TerminalMode.ps1 - SSH/tmux 退出后恢复终端状态
# 设计:采用【并集】实现,合并 Invoke-SshCommand (5 项 ANSI) 与
#       Start-SshInteractive (本地控制台层) 两版不同维度的恢复;
#       任何一项漏掉都会导致用户感知异常(鼠标乱码/光标不可见/编码污染)。
# 状态源: 调用方在 try 顶部把原始值写入 $script:OriginalOutputEncoding /
#         $script:OriginalInputEncoding / $script:OriginalTerm,本函数 finally 读取并恢复。

function Reset-TerminalMode {
    [CmdletBinding()]
    param()

    # --- A. 远程协议层 (原 Invoke-SshCommand 版) ---
    # 关闭 tmux 启用过的鼠标追踪模式 + 显示光标 + 重置 SGR
    # 5 项 ANSI 序列在 1 次 Write 中完成(批次 A 性能优化产物)
    [Console]::Write(
        "`e[?1000l" +
        "`e[?1002l" +
        "`e[?1003l" +
        "`e[?1006l" +
        "`e[?25h" +
        "`e[m"
    )

    # --- B. 本地控制台层 (原 Start-SshInteractive 版) ---
    # B-1 恢复 Ctrl+C 中断语义 - tmux 启动时可能改为 TreatControlCAsInput=$true
    try { [Console]::TreatControlCAsInput = $false } catch {}
    # B-2 双重保险光标显示 (ANSI ?25h 已处理,此处再设一次 .NET 属性)
    try { [Console]::CursorVisible = $true } catch {}
    # B-3 恢复控制台编码(若调用方在 try 顶部已保存到 $script:Original*)
    if ($script:OriginalOutputEncoding) {
        try { [Console]::OutputEncoding = $script:OriginalOutputEncoding } catch {}
    }
    if ($script:OriginalInputEncoding) {
        try { [Console]::InputEncoding = $script:OriginalInputEncoding } catch {}
    }
    # B-4 恢复 TERM 环境变量(对应方案 §1.3 X-03 内联)
    if ($script:OriginalTerm) {
        $env:TERM = $script:OriginalTerm
    }
    if ($env:SUDO_USER) {
        # sudo 提权场景下,清空 TERM 让子进程从父进程重新探测
        try { Remove-Item Env:TERM -ErrorAction SilentlyContinue } catch {}
    }
}
