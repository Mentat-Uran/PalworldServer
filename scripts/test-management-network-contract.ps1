[CmdletBinding()]
param()

# Source-only regression for the shared management and network contracts. It
# never reads the private .env and never contacts a runtime or tunnel provider.
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'management-api.ps1')
. (Join-Path $PSScriptRoot 'networking.ps1')

function Assert-Contract([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "MANAGEMENT_NETWORK_CONTRACT_FAILED: $Message" }
}

$environment = @{
    REST_API_ENABLED = 'true'; REST_API_PORT = '8212'; RCON_ENABLED = 'false';
    ENABLE_LEGACY_RCON = 'false'; RCON_PORT = '25575'; PORT = '8211'; QUERY_PORT = '27015';
    NETWORK_MODE = 'direct'; TUNNEL_PROVIDER = 'none'
}
$config = Get-ManagementEndpointConfig -ProjectDirectory $projectDir -Environment $environment
Assert-Contract ([bool]$config.restEnabled) 'REST must be enabled by the neutral management contract.'
Assert-Contract ([string]$config.restBaseUrl -eq 'http://127.0.0.1:8212/v1/api') 'REST must remain loopback-bound.'
Assert-Contract ([string]$config.containerName -eq 'palworld-server') 'Default container identity must remain backward compatible.'
Assert-Contract ([string]$config.windowsRestCompatibilityMode -eq 'ini-only') 'Windows REST must default to the documented INI-only mode.'
Assert-Contract (-not [bool]$config.legacyRconEnabled) 'Legacy RCON must remain disabled by default.'

$isolatedEnvironment = $environment.Clone()
$isolatedEnvironment.PROJECT_INSTANCE_ID = 'palworld-family-a'
$isolatedConfig = Get-ManagementEndpointConfig -ProjectDirectory $projectDir -Environment $isolatedEnvironment
Assert-Contract ([string]$isolatedConfig.containerName -eq 'palworld-family-a') 'Configured instance identity must be used by the management contract.'
Assert-Contract ([string](Get-ManagementMutexName -ProjectDirectory $projectDir -Environment $isolatedEnvironment) -eq 'Global\PalworldServerRuntime_palworld-family-a') 'Runtime mutex must be scoped to the configured instance.'

$invalidInstance = $environment.Clone()
$invalidInstance.PROJECT_INSTANCE_ID = 'Not Safe/For Docker'
$invalidRejected = $false
try { [void](Get-ManagementEndpointConfig -ProjectDirectory $projectDir -Environment $invalidInstance) } catch { $invalidRejected = $true }
Assert-Contract $invalidRejected 'Unsafe instance identities must be rejected.'

$invalidRestMode = $environment.Clone()
$invalidRestMode.WINDOWS_REST_COMPATIBILITY_MODE = 'unknown'
$invalidRestModeRejected = $false
try { [void](Get-ManagementEndpointConfig -ProjectDirectory $projectDir -Environment $invalidRestMode) } catch { $invalidRestModeRejected = $true }
Assert-Contract $invalidRestModeRejected 'Unknown Windows REST compatibility modes must be rejected.'

$direct = Test-NetworkConfiguration -Environment $environment
Assert-Contract ([bool]$direct.ok) 'Direct mode should pass with the neutral defaults.'

$tunnelEnvironment = $environment.Clone()
$tunnelEnvironment.NETWORK_MODE = 'tunnel'
$tunnelEnvironment.TUNNEL_PROVIDER = 'sakurafrp'
$tunnelEnvironment.TUNNEL_LOCAL_PORT = '8211'
$tunnel = Test-NetworkConfiguration -Environment $tunnelEnvironment
Assert-Contract ([bool]$tunnel.ok -and [string]$tunnel.provider -eq 'sakurafrp') 'Sakura FRP tunnel mode should pass when the local game port matches.'

$communityEnvironment = $environment.Clone()
$communityEnvironment.NETWORK_MODE = 'community'
$communityEnvironment.TUNNEL_PROVIDER = 'none'
$community = Test-NetworkConfiguration -Environment $communityEnvironment
Assert-Contract (-not [bool]$community.ok -and @($community.errors).Count -ge 2) 'Community mode must fail closed without PUBLIC_IP and PUBLIC_PORT.'

$conflictEnvironment = $environment.Clone()
$conflictEnvironment.RCON_ENABLED = 'true'
$conflictEnvironment.ENABLE_LEGACY_RCON = 'true'
$conflictEnvironment.RCON_PORT = '8212'
$conflictRejected = $false
try { [void](Get-ManagementEndpointConfig -ProjectDirectory $projectDir -Environment $conflictEnvironment) } catch { $conflictRejected = $true }
Assert-Contract $conflictRejected 'REST and legacy RCON port collisions must be rejected.'

Write-Output 'MANAGEMENT_NETWORK_CONTRACT=passed'
Write-Output 'MANAGEMENT_NETWORK_CONTRACT_SCOPE=source-only'
