# switch-runtime.ps1
#
# Atomic runtime switching between Docker and Windows native Palworld server.
# Creates pre/post snapshots, stops current runtime, compiles INI, starts target.
#
# Usage:
#   .\scripts\switch-runtime.ps1 -To windows
#   .\scripts\switch-runtime.ps1 -To docker
#   .\scripts\switch-runtime.ps1 -To windows -Force
#   .\scripts\switch-runtime.ps1 -To windows -FullSnapshot
#   .\scripts\switch-runtime.ps1 -To docker -HealthTimeoutSeconds 900
#   .\scripts\switch-runtime.ps1 -To windows -SkipSnapshot  # emergency only
#
# Exit codes:
#   0 = success
#   1 = parameter error
#   2 = same runtime, -Force not specified
#   3 = current runtime stop failed
#   4 = target dependency missing
#   5 = junction assertion failed
#   6 = INI compilation failed
#   7 = target runtime start failed
#   8 = target health check timeout
#   9 = snapshot creation failed

param(
    [Parameter(Mandatory)][ValidateSet('docker','windows')][string]$To,
    [switch]$Force,
    [switch]$SkipSnapshot,
    [switch]$FullSnapshot,
    [ValidateRange(120, 1800)][int]$HealthTimeoutSeconds = 900,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot

# Load runtime common + both providers
. (Join-Path $PSScriptRoot 'runtime-common.ps1')
. (Join-Path $PSScriptRoot 'docker-runtime.ps1')
. (Join-Path $PSScriptRoot 'win-runtime.ps1')

$snapshotDir = Join-Path $projectDir 'data\switch-snapshots'
$manifestPath = Join-Path $snapshotDir 'manifest.json'

# ---------------------------------------------------------------------------
# Snapshot functions
# ---------------------------------------------------------------------------

function Get-SnapshotManifest {
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        return @{ snapshots = @(); retentionPolicy = @{
            maxFullCount = 3
            maxFullTotalBytes = 1073741824
            maxLightCount = 10
            minFullKeepHours = 24
        }}
    }
    try {
        $raw = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
        $m = $raw | ConvertFrom-Json -ErrorAction Stop
        # Normalize to a hashtable-like structure for easier mutation
        $result = @{
            snapshots = @()
            retentionPolicy = @{
                maxFullCount = 3
                maxFullTotalBytes = 1073741824
                maxLightCount = 10
                minFullKeepHours = 24
            }
        }
        if ($m.PSObject.Properties.Name -contains 'snapshots' -and $m.snapshots) {
            $result.snapshots = @($m.snapshots)
        }
        if ($m.PSObject.Properties.Name -contains 'retentionPolicy' -and $m.retentionPolicy) {
            $rp = $m.retentionPolicy
            $result.retentionPolicy = @{
                maxFullCount = if ($rp.PSObject.Properties.Name -contains 'maxFullCount') { [int]$rp.maxFullCount } else { 3 }
                maxFullTotalBytes = if ($rp.PSObject.Properties.Name -contains 'maxFullTotalBytes') { [int64]$rp.maxFullTotalBytes } else { 1073741824 }
                maxLightCount = if ($rp.PSObject.Properties.Name -contains 'maxLightCount') { [int]$rp.maxLightCount } else { 10 }
                minFullKeepHours = if ($rp.PSObject.Properties.Name -contains 'minFullKeepHours') { [int]$rp.minFullKeepHours } else { 24 }
            }
        }
        return $result
    } catch {
        Write-Warning "Snapshot manifest parse failed: $_; starting fresh"
        return @{ snapshots = @(); retentionPolicy = @{
            maxFullCount = 3
            maxFullTotalBytes = 1073741824
            maxLightCount = 10
            minFullKeepHours = 24
        }}
    }
}

function Save-SnapshotManifest {
    param($Manifest)
    if (-not (Test-Path -LiteralPath $snapshotDir -PathType Container)) {
        New-Item -ItemType Directory -Path $snapshotDir -Force | Out-Null
    }
    $json = $Manifest | ConvertTo-Json -Depth 10 -Compress
    $temp = "$manifestPath.tmp.$PID"
    [System.IO.File]::WriteAllText($temp, $json, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temp -Destination $manifestPath -Force
}

function Get-SaveGamesFingerprint {
    <# Recursive SHA-256 of SaveGames directory tree (file names + sizes + hashes). #>
    $saveGamesPath = Join-Path $projectDir 'data\Pal\Saved\SaveGames'
    if (-not (Test-Path -LiteralPath $saveGamesPath -PathType Container)) { return 'sha256:empty' }

    $sb = New-Object System.Text.StringBuilder
    $files = Get-ChildItem -LiteralPath $saveGamesPath -Recurse -File -ErrorAction SilentlyContinue | Sort-Object FullName
    foreach ($f in $files) {
        $relPath = $f.FullName.Substring($saveGamesPath.Length).TrimStart('\')
        $size = $f.Length
        [void]$sb.Append("$relPath|$size;")
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($sb.ToString())
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash($bytes)
    $hex = ($hash | ForEach-Object { $_.ToString('x2') }) -join ''
    return "sha256:$hex"
}

function Get-IniFingerprint {
    # PalServer.exe reads the native config under win-server.  The data
    # WindowsServer directory is only a legacy shadow and is not live state.
    $iniPath = Join-Path $projectDir 'win-server\Pal\Saved\Config\WindowsServer\PalWorldSettings.ini'
    if (-not (Test-Path -LiteralPath $iniPath -PathType Leaf)) { return 'sha256:empty' }
    $bytes = [System.IO.File]::ReadAllBytes($iniPath)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash($bytes)
    $hex = ($hash | ForEach-Object { $_.ToString('x2') }) -join ''
    return "sha256:$hex"
}

function Test-NeedsFullSnapshot {
    <# Determine if a Full snapshot is needed instead of Light. #>
    $manifest = Get-SnapshotManifest
    $snapshots = @($manifest.snapshots)

    # No Full snapshot in last 24h → need Full
    $lastFull = $snapshots | Where-Object { $_.type -eq 'Full' } | Sort-Object createdAt -Descending | Select-Object -First 1
    if (-not $lastFull) { return $true }
    try {
        $lastFullTime = [datetime]$lastFull.createdAt
        if (((Get-Date) - $lastFullTime).TotalHours -gt 24) { return $true }
    } catch { return $true }

    return $false
}

function New-SwitchSnapshot {
    param(
        [ValidateSet('Light','Full')][string]$Type,
        [ValidateSet('pre','post')][string]$Phase,
        [string]$From,
        [string]$To
    )

    if (-not (Test-Path -LiteralPath $snapshotDir -PathType Container)) {
        New-Item -ItemType Directory -Path $snapshotDir -Force | Out-Null
    }

    $timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $name = "$timestamp-$Type-$Phase-$From-to-$To.tar.gz"
    $archivePath = Join-Path $snapshotDir $name

    # Build list of files to include
    $tempStaging = Join-Path $env:TEMP "palworld-snapshot-$PID"
    if (Test-Path -LiteralPath $tempStaging) { Remove-Item -LiteralPath $tempStaging -Recurse -Force }
    New-Item -ItemType Directory -Path $tempStaging -Force | Out-Null

    try {
        # Always include: INI files, .env, runtime.state
        $configDirectories = @{
            LinuxServer   = Join-Path $projectDir 'data\Pal\Saved\Config\LinuxServer'
            WindowsServer = Join-Path $projectDir 'win-server\Pal\Saved\Config\WindowsServer'
        }
        foreach ($platform in @('LinuxServer','WindowsServer')) {
            $platformDir = $configDirectories[$platform]
            if (Test-Path -LiteralPath $platformDir -PathType Container) {
                $destDir = Join-Path $tempStaging "Config\$platform"
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                Copy-Item -Path (Join-Path $platformDir 'PalWorldSettings.ini') -Destination $destDir -ErrorAction SilentlyContinue
                Copy-Item -Path (Join-Path $platformDir 'Engine.ini') -Destination $destDir -ErrorAction SilentlyContinue
            }
        }
        Copy-Item -Path (Join-Path $projectDir '.env') -Destination $tempStaging -ErrorAction SilentlyContinue
        Copy-Item -Path (Join-Path $projectDir 'data\runtime.state') -Destination $tempStaging -ErrorAction SilentlyContinue

        if ($Type -eq 'Full') {
            # Include SaveGames
            $saveGamesPath = Join-Path $projectDir 'data\Pal\Saved\SaveGames'
            if (Test-Path -LiteralPath $saveGamesPath -PathType Container) {
                Copy-Item -Path $saveGamesPath -Destination (Join-Path $tempStaging 'SaveGames') -Recurse -Force
            }
        }

        # Create tar.gz
        $tarArgs = "-czf `"$archivePath`" -C `"$tempStaging`" ."
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'tar.exe'
        $psi.Arguments = $tarArgs
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $psi
        [void]$proc.Start()
        $proc.WaitForExit(60000)

        if ($proc.ExitCode -ne 0) {
            $stderr = $proc.StandardError.ReadToEnd()
            throw "tar failed: $stderr"
        }

        # Compute SHA-256
        $bytes = [System.IO.File]::ReadAllBytes($archivePath)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $hash = $sha.ComputeHash($bytes)
        $hex = ($hash | ForEach-Object { $_.ToString('x2') }) -join ''
        $sha256 = "sha256:$hex"

        $size = (Get-Item -LiteralPath $archivePath).Length

        # Update manifest
        $manifest = Get-SnapshotManifest
        $entry = [ordered]@{
            name = $name
            type = $Type
            phase = $Phase
            createdAt = (Get-Date).ToString('o')
            trigger = 'switch'
            from = $From
            to = $To
            sizeBytes = $size
            sha256 = $sha256
            savegamesFingerprint = Get-SaveGamesFingerprint
            iniFingerprint = Get-IniFingerprint
        }
        $snapList = [System.Collections.ArrayList]@($manifest.snapshots)
        $snapList.Add($entry) | Out-Null
        $manifest.snapshots = $snapList.ToArray()
        Save-SnapshotManifest -Manifest $manifest

        Write-SwitchLog "  Snapshot created: $name ($Type, $([math]::Round($size/1KB)) KB)"
        return $entry
    } finally {
        if (Test-Path -LiteralPath $tempStaging) {
            Remove-Item -LiteralPath $tempStaging -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-SnapshotRetention {
    <# Apply retention policy: keep N Full, N Light, total size under limit. #>
    $manifest = Get-SnapshotManifest
    $policy = $manifest.retentionPolicy
    $snapshots = [System.Collections.ArrayList]@($manifest.snapshots)

    if ($snapshots.Count -eq 0) { return }

    $changed = $false

    # Full snapshots: sort by time desc, keep newest N
    $fulls = @($snapshots | Where-Object { $_.type -eq 'Full' } | Sort-Object createdAt -Descending)
    if ($fulls.Count -gt $policy.maxFullCount) {
        # Don't delete if newer than minFullKeepHours
        $cutoff = (Get-Date).AddHours(-$policy.minFullKeepHours)
        foreach ($s in $fulls[$policy.maxFullCount..($fulls.Count-1)]) {
            try {
                $created = [datetime]$s.createdAt
                if ($created -lt $cutoff) {
                    $path = Join-Path $snapshotDir $s.name
                    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
                    $snapshots.Remove($s) | Out-Null
                    $changed = $true
                    Write-SwitchLog "  Retention: removed old Full snapshot $($s.name)"
                }
            } catch { }
        }
    }

    # Full total bytes
    $fullBytes = ($snapshots | Where-Object { $_.type -eq 'Full' } | Measure-Object -Property sizeBytes -Sum).Sum
    if ($fullBytes -gt $policy.maxFullTotalBytes) {
        $oldFulls = @($snapshots | Where-Object { $_.type -eq 'Full' } | Sort-Object createdAt)
        foreach ($s in $oldFulls) {
            if ($fullBytes -le $policy.maxFullTotalBytes) { break }
            $path = Join-Path $snapshotDir $s.name
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
            $fullBytes -= $s.sizeBytes
            $snapshots.Remove($s) | Out-Null
            $changed = $true
            Write-SwitchLog "  Retention: removed oversized Full snapshot $($s.name)"
        }
    }

    # Light snapshots: keep newest N
    $lights = @($snapshots | Where-Object { $_.type -eq 'Light' } | Sort-Object createdAt -Descending)
    if ($lights.Count -gt $policy.maxLightCount) {
        foreach ($s in $lights[$policy.maxLightCount..($lights.Count-1)]) {
            $path = Join-Path $snapshotDir $s.name
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
            $snapshots.Remove($s) | Out-Null
            $changed = $true
            Write-SwitchLog "  Retention: removed old Light snapshot $($s.name)"
        }
    }

    if ($changed) {
        $manifest.snapshots = @($snapshots)
        Save-SnapshotManifest -Manifest $manifest
        Write-Incident -Level 'INFO' -Type 'snapshot-retention' -Message "Snapshot retention applied"
    }
}

# ---------------------------------------------------------------------------
# DedicatedServerName sync (design: cross-runtime world continuity)
# ---------------------------------------------------------------------------

function Sync-DedicatedServerName {
    <#
        Syncs DedicatedServerName from the Linux GameUserSettings.ini (or, as
        a fallback, the oldest world GUID under SaveGames\0\) into the Windows
        GameUserSettings.ini. Without this, a fresh Windows install generates
        a new GUID and loads an empty world instead of the existing one.
        Only called when switching TO windows.
    #>
    $linuxGus = Join-Path $projectDir 'data\Pal\Saved\Config\LinuxServer\GameUserSettings.ini'
    $winGus = Join-Path $projectDir 'win-server\Pal\Saved\Config\WindowsServer\GameUserSettings.ini'

    # 1. Determine the desired world GUID from Linux config
    $worldGuid = $null
    if (Test-Path -LiteralPath $linuxGus -PathType Leaf) {
        foreach ($line in [System.IO.File]::ReadAllLines($linuxGus)) {
            if ($line -match '^\s*DedicatedServerName=(.+)\s*$') {
                $worldGuid = $matches[1].Trim()
                break
            }
        }
    }
    # Fallback: scan SaveGames\0\ for the oldest world with a non-empty Level.sav
    if (-not $worldGuid) {
        $worldsParent = Join-Path $projectDir 'data\Pal\Saved\SaveGames\0'
        if (Test-Path -LiteralPath $worldsParent -PathType Container) {
            $worldDirs = @(Get-ChildItem -LiteralPath $worldsParent -Directory -ErrorAction SilentlyContinue |
                          Where-Object {
                              $ls = Join-Path $_.FullName 'Level.sav'
                              (Test-Path -LiteralPath $ls -PathType Leaf) -and ((Get-Item -LiteralPath $ls).Length -gt 0)
                          } | Sort-Object LastWriteTime)
            if ($worldDirs.Count -gt 0) { $worldGuid = $worldDirs[0].Name }
        }
    }
    if (-not $worldGuid) {
        Write-SwitchLog "  Sync-DedicatedServerName: no world GUID found; skipping"
        return
    }

    # 2. Read Windows GameUserSettings.ini
    if (-not (Test-Path -LiteralPath $winGus -PathType Leaf)) {
        Write-SwitchLog "  Sync-DedicatedServerName: Windows GameUserSettings.ini missing; skipping"
        return
    }

    # 3. Replace or append DedicatedServerName line
    $lines = [System.IO.File]::ReadAllLines($winGus)
    $found = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*DedicatedServerName=.+$') {
            if ($lines[$i] -match "DedicatedServerName=$worldGuid") {
                Write-SwitchLog "  Sync-DedicatedServerName: already correct ($worldGuid)"
                return
            }
            $lines[$i] = "DedicatedServerName=$worldGuid"
            $found = $true
            break
        }
    }
    if (-not $found) { $lines += "DedicatedServerName=$worldGuid" }

    # 4. Write back (UTF-8 BOM, CRLF — UE Windows convention)
    $content = ($lines -join "`r`n") + "`r`n"
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($winGus, $content, $utf8Bom)
    Write-SwitchLog "  Sync-DedicatedServerName: set to $worldGuid"
    Write-Incident -Level 'INFO' -Type 'dedicated-server-name-sync' -Message "Synced DedicatedServerName to $worldGuid"
}

# ---------------------------------------------------------------------------
# Main switch flow
# ---------------------------------------------------------------------------

$mutex = $null
try {
    $mutex = Acquire-RuntimeMutex -TimeoutMs 10000
} catch {
    Write-Host "[switch-runtime] ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

try {
    # A stale runtime.state must not make this switch stop the wrong provider
    # or skip the pre-operation protection.  Recovery performs only live
    # detection and an atomic state repair; it now fails closed if both
    # runtimes are active.
    & (Join-Path $PSScriptRoot 'recover-runtime-state.ps1') -Quiet
    $recoveryExit = $LASTEXITCODE
    if ($recoveryExit -ne 0) {
        throw "Runtime-state recovery failed (exit=$recoveryExit). Inspect the live runtimes before switching."
    }

    $state = Get-RuntimeState
    $fromRuntime = if ($state.active -eq 'none') { 'none' } else { $state.active }

    Write-SwitchLog "BEGIN switch $fromRuntime -> $To"
    if (-not $Quiet) { Write-Host "[switch-runtime] Switching: $fromRuntime -> $To" }

    # Step 1: Same-target check
    if ($state.active -eq $To -and -not $Force) {
        Write-Host "[switch-runtime] Already on $To. Use -Force to restart." -ForegroundColor Yellow
        exit 2
    }

    # Step 2: Save the live world when applicable, then always protect the
    # current offline state before a target start.  UPDATE_ON_BOOT may change
    # game files even for a cold start, so a none -> target launch needs the
    # same pre-operation snapshot policy as a runtime-to-runtime switch.
    if ($state.active -ne 'none') {
        # 2a. REST save
        if (-not $Quiet) { Write-Host "[switch-runtime] Saving world..." }
        try {
            if ($state.active -eq 'docker') { $saveResult = Invoke-DockerRuntimeSave -Timeout 30 }
            else { $saveResult = Invoke-WindowsRuntimeSave -Timeout 30 }
            if ($saveResult.ok) {
                Write-SwitchLog "  REST save ok (method=$($saveResult.method))"
            } else {
                Write-SwitchLog "  REST save failed: $($saveResult.error); continuing"
                Write-Incident -Level 'WARN' -Type 'switch-save-failed' -Message "Pre-switch save failed for $($state.active): $($saveResult.error)"
            }
        } catch {
            Write-SwitchLog "  REST save error: $_; continuing"
        }

    }

    # 2b. Pre-switch snapshot.  This deliberately runs for fromRuntime=none
    # as well: a cold start can still update the server and open shared saves.
    if (-not $SkipSnapshot) {
        if (-not $Quiet) { Write-Host "[switch-runtime] Creating pre-switch snapshot..." }
        $snapType = if ($FullSnapshot) { 'Full' } elseif (Test-NeedsFullSnapshot) { 'Full' } else { 'Light' }
        try {
            New-SwitchSnapshot -Type $snapType -Phase 'pre' -From $fromRuntime -To $To | Out-Null
        } catch {
            Write-Incident -Level 'ERROR' -Type 'snapshot-failed' -Message "Pre-switch snapshot failed: $_"
            Write-Host "[switch-runtime] ERROR: Snapshot failed: $_" -ForegroundColor Red
            exit 9
        }
    } else {
        Write-SwitchLog "  Snapshot skipped (-SkipSnapshot)"
        Write-Incident -Level 'WARN' -Type 'switch-snapshot-skipped' -Message "User skipped pre-switch snapshot"
    }

    if ($state.active -ne 'none') {
        # 2c. Stop
        if (-not $Quiet) { Write-Host "[switch-runtime] Stopping $($state.active)..." }
        Write-SwitchLog "  Stopping $($state.active)..."
        if ($state.active -eq 'docker') { $stopResult = Stop-DockerRuntime -Grace 120 }
        else { $stopResult = Stop-WindowsRuntime -Grace 120 }

        if (-not $stopResult.ok) {
            Write-SwitchLog "  Stop FAILED: $($stopResult.error)"
            Write-Incident -Level 'ERROR' -Type 'switch-stop-failed' -Message "Failed to stop $($state.active): $($stopResult.error)"
            Write-Host "[switch-runtime] ERROR: Stop failed: $($stopResult.error)" -ForegroundColor Red
            exit 3
        }
        Write-SwitchLog "  Stop ok"

        # 2d. Wait for ports to release
        Start-Sleep -Seconds 3
        $portWait = 0
        while ($portWait -lt 30 -and -not (Test-PortsReleased)) {
            Start-Sleep -Seconds 2
            $portWait += 2
        }
        if (Test-PortsReleased) {
            Write-SwitchLog "  Ports released"
        } else {
            Write-SwitchLog "  Ports still bound after 30s; continuing anyway"
            Write-Incident -Level 'WARN' -Type 'switch-ports-busy' -Message "Ports not fully released after stop"
        }

        # 2e. Mark switching state
        Update-RuntimeState -Active 'none' -PidValue $null -Switching $true -LastSwitchAt (Get-RuntimeIsoTimestamp) -LastSwitchFrom $fromRuntime -LastSwitchTo $To
    } else {
        Update-RuntimeState -Switching $true -LastSwitchAt (Get-RuntimeIsoTimestamp) -LastSwitchFrom 'none' -LastSwitchTo $To
    }

    # Step 3: Validate target dependencies
    if (-not $Quiet) { Write-Host "[switch-runtime] Checking $To dependencies..." }
    if ($To -eq 'docker') { $deps = Test-DockerRuntimeDeps }
    else { $deps = Test-WindowsRuntimeDeps }

    if (-not $deps.ok) {
        Write-SwitchLog "  Deps missing: $($deps.missing -join ', ')"
        Write-Incident -Level 'ERROR' -Type 'switch-deps-missing' -Message "$To deps missing: $($deps.missing -join ', ')"
        Update-RuntimeState -Active 'none' -Switching $false
        Write-Host "[switch-runtime] ERROR: $To dependencies missing: $($deps.missing -join ', ')" -ForegroundColor Red
        Write-Host "[switch-runtime] Double-click install-windows-server.bat first." -ForegroundColor Yellow
        exit 4
    }
    Write-SwitchLog "  Deps ok"

    # Step 4: Junction assertion (windows only)
    if ($To -eq 'windows') {
        if (-not $Quiet) { Write-Host "[switch-runtime] Asserting junction..." }
        try {
            Assert-SaveGamesJunction
            Write-SwitchLog "  Junction ok"
        } catch {
            Write-SwitchLog "  Junction FAILED: $_"
            Write-Incident -Level 'ERROR' -Type 'junction-failed' -Message "Junction assertion failed: $_"
            Update-RuntimeState -Active 'none' -Switching $false
            Write-Host "[switch-runtime] ERROR: Junction failed: $_" -ForegroundColor Red
            exit 5
        }
    }

    # Step 5: Compile INI
    if (-not $Quiet) { Write-Host "[switch-runtime] Compiling INI..." }
    try {
        & (Join-Path $PSScriptRoot 'compile-settings.ps1') -Quiet
        if ($LASTEXITCODE -ne 0) { throw "compile-settings.ps1 exit code $LASTEXITCODE" }
        Write-SwitchLog "  INI compiled"
    } catch {
        Write-SwitchLog "  INI compile FAILED: $_"
        Write-Incident -Level 'ERROR' -Type 'ini-compile-failed' -Message "INI compilation failed: $_"
        Update-RuntimeState -Active 'none' -Switching $false
        Write-Host "[switch-runtime] ERROR: INI compile failed: $_" -ForegroundColor Red
        exit 6
    }

    # Step 5b: Sync DedicatedServerName (windows only)
    if ($To -eq 'windows') {
        if (-not $Quiet) { Write-Host "[switch-runtime] Syncing DedicatedServerName..." }
        try {
            Sync-DedicatedServerName
            Write-SwitchLog "  DedicatedServerName synced"
        } catch {
            Write-SwitchLog "  DedicatedServerName sync failed: $_ (non-fatal)"
            Write-Incident -Level 'WARN' -Type 'dedicated-server-name-sync' -Message "Sync failed: $_"
        }
    }

    # Step 6: Start target runtime
    if (-not $Quiet) { Write-Host "[switch-runtime] Starting $To..." }
    Write-SwitchLog "  Starting $To..."
    if ($To -eq 'docker') { $startResult = Start-DockerRuntime }
    else { $startResult = Start-WindowsRuntime }

    if (-not $startResult.ok) {
        Write-SwitchLog "  Start FAILED: $($startResult.error)"
        Write-Incident -Level 'ERROR' -Type 'runtime-start-failed' -Message "$To start failed: $($startResult.error)"

        # Attempt rollback to previous runtime
        if ($fromRuntime -ne 'none') {
            Write-SwitchLog "  Attempting rollback to $fromRuntime..."
            Write-Host "[switch-runtime] Start failed. Rolling back to $fromRuntime..." -ForegroundColor Yellow
            try {
                if ($fromRuntime -eq 'docker') { $rollbackResult = Start-DockerRuntime }
                else { $rollbackResult = Start-WindowsRuntime }
                if ($rollbackResult.ok) {
                    $version = ''
                    if ($fromRuntime -eq 'docker') { $v = Get-DockerRuntimeVersion; if ($v.ok) { $version = $v.version } }
                    else { $v = Get-WindowsRuntimeVersion; if ($v.ok) { $version = $v.version } }
                    Update-RuntimeState -Active $fromRuntime -PidValue $rollbackResult.pid -StartedAt (Get-RuntimeIsoTimestamp) -Version $version -Switching $false
                    Write-SwitchLog "  Rollback to $fromRuntime ok"
                    Write-Incident -Level 'WARN' -Type 'switch-rollback' -Message "Rolled back to $fromRuntime after $To start failure"
                } else {
                    Update-RuntimeState -Active 'none' -Switching $false
                    Write-SwitchLog "  Rollback also failed: $($rollbackResult.error)"
                }
            } catch {
                Update-RuntimeState -Active 'none' -Switching $false
                Write-SwitchLog "  Rollback error: $_"
            }
        } else {
            Update-RuntimeState -Active 'none' -Switching $false
        }
        Write-Host "[switch-runtime] ERROR: $To start failed: $($startResult.error)" -ForegroundColor Red
        exit 7
    }
    Write-SwitchLog "  Start ok (PID=$($startResult.pid))"

    # Step 7: Wait for health.  The Docker image may run SteamCMD verification
    # or a multi-GB game update on boot; 120 seconds proves neither failure
    # nor readiness.  Keep a finite default so an actually stalled server is
    # still surfaced to the operator.
    if (-not $Quiet) { Write-Host "[switch-runtime] Waiting for health (up to ${HealthTimeoutSeconds}s)..." }
    $healthOk = $false
    $healthWait = 0
    while ($healthWait -lt $HealthTimeoutSeconds) {
        if ($To -eq 'docker') { $health = Get-DockerRuntimeHealth }
        else { $health = Get-WindowsRuntimeHealth }
        if ($health.status -eq 'healthy') { $healthOk = $true; break }
        Start-Sleep -Seconds 2
        $healthWait += 2
    }

    if (-not $healthOk) {
        Write-SwitchLog "  Health check timeout after ${healthWait}s (limit=${HealthTimeoutSeconds}s, status=$($health.status))"
        Write-Incident -Level 'ERROR' -Type 'runtime-health-failed' -Message "$To health check timeout after ${healthWait}s (limit=${HealthTimeoutSeconds}s, status=$($health.status))"
        # Don't auto-rollback; leave runtime running for user inspection
        Update-RuntimeState -Active $To -PidValue $startResult.pid -StartedAt (Get-RuntimeIsoTimestamp) -Switching $false
        Write-Host "[switch-runtime] WARN: $To health check timed out. Runtime is running but may not be ready." -ForegroundColor Yellow
        Write-Host "[switch-runtime] Check logs and decide whether to keep or switch back." -ForegroundColor Yellow
        exit 8
    }
    Write-SwitchLog "  Health: healthy (${healthWait}s)"

    # Step 8: Update state
    $version = ''
    if ($To -eq 'docker') { $v = Get-DockerRuntimeVersion; if ($v.ok) { $version = $v.version } }
    else { $v = Get-WindowsRuntimeVersion; if ($v.ok) { $version = $v.version } }

    Update-RuntimeState -Active $To -PidValue $startResult.pid -StartedAt (Get-RuntimeIsoTimestamp) -Version $version -Switching $false -LastSwitchAt (Get-RuntimeIsoTimestamp) -LastSwitchFrom $fromRuntime -LastSwitchTo $To

    # Step 8b: Sync manifest.runtime field to match the new active runtime (design §7.2.2).
    # Note: managerEnabled is NOT auto-flipped; that remains a user decision.
    try {
        Sync-ModManifestRuntime -Runtime $To
    } catch {
        Write-SwitchLog "  Manifest runtime sync failed: $_ (non-fatal)"
        Write-Incident -Level 'WARN' -Type 'mod-manifest-sync' -Message "manifest.runtime sync failed: $_"
    }

    # Step 9: Post-switch snapshot
    if (-not $SkipSnapshot) {
        if (-not $Quiet) { Write-Host "[switch-runtime] Creating post-switch snapshot..." }
        $postType = if ($FullSnapshot) { 'Full' } else { 'Light' }
        try {
            New-SwitchSnapshot -Type $postType -Phase 'post' -From $fromRuntime -To $To | Out-Null
        } catch {
            Write-SwitchLog "  Post snapshot failed: $_ (non-fatal)"
            Write-Incident -Level 'WARN' -Type 'snapshot-failed' -Message "Post-switch snapshot failed: $_"
        }
    }

    # Step 10: Retention
    Invoke-SnapshotRetention

    Write-SwitchLog "END switch ok ($fromRuntime -> $To)"
    Write-Incident -Level 'INFO' -Type 'switch-completed' -Message "Runtime switched: $fromRuntime -> $To (health ok in ${healthWait}s)"

    if (-not $Quiet) {
        Write-Host ""
        Write-Host "[switch-runtime] ============================================" -ForegroundColor Green
        Write-Host "[switch-runtime]   Switch complete: $fromRuntime -> $To" -ForegroundColor Green
        Write-Host "[switch-runtime]   Version: $version" -ForegroundColor Green
        Write-Host "[switch-runtime]   PID: $($startResult.pid)" -ForegroundColor Green
        Write-Host "[switch-runtime] ============================================" -ForegroundColor Green
    }
    exit 0

} finally {
    if ($mutex) {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
}
