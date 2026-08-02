[CmdletBinding()]
param([string]$Tag = '')

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
function Fail([string]$Message) { throw "VERSION_CONSISTENCY_FAILED: $Message" }
$source = Get-Content -LiteralPath (Join-Path $projectDir 'version.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$version = [string]$source.version
if ($version -notmatch '^\d+\.\d+\.\d+$') { Fail 'version.json contains an invalid semantic version.' }
$package = Get-Content -LiteralPath (Join-Path $projectDir 'package.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$package.version -ne $version) { Fail 'package.json version does not match version.json.' }
$lock = Get-Content -LiteralPath (Join-Path $projectDir 'package-lock.json') -Raw -Encoding UTF8
if ($lock -notmatch ('(?m)^\s*"version"\s*:\s*"' + [regex]::Escape($version) + '"')) { Fail 'package-lock.json root version does not match version.json.' }
$changelog = Get-Content -LiteralPath (Join-Path $projectDir 'CHANGELOG.md') -Raw -Encoding UTF8
if ($changelog -notmatch ('(?m)^## \[' + [regex]::Escape($version) + '\]')) { Fail "CHANGELOG.md has no section for $version." }
$build = Get-Content -LiteralPath (Join-Path $projectDir 'scripts\build-desktop-app.ps1') -Raw -Encoding UTF8
if ($build -match "\[string\]\$Version\s*=\s*'\d+\.\d+\.\d+'") { Fail 'Desktop build script contains a hard-coded default version.' }
foreach ($file in @('README.md','README.en.md')) {
    $text = Get-Content -LiteralPath (Join-Path $projectDir $file) -Raw -Encoding UTF8
    if ($text -match 'build-desktop-app\.ps1[^\r\n]*-Version\s+\d+\.\d+\.\d+') { Fail "$file hard-codes a build version." }
}
$versioning = Get-Content -LiteralPath (Join-Path $projectDir 'docs\versioning-and-releases.md') -Raw -Encoding UTF8
if ($versioning -notmatch ('v' + [regex]::Escape($version))) { Fail 'Versioning document does not identify the current source version.' }
if ($Tag -and $Tag -ne "v$version") { Fail "Tag $Tag does not match v$version." }
Write-Output "VERSION_SOURCE=$version"
Write-Output 'VERSION_CONSISTENCY=passed'
