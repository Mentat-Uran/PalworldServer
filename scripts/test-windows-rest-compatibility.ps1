[CmdletBinding()]
param()

# Source-only behavior regression for the Windows REST launch mode. The tested
# argument builder is pure; this script never starts a server or contacts a
# runtime, Docker, REST, or RCON endpoint.
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'win-runtime.ps1')

function Assert-WindowsRestCompatibility {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "WINDOWS_REST_COMPATIBILITY_FAILED: $Message" }
}

$environment = @{
    PORT = '8211'; QUERY_PORT = '27015'; REST_API_ENABLED = 'true'; REST_API_PORT = '8212';
    RCON_ENABLED = 'false'; ENABLE_LEGACY_RCON = 'false'; RCON_PORT = '25575';
    WINDOWS_REST_COMPATIBILITY_MODE = 'compat'; LOG_FORMAT_TYPE = 'text';
    ENABLE_PERF_THREADING_ARGS = 'false'
}
$management = Get-ManagementEndpointConfig -ProjectDirectory $projectDir -Environment $environment
$compat = Get-WindowsRuntimeLaunchArguments -Management $management -Environment $environment -LogPath 'C:\temp\palworld-engine.log'
Assert-WindowsRestCompatibility (@($compat.flags) -contains '-restapi') 'compat mode must add the REST compatibility switch.'
Assert-WindowsRestCompatibility (@($compat.flags) -notcontains '-rcon') 'compat mode must not add the deprecated RCON switch.'
Assert-WindowsRestCompatibility (@($compat.flags) -notcontains '-rpc') 'compat mode must not add the deprecated RPC switch.'

$iniOnlyEnvironment = $environment.Clone()
$iniOnlyEnvironment.WINDOWS_REST_COMPATIBILITY_MODE = 'ini-only'
$iniOnlyManagement = Get-ManagementEndpointConfig -ProjectDirectory $projectDir -Environment $iniOnlyEnvironment
$iniOnly = Get-WindowsRuntimeLaunchArguments -Management $iniOnlyManagement -Environment $iniOnlyEnvironment -LogPath 'C:\temp\palworld-engine.log'
Assert-WindowsRestCompatibility (@($iniOnly.flags) -notcontains '-restapi') 'ini-only mode must not add the compatibility switch.'

$disabledEnvironment = $environment.Clone()
$disabledEnvironment.REST_API_ENABLED = 'false'
$disabledManagement = Get-ManagementEndpointConfig -ProjectDirectory $projectDir -Environment $disabledEnvironment
$disabled = Get-WindowsRuntimeLaunchArguments -Management $disabledManagement -Environment $disabledEnvironment -LogPath 'C:\temp\palworld-engine.log'
Assert-WindowsRestCompatibility (@($disabled.flags) -notcontains '-restapi') 'disabled REST must not add the compatibility switch.'

$announceCommand = Get-WindowsRconFallbackCommand -Operation announce -Payload ([ordered]@{ message = 'Maintenance soon' })
$kickCommand = Get-WindowsRconFallbackCommand -Operation kick -Payload ([ordered]@{ userid = 'steam-123' })
$banCommand = Get-WindowsRconFallbackCommand -Operation ban -Payload ([ordered]@{ userid = 'steam-123' })
$unbanCommand = Get-WindowsRconFallbackCommand -Operation unban -Payload ([ordered]@{ userid = 'steam-123' })
Assert-WindowsRestCompatibility ($announceCommand -eq 'Broadcast Maintenance soon') 'announce fallback must map to Broadcast.'
Assert-WindowsRestCompatibility ($kickCommand -eq 'KickPlayer steam-123') 'kick fallback must map to KickPlayer.'
Assert-WindowsRestCompatibility ($banCommand -eq 'BanPlayer steam-123') 'ban fallback must map to BanPlayer.'
Assert-WindowsRestCompatibility ($unbanCommand -eq 'UnBanPlayer steam-123') 'unban fallback must map to UnBanPlayer.'

$invalidRejected = $false
try { Get-WindowsRconFallbackCommand -Operation kick -Payload ([ordered]@{ userid = 'not safe!' }) | Out-Null } catch { $invalidRejected = $true }
Assert-WindowsRestCompatibility $invalidRejected 'fallback command builder must reject unsafe player IDs.'

Write-Output 'WINDOWS_REST_COMPATIBILITY=passed'
Write-Output 'WINDOWS_REST_COMPATIBILITY_SCOPE=pure-launch-and-rcon-command-builders'
