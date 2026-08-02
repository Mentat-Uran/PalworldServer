# recover-runtime-state.ps1
#
# Disaster recovery for runtime.state.
# Used when runtime.state is missing, corrupt, or inconsistent with reality.
#
# Detection rules:
#   1. If Docker container palworld-server is running -> active=docker
#   2. Else if PalServer.exe process is running      -> active=windows
#   3. Else                                           -> active=none
#
# Optionally detects and reports SaveGames corruption.
#
# Usage:
#   .\scripts\recover-runtime-state.ps1              # Repair missing, corrupt, or stale runtime.state
#   .\scripts\recover-runtime-state.ps1 -DryRun      # Only report, don't write
#   .\scripts\recover-runtime-state.ps1 -Force       # Overwrite even if state looks fine
#
# Exit codes:
#   0 = state written (or dry-run completed)
#   1 = unrecoverable error
#   2 = SaveGames corruption detected (state written, manual action required)

param(
    [switch]$DryRun,
    [switch]$Force,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot

. (Join-Path $PSScriptRoot 'runtime-common.ps1')
. (Join-Path $PSScriptRoot 'management-api.ps1')

$statePath = Join-Path $projectDir 'data\runtime.state'
$saveGamesPath = Join-Path $projectDir 'data\Pal\Saved\SaveGames'
$management = Get-ManagementEndpointConfig -ProjectDirectory $projectDir
$containerName = $management.containerName

function Write-RecoverLog {
    param([Parameter(Mandatory)][string]$Message)
    $logPath = Join-Path $projectDir 'data\diagnostics\recover.log'
    $dir = Split-Path -Parent $logPath
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Add-Content -LiteralPath $logPath -Value "[$ts] $Message" -Encoding UTF8
}

function Test-DockerContainerRunning {
    try {
        $null = Get-Command docker.exe -ErrorAction Stop
    } catch { return $false }
    try {
        $inspect = docker inspect -f '{{.State.Running}}|{{.State.Pid}}|{{.State.StartedAt}}' $containerName 2>$null
        if ($LASTEXITCODE -eq 0 -and $inspect) {
            $parts = $inspect.Trim() -split '\|'
            if ($parts[0] -eq 'true') {
                $dockerPid = $null
                if ($parts.Length -gt 1 -and $parts[1] -match '^\d+$') { $dockerPid = [int]$parts[1] }
                $startedAt = if ($parts.Length -gt 2) { $parts[2] } else { $null }
                return @{ running = $true; pid = $dockerPid; startedAt = $startedAt }
            }
        }
    } catch { }
    return @{ running = $false }
}

function Test-WinServerRunning {
    $expectedPath = [System.IO.Path]::GetFullPath((Join-Path $projectDir 'win-server\PalServer.exe'))
    $procs = @(Get-Process -Name 'PalServer' -ErrorAction SilentlyContinue)
    foreach ($p in $procs) {
        $actualPath = $null
        try { $actualPath = $p.Path } catch { }
        if (-not $actualPath) {
            try { $actualPath = $p.MainModule.FileName } catch { }
        }
        if (-not $actualPath) { continue }

        try {
            $actualPath = [System.IO.Path]::GetFullPath($actualPath)
        } catch {
            continue
        }
        if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals($actualPath, $expectedPath)) { continue }

        return @{ running = $true; pid = $p.Id; startedAt = $p.StartTime.ToString('o') }
    }
    return @{ running = $false }
}

function Test-SaveGamesIntegrity {
    param([switch]$CheckBackupFreshness)

    <# Returns @{ ok=$true; warnings=@(...) } or @{ ok=$false; issues=@(...); warnings=@(...) }.
       A backup age is an operational warning, not evidence that the current
       save is corrupt: a just-started server has not yet reached its backup
       cron schedule. #>
    $issues = @()
    $warnings = @()
    if (-not (Test-Path -LiteralPath $saveGamesPath -PathType Container)) {
        return @{ ok = $false; issues = @('SaveGames directory missing'); warnings = $warnings }
    }

    # Find Level.sav under SaveGames\0\<GUID>\
    $levelFiles = Get-ChildItem -LiteralPath $saveGamesPath -Recurse -Filter 'Level.sav' -File -ErrorAction SilentlyContinue
    if ($levelFiles.Count -eq 0) {
        $issues += 'No Level.sav found under SaveGames (server may not have saved yet, or save is corrupted)'
    } else {
        foreach ($lvl in $levelFiles) {
            if ($lvl.Length -eq 0) {
                $issues += "Empty Level.sav: $($lvl.FullName)"
            }
        }
    }

    # Check backup directory has at least one recent backup (within last 2 hours) — informational only
    $backupDirs = Get-ChildItem -LiteralPath $saveGamesPath -Recurse -Directory -Filter 'backup' -ErrorAction SilentlyContinue
    # Freshness is meaningful only while a runtime is active. An offline server
    # must not be reported as corrupt merely because its backup is older than 2h.
    if ($CheckBackupFreshness -and $backupDirs.Count -gt 0) {
        $newestBackup = $null
        foreach ($bdir in $backupDirs) {
            $files = Get-ChildItem -LiteralPath $bdir.FullName -Recurse -File -ErrorAction SilentlyContinue
            if ($files) {
                $maxTime = ($files | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
                if (-not $newestBackup -or $maxTime -gt $newestBackup) { $newestBackup = $maxTime }
            }
        }
        if ($newestBackup) {
            $ageHours = ((Get-Date) - $newestBackup).TotalHours
            if ($ageHours -gt 2) {
                $warnings += "Newest SaveGames backup is $([int]$ageHours)h old (auto-backup may not have run yet)"
            }
        }
    }

    if ($issues.Count -gt 0) { return @{ ok = $false; issues = $issues; warnings = $warnings } }
    return @{ ok = $true; issues = @(); warnings = $warnings }
}

function Get-DockerVersion {
    try {
        $r = docker exec $containerName rest-cli info 2>$null
        if ($LASTEXITCODE -eq 0 -and $r) {
            $info = $r | ConvertFrom-Json -ErrorAction Stop
            return [string]$info.version
        }
    } catch { }
    return $null
}

function Get-WinVersion {
    try {
        $resp = Invoke-WebRequest -Uri ($management.restBaseUrl.TrimEnd('/') + '/info') -Method GET -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
        $info = $resp.Content | ConvertFrom-Json -ErrorAction Stop
        return [string]$info.version
    } catch { }
    $versionFile = Join-Path $projectDir 'win-server\version.txt'
    if (Test-Path -LiteralPath $versionFile -PathType Leaf) {
        $buildId = (Get-Content -LiteralPath $versionFile -Raw).Trim()
        return "build:$buildId"
    }
    return $null
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# Check current state
$currentState = $null
$stateCorrupt = $false
if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    try {
        $raw = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8
        $currentState = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        $stateCorrupt = $true
        Write-RecoverLog "runtime.state is corrupt: $($_.Exception.Message)"
        if (-not $Quiet) { Write-Host "[recover] runtime.state is corrupt: $($_.Exception.Message)" -ForegroundColor Yellow }
    }
}

Write-RecoverLog "BEGIN recovery (force=$Force, dryRun=$DryRun, corrupt=$stateCorrupt)"
if (-not $Quiet) { Write-Host "[recover] Detecting actual runtime state..." }

# Detect what's actually running.  Never collapse a dual-runtime violation into
# a seemingly valid Docker state: doing so would permit later automation to
# touch the shared SaveGames directory without an explicit operator decision.
$docker = Test-DockerContainerRunning
$win = Test-WinServerRunning

if ($docker.running -and $win.running) {
    $message = "Both Docker and PalServer.exe are running (docker PID=$($docker.pid), Windows PID=$($win.pid)). Recovery refuses to choose a runtime. Stop one runtime, then rerun recovery."
    Write-RecoverLog "DUAL RUNTIME VIOLATION: $message"
    Write-Incident -Level 'ERROR' -Type 'runtime-dual-active' -Message $message
    if (-not $Quiet) {
        Write-Host "[recover] ERROR: $message" -ForegroundColor Red
    }
    exit 1
}

$detected = 'none'
$detectedPid = $null
$startedAt = $null
$version = $null

if ($docker.running) {
    $detected = 'docker'
    $detectedPid = $docker.pid
    $startedAt = $docker.startedAt
    $version = Get-DockerVersion
    if (-not $Quiet) { Write-Host "[recover] Detected: Docker container running (PID=$detectedPid)" }
    Write-RecoverLog "  Detected docker (PID=$detectedPid, startedAt=$startedAt, version=$version)"
} elseif ($win.running) {
    $detected = 'windows'
    $detectedPid = $win.pid
    $startedAt = $win.startedAt
    $version = Get-WinVersion
    if (-not $Quiet) { Write-Host "[recover] Detected: PalServer.exe running (PID=$detectedPid)" }
    Write-RecoverLog "  Detected windows (PID=$detectedPid, startedAt=$startedAt, version=$version)"
} else {
    if (-not $Quiet) { Write-Host "[recover] No runtime detected (active=none)" }
    Write-RecoverLog "  No runtime detected"
}

$stateMatchesLiveRuntime = $false
if (-not $stateCorrupt -and $currentState -and -not [bool]$currentState.switching -and $currentState.active -eq $detected) {
    if ($detected -eq 'none') {
        $stateMatchesLiveRuntime = $true
    } elseif ($null -ne $currentState.pid -and [string]$currentState.pid -eq [string]$detectedPid) {
        $stateMatchesLiveRuntime = $true
    }
}

if (-not $Force -and $stateMatchesLiveRuntime) {
    if (-not $Quiet) {
        Write-Host "[recover] runtime.state matches the live runtime (active=$detected); no write needed. Use -Force to refresh metadata." -ForegroundColor Yellow
    }
    Write-RecoverLog "No recovery needed: state matches live runtime (active=$detected, pid=$detectedPid)"
    exit 0
}

if ($currentState -and -not $stateMatchesLiveRuntime) {
    Write-RecoverLog "State mismatch: recorded active=$($currentState.active), pid=$($currentState.pid); detected active=$detected, pid=$detectedPid"
    if (-not $Quiet) {
        Write-Host "[recover] runtime.state differs from the live runtime; repairing it." -ForegroundColor Yellow
    }
}

# Detect SaveGames corruption (informational; doesn't block recovery)
$saveGamesStatus = Test-SaveGamesIntegrity -CheckBackupFreshness:($detected -ne 'none')
$corruptionDetected = $false
if ($saveGamesStatus.warnings.Count -gt 0) {
    if (-not $Quiet) {
        foreach ($warning in $saveGamesStatus.warnings) { Write-Host "[recover] WARN: $warning" -ForegroundColor Yellow }
    }
    Write-RecoverLog "  SaveGames backup freshness warning: $($saveGamesStatus.warnings -join '; ')"
    Write-Incident -Level 'WARN' -Type 'savegames-backup-stale' -Message "SaveGames backup freshness warning: $($saveGamesStatus.warnings -join '; ')"
}
if (-not $saveGamesStatus.ok) {
    $corruptionDetected = $true
    if (-not $Quiet) {
        Write-Host "[recover] SaveGames integrity issues:" -ForegroundColor Yellow
        foreach ($i in $saveGamesStatus.issues) { Write-Host "  - $i" -ForegroundColor Yellow }
    }
    Write-RecoverLog "  SaveGames integrity issues: $($saveGamesStatus.issues -join '; ')"
    Write-Incident -Level 'WARN' -Type 'savegames-integrity' -Message "SaveGames integrity issues: $($saveGamesStatus.issues -join '; ')"
}

# Build new state
$newState = [ordered]@{
    active          = $detected
    pid             = $detectedPid
    startedAt       = $startedAt
    version         = $version
    switching       = $false
    lastSwitchAt    = if ($currentState -and $currentState.lastSwitchAt) { $currentState.lastSwitchAt } else { $null }
    lastSwitchFrom  = if ($currentState -and $currentState.lastSwitchFrom) { $currentState.lastSwitchFrom } else { $null }
    lastSwitchTo    = if ($currentState -and $currentState.lastSwitchTo) { $currentState.lastSwitchTo } else { $null }
}

if ($DryRun) {
    if (-not $Quiet) {
        Write-Host ""
        Write-Host "[recover] Dry-run result (not written):" -ForegroundColor Cyan
        $newState | ConvertTo-Json | Write-Host
    }
    Write-RecoverLog "END dry-run (would have written active=$detected)"
    exit 0
}

# Atomic write
$json = $newState | ConvertTo-Json -Compress
$tmp = "$statePath.recover.$PID"
$dataDir = Split-Path -Parent $statePath
if (-not (Test-Path -LiteralPath $dataDir -PathType Container)) {
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
}
[System.IO.File]::WriteAllText($tmp, $json, [System.Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $tmp -Destination $statePath -Force

Write-Incident -Level 'INFO' -Type 'runtime-state-recovered' -Message "runtime.state recovered: active=$detected, pid=$detectedPid, version=$version"
Write-RecoverLog "END recovery ok (active=$detected, pid=$detectedPid, corruption=$corruptionDetected)"

if (-not $Quiet) {
    Write-Host ""
    Write-Host "[recover] ============================================" -ForegroundColor Green
    Write-Host "[recover]   runtime.state recovered" -ForegroundColor Green
    Write-Host "[recover]   active:  $detected" -ForegroundColor Green
    if ($detectedPid) { Write-Host "[recover]   pid:     $detectedPid" -ForegroundColor Green }
    if ($version) { Write-Host "[recover]   version: $version" -ForegroundColor Green }
    Write-Host "[recover] ============================================" -ForegroundColor Green
    if ($corruptionDetected) {
        Write-Host ""
        Write-Host "[recover] WARNING: SaveGames integrity issues detected." -ForegroundColor Yellow
        Write-Host "[recover] Consider restoring from a snapshot:" -ForegroundColor Yellow
        Write-Host "  .\scripts\restore-snapshot.ps1 -List"
    }
}

if ($corruptionDetected) { exit 2 }
exit 0
