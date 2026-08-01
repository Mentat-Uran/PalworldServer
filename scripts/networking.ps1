# Network mode validation shared by onboarding and the Web Console.

function Get-NetworkModeContract {
    param([Parameter(Mandatory)][string]$Mode)
    switch ($Mode.ToLowerInvariant()) {
        'direct' {
            return [ordered]@{
                mode = 'direct'; label = 'Direct connection';
                requiredPorts = @('PORT/UDP'); externalPorts = @('PORT/UDP');
                forbiddenPorts = @('REST_API_PORT/TCP', 'RCON_PORT/TCP');
                requiredKeys = @(); platforms = @('Steam', 'Xbox', 'PS5', 'Mac');
                health = 'server process + local UDP listener + external player test'
            }
        }
        'community' {
            return [ordered]@{
                mode = 'community'; label = 'Community server';
                requiredPorts = @('PORT/UDP', 'PUBLIC_PORT/UDP'); externalPorts = @('PUBLIC_PORT/UDP');
                forbiddenPorts = @('REST_API_PORT/TCP', 'RCON_PORT/TCP');
                requiredKeys = @('PUBLIC_IP', 'PUBLIC_PORT'); platforms = @('Steam', 'Xbox', 'PS5', 'Mac');
                health = 'server process + local listener + listing/join test from an external network'
            }
        }
        'tunnel' {
            return [ordered]@{
                mode = 'tunnel'; label = 'UDP tunnel provider';
                requiredPorts = @('PORT/UDP'); externalPorts = @('provider remote UDP port');
                forbiddenPorts = @('REST_API_PORT/TCP', 'RCON_PORT/TCP');
                requiredKeys = @('TUNNEL_PROVIDER'); platforms = @('provider-dependent');
                health = 'server process + local listener + provider process + external player test'
            }
        }
        default { throw "Unsupported NETWORK_MODE: $Mode" }
    }
}

function Test-NetworkConfiguration {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Environment)
    $mode = if ($Environment.ContainsKey('NETWORK_MODE') -and $Environment['NETWORK_MODE']) { [string]$Environment['NETWORK_MODE'] } else { 'direct' }
    $contract = Get-NetworkModeContract -Mode $mode
    $errors = @()
    $provider = if ($Environment.ContainsKey('TUNNEL_PROVIDER') -and $Environment['TUNNEL_PROVIDER']) { [string]$Environment['TUNNEL_PROVIDER'] } else { 'none' }
    if ($mode -eq 'tunnel' -and $provider -eq 'none') { $errors += 'NETWORK_MODE=tunnel requires an explicit TUNNEL_PROVIDER.' }
    if ($mode -ne 'tunnel' -and $provider -ne 'none') { $errors += 'TUNNEL_PROVIDER must be none unless NETWORK_MODE=tunnel.' }
    if ($mode -eq 'community') {
        if ([string]::IsNullOrWhiteSpace([string]$Environment['PUBLIC_IP'])) { $errors += 'COMMUNITY mode requires PUBLIC_IP.' }
        $publicPort = 0
        if (-not [int]::TryParse([string]$Environment['PUBLIC_PORT'], [ref]$publicPort) -or $publicPort -lt 1 -or $publicPort -gt 65535) { $errors += 'COMMUNITY mode requires a valid PUBLIC_PORT.' }
    }
    if ($mode -eq 'tunnel') {
        $localPort = if ($Environment['TUNNEL_LOCAL_PORT']) { [string]$Environment['TUNNEL_LOCAL_PORT'] } else { [string]$Environment['PORT'] }
        if ($localPort -ne [string]$Environment['PORT']) { $errors += 'TUNNEL_LOCAL_PORT must equal PORT so the game and tunnel target agree.' }
    }
    return [ordered]@{ ok = ($errors.Count -eq 0); mode = $mode; provider = $provider; contract = $contract; errors = $errors }
}
