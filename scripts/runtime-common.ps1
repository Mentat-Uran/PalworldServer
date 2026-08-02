[CmdletBinding()]
# Runtime common helpers: state file, mutex, incidents, switch log.
# Loaded by docker-runtime.ps1, win-runtime.ps1, switch-runtime.ps1, settings-panel.ps1.
# Keep PowerShell 5.1 compatible and ASCII-only.

$projectDir = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'management-api.ps1')
$statePath = Join-Path $projectDir 'data\runtime.state'
$stateTmpPath = Join-Path $projectDir 'data\runtime.state.tmp'
$incidentsPath = Join-Path $projectDir 'data\diagnostics\incidents.jsonl'
$switchLogPath = Join-Path $projectDir 'data\diagnostics\switch.log'

# ---------------------------------------------------------------------------
# runtime.state
# ---------------------------------------------------------------------------

function Get-RuntimeState {
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        return [pscustomobject]@{
            active          = 'none'
            pid             = $null
            startedAt       = $null
            version         = $null
            switching       = $false
            lastSwitchAt    = $null
            lastSwitchFrom  = $null
            lastSwitchTo    = $null
        }
    }
    try {
        $raw = Get-Content -LiteralPath $statePath -Raw -ErrorAction Stop
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
        # Ensure required fields exist
        if ($null -eq $obj.active)          { $obj | Add-Member -NotePropertyName active -NotePropertyValue 'none' -Force }
        if ($null -eq $obj.switching)       { $obj | Add-Member -NotePropertyName switching -NotePropertyValue $false -Force }
        if ($null -eq $obj.pid)             { $obj | Add-Member -NotePropertyName pid -NotePropertyValue $null -Force }
        if ($null -eq $obj.startedAt)       { $obj | Add-Member -NotePropertyName startedAt -NotePropertyValue $null -Force }
        if ($null -eq $obj.version)         { $obj | Add-Member -NotePropertyName version -NotePropertyValue $null -Force }
        if ($null -eq $obj.lastSwitchAt)    { $obj | Add-Member -NotePropertyName lastSwitchAt -NotePropertyValue $null -Force }
        if ($null -eq $obj.lastSwitchFrom)  { $obj | Add-Member -NotePropertyName lastSwitchFrom -NotePropertyValue $null -Force }
        if ($null -eq $obj.lastSwitchTo)    { $obj | Add-Member -NotePropertyName lastSwitchTo -NotePropertyValue $null -Force }
        return $obj
    } catch {
        Write-Warning "runtime.state parse failed: $($_.Exception.Message); treating as unknown"
        return [pscustomobject]@{
            active          = 'unknown'
            pid             = $null
            startedAt       = $null
            version         = $null
            switching       = $false
            lastSwitchAt    = $null
            lastSwitchFrom  = $null
            lastSwitchTo    = $null
        }
    }
}

function Update-RuntimeState {
    param(
        [Parameter(Mandatory = $false)][string]$Active,
        [Parameter(Mandatory = $false)]$PidValue,
        [Parameter(Mandatory = $false)][string]$StartedAt,
        [Parameter(Mandatory = $false)][string]$Version,
        [Parameter(Mandatory = $false)][Nullable[bool]]$Switching,
        [Parameter(Mandatory = $false)][string]$LastSwitchAt,
        [Parameter(Mandatory = $false)][string]$LastSwitchFrom,
        [Parameter(Mandatory = $false)][string]$LastSwitchTo
    )

    $current = Get-RuntimeState
    $hash = [ordered]@{}
    $hash['active']         = if ($PSBoundParameters.ContainsKey('Active'))         { $Active }         else { $current.active }
    $hash['pid']            = if ($PSBoundParameters.ContainsKey('PidValue'))        { $PidValue }        else { $current.pid }
    $hash['startedAt']      = if ($PSBoundParameters.ContainsKey('StartedAt'))       { $StartedAt }       else { $current.startedAt }
    $hash['version']        = if ($PSBoundParameters.ContainsKey('Version'))         { $Version }         else { $current.version }
    $hash['switching']      = if ($PSBoundParameters.ContainsKey('Switching'))       { [bool]$Switching } else { [bool]$current.switching }
    $hash['lastSwitchAt']   = if ($PSBoundParameters.ContainsKey('LastSwitchAt'))    { $LastSwitchAt }    else { $current.lastSwitchAt }
    $hash['lastSwitchFrom'] = if ($PSBoundParameters.ContainsKey('LastSwitchFrom'))  { $LastSwitchFrom }  else { $current.lastSwitchFrom }
    $hash['lastSwitchTo']   = if ($PSBoundParameters.ContainsKey('LastSwitchTo'))    { $LastSwitchTo }    else { $current.lastSwitchTo }

    $json = $hash | ConvertTo-Json -Compress

    # Ensure data directory exists
    $dataDir = Join-Path $projectDir 'data'
    if (-not (Test-Path -LiteralPath $dataDir -PathType Container)) {
        New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    }

    # Atomic write via temp + Move-Item
    [System.IO.File]::WriteAllText($stateTmpPath, $json, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $stateTmpPath -Destination $statePath -Force
}

function Test-RuntimeSwitching {
    <#
        Returns $true if a switch is currently in progress.
        Auto-resets the switching flag if it has been stuck for more than 5 minutes.
    #>
    $state = Get-RuntimeState
    if (-not $state.switching) { return $false }

    if ($state.lastSwitchAt) {
        try {
            $last = [datetime]$state.lastSwitchAt
            $elapsed = (Get-Date) - $last
            if ($elapsed.TotalMinutes -gt 5) {
                Write-Warning "runtime.state switching flag stuck for $([int]$elapsed.TotalMinutes) min; resetting"
                Update-RuntimeState -Switching $false
                Write-Incident -Level 'WARN' -Type 'switch-stuck' -Message "switching flag stuck > 5 min, auto-reset"
                return $false
            }
        } catch {
            # lastSwitchAt unparseable; do not auto-reset blindly
        }
    }
    return $true
}

# ---------------------------------------------------------------------------
# Global mutex
# ---------------------------------------------------------------------------

function Acquire-RuntimeMutex {
    param(
        [int]$TimeoutMs = 5000,
        [string]$MutexName = ''
    )
    if ([string]::IsNullOrWhiteSpace($MutexName)) {
        $MutexName = Get-ManagementMutexName -ProjectDirectory $projectDir
    }
    $mutex = New-Object System.Threading.Mutex($false, $MutexName)
    if (-not $mutex.WaitOne($TimeoutMs)) {
        $mutex.Dispose()
        throw "Failed to acquire runtime mutex '$MutexName' within $TimeoutMs ms (another operation in progress)"
    }
    return $mutex
}

# ---------------------------------------------------------------------------
# Incidents (single-line JSON appended to incidents.jsonl)
# ---------------------------------------------------------------------------

function Write-Incident {
    param(
        [Parameter(Mandatory)][ValidateSet('INFO','WARN','ERROR','CRITICAL')][string]$Level,
        [string]$Type = 'generic',
        [Parameter(Mandatory)][string]$Message,
        [string]$Detail = $null
    )
    $dir = Split-Path -Parent $incidentsPath
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    # Mask sensitive tokens: webhook URLs, passwords, last IPv4 octet
    $masked = $Message
    $masked = [regex]::Replace($masked, 'https?://[^/\s]+/api/webhooks/\S+', '<webhook>')
    $masked = [regex]::Replace($masked, '(?i)(password|passwd|token|secret|api[_-]?key)\s*[=:]\s*\S+', '$1=<masked>')
    $masked = [regex]::Replace($masked, '(\d{1,3}\.\d{1,3}\.\d{1,3}\.)\d{1,3}', '$1<masked>')

    $entry = [ordered]@{
        ts      = (Get-Date).ToString('o')
        level   = $Level
        type    = $Type
        message = $masked
    }
    if ($Detail) { $entry['detail'] = $Detail }

    $line = $entry | ConvertTo-Json -Compress
    Add-Content -LiteralPath $incidentsPath -Value $line -Encoding UTF8
}

# ---------------------------------------------------------------------------
# Switch log
# ---------------------------------------------------------------------------

function Write-SwitchLog {
    param([Parameter(Mandatory)][string]$Message)
    $dir = Split-Path -Parent $switchLogPath
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Add-Content -LiteralPath $switchLogPath -Value "[$ts] $Message" -Encoding UTF8
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Get-RuntimeIsoTimestamp {
    return (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
}

# ---------------------------------------------------------------------------
# Mod manifest runtime sync (design §7.2.2)
# ---------------------------------------------------------------------------

function Sync-ModManifestRuntime {
    <#
        Updates mods/manifest.json to match the current active runtime.
        - runtime field: 'windows-dedicated' or 'linux-docker'
        - managerEnabled: $true only for a configured Mod set on Windows;
          an empty manifest remains disabled on every runtime.
        Does NOT touch the mods array.
        Atomic write. No-op if manifest is missing or both fields already match.
    #>
    param([Parameter(Mandatory)][ValidateSet('docker','windows','none')][string]$Runtime)

    $manifestPath = Join-Path $projectDir 'mods\manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        return
    }

    $raw = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
    $manifest = $raw | ConvertFrom-Json
    $targetRuntime = if ($Runtime -eq 'windows') { 'windows-dedicated' } else { 'linux-docker' }
    $hasConfiguredMods = @($manifest.mods).Count -gt 0
    $targetManagerEnabled = ($Runtime -eq 'windows' -and $hasConfiguredMods)
    if ([string]$manifest.runtime -eq $targetRuntime -and
        [bool]$manifest.managerEnabled -eq $targetManagerEnabled) { return }

    $manifest.runtime = $targetRuntime
    $manifest.managerEnabled = $targetManagerEnabled
    $json = $manifest | ConvertTo-Json -Depth 20 -Compress
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $tmp = "$manifestPath.tmp.$PID"
    $rollback = "$manifestPath.rollback.$PID"
    try {
        [System.IO.File]::WriteAllText($tmp, $json + "`r`n", $utf8NoBom)
        [System.IO.File]::Replace($tmp, $manifestPath, $rollback)
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
        if (Test-Path -LiteralPath $rollback) { Remove-Item -LiteralPath $rollback -Force }
    }
}

function ConvertTo-RuntimeBoolean {
    param([object]$Value, [bool]$Default = $false)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $Default }
    return ([string]$Value -match '^(?i:true|1|yes)$')
}

function Get-RuntimePortConfig {
    <# Read only the non-secret port/enabled values needed by local probes. #>
    $values = @{}
    $envPath = Join-Path $projectDir '.env'
    if (Test-Path -LiteralPath $envPath -PathType Leaf) {
        foreach ($lineObject in [System.IO.File]::ReadAllLines($envPath)) {
            $line = ([string]$lineObject).Trim()
            if (-not $line -or $line.StartsWith('#')) { continue }
            $separator = $line.IndexOf('=')
            if ($separator -le 0) { continue }
            $key = $line.Substring(0, $separator).Trim()
            $value = $line.Substring($separator + 1).Trim()
            if ($value.Length -ge 2 -and
                (($value.StartsWith('"') -and $value.EndsWith('"')) -or
                 ($value.StartsWith("'") -and $value.EndsWith("'")))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            $values[$key] = $value
        }
    }

    $readPort = {
        param([string]$Key, [int]$Default)
        $parsed = 0
        if (-not [int]::TryParse([string]$values[$Key], [ref]$parsed) -or $parsed -lt 1 -or $parsed -gt 65535) {
            return $Default
        }
        return $parsed
    }
    return [ordered]@{
        gamePort = & $readPort 'PORT' 8211
        restPort = & $readPort 'REST_API_PORT' 8212
        rconPort = & $readPort 'RCON_PORT' 25575
        restEnabled = ConvertTo-RuntimeBoolean $values['REST_API_ENABLED'] $true
        rconEnabled = (ConvertTo-RuntimeBoolean $values['RCON_ENABLED'] $false) -or
            (ConvertTo-RuntimeBoolean $values['ENABLE_LEGACY_RCON'] $false)
    }
}

function Test-PortsReleased {
    <# Returns $true when configured game/REST/RCON ports are NOT listening. #>
    $config = Get-RuntimePortConfig
    $ports = @($config.gamePort, $config.restPort, $config.rconPort) | Sort-Object -Unique
    foreach ($p in $ports) {
        $udp = Get-NetUDPEndpoint -LocalPort $p -ErrorAction SilentlyContinue
        $tcp = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue
        if ($udp -or $tcp) { return $false }
    }
    return $true
}

function Test-RuntimePorts {
    <# Returns configured per-port listening status and bind address checks. #>
    $config = Get-RuntimePortConfig
    $result = [ordered]@{
        gamePort       = $config.gamePort
        restPort       = $config.restPort
        rconPort       = $config.rconPort
        udpGame        = $false
        tcpRest        = $false
        tcpRcon        = $false
        restBindLocal   = $false
        rconBindLocal   = $false
        firewallRules   = $false
    }

    $udp = Get-NetUDPEndpoint -LocalPort $config.gamePort -ErrorAction SilentlyContinue
    if ($udp) { $result.udpGame = $true }

    $tcpRest = Get-NetTCPConnection -LocalPort $config.restPort -State Listen -ErrorAction SilentlyContinue
    if ($tcpRest) {
        $result.tcpRest = $true
        $result.restBindLocal = ($tcpRest.LocalAddress -in @('127.0.0.1','0.0.0.0','::','::1'))
    }

    $tcpRcon = Get-NetTCPConnection -LocalPort $config.rconPort -State Listen -ErrorAction SilentlyContinue
    if ($tcpRcon) {
        $result.tcpRcon = $true
        $result.rconBindLocal = ($tcpRcon.LocalAddress -in @('127.0.0.1','0.0.0.0','::','::1'))
    }

    $firewallReady = $true
    $requiredFirewallRules = @()
    if ($config.restEnabled) { $requiredFirewallRules += "Palworld Block REST $($config.restPort) Public" }
    if ($config.rconEnabled) { $requiredFirewallRules += "Palworld Block RCON $($config.rconPort) Public" }
    foreach ($ruleName in $requiredFirewallRules) {
        try {
            if (-not (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) {
                $firewallReady = $false
            }
        } catch {
            $firewallReady = $false
        }
    }
    $result.firewallRules = $firewallReady

    # Keep dynamic aliases for existing consumers that used udp8211/tcp8212/
    # tcp25575, while making the fields truthful when operators change ports.
    $result["udp$($config.gamePort)"] = $result.udpGame
    $result["tcp$($config.restPort)"] = $result.tcpRest
    $result["tcp$($config.rconPort)"] = $result.tcpRcon

    return $result
}

# ---------------------------------------------------------------------------
# Bootstrap: if runtime.state doesn't exist, write an initial 'none' state.
# This makes the file presence itself a signal of having been initialized.
# ---------------------------------------------------------------------------

if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    # Only bootstrap if Docker is NOT currently running, to avoid clobbering an active runtime.
    $dockerRunning = $false
    try {
        $containerName = Get-ManagementContainerName -ProjectDirectory $projectDir
        $inspect = docker inspect -f '{{.State.Running}}' $containerName 2>$null
        if ($LASTEXITCODE -eq 0 -and $inspect -eq 'true') { $dockerRunning = $true }
    } catch { }

    if ($dockerRunning) {
        Update-RuntimeState -Active 'docker' -StartedAt (Get-RuntimeIsoTimestamp) -Switching $false
    } else {
        Update-RuntimeState -Active 'none' -Switching $false
    }
}

# Export-like: this module is dot-sourced, so functions are directly available.
