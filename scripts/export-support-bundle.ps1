[CmdletBinding()]
param([string]$OutputDirectory = '')

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $projectDir 'output\support-bundle' }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stage = Join-Path $OutputDirectory "support-$stamp"
$zip = Join-Path $OutputDirectory "PalworldServer-support-$stamp.zip"
New-Item -ItemType Directory -Path $stage -Force | Out-Null

function Redact([string]$Text) {
    if ($null -eq $Text) { return '' }
    $value = $Text
    $value = $value -replace '(?i)(ADMIN_PASSWORD|SERVER_PASSWORD|WEBHOOK|TOKEN|TUNNEL_ARGUMENTS)\s*[=:]\s*[^\s,;]+', '$1=<redacted>'
    $value = $value -replace '(?i)https?://[^\s"''<>]+', '<url-redacted>'
    $value = $value -replace '\b(?:\d{1,3}\.){3}\d{1,3}(?::\d{1,5})?\b', '<address-redacted>'
    $value = $value -replace '(?i)\b(?:steam|xbox|psn|epic)[_:-][A-Za-z0-9_-]+\b', '<player-id-redacted>'
    $value = $value -replace '\b[A-F0-9]{16,}\b', '<identifier-redacted>'
    $value = $value -replace '(?i)[A-Z]:\\[^\r\n ]+', '<path-redacted>'
    return $value
}

function Write-SafeFile([string]$Name, [string]$Content) {
    [System.IO.File]::WriteAllText((Join-Path $stage $Name), (Redact $Content), (New-Object System.Text.UTF8Encoding($false)))
}

$version = (Get-Content -LiteralPath (Join-Path $projectDir 'version.json') -Raw -Encoding UTF8 | ConvertFrom-Json).version
$dockerVersion = 'not-installed'
try { $dockerVersion = (& docker.exe version --format '{{.Server.Version}}' 2>$null | Out-String).Trim() } catch { }
$dotnetVersion = 'not-installed'
try { $dotnetVersion = (& dotnet.exe --version 2>$null | Out-String).Trim() } catch { }
$metadata = [ordered]@{
    projectVersion = [string]$version
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    windows = [Environment]::OSVersion.VersionString
    powershell = $PSVersionTable.PSVersion.ToString()
    dotnet = $dotnetVersion
    docker = $dockerVersion
    runtime = 'not-read'
    configuredKeys = @()
}
$envPath = Join-Path $projectDir '.env'
if (Test-Path -LiteralPath $envPath -PathType Leaf) {
    $keys = @()
    foreach ($line in [System.IO.File]::ReadAllLines($envPath)) {
        $index = $line.IndexOf('=')
        if ($index -gt 0) { $keys += $line.Substring(0,$index).Trim() }
    }
    $metadata.configuredKeys = @($keys | Sort-Object -Unique | Where-Object { $_ -notmatch '(?i)(PASSWORD|SECRET|TOKEN|WEBHOOK|TUNNEL_ARGUMENTS)' })
}
$statePath = Join-Path $projectDir 'data\runtime.state'
if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    try {
        $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $metadata.runtime = [ordered]@{ active = [string]$state.active; switching = [bool]$state.switching; version = [string]$state.version }
    } catch { $metadata.runtime = 'unreadable' }
}
Write-SafeFile 'metadata.json' ($metadata | ConvertTo-Json -Depth 6)

$tcpPorts = @()
$udpPorts = @()
try { $tcpPorts = @(Get-NetTCPConnection -State Listen -ErrorAction Stop | Select-Object -ExpandProperty LocalPort -Unique | Sort-Object) } catch { }
try { $udpPorts = @(Get-NetUDPEndpoint -ErrorAction Stop | Select-Object -ExpandProperty LocalPort -Unique | Sort-Object) } catch { }
Write-SafeFile 'ports.txt' ("tcpListenPorts=$($tcpPorts -join ',')`nudpLocalPorts=$($udpPorts -join ',')")

$checkOutput = try { (& (Join-Path $PSScriptRoot 'verify-project.ps1') -SkipDocker 2>&1 | Out-String) } catch { "validation-error=$($_.Exception.Message)" }
Write-SafeFile 'validation.txt' $checkOutput

$logLines = New-Object System.Collections.Generic.List[string]
$logRoots = @((Join-Path $projectDir 'data\log-sources'), (Join-Path $projectDir 'data\diagnostics'))
foreach ($root in $logRoots) {
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
    foreach ($file in @(Get-ChildItem -LiteralPath $root -File -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 8)) {
        $logLines.Add("--- $($file.Name) ---")
        foreach ($line in @(Get-Content -LiteralPath $file.FullName -Tail 80 -Encoding UTF8 -ErrorAction SilentlyContinue)) { $logLines.Add([string]$line) }
    }
}
Write-SafeFile 'recent-logs.txt' ($logLines -join [Environment]::NewLine)
[System.IO.File]::WriteAllText((Join-Path $stage 'CONTENTS.txt'), "This support bundle is redacted. It excludes .env values, saves, backups, player identifiers, tunnel addresses, and raw commands.`n", (New-Object System.Text.UTF8Encoding($false)))
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Optimal
$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "SUPPORT_BUNDLE=$zip"
Write-Host "SUPPORT_BUNDLE_SHA256=$hash"
