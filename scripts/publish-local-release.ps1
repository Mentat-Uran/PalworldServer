[CmdletBinding()]
param(
    [string]$Version = '',
    [Parameter(Mandatory)][string]$CertificateThumbprint,
    [string]$SignToolPath = '',
    [string]$TimestampUrl = 'https://timestamp.digicert.com'
)

# Formal release orchestrator. It builds, signs, verifies, and hashes artifacts
# on the maintainer's Windows machine; it never tags, pushes, or creates a
# GitHub Release and never starts a Palworld runtime.
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$sourceVersion = [string]((Get-Content -LiteralPath (Join-Path $projectDir 'version.json') -Raw -Encoding UTF8 | ConvertFrom-Json).version)
if (-not $Version) { $Version = $sourceVersion }
if ($Version -ne $sourceVersion) { throw "Release version $Version does not match version.json ($sourceVersion)." }

function Assert-LocalRelease {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "LOCAL_RELEASE_FAILED: $Message" }
}

function Invoke-LocalPowerShellScript {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string[]]$Arguments = @()
    )
    $powershell = Join-Path $PSHOME 'powershell.exe'
    $stdoutPath = Join-Path ([System.IO.Path]::GetTempPath()) ('.palworld-release-' + [guid]::NewGuid().ToString('N') + '.out')
    $stderrPath = Join-Path ([System.IO.Path]::GetTempPath()) ('.palworld-release-' + [guid]::NewGuid().ToString('N') + '.err')
    try {
        $argumentList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $Path))
        foreach ($argument in $Arguments) {
            if ([string]$argument -match '[\s"]') {
                $argumentList += ('"{0}"' -f ([string]$argument).Replace('"', '\"'))
            } else {
                $argumentList += [string]$argument
            }
        }
        $process = Start-Process -FilePath $powershell -ArgumentList $argumentList -Wait -PassThru -NoNewWindow `
            -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw } else { '' }
        $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw } else { '' }
        foreach ($line in (($stdout, $stderr) -join "`n" -split "`r?`n")) {
            if ($line) { Write-Host $line }
        }
        if ($process.ExitCode -ne 0) { throw "Local script failed with exit code $($process.ExitCode): $Path" }
    } finally {
        Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
    }
}

$normalizedThumbprint = ($CertificateThumbprint -replace '\s', '').ToUpperInvariant()
Assert-LocalRelease ($normalizedThumbprint -match '^[0-9A-F]{40}$') 'CertificateThumbprint must be a 40-character SHA-1 thumbprint.'
$certificate = Get-ChildItem -LiteralPath "Cert:\CurrentUser\My\$normalizedThumbprint" -ErrorAction SilentlyContinue
Assert-LocalRelease ($null -ne $certificate) 'The signing certificate was not found in CurrentUser\My.'
Assert-LocalRelease ([bool]$certificate.HasPrivateKey) 'The signing certificate has no private key.'

if (-not $SignToolPath) {
    $signTool = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($signTool) { $SignToolPath = $signTool.Source }
}
Assert-LocalRelease ($SignToolPath -and (Test-Path -LiteralPath $SignToolPath -PathType Leaf)) 'SignTool.exe is required for a formal release.'
Assert-LocalRelease ($TimestampUrl -match '^https://') 'TimestampUrl must use HTTPS.'

$workflowPath = Join-Path $projectDir '.github\workflows\validate.yml'
Assert-LocalRelease (Test-Path -LiteralPath $workflowPath -PathType Leaf) 'The source-validation workflow is missing.'
$outputRoot = Join-Path $projectDir 'output'
$desktopPublishDir = Join-Path $outputRoot 'desktop-app\win-x64\Release'
$desktopZip = Join-Path $outputRoot "desktop-app\PalworldServerConsole-$Version-win-x64-Release.zip"
$desktopZipSha = "$desktopZip.sha256"
$desktopMsi = Join-Path $outputRoot "desktop-app\PalworldServerConsole-$Version-win-x64-Release.msi"

# These checks are intentionally before any build or signing command.
Invoke-LocalPowerShellScript (Join-Path $projectDir 'scripts\test-version-consistency.ps1')
Invoke-LocalPowerShellScript (Join-Path $projectDir 'scripts\test-release-policy.ps1')
Invoke-LocalPowerShellScript (Join-Path $projectDir 'scripts\audit-public-release.ps1') @('-Strict')
Invoke-LocalPowerShellScript (Join-Path $projectDir 'scripts\verify-project.ps1') @('-SkipDocker')
Invoke-LocalPowerShellScript (Join-Path $projectDir 'scripts\test-clean-checkout.ps1')

Invoke-LocalPowerShellScript (Join-Path $projectDir 'scripts\build-desktop-app.ps1') @(
    '-Version', $Version, '-SelfContained', '-Msi'
)
Assert-LocalRelease (Test-Path -LiteralPath (Join-Path $desktopPublishDir 'PalworldServerConsole.exe') -PathType Leaf) 'Desktop executable was not built.'
Assert-LocalRelease (Test-Path -LiteralPath $desktopMsi -PathType Leaf) 'Desktop MSI was not built.'

function Invoke-SignAndVerify {
    param([Parameter(Mandatory)][string]$Path)
    & $SignToolPath sign /fd SHA256 /sha1 $normalizedThumbprint /tr $TimestampUrl /td SHA256 $Path
    if ($LASTEXITCODE -ne 0) { throw "Signing failed for $Path (exit $LASTEXITCODE)." }
    & $SignToolPath verify /pa /all $Path
    if ($LASTEXITCODE -ne 0) { throw "Signature verification failed for $Path (exit $LASTEXITCODE)." }
    Write-Host "SIGNED_AND_VERIFIED=$Path"
}

foreach ($signTarget in @(Get-ChildItem -LiteralPath $desktopPublishDir -Filter '*.exe' -File) + @((Get-Item -LiteralPath $desktopMsi))) {
    Invoke-SignAndVerify -Path $signTarget.FullName
}
$msiHash = (Get-FileHash -LiteralPath $desktopMsi -Algorithm SHA256).Hash.ToLowerInvariant()
[System.IO.File]::WriteAllText("$desktopMsi.sha256", "$msiHash *$([System.IO.Path]::GetFileName($desktopMsi))`n", [System.Text.UTF8Encoding]::new($false))

if (Test-Path -LiteralPath $desktopZip) { Remove-Item -LiteralPath $desktopZip -Force }
Compress-Archive -Path (Join-Path $desktopPublishDir '*') -DestinationPath $desktopZip -CompressionLevel Optimal
$desktopHash = (Get-FileHash -LiteralPath $desktopZip -Algorithm SHA256).Hash.ToLowerInvariant()
[System.IO.File]::WriteAllText($desktopZipSha, "$desktopHash *$([System.IO.Path]::GetFileName($desktopZip))`n", [System.Text.UTF8Encoding]::new($false))

Invoke-LocalPowerShellScript (Join-Path $projectDir 'scripts\build-release-bundle.ps1') @(
    '-Version', $Version, '-DesktopPublishDir', $desktopPublishDir
)
$sourceZip = Join-Path $outputRoot "release-bundle\PalworldServer-$Version-win-x64.zip"
$sourceZipSha = "$sourceZip.sha256"
Assert-LocalRelease (Test-Path -LiteralPath $sourceZip -PathType Leaf) 'Complete source release bundle was not created.'
Assert-LocalRelease (Test-Path -LiteralPath $sourceZipSha -PathType Leaf) 'Source bundle checksum was not created.'

$artifactPaths = @($desktopZip, $desktopZipSha, $desktopMsi, "$desktopMsi.sha256", $sourceZip, $sourceZipSha)
$manifestEntries = @()
foreach ($artifact in $artifactPaths) {
    Assert-LocalRelease (Test-Path -LiteralPath $artifact -PathType Leaf) "Missing release artifact: $artifact"
    $manifestEntries += [ordered]@{
        file = [System.IO.Path]::GetFileName($artifact)
        sha256 = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}
$manifest = [ordered]@{
    version = $Version
    sourceCommit = (& git -C $projectDir rev-parse HEAD).Trim()
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    signing = [ordered]@{ authenticode = $true; timestampUrl = $TimestampUrl; certificateThumbprintSuffix = $normalizedThumbprint.Substring($normalizedThumbprint.Length - 8) }
    artifacts = $manifestEntries
    publication = 'manual upload only; this script does not tag, push, or create a GitHub Release'
}
$manifestPath = Join-Path $outputRoot "PalworldServer-$Version-RELEASE-MANIFEST.json"
[System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
Write-Host "LOCAL_RELEASE_MANIFEST=$manifestPath"
Write-Host 'LOCAL_RELEASE=passed'
