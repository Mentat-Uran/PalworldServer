[CmdletBinding()]
param()

# Source and launcher-contract test for the one-click Windows-native installer.
# /self-test never downloads SteamCMD, modifies win-server, changes firewall
# rules, or starts PalServer.
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$batPath = Join-Path $projectDir 'install-windows-server.bat'

function Assert-WindowsInstallerBat([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "WINDOWS_INSTALLER_BAT_TEST_FAILED: $Message" }
}

Assert-WindowsInstallerBat (Test-Path -LiteralPath $batPath -PathType Leaf) 'One-click installer BAT is missing.'
$bytes = [System.IO.File]::ReadAllBytes($batPath)
Assert-WindowsInstallerBat (-not ($bytes | Where-Object { $_ -gt 127 })) 'BAT must remain ASCII for reliable double-click execution.'
$source = [System.IO.File]::ReadAllText($batPath, [System.Text.Encoding]::ASCII)

foreach ($required in @(
    'set "PROJECT_DIR=%~dp0"',
    'powershell.exe -NoProfile -ExecutionPolicy Bypass -File',
    'scripts\install-win-server.ps1',
    'if errorlevel 1',
    'pause',
    '/self-test',
    'BAT_SELF_TEST=passed'
)) {
    Assert-WindowsInstallerBat ($source.Contains($required)) "BAT is missing required launcher behavior: $required"
}

$output = & cmd.exe /d /c "`"$batPath`" /self-test" 2>&1 | Out-String
$exitCode = $LASTEXITCODE
Assert-WindowsInstallerBat ($exitCode -eq 0) "BAT self-test exited with code $exitCode. Output: $output"
Assert-WindowsInstallerBat ($output -match 'BAT_SELF_TEST=passed') 'BAT self-test did not report success.'

Write-Output 'WINDOWS_INSTALL_BAT_SOURCE=passed'
Write-Output 'WINDOWS_INSTALL_BAT_EXECUTION=passed'
exit 0
