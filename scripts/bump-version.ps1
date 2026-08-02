[CmdletBinding()]
param([Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version)

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$versionPath = Join-Path $projectDir 'version.json'
$versionJson = [ordered]@{ version = $Version; channel = 'stable'; minSupportedWindows = 'Windows 10 22H2' }
[System.IO.File]::WriteAllText($versionPath, ($versionJson | ConvertTo-Json -Depth 3), (New-Object System.Text.UTF8Encoding($false)))
$packagePath = Join-Path $projectDir 'package.json'
$package = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 | ConvertFrom-Json
$package.version = $Version
[System.IO.File]::WriteAllText($packagePath, ($package | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding($false)))
$lockPath = Join-Path $projectDir 'package-lock.json'
$lockText = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8
$lockText = [regex]::Replace($lockText, '(?m)(^\s*"version"\s*:\s*")\d+\.\d+\.\d+("\s*,)', { param($match) $match.Groups[1].Value + $Version + $match.Groups[2].Value }, 2)
[System.IO.File]::WriteAllText($lockPath, $lockText, (New-Object System.Text.UTF8Encoding($false)))
$changelogPath = Join-Path $projectDir 'CHANGELOG.md'
$changelog = Get-Content -LiteralPath $changelogPath -Raw -Encoding UTF8
if ($changelog -notmatch "(?m)^## \[$([regex]::Escape($Version))\]") {
    $entry = "## [$Version] - $((Get-Date).ToString('yyyy-MM-dd'))`r`n`r`n### Changed`r`n`r`n- Pending release notes; replace this line before publishing.`r`n`r`n"
    $changelog = $changelog -replace '(?m)^## \[Unreleased\]\r?\n', "## [Unreleased]`r`n`r`nNo unreleased changes.`r`n`r`n$entry"
    [System.IO.File]::WriteAllText($changelogPath, $changelog, (New-Object System.Text.UTF8Encoding($false)))
}
& (Join-Path $PSScriptRoot 'test-version-consistency.ps1')
