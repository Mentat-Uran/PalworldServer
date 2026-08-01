[CmdletBinding()]
param(
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'management-api.ps1')
$management = Get-ManagementEndpointConfig -ProjectDirectory $projectDir

$requiredRules = @()
if ($management.restEnabled) {
    $requiredRules += @{ Name = "Palworld Block REST $($management.restPort) Public"; Port = $management.restPort }
}
if ($management.legacyRconEnabled) {
    $requiredRules += @{ Name = "Palworld Block RCON $($management.rconPort) Public"; Port = $management.rconPort }
}

function Test-ManagementFirewallRules {
    $missing = @()
    foreach ($required in $requiredRules) {
        $matching = @()
        $rules = @(Get-NetFirewallRule -DisplayName $required.Name -ErrorAction SilentlyContinue |
            Where-Object { $_.Enabled -eq 'True' -and $_.Direction -eq 'Inbound' -and $_.Action -eq 'Block' })
        foreach ($rule in $rules) {
            $filters = @(Get-NetFirewallPortFilter -AssociatedNetFirewallRule $rule -ErrorAction SilentlyContinue)
            if ($filters | Where-Object { $_.Protocol -eq 'TCP' -and [string]$_.LocalPort -eq [string]$required.Port }) {
                $matching += $rule
            }
        }
        if ($matching.Count -eq 0) { $missing += "$($required.Name) (TCP $($required.Port))" }
    }
    return $missing
}

function Remove-StaleManagementRules {
    $expectedNames = @($requiredRules | ForEach-Object { $_.Name })
    $stale = @(Get-NetFirewallRule -ErrorAction SilentlyContinue |
        Where-Object {
            $_.DisplayName -like 'Palworld Block REST * Public' -or
            $_.DisplayName -like 'Palworld Block RCON * Public'
        } |
        Where-Object { $expectedNames -notcontains $_.DisplayName })
    foreach ($rule in $stale) {
        try { Remove-NetFirewallRule -Name $rule.Name -ErrorAction Stop } catch { throw "Failed to remove stale management firewall rule '$($rule.DisplayName)': $($_.Exception.Message)" }
        Write-Host "Removed stale firewall rule: $($rule.DisplayName)"
    }
}

if (-not $Check) {
    Remove-StaleManagementRules
}
$missing = Test-ManagementFirewallRules
if ($Check) {
    if ($missing.Count -eq 0) {
        Write-Host "WIN_MANAGEMENT_FIREWALL_READY=true rest=$($management.restEnabled) rcon=$($management.legacyRconEnabled)"
        exit 0
    }
    Write-Host "WIN_MANAGEMENT_FIREWALL_READY=false missing=$($missing -join '; ')"
    exit 1
}

foreach ($required in $requiredRules) {
    $currentMissing = Test-ManagementFirewallRules
    if ($currentMissing -notcontains "$($required.Name) (TCP $($required.Port))") { continue }
    try {
        New-NetFirewallRule -DisplayName $required.Name -Direction Inbound -Action Block `
            -Protocol TCP -LocalPort $required.Port -RemoteAddress Any -Profile Any -Enabled True `
            -ErrorAction Stop | Out-Null
        Write-Host "Created firewall rule: $($required.Name)"
    } catch {
        Write-Error "Failed to create $($required.Name): $($_.Exception.Message). Run this script from an elevated Administrator PowerShell."
        exit 1
    }
}

$missing = Test-ManagementFirewallRules
if ($missing.Count -gt 0) {
    Write-Error "Windows management firewall gate is incomplete: $($missing -join '; ')"
    exit 1
}
Write-Host 'WIN_MANAGEMENT_FIREWALL_READY=true'
exit 0
