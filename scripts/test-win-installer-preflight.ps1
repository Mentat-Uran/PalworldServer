[CmdletBinding()]
param()

# Source-only contract test. It must not start SteamCMD, modify win-server,
# touch firewall rules, or change a live runtime.
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$installerPath = Join-Path $projectDir 'scripts\install-win-server.ps1'

function Assert-InstallerPreflight([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "WIN_INSTALLER_PREFLIGHT_TEST_FAILED: $Message" }
}

Assert-InstallerPreflight (Test-Path -LiteralPath $installerPath -PathType Leaf) 'Windows installer script is missing.'
$source = [System.IO.File]::ReadAllText($installerPath)

foreach ($required in @(
    'function Test-IsAdministrator',
    'WindowsBuiltInRole]::Administrator',
    'function Test-InstallerElevation',
    'Administrator privileges are required before installation',
    'win-installer-privilege-failed',
    'if (-not (Test-InstallerElevation))'
)) {
    Assert-InstallerPreflight ($source.Contains($required)) "Missing preflight behavior: $required"
}

$elevationGate = $source.IndexOf("if (-not (Test-InstallerElevation)) {")
$forceRemoval = $source.IndexOf('Remove-Item -LiteralPath $winServerDir -Recurse -Force')
$steamDownload = $source.IndexOf('Invoke-WebRequest -Uri $steamcmdUrl -OutFile $steamcmdZip')
Assert-InstallerPreflight ($elevationGate -ge 0) 'Privilege gate was not found.'
Assert-InstallerPreflight ($forceRemoval -gt $elevationGate) 'Force removal must occur after the privilege gate.'
Assert-InstallerPreflight ($steamDownload -gt $elevationGate) 'SteamCMD download must occur after the privilege gate.'

Write-Output 'WIN_INSTALLER_PREFLIGHT_SOURCE=passed'
exit 0
