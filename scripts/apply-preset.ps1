[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateSet('vanilla','casual-small-server','performance-conservative')][string]$Preset,
    [switch]$WhatIfOnly
)

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $projectDir '.env'
$presetPath = Join-Path $projectDir "presets\$Preset.env"
if (-not (Test-Path -LiteralPath $envPath -PathType Leaf)) { throw 'Create .env with scripts\bootstrap-first-run.ps1 before applying a preset.' }
if (-not (Test-Path -LiteralPath $presetPath -PathType Leaf)) { throw "Preset not found: $Preset" }

$protected = @('ADMIN_PASSWORD','SERVER_PASSWORD','PUBLIC_IP','PUBLIC_PORT','PORT','QUERY_PORT','REST_API_PORT','RCON_PORT','NETWORK_MODE','TUNNEL_PROVIDER','TUNNEL_EXECUTABLE','TUNNEL_ARGUMENTS')
$current = @{}
$lines = [System.IO.File]::ReadAllLines($envPath)
foreach ($line in $lines) {
    $index = $line.IndexOf('=')
    if ($index -gt 0) { $current[$line.Substring(0,$index).Trim()] = $line.Substring($index + 1).Trim().Trim('"').Trim("'") }
}
$updates = [ordered]@{}
foreach ($line in [System.IO.File]::ReadAllLines($presetPath)) {
    $trimmed = $line.Trim()
    if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
    $index = $trimmed.IndexOf('=')
    if ($index -le 0) { continue }
    $key = $trimmed.Substring(0,$index).Trim()
    if ($protected -contains $key) { throw "Preset cannot modify protected key: $key" }
    $value = $trimmed.Substring($index + 1)
    if (-not $current.ContainsKey($key) -or [string]$current[$key] -cne [string]$value) { $updates[$key] = $value }
}
if ($WhatIfOnly) { $updates | ConvertTo-Json -Compress; exit 0 }
if ($updates.Count -eq 0) { Write-Host "PRESET=$Preset CHANGED=0"; exit 0 }
$output = New-Object System.Collections.Generic.List[string]
$seen = @{}
foreach ($line in $lines) {
    $index = $line.IndexOf('=')
    if ($index -le 0) { $output.Add($line); continue }
    $key = $line.Substring(0,$index).Trim()
    if ($updates.Contains($key)) { $output.Add("$key=$($updates[$key])"); $seen[$key] = $true } else { $output.Add($line) }
}
foreach ($key in $updates.Keys) { if (-not $seen.ContainsKey($key)) { $output.Add("$key=$($updates[$key])") } }
if ($PSCmdlet.ShouldProcess($envPath, "Apply preset $Preset")) {
    [System.IO.File]::WriteAllLines($envPath, [string[]]$output, (New-Object System.Text.UTF8Encoding($false)))
}
Write-Host "PRESET=$Preset CHANGED=$($updates.Count)"
