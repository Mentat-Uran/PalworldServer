[CmdletBinding()]
param()

# Source-only policy test. It proves that cloud CI validates source but does
# not build, sign, upload, or publish a formal release.
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot

function Assert-ReleasePolicy {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "RELEASE_POLICY_TEST_FAILED: $Message" }
}

$workflowPath = Join-Path $projectDir '.github\workflows\validate.yml'
$localReleasePath = Join-Path $projectDir 'scripts\publish-local-release.ps1'
Assert-ReleasePolicy (Test-Path -LiteralPath $workflowPath -PathType Leaf) 'Validation workflow is missing.'
Assert-ReleasePolicy (Test-Path -LiteralPath $localReleasePath -PathType Leaf) 'Local release orchestrator is missing.'
$workflow = [System.IO.File]::ReadAllText($workflowPath)
$localRelease = [System.IO.File]::ReadAllText($localReleasePath)

foreach ($forbidden in @(
    'actions/setup-dotnet@', 'dotnet restore', 'dotnet build', 'dotnet publish',
    'signtool', 'actions/upload-artifact', 'softprops/action-gh-release',
    'gh release', 'softprops/action-gh-release'
)) {
    Assert-ReleasePolicy (-not $workflow.Contains($forbidden)) "Cloud workflow contains forbidden release/build capability: $forbidden"
}
foreach ($required in @(
    'permissions:', 'contents: read', 'audit-public-release.ps1',
    'test-release-policy.ps1', 'verify-project.ps1 -SkipDocker'
)) {
    Assert-ReleasePolicy ($workflow.Contains($required)) "Cloud workflow is missing source-only policy token: $required"
}
foreach ($required in @(
    'CertificateThumbprint', 'SignTool.exe', 'Invoke-SignAndVerify',
    'test-clean-checkout.ps1', 'audit-public-release.ps1',
    'verify-project.ps1', 'build-desktop-app.ps1',
    'build-release-bundle.ps1', 'Get-FileHash',
    'does not tag, push, or create a GitHub Release'
)) {
    Assert-ReleasePolicy ($localRelease.Contains($required)) "Local release orchestrator is missing: $required"
}
$signPreflight = $localRelease.IndexOf('Assert-LocalRelease ($SignToolPath', [System.StringComparison]::Ordinal)
$firstBuild = $localRelease.IndexOf('build-desktop-app.ps1', [System.StringComparison]::Ordinal)
Assert-ReleasePolicy ($signPreflight -ge 0 -and $firstBuild -gt $signPreflight) 'Signing tool preflight must happen before the first build.'

Write-Output 'RELEASE_POLICY=passed'
Write-Output 'RELEASE_POLICY_SCOPE=source-only'
exit 0
