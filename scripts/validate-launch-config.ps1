[CmdletBinding()]
param(
    [switch]$Summary
)

# Read-only launch gate. It validates .env and prints non-sensitive endpoint
# metadata; it never starts a runtime, provider, Docker, or PalServer.
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'management-api.ps1')
. (Join-Path $PSScriptRoot 'networking.ps1')

try {
    $environment = Read-ManagementEnv -ProjectDirectory $projectDir
    if ($environment.Count -eq 0) { throw '.env is missing or empty.' }
    . (Join-Path $PSScriptRoot 'tunnel-provider-catalog.ps1')
    $management = Get-ManagementEndpointConfig -ProjectDirectory $projectDir -Environment $environment
    $network = Test-NetworkConfiguration -Environment $environment
    if (-not $network.ok) {
        throw ('Network configuration is invalid: ' + (@($network.errors) -join '; '))
    }
    $provider = if ($network.provider) { [string]$network.provider } else { 'none' }
    if ($provider -notin @(Get-TunnelProviderIds -ProjectDirectory $projectDir)) { throw "Unsupported tunnel provider: $provider" }

    if (-not $Summary) { Write-Output 'LAUNCH_CONFIGURATION=passed' }
    Write-Output "GAME_PORT=$($management.gamePort)"
    Write-Output "CONTAINER_NAME=$($management.containerName)"
    Write-Output "WINDOWS_REST_COMPATIBILITY_MODE=$($management.windowsRestCompatibilityMode)"
    Write-Output "QUERY_PORT=$($management.queryPort)"
    Write-Output "REST_API_PORT=$($management.restPort)"
    Write-Output "REST_ENABLED=$($management.restEnabled.ToString().ToLowerInvariant())"
    Write-Output "RCON_PORT=$($management.rconPort)"
    Write-Output "RCON_ENABLED=$($management.legacyRconEnabled.ToString().ToLowerInvariant())"
    Write-Output "NETWORK_MODE=$($network.mode)"
    Write-Output "TUNNEL_PROVIDER=$provider"
    exit 0
} catch {
    Write-Host "[FAIL] Launch configuration is invalid: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
