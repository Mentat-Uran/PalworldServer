[CmdletBinding()]
param(
    [string]$Version = '',
    [string]$DesktopPublishDir = ''
)

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$sourceVersion = [string]((Get-Content -LiteralPath (Join-Path $projectDir 'version.json') -Raw -Encoding UTF8 | ConvertFrom-Json).version)
if (-not $Version) { $Version = $sourceVersion }
if ($Version -ne $sourceVersion) { throw "Bundle version $Version does not match version.json ($sourceVersion)." }
$outputDir = Join-Path $projectDir 'output\release-bundle'
$stageDir = Join-Path $outputDir "PalworldServer-$Version-win-x64"
$zipPath = Join-Path $outputDir "PalworldServer-$Version-win-x64.zip"
if (Test-Path -LiteralPath $stageDir) { Remove-Item -LiteralPath $stageDir -Recurse -Force }
New-Item -ItemType Directory -Path $stageDir -Force | Out-Null

$rootFiles = @(
    '.env.example','docker-compose.yml','docker-compose.override.example.yml',
    'install-windows-server.bat','start-windows.bat','start-docker.bat',
    'README.md','README.en.md','CHANGELOG.md','LICENSE','SECURITY.md','SUPPORT.md',
    'CONTRIBUTING.md','GOVERNANCE.md','CODE_OF_CONDUCT.md','package.json','package-lock.json',
    'version.json'
)
$directories = @('scripts','web','docs','presets','providers','installer','mods')
foreach ($file in $rootFiles) {
    $path = Join-Path $projectDir $file
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Release source file is missing: $file" }
    Copy-Item -LiteralPath $path -Destination (Join-Path $stageDir $file) -Force
}
foreach ($directory in $directories) {
    $path = Join-Path $projectDir $directory
    if (Test-Path -LiteralPath $path -PathType Container) {
        Copy-Item -LiteralPath $path -Destination (Join-Path $stageDir $directory) -Recurse -Force
    }
}
$desktopSource = Join-Path $projectDir 'desktop\PalworldConsole.Desktop'
$desktopStage = Join-Path $stageDir 'desktop\PalworldConsole.Desktop'
New-Item -ItemType Directory -Path $desktopStage -Force | Out-Null
foreach ($desktopFile in @('app.manifest', 'packages.lock.json', 'PalworldConsole.Desktop.csproj', 'Program.cs')) {
    $desktopPath = Join-Path $desktopSource $desktopFile
    if (-not (Test-Path -LiteralPath $desktopPath -PathType Leaf)) { throw "Desktop source file is missing: $desktopFile" }
    Copy-Item -LiteralPath $desktopPath -Destination (Join-Path $desktopStage $desktopFile) -Force
}
$firstRun = @'
@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\bootstrap-first-run.ps1" %*
if errorlevel 1 pause
exit /b %errorlevel%
'@
[System.IO.File]::WriteAllText((Join-Path $stageDir 'FIRST_RUN.bat'), $firstRun, [System.Text.Encoding]::ASCII)

if ($DesktopPublishDir) {
    if (-not (Test-Path -LiteralPath $DesktopPublishDir -PathType Container)) { throw "Desktop publish directory not found: $DesktopPublishDir" }
    $desktopTarget = Join-Path $stageDir 'desktop-app'
    New-Item -ItemType Directory -Path $desktopTarget -Force | Out-Null
    Copy-Item -Path (Join-Path $DesktopPublishDir '*') -Destination $desktopTarget -Recurse -Force
}
$info = [ordered]@{ sourceVersion = $Version; package = 'PalworldServer'; runtime = 'win-x64'; generatedAt = (Get-Date).ToUniversalTime().ToString('o'); containsGameFiles = $false; containsSaves = $false; containsSecrets = $false }
[System.IO.File]::WriteAllText((Join-Path $stageDir 'RELEASE_PACKAGE.json'), ($info | ConvertTo-Json -Depth 3), (New-Object System.Text.UTF8Encoding($false)))
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path (Join-Path $stageDir '*') -DestinationPath $zipPath -CompressionLevel Optimal
$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
[System.IO.File]::WriteAllText("$zipPath.sha256", "$hash *$([System.IO.Path]::GetFileName($zipPath))`n", (New-Object System.Text.UTF8Encoding($false)))
Write-Host "RELEASE_BUNDLE=$zipPath"
Write-Host "RELEASE_BUNDLE_SHA256=$hash"
