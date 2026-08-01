[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$versionPath = Join-Path $projectDir 'version.json'
if (-not (Test-Path -LiteralPath $versionPath -PathType Leaf)) { throw "Version source is missing: $versionPath" }
$version = Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$version.version -notmatch '^\d+\.\d+\.\d+$') { throw 'version.json.version must be semantic major.minor.patch.' }
Write-Output ([string]$version.version)
