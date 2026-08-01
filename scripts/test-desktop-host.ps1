[CmdletBinding()]
param()

# Source-only contract for the Windows desktop host. It does not start a
# WebView, Web Console, Docker, Windows runtime, or game server.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$desktopDir = Join-Path $projectRoot 'desktop\PalworldConsole.Desktop'
$projectFile = Join-Path $desktopDir 'PalworldConsole.Desktop.csproj'
$sourceFile = Join-Path $desktopDir 'Program.cs'
$lockFile = Join-Path $desktopDir 'packages.lock.json'
$buildScript = Join-Path $projectRoot 'scripts\build-desktop-app.ps1'
$installerTest = Join-Path $projectRoot 'scripts\test-desktop-installer.ps1'

function Assert-DesktopHost([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "DESKTOP_HOST_TEST_FAILED: $Message" }
}

foreach ($path in @($projectFile, $sourceFile, $lockFile, $buildScript, $installerTest, (Join-Path $projectRoot 'docs\desktop-app.md'))) {
    Assert-DesktopHost (Test-Path -LiteralPath $path -PathType Leaf) "Required desktop-host file is missing: $path"
}

[xml]$project = Get-Content -LiteralPath $projectFile -Raw -Encoding utf8
$projectText = [System.IO.File]::ReadAllText($projectFile)
$source = [System.IO.File]::ReadAllText($sourceFile)
$lockText = [System.IO.File]::ReadAllText($lockFile)
$buildText = [System.IO.File]::ReadAllText($buildScript)

Assert-DesktopHost ($projectText -match '<TargetFramework>net8\.0-windows</TargetFramework>') 'Desktop host must target supported net8.0-windows.'
Assert-DesktopHost ($projectText -match '<UseWindowsForms>true</UseWindowsForms>') 'Desktop host must use the Windows Forms WebView2 host.'
Assert-DesktopHost ($projectText -match 'PackageReference Include="Microsoft\.Web\.WebView2" Version="1\.0\.4078\.44"') 'Desktop host must pin Microsoft.Web.WebView2.'
Assert-DesktopHost ($projectText -match '<RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>') 'Desktop host must require a NuGet lock file.'
Assert-DesktopHost ($projectText -match '<RuntimeIdentifiers>win-x64</RuntimeIdentifiers>') 'Desktop host must lock its supported Windows x64 runtime identifier.'
Assert-DesktopHost ($lockText -match '"Microsoft\.Web\.WebView2"' -and $lockText -match '"resolved": "1\.0\.4078\.44"') 'NuGet lock file must resolve the declared WebView2 version.'

foreach ($required in @('EnsureConsoleAsync', 'FindReachableConsoleAsync', 'EnsureCoreWebView2Async', 'WebView2RuntimeNotFoundException', 'settings-panel.ps1', 'api/runtime', 'IsLocalConsoleUri', 'UseShellExecute = false')) {
    Assert-DesktopHost ($source.Contains($required)) "Desktop host is missing required local-console boundary: $required"
}
Assert-DesktopHost (-not $source.Contains('api/dashboard')) 'Desktop host readiness must not wait on the slow dashboard endpoint.'
foreach ($forbidden in @('docker.exe', 'docker compose', 'PalServer.exe', 'http://+:', 'http://0.0.0.0')) {
    Assert-DesktopHost (-not $source.Contains($forbidden)) "Desktop host must not bypass the protected backend with: $forbidden"
}
Assert-DesktopHost ($buildText -match '--locked-mode' -and $buildText -match 'PublishSingleFile=true') 'Desktop build script must use locked restore and single-file publishing.'
Assert-DesktopHost ($buildText -match "https://api\.nuget\.org/v3/index\.json") 'Desktop build script must restore from the public NuGet source.'

Write-Output 'DESKTOP_HOST_SOURCE=passed'
exit 0
