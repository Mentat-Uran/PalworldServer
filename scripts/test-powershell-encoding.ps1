[CmdletBinding()]
param()

# Windows PowerShell 5.1 reads non-ASCII PowerShell source safely only when
# the UTF-8 BOM is present. ASCII-only scripts may remain BOM-free.
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
$files = Get-ChildItem -LiteralPath $projectDir -Recurse -File -Filter '*.ps1' |
    Where-Object { $_.FullName -notmatch '\\(node_modules|output|data)\\' }

foreach ($file in $files) {
    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
    if ($bytes.Length -ge 2 -and
        (($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or
         ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF))) {
        throw "POWERSHELL_ENCODING_TEST_FAILED: UTF-16 is not supported for $($file.FullName)."
    }

    try {
        [void]$utf8Strict.GetString($bytes)
    } catch {
        throw "POWERSHELL_ENCODING_TEST_FAILED: invalid UTF-8 in $($file.FullName)."
    }

    $hasUtf8Bom = $bytes.Length -ge 3 -and
        $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $hasNonAscii = [bool]($bytes | Where-Object { $_ -gt 127 })
    if ($hasNonAscii -and -not $hasUtf8Bom) {
        throw "POWERSHELL_ENCODING_TEST_FAILED: non-ASCII PowerShell source requires a UTF-8 BOM: $($file.FullName)."
    }
}

Write-Output 'POWERSHELL_ENCODING=passed'
exit 0
