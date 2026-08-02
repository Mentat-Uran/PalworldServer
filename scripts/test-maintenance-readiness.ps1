[CmdletBinding()]
param(
    [ValidateSet('switch', 'restore', 'tunnel', 'stability', 'vanilla')]
    [string]$Operation = 'switch',
    [ValidateSet('docker', 'windows')]
    [string]$Target,
    [string]$SnapshotName,
    [switch]$AsJson
)

# Read-only P2 preflight. It never invokes a runtime provider or a mutating
# Docker/REST/RCON command. Its result establishes readiness only, not acceptance.
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'management-api.ps1')
$management = Get-ManagementEndpointConfig -ProjectDirectory $projectDir
$containerName = $management.containerName
$results = New-Object System.Collections.Generic.List[object]

function Add-Result {
    param(
        [ValidateSet('ok', 'warning', 'error')][string]$Status,
        [string]$Check,
        [string]$Detail
    )
    $results.Add([pscustomobject][ordered]@{ status = $Status; check = $Check; detail = $Detail })
}

function Read-RuntimeState {
    $path = Join-Path $projectDir 'data\runtime.state'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Result error 'runtime-state' 'data\\runtime.state is missing; inspect recovery with -DryRun before a maintenance operation.'
        return $null
    }
    try {
        return Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Add-Result error 'runtime-state' "data\\runtime.state is not valid JSON: $($_.Exception.Message)"
        return $null
    }
}

function Get-DockerLiveState {
    try {
        $null = Get-Command docker.exe -ErrorAction Stop
        $line = & docker.exe inspect -f '{{.State.Running}}|{{.State.Pid}}|{{.State.Health.Status}}|{{.Config.Image}}' $containerName 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $line) { return @{ known = $true; running = $false } }
        $parts = $line.Trim() -split '\|', 4
        return @{
            known = $true
            running = ($parts[0] -eq 'true')
            pid = if ($parts.Length -gt 1) { $parts[1] } else { $null }
            health = if ($parts.Length -gt 2) { $parts[2] } else { $null }
            image = if ($parts.Length -gt 3) { $parts[3] } else { $null }
        }
    } catch {
        Add-Result error 'docker-detection' "Docker state cannot be read: $($_.Exception.Message)"
        return @{ known = $false; running = $false }
    }
}

$state = Read-RuntimeState
$docker = Get-DockerLiveState
$win = @(Get-Process -Name 'PalServer' -ErrorAction SilentlyContinue)
$liveRuntime = if ($docker.running) { 'docker' } elseif ($win.Count -gt 0) { 'windows' } else { 'none' }

if ($docker.running -and $win.Count -gt 0) {
    Add-Result error 'runtime-exclusivity' 'Both Docker and PalServer.exe are running. Stop and recover only under operator direction.'
} else {
    Add-Result ok 'runtime-exclusivity' "Detected active runtime: $liveRuntime."
}

if ($docker.running) {
    if ($docker.health -eq 'healthy') {
        Add-Result ok 'docker-health' "Docker is running and reports health=$($docker.health)."
    } else {
        Add-Result error 'docker-health' "Docker is running but reports health=$($docker.health)."
    }
}

if ($state) {
    $recorded = [string]$state.active
    if ($recorded -notin @('docker', 'windows', 'none', 'unknown')) {
        Add-Result error 'runtime-state' "runtime.state has an unsupported active value: $recorded."
    } elseif ([bool]$state.switching) {
        Add-Result error 'runtime-state' 'runtime.state indicates switching=true; do not begin another maintenance operation.'
    } elseif ($recorded -ne $liveRuntime) {
        Add-Result error 'runtime-state' "runtime.state records active=$recorded while live detection is $liveRuntime. Run recover-runtime-state.ps1 -DryRun and obtain operator direction before changing it."
    } else {
        Add-Result ok 'runtime-state' "runtime.state matches the live runtime ($liveRuntime)."
    }
}

$saveGames = Join-Path $projectDir 'data\Pal\Saved\SaveGames'
if (Test-Path -LiteralPath $saveGames -PathType Container) {
    $levels = @(Get-ChildItem -LiteralPath $saveGames -Recurse -Filter 'Level.sav' -File -ErrorAction SilentlyContinue)
    if ($levels.Count -gt 0 -and @($levels | Where-Object { $_.Length -eq 0 }).Count -eq 0) {
        Add-Result ok 'savegames' "Found $($levels.Count) non-empty Level.sav file(s)."
    } else {
        Add-Result error 'savegames' 'No non-empty Level.sav was found in the shared SaveGames path.'
    }
} else {
    Add-Result error 'savegames' 'Shared SaveGames directory is missing.'
}

$backups = Join-Path $projectDir 'data\backups'
$backupCount = if (Test-Path -LiteralPath $backups -PathType Container) { @(Get-ChildItem -LiteralPath $backups -File -ErrorAction SilentlyContinue).Count } else { 0 }
if ($backupCount -gt 0) {
    Add-Result ok 'backup-presence' "Found $backupCount backup file(s). Verify a selected backup separately; presence is not restore evidence."
} else {
    Add-Result error 'backup-presence' 'No backup files are available for the planned recovery path.'
}

$snapshotDir = Join-Path $projectDir 'data\switch-snapshots'
$manifestPath = Join-Path $snapshotDir 'manifest.json'
$manifest = $null
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json -ErrorAction Stop
        Add-Result ok 'snapshot-manifest' "Snapshot manifest contains $(@($manifest.snapshots).Count) record(s)."
    } catch {
        Add-Result error 'snapshot-manifest' "Snapshot manifest is unreadable: $($_.Exception.Message)"
    }
} else {
    Add-Result warning 'snapshot-manifest' 'No snapshot manifest is present. A pre-operation snapshot must be created and verified during the approved window.'
}

if ($Operation -eq 'switch') {
    if (-not $Target) {
        Add-Result error 'switch-target' 'Specify -Target docker or -Target windows for a switch preflight.'
    } elseif ($Target -eq $liveRuntime) {
        Add-Result error 'switch-target' "Target $Target is already active; a same-runtime restart is not a Docker-to-Windows or Windows-to-Docker drill."
    } elseif ($Target -eq 'windows') {
        $exe = Join-Path $projectDir 'win-server\PalServer.exe'
        if (Test-Path -LiteralPath $exe -PathType Leaf) {
            Add-Result ok 'windows-dependency' 'win-server\\PalServer.exe is present.'
        } else {
            Add-Result error 'windows-dependency' 'win-server\\PalServer.exe is missing.'
        }
        $firewallScript = Join-Path $projectDir 'scripts\ensure-win-management-firewall.ps1'
        if (-not (Test-Path -LiteralPath $firewallScript -PathType Leaf)) {
            Add-Result error 'windows-firewall' 'Windows management firewall gate script is missing.'
        } else {
            $null = & $firewallScript -Check
            if ($LASTEXITCODE -eq 0) {
                Add-Result ok 'windows-firewall' ("Inbound management block rules are active (REST=$($management.restEnabled):$($management.restPort), RCON=$($management.legacyRconEnabled):$($management.rconPort)).")
            } else {
                Add-Result error 'windows-firewall' ("Inbound management block rules are missing (REST=$($management.restEnabled):$($management.restPort), RCON=$($management.legacyRconEnabled):$($management.rconPort)); do not start Windows runtime.")
            }
        }
    } elseif ($Target -eq 'docker' -and -not $docker.known) {
        Add-Result error 'docker-dependency' 'Docker availability could not be confirmed.'
    }
} elseif ($Operation -eq 'restore') {
    if (-not $SnapshotName) {
        Add-Result error 'restore-snapshot' 'Specify -SnapshotName; this preflight does not restore it.'
    } elseif (-not $manifest) {
        Add-Result error 'restore-snapshot' 'A readable snapshot manifest is required to verify the selected snapshot.'
    } else {
        $record = @($manifest.snapshots | Where-Object { [string]$_.name -eq $SnapshotName } | Select-Object -First 1)
        $file = Join-Path $snapshotDir $SnapshotName
        if ($record.Count -eq 0 -or -not (Test-Path -LiteralPath $file -PathType Leaf)) {
            Add-Result error 'restore-snapshot' 'The selected snapshot is absent from the manifest or filesystem.'
        } else {
            $actual = 'sha256:' + (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actual -eq [string]$record[0].sha256) {
                Add-Result ok 'restore-snapshot' 'Selected snapshot hash matches its manifest record.'
            } else {
                Add-Result error 'restore-snapshot' 'Selected snapshot hash does not match its manifest record.'
            }
        }
    }
} elseif ($Operation -eq 'tunnel') {
    Add-Result warning 'external-evidence' 'A remote join or external data-traffic observation is still required; local process and port state cannot prove it.'
} elseif ($Operation -eq 'stability') {
    Add-Result warning 'external-evidence' 'A timed six-player run with aggregate evidence is still required; this preflight does not simulate players.'
} elseif ($Operation -eq 'vanilla') {
    Add-Result warning 'policy-decision' 'Operator must explicitly select strict vanilla or a bounded mod-enabled-client policy; no configuration was changed.'
}

$errorCount = @($results | Where-Object { $_.status -eq 'error' }).Count
$warningCount = @($results | Where-Object { $_.status -eq 'warning' }).Count
$summary = [pscustomobject][ordered]@{
    operation = $Operation
    target = $Target
    liveRuntime = $liveRuntime
    # Legacy ready remains a preflight-only indicator for callers that already
    # consume it. A read-only preflight can never establish P2 acceptance.
    ready = ($errorCount -eq 0)
    preflightReady = ($errorCount -eq 0)
    acceptanceReady = $false
    acceptanceReason = 'Read-only preflight cannot prove an executed operation, remote join, stability run, restore result, or policy decision.'
    errors = $errorCount
    warnings = $warningCount
    generatedAt = (Get-Date).ToString('o')
    results = $results
}

if ($AsJson) {
    $summary | ConvertTo-Json -Depth 5
} else {
    foreach ($item in $results) {
        $color = if ($item.status -eq 'ok') { 'Green' } elseif ($item.status -eq 'warning') { 'Yellow' } else { 'Red' }
        Write-Host "[$($item.status.ToUpperInvariant())] $($item.check): $($item.detail)" -ForegroundColor $color
    }
    Write-Host "MAINTENANCE_PREFLIGHT_READY=$($summary.ready.ToString().ToLowerInvariant())"
    Write-Host "MAINTENANCE_ACCEPTANCE_READY=false"
    Write-Host "MAINTENANCE_PREFLIGHT_ERRORS=$errorCount"
}

if ($errorCount -gt 0) { exit 2 }
exit 0
