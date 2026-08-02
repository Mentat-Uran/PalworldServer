# Shared management endpoint and REST adapter.
# Keep this file compatible with Windows PowerShell 5.1 and PowerShell 7.

function Read-ManagementEnv {
    param([Parameter(Mandatory)][string]$ProjectDirectory)
    $path = Join-Path $ProjectDirectory '.env'
    $values = @{}
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $values }
    foreach ($lineObject in [System.IO.File]::ReadAllLines($path)) {
        $line = ([string]$lineObject).Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        $separator = $line.IndexOf('=')
        if ($separator -le 0) { continue }
        $key = $line.Substring(0, $separator).Trim()
        $value = $line.Substring($separator + 1).Trim()
        if ($value.Length -ge 2 -and $value.StartsWith('"') -and $value.EndsWith('"')) {
            $value = $value.Substring(1, $value.Length - 2)
        } elseif ($value.Length -ge 2 -and $value.StartsWith("'") -and $value.EndsWith("'")) {
            $value = $value.Substring(1, $value.Length - 2).Replace("\'", "'")
        }
        $values[$key] = $value
    }
    return $values
}

function ConvertTo-ManagementBoolean {
    param([object]$Value, [bool]$Default = $false)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $Default }
    return ([string]$Value -match '^(?i:true|1|yes)$')
}

function ConvertTo-ManagementPort {
    param([object]$Value, [int]$Default)
    $parsed = 0
    if (-not [int]::TryParse([string]$Value, [ref]$parsed)) { $parsed = $Default }
    if ($parsed -lt 1 -or $parsed -gt 65535) {
        throw "Management port must be between 1 and 65535: $parsed"
    }
    return $parsed
}

function Get-WindowsRestCompatibilityMode {
    param([System.Collections.IDictionary]$Environment)
    $mode = if ($null -ne $Environment -and $Environment.ContainsKey('WINDOWS_REST_COMPATIBILITY_MODE') -and $Environment['WINDOWS_REST_COMPATIBILITY_MODE']) {
        ([string]$Environment['WINDOWS_REST_COMPATIBILITY_MODE']).Trim().ToLowerInvariant()
    } else {
        'ini-only'
    }
    if ($mode -notin @('compat', 'ini-only')) {
        throw 'WINDOWS_REST_COMPATIBILITY_MODE must be compat or ini-only.'
    }
    return $mode
}

function Get-ManagementContainerName {
    param(
        [Parameter(Mandatory)][string]$ProjectDirectory,
        [System.Collections.IDictionary]$Environment
    )
    if ($null -eq $Environment) { $Environment = Read-ManagementEnv -ProjectDirectory $ProjectDirectory }
    $name = if ($Environment.ContainsKey('PROJECT_INSTANCE_ID') -and $Environment['PROJECT_INSTANCE_ID']) {
        [string]$Environment['PROJECT_INSTANCE_ID']
    } else {
        'palworld-server'
    }
    if ($name -notmatch '^[a-z0-9][a-z0-9_.-]{0,62}$') {
        throw 'PROJECT_INSTANCE_ID must be a Docker-safe name: lowercase letters, numbers, dot, underscore, or hyphen; maximum 63 characters.'
    }
    return $name
}

function Get-ManagementMutexName {
    param(
        [Parameter(Mandatory)][string]$ProjectDirectory,
        [System.Collections.IDictionary]$Environment
    )
    $containerName = Get-ManagementContainerName -ProjectDirectory $ProjectDirectory -Environment $Environment
    return "Global\PalworldServerRuntime_$containerName"
}

function Get-ManagementEndpointConfig {
    param(
        [Parameter(Mandatory)][string]$ProjectDirectory,
        [System.Collections.IDictionary]$Environment
    )
    if ($null -eq $Environment) { $Environment = Read-ManagementEnv -ProjectDirectory $ProjectDirectory }
    $restEnabled = ConvertTo-ManagementBoolean $Environment['REST_API_ENABLED'] $true
    $rconEnabled = ConvertTo-ManagementBoolean $Environment['RCON_ENABLED'] $false
    $legacyEnabled = ConvertTo-ManagementBoolean $Environment['ENABLE_LEGACY_RCON'] $false
    if ($rconEnabled -and -not $legacyEnabled) { $legacyEnabled = $true }
    $restPort = ConvertTo-ManagementPort $Environment['REST_API_PORT'] 8212
    $rconPort = ConvertTo-ManagementPort $Environment['RCON_PORT'] 25575
    if ($restPort -eq $rconPort -and $restEnabled -and $legacyEnabled) {
        throw 'REST_API_PORT and RCON_PORT must be different when both management APIs are enabled.'
    }
    $config = [ordered]@{
        containerName = Get-ManagementContainerName -ProjectDirectory $ProjectDirectory -Environment $Environment
        windowsRestCompatibilityMode = Get-WindowsRestCompatibilityMode -Environment $Environment
        restEnabled = $restEnabled
        restPort = $restPort
        restBindAddress = '127.0.0.1'
        restBaseUrl = "http://127.0.0.1:$restPort/v1/api"
        rconEnabled = $rconEnabled
        legacyRconEnabled = $legacyEnabled
        rconPort = $rconPort
        rconBindAddress = '127.0.0.1'
        gamePort = ConvertTo-ManagementPort $Environment['PORT'] 8211
        queryPort = ConvertTo-ManagementPort $Environment['QUERY_PORT'] 27015
        networkMode = if ($Environment.ContainsKey('NETWORK_MODE') -and $Environment['NETWORK_MODE']) { [string]$Environment['NETWORK_MODE'] } else { 'direct' }
    }
    if ($config.networkMode -notin @('direct', 'community', 'tunnel')) {
        throw "NETWORK_MODE must be direct, community, or tunnel: $($config.networkMode)"
    }
    return $config
}

function Get-ManagementAdminPassword {
    param([Parameter(Mandatory)][string]$ProjectDirectory)
    $environment = Read-ManagementEnv -ProjectDirectory $ProjectDirectory
    if (-not $environment.ContainsKey('ADMIN_PASSWORD') -or [string]::IsNullOrWhiteSpace([string]$environment['ADMIN_PASSWORD'])) {
        throw 'ADMIN_PASSWORD is not configured.'
    }
    return [string]$environment['ADMIN_PASSWORD']
}

function Invoke-ManagementRestRequest {
    param(
        [Parameter(Mandatory)][string]$ProjectDirectory,
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('GET','POST')][string]$Method = 'GET',
        [System.Collections.IDictionary]$Body,
        [int]$TimeoutMs = 30000
    )
    $config = Get-ManagementEndpointConfig -ProjectDirectory $ProjectDirectory
    if (-not $config.restEnabled) {
        return @{ ok = $false; code = 'rest-disabled'; error = 'REST_API_ENABLED=false; management operation refused.' }
    }
    if ($Path -notmatch '^/[A-Za-z0-9._/-]+$') { throw "Invalid REST path: $Path" }
    $password = Get-ManagementAdminPassword -ProjectDirectory $ProjectDirectory
    $basicBytes = [System.Text.Encoding]::UTF8.GetBytes("admin:$password")
    $headers = @{ Authorization = 'Basic ' + [Convert]::ToBase64String($basicBytes) }
    $uri = $config.restBaseUrl.TrimEnd('/') + $Path
    $timeoutSeconds = [math]::Max(1, [int][math]::Ceiling($TimeoutMs / 1000.0))
    try {
        $request = @{ Uri = $uri; Method = $Method; Headers = $headers; TimeoutSec = $timeoutSeconds; UseBasicParsing = $true; ErrorAction = 'Stop' }
        if ($null -ne $Body) {
            $request.Body = ($Body | ConvertTo-Json -Compress -Depth 5)
            $request.ContentType = 'application/json'
        }
        $response = Invoke-WebRequest @request
        return @{ ok = $true; statusCode = [int]$response.StatusCode; content = [string]$response.Content; method = 'rest'; endpoint = $Path }
    } catch {
        return @{ ok = $false; code = 'rest-request-failed'; error = $_.Exception.Message; endpoint = $Path }
    }
}

function Invoke-ManagementOperation {
    param(
        [Parameter(Mandatory)][string]$ProjectDirectory,
        [Parameter(Mandatory)][ValidateSet('save','announce','kick','ban','unban','shutdown')][string]$Operation,
        [System.Collections.IDictionary]$Payload
    )
    $body = if ($null -eq $Payload) { @{} } else { $Payload }
    switch ($Operation) {
        'save' { $path = '/save'; $body = $null }
        'announce' { $path = '/announce' }
        'kick' { $path = '/kick' }
        'ban' { $path = '/ban' }
        'unban' { $path = '/unban' }
        'shutdown' { $path = '/shutdown' }
    }
    return Invoke-ManagementRestRequest -ProjectDirectory $ProjectDirectory -Path $path -Method POST -Body $body -TimeoutMs 30000
}
