# Encoding regression diagnostics
Write-Host "=== Step 1: Current Encoding State ==="
Write-Host ("`$OutputEncoding.CodePage = " + $OutputEncoding.CodePage)
Write-Host ("[Console]::OutputEncoding.CodePage = " + [Console]::OutputEncoding.CodePage)
Write-Host ("[Console]::InputEncoding.CodePage = " + [Console]::InputEncoding.CodePage)
Write-Host ("[System.Text.Encoding]::Default.CodePage = " + [System.Text.Encoding]::Default.CodePage)
$cp = chcp
Write-Host ("chcp = " + $cp)

Write-Host "`n=== Step 2: Simulate actual ssh error message ==="
$errMsg = 'ssh: Could not resolve hostname unraid: 不知道这样的主机。'
Write-Host ("Raw message: " + $errMsg)
Write-Host ("Length: " + $errMsg.Length)

$utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($errMsg)
Write-Host ("UTF8 bytes: " + ($utf8Bytes -join ' '))
$utf8Octal = ($utf8Bytes | ForEach-Object { '\' + [Convert]::ToString($_, 8).PadLeft(3, '0') }) -join ''
Write-Host ("UTF8 -> Octal: " + $utf8Octal)

Write-Host "`n=== Step 3: Test decoding with wrong encoding (GBK 936) ==="
$badEnc = [System.Text.Encoding]::GetEncoding(936)
# Take the ssh error portion: "不能解析指定的主机名。" -> get the UTF8 bytes, then decode as GBK
$chinesePart = '不知道这样的主机。'
$chineseBytes = [System.Text.Encoding]::UTF8.GetBytes($chinesePart)
Write-Host ("Chinese UTF8 bytes: " + ($chineseBytes -join ' '))
$misDecoded = $badEnc.GetString($chineseBytes)
Write-Host ("GBK-misdecoded: " + $misDecoded)

# Now re-encode the mis-decoded string back to UTF8 bytes and convert to octal
$reUtf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($misDecoded)
$reOctal = ($reUtf8Bytes | ForEach-Object { '\' + [Convert]::ToString($_, 8).PadLeft(3, '0') }) -join ''
Write-Host ("Re-encoded -> Octal: " + $reOctal)

Write-Host "`n=== Step 4: Compare with user's actual error ==="
$userOctal = '\344\270\215\347\237\245\351\201\223\350\277\231\346\240\267\347\232\204\344\270\273\346\234\272\343\200\202'
Write-Host ("User's reported octal: " + $userOctal)
$userBytes = $userOctal -split '\\' | Where-Object { $_ -ne '' } | ForEach-Object { [Convert]::ToByte($_, 8) }
$userDecoded = [System.Text.Encoding]::UTF8.GetString($userBytes)
Write-Host ("User's octal -> UTF8: " + $userDecoded)

Write-Host "`n=== Step 5: Test with '不能解析指定的主机名。' ==="
$altChinese = '不能解析指定的主机名。'
$altBytes = [System.Text.Encoding]::UTF8.GetBytes($altChinese)
$altOctal = ($altBytes | ForEach-Object { '\' + [Convert]::ToString($_, 8).PadLeft(3, '0') }) -join ''
Write-Host ("'不能解析指定的主机名。' -> Octal: " + $altOctal)

# Compare
if ($userOctal -eq $altOctal) {
    Write-Host "MATCH: User's error says '不能解析指定的主机名。'"
} elseif ($userOctal -eq $reOctal) {
    Write-Host "MATCH: User's error is '不知道这样的主机。' mis-decoded via GBK"
} else {
    Write-Host "Neither matches exactly, comparing byte by byte"
    Write-Host ("User oct:     " + $userOctal)
    Write-Host ("'不能解析' oct: " + $altOctal)
    Write-Host ("GBK mis oct:  " + $reOctal)
}

Write-Host "`n=== Step 6: Check what ssh actually outputs ==="
# Try to reproduce the actual error
Write-Host "Attempting ssh to 'unraid' (expected to fail)..."
try {
    $result = ssh -o ConnectTimeout=3 unraid 2>&1
    Write-Host ("ssh output: " + $result)
} catch {
    Write-Host ("Exception: " + $_.Exception.Message)
    if ($_.Exception.Message -match '\\\d{3}') {
        Write-Host "CONTAINS OCTAL ESCAPES!"
    }
}
