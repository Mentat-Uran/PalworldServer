[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',
    [ValidateSet('win-x64')]
    [string]$RuntimeIdentifier = 'win-x64',
    [switch]$SelfContained,
    [switch]$Zip
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$projectFile = Join-Path $projectRoot 'desktop\PalworldConsole.Desktop\PalworldConsole.Desktop.csproj'
$dotnet = Get-Command dotnet.exe -ErrorAction SilentlyContinue
if (-not $dotnet) { throw 'dotnet.exe is required. Install the .NET 8 SDK to build the desktop host.' }
if (-not (Test-Path -LiteralPath $projectFile -PathType Leaf)) { throw "Desktop project is missing: $projectFile" }

$publishDir = Join-Path $projectRoot "output\desktop-app\$RuntimeIdentifier\$Configuration"
$selfContainedValue = if ($SelfContained) { 'true' } else { 'false' }

& $dotnet.Source restore $projectFile --runtime $RuntimeIdentifier --locked-mode --source 'https://api.nuget.org/v3/index.json'
if ($LASTEXITCODE -ne 0) { throw "Desktop dependency restore failed (exit $LASTEXITCODE)." }

& $dotnet.Source publish $projectFile --configuration $Configuration --runtime $RuntimeIdentifier --no-restore `
    --self-contained $selfContainedValue --output $publishDir `
    -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=None -p:DebugSymbols=false
if ($LASTEXITCODE -ne 0) { throw "Desktop publish failed (exit $LASTEXITCODE)." }

$exePath = Join-Path $publishDir 'PalworldServerConsole.exe'
if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) { throw "Publish did not create the desktop application: $exePath" }
Write-Host "DESKTOP_APP_EXE=$exePath"
Write-Host "DESKTOP_APP_RUNTIME=$RuntimeIdentifier"
Write-Host "DESKTOP_APP_SELF_CONTAINED=$selfContainedValue"

if ($Zip) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $zipPath = Join-Path $projectRoot "output\desktop-app\PalworldServerConsole-$RuntimeIdentifier-$Configuration-$stamp.zip"
    Compress-Archive -Path (Join-Path $publishDir '*') -DestinationPath $zipPath -CompressionLevel Optimal
    Write-Host "DESKTOP_APP_ZIP=$zipPath"
}
