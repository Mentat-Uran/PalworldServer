[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',
    [ValidateSet('win-x64')]
    [string]$RuntimeIdentifier = 'win-x64',
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version = '',
    [switch]$SelfContained,
    [switch]$Zip,
    [switch]$Msi
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$versionSource = Join-Path $projectRoot 'version.json'
if (-not (Test-Path -LiteralPath $versionSource -PathType Leaf)) { throw "Version source is missing: $versionSource" }
$sourceVersion = [string]((Get-Content -LiteralPath $versionSource -Raw -Encoding UTF8 | ConvertFrom-Json).version)
if (-not $Version) { $Version = $sourceVersion }
if ($Version -ne $sourceVersion) { throw "Build version $Version does not match version.json ($sourceVersion). Use scripts\bump-version.ps1 first." }
$projectFile = Join-Path $projectRoot 'desktop\PalworldConsole.Desktop\PalworldConsole.Desktop.csproj'
$installerSource = Join-Path $projectRoot 'installer\PalworldServerConsole.wxs'
$dotnet = Get-Command dotnet.exe -ErrorAction SilentlyContinue
if (-not $dotnet) { throw 'dotnet.exe is required. Install the .NET 8 SDK to build the desktop host.' }
if (-not (Test-Path -LiteralPath $projectFile -PathType Leaf)) { throw "Desktop project is missing: $projectFile" }
if ($Msi -and -not (Test-Path -LiteralPath $installerSource -PathType Leaf)) { throw "Desktop installer source is missing: $installerSource" }

$publishDir = Join-Path $projectRoot "output\desktop-app\$RuntimeIdentifier\$Configuration"
$selfContainedValue = if ($SelfContained -or $Msi) { 'true' } else { 'false' }
$artifactStem = "PalworldServerConsole-$Version-$RuntimeIdentifier-$Configuration"

& $dotnet.Source restore $projectFile --runtime $RuntimeIdentifier --locked-mode --source 'https://api.nuget.org/v3/index.json'
if ($LASTEXITCODE -ne 0) { throw "Desktop dependency restore failed (exit $LASTEXITCODE)." }

& $dotnet.Source publish $projectFile --configuration $Configuration --runtime $RuntimeIdentifier --no-restore `
    --self-contained $selfContainedValue --output $publishDir `
    -p:Version=$Version -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=None -p:DebugSymbols=false
if ($LASTEXITCODE -ne 0) { throw "Desktop publish failed (exit $LASTEXITCODE)." }

$exePath = Join-Path $publishDir 'PalworldServerConsole.exe'
if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) { throw "Publish did not create the desktop application: $exePath" }
Write-Host "DESKTOP_APP_EXE=$exePath"
Write-Host "DESKTOP_APP_RUNTIME=$RuntimeIdentifier"
Write-Host "DESKTOP_APP_SELF_CONTAINED=$selfContainedValue"

if ($Zip) {
    $zipPath = Join-Path $projectRoot "output\desktop-app\$artifactStem.zip"
    Compress-Archive -Path (Join-Path $publishDir '*') -DestinationPath $zipPath -CompressionLevel Optimal -Force
    Write-Host "DESKTOP_APP_ZIP=$zipPath"
    $zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $zipChecksum = Join-Path $projectRoot "output\desktop-app\$artifactStem.zip.sha256"
    [System.IO.File]::WriteAllText($zipChecksum, "$zipHash *$([System.IO.Path]::GetFileName($zipPath))`n", [System.Text.UTF8Encoding]::new($false))
    Write-Host "DESKTOP_APP_ZIP_SHA256=$zipHash"
}

if ($Msi) {
    $wixVersion = '5.0.2'
    $wixDir = Join-Path $projectRoot 'output\wix'
    $wixPath = Join-Path $wixDir 'wix.exe'
    if (-not (Test-Path -LiteralPath $wixPath -PathType Leaf)) {
        New-Item -ItemType Directory -Force -Path $wixDir | Out-Null
        & $dotnet.Source tool install --tool-path $wixDir --version $wixVersion wix
        if ($LASTEXITCODE -ne 0) { throw "WiX $wixVersion bootstrap failed (exit $LASTEXITCODE)." }
    }
    if (-not (Test-Path -LiteralPath $wixPath -PathType Leaf)) { throw "WiX CLI was not found after bootstrap: $wixPath" }

    $msiPath = Join-Path $projectRoot "output\desktop-app\$artifactStem.msi"
    & $wixPath build $installerSource -arch x64 `
        -d "ProductVersion=$Version" `
        -d "PublishDir=$publishDir" `
        -out $msiPath -pdbtype none
    if ($LASTEXITCODE -ne 0) { throw "Desktop MSI build failed (exit $LASTEXITCODE)." }
    if (-not (Test-Path -LiteralPath $msiPath -PathType Leaf)) { throw "WiX did not create the desktop installer: $msiPath" }
    $msiHash = (Get-FileHash -LiteralPath $msiPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $msiChecksum = Join-Path $projectRoot "output\desktop-app\$artifactStem.msi.sha256"
    [System.IO.File]::WriteAllText($msiChecksum, "$msiHash *$([System.IO.Path]::GetFileName($msiPath))`n", [System.Text.UTF8Encoding]::new($false))
    Write-Host "DESKTOP_APP_MSI=$msiPath"
    Write-Host "DESKTOP_APP_MSI_SHA256=$msiHash"
}
