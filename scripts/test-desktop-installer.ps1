[CmdletBinding()]
param()

# Source-only contract for the current-user MSI. It never installs, removes,
# launches, or upgrades anything on the host.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$installerSource = Join-Path $projectRoot 'installer\PalworldServerConsole.wxs'
$buildScript = Join-Path $projectRoot 'scripts\build-desktop-app.ps1'
$desktopDoc = Join-Path $projectRoot 'docs\desktop-app.md'

function Assert-DesktopInstaller([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "DESKTOP_INSTALLER_TEST_FAILED: $Message" }
}

foreach ($path in @($installerSource, $buildScript, $desktopDoc)) {
    Assert-DesktopInstaller (Test-Path -LiteralPath $path -PathType Leaf) "Required installer file is missing: $path"
}

$source = [System.IO.File]::ReadAllText($installerSource)
$build = [System.IO.File]::ReadAllText($buildScript)
$doc = [System.IO.File]::ReadAllText($desktopDoc)

foreach ($required in @(
    'Scope="perUser"',
    'UpgradeCode=',
    '<MajorUpgrade',
    '<MediaTemplate EmbedCab="yes"',
    'LocalAppDataFolder',
    'APPLICATIONPROGRAMSFOLDER',
    'PalworldServerConsole.exe',
    '<Shortcut',
    '<RemoveFolder',
    'Root="HKCU"'
)) {
    Assert-DesktopInstaller ($source.Contains($required)) "MSI source is missing required install behavior: $required"
}

foreach ($required in @(
    '[switch]$Msi',
    'wix',
    '5.0.2',
    'ProductVersion=',
    'PublishDir=',
    'artifactStem',
    'output\desktop-app\$artifactStem.msi'
)) {
    Assert-DesktopInstaller ($build.Contains($required)) "Desktop build script is missing installer support: $required"
}

Assert-DesktopInstaller ($doc.Contains('-SelfContained -Msi -Zip')) 'Desktop documentation must describe both MSI and portable ZIP packaging.'
Write-Output 'DESKTOP_INSTALLER_SOURCE=passed'
exit 0
