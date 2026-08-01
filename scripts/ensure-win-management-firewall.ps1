[CmdletBinding()]
param(
    [switch]$Check
)

$ErrorActionPreference = 'Stop'

$requiredRules = @(
    @{ Name = 'Palworld Block REST 8212 Public'; Port = 8212 },
    @{ Name = 'Palworld Block RCON 25575 Public'; Port = 25575 }
)

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

$missing = Test-ManagementFirewallRules
if ($Check) {
    if ($missing.Count -eq 0) {
        Write-Host 'WIN_MANAGEMENT_FIREWALL_READY=true'
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
