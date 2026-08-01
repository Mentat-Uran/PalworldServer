[CmdletBinding()]
param(
    [ValidateSet('windows','docker')][string]$Runtime = 'windows',
    [string]$DisplayName = 'My Palworld Server',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $projectDir '.env'
$templatePath = Join-Path $projectDir '.env.example'
$descriptorPath = Join-Path $projectDir 'project.json'
if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) { throw '.env.example is missing.' }
if ((Test-Path -LiteralPath $envPath -PathType Leaf) -and -not $Force) { throw '.env already exists. Use -Force only after reviewing a backup.' }
if (Test-Path -LiteralPath $envPath -PathType Leaf) {
    $backupDir = Join-Path $projectDir 'data\diagnostics'
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    $backupPath = Join-Path $backupDir ('.env.before-bootstrap-' + (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ') + '.bak')
    Copy-Item -LiteralPath $envPath -Destination $backupPath -Force
    Write-Host "EXISTING_ENV_BACKUP=$backupPath"
}

$bytes = New-Object byte[] 32
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$adminPassword = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+','-').Replace('/','_')
$content = [System.IO.File]::ReadAllText($templatePath)
$content = $content.Replace('ADMIN_PASSWORD=CHANGE_ME_WITH_A_LONG_RANDOM_PASSWORD', "ADMIN_PASSWORD=$adminPassword")
[System.IO.File]::WriteAllText($envPath, $content, (New-Object System.Text.UTF8Encoding($false)))
$descriptor = [ordered]@{
    schemaVersion = 1
    projectId = [guid]::NewGuid().ToString()
    displayName = if ($DisplayName.Trim()) { $DisplayName.Trim() } else { 'My Palworld Server' }
    runtimePreference = $Runtime
    createdAt = (Get-Date).ToUniversalTime().ToString('o')
}
[System.IO.File]::WriteAllText($descriptorPath, ($descriptor | ConvertTo-Json -Depth 3), (New-Object System.Text.UTF8Encoding($false)))
Write-Host 'FIRST_RUN_CONFIGURED=true'
Write-Host "RUNTIME=$Runtime"
Write-Host "PROJECT_DESCRIPTOR=$descriptorPath"
Write-Host 'ADMIN_PASSWORD_CREATED=true'
Write-Host 'The generated password is intentionally not printed. Store it in a password manager.'
