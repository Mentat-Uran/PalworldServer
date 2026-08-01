# restore-snapshot.ps1
#
# Restores Palworld server state from a switch-snapshot.
# - Requires runtime active=none (or -Force to stop first)
# - Verifies snapshot SHA-256 against manifest.json
# - Creates a temporary pre-restore Light snapshot for safety
# - Backs up current SaveGames to data\restore-backup\<timestamp>\
# - Replaces SaveGames (Full) or INI/.env (Light) from snapshot
# - Re-runs compile-settings.ps1 to ensure INI/.env consistency
# - Leaves runtime.state active=none; user must start target runtime manually
#
# Usage:
#   .\scripts\restore-snapshot.ps1 -Name 20260728-173000-Full-pre-docker-to-windows.tar.gz
#   .\scripts\restore-snapshot.ps1 -Name <name> -Force   # stop active runtime first
#   .\scripts\restore-snapshot.ps1 -List                 # list available snapshots
#
# Exit codes:
#   0 = success
#   1 = parameter / snapshot not found
#   2 = runtime active (use -Force)
#   3 = SHA-256 mismatch
#   4 = pre-restore snapshot failed (aborting)
#   5 = extraction failed
#   6 = INI recompile failed

param(
    [Parameter(Mandatory = $false)][string]$Name,
    [switch]$Force,
    [switch]$List,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot

. (Join-Path $PSScriptRoot 'runtime-common.ps1')
. (Join-Path $PSScriptRoot 'docker-runtime.ps1')
. (Join-Path $PSScriptRoot 'win-runtime.ps1')

$snapshotDir = Join-Path $projectDir 'data\switch-snapshots'
$manifestPath = Join-Path $snapshotDir 'manifest.json'
$restoreBackupDir = Join-Path $projectDir 'data\restore-backup'

function Get-RuntimeConfigDirectory {
    param([Parameter(Mandatory)][ValidateSet('LinuxServer','WindowsServer')][string]$Platform)

    if ($Platform -eq 'LinuxServer') {
        return Join-Path $projectDir 'data\Pal\Saved\Config\LinuxServer'
    }

    # Retain Config\WindowsServer as the snapshot format for compatibility
    # with existing archives, but always write it to PalServer.exe's live path.
    return Join-Path $projectDir 'win-server\Pal\Saved\Config\WindowsServer'
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Get-RestoreManifest {
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        return $null
    }
    try {
        $raw = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
        return $raw | ConvertFrom-Json
    } catch {
        Write-Warning "Manifest parse failed: $($_.Exception.Message)"
        return $null
    }
}

function Get-FileSha256Hex {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash($bytes)
    return ($hash | ForEach-Object { $_.ToString('x2') }) -join ''
}

function Write-RestoreLog {
    param([Parameter(Mandatory)][string]$Message)
    $logPath = Join-Path $projectDir 'data\diagnostics\restore.log'
    $dir = Split-Path -Parent $logPath
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Add-Content -LiteralPath $logPath -Value "[$ts] $Message" -Encoding UTF8
}

function New-TemporaryLightSnapshot {
    <# Creates a Light snapshot of the current state before destructive restore. #>
    $ts = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $name = "$ts-Light-pre-restore.tar.gz"
    $archivePath = Join-Path $snapshotDir $name

    $tempStaging = Join-Path $env:TEMP "palworld-restore-$PID"
    if (Test-Path -LiteralPath $tempStaging) { Remove-Item -LiteralPath $tempStaging -Recurse -Force }
    New-Item -ItemType Directory -Path $tempStaging -Force | Out-Null

    try {
        foreach ($platform in @('LinuxServer','WindowsServer')) {
            $platformDir = Get-RuntimeConfigDirectory -Platform $platform
            if (Test-Path -LiteralPath $platformDir -PathType Container) {
                $destDir = Join-Path $tempStaging "Config\$platform"
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                Copy-Item -Path (Join-Path $platformDir 'PalWorldSettings.ini') -Destination $destDir -ErrorAction SilentlyContinue
                Copy-Item -Path (Join-Path $platformDir 'Engine.ini') -Destination $destDir -ErrorAction SilentlyContinue
            }
        }
        Copy-Item -Path (Join-Path $projectDir '.env') -Destination $tempStaging -ErrorAction SilentlyContinue
        Copy-Item -Path (Join-Path $projectDir 'data\runtime.state') -Destination $tempStaging -ErrorAction SilentlyContinue

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

        $sha = "sha256:$(Get-FileSha256Hex -Path $archivePath)"
        $size = (Get-Item -LiteralPath $archivePath).Length

        # Update manifest
        $manifest = Get-RestoreManifest
        if ($manifest) {
            $entry = [ordered]@{
                name = $name
                type = 'Light'
                phase = 'pre-restore'
                createdAt = (Get-Date).ToString('o')
                trigger = 'restore'
                from = $null
                to = $null
                sizeBytes = $size
                sha256 = $sha
            }
            $snapList = [System.Collections.ArrayList]@($manifest.snapshots)
            $snapList.Add($entry) | Out-Null
            $manifest.snapshots = $snapList.ToArray()
            $json = $manifest | ConvertTo-Json -Depth 10 -Compress
            $tmpManifest = "$manifestPath.tmp.$PID"
            [System.IO.File]::WriteAllText($tmpManifest, $json, [System.Text.UTF8Encoding]::new($false))
            Move-Item -LiteralPath $tmpManifest -Destination $manifestPath -Force
        }
        Write-RestoreLog "  Pre-restore snapshot created: $name"
        return $true
    } finally {
        if (Test-Path -LiteralPath $tempStaging) {
            Remove-Item -LiteralPath $tempStaging -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
# -List mode
# ---------------------------------------------------------------------------
if ($List) {
    $manifest = Get-RestoreManifest
    if (-not $manifest -or -not $manifest.snapshots) {
        Write-Host "[restore-snapshot] No snapshots found in $snapshotDir"
        exit 0
    }
    Write-Host "[restore-snapshot] Available snapshots:"
    Write-Host ""
    $fmt = "{0,-50} {1,-5} {2,-12} {3,12}  {4}"
    Write-Host ($fmt -f 'Name','Type','Phase','Size','Created')
    Write-Host ($fmt -f '----','----','-----','----','-------')
    foreach ($s in $manifest.snapshots) {
        $sizeKB = [math]::Round($s.sizeBytes / 1KB, 1)
        Write-Host ($fmt -f $s.name, $s.type, $s.phase, "${sizeKB}KB", $s.createdAt)
    }
    exit 0
}

# ---------------------------------------------------------------------------
# Validate parameters
# ---------------------------------------------------------------------------
if (-not $Name) {
    Write-Host "[restore-snapshot] ERROR: -Name is required (or use -List to see available)" -ForegroundColor Red
    Write-Host "Usage: .\scripts\restore-snapshot.ps1 -Name <snapshot-name> [-Force]"
    exit 1
}

$snapshotPath = Join-Path $snapshotDir $Name
if (-not (Test-Path -LiteralPath $snapshotPath -PathType Leaf)) {
    Write-Host "[restore-snapshot] ERROR: Snapshot not found: $Name" -ForegroundColor Red
    Write-Host "[restore-snapshot] Available in: $snapshotDir"
    Write-Host "[restore-snapshot] Use -List to see all snapshots"
    exit 1
}

# Verify against manifest
$manifest = Get-RestoreManifest
$snapshotMeta = $null
if ($manifest) {
    foreach ($s in $manifest.snapshots) {
        if ($s.name -eq $Name) { $snapshotMeta = $s; break }
    }
}

if (-not $snapshotMeta) {
    Write-Host "[restore-snapshot] WARN: Snapshot not recorded in manifest.json" -ForegroundColor Yellow
    Write-Host "[restore-snapshot] Proceeding without SHA-256 verification (use caution)" -ForegroundColor Yellow
} else {
    Write-RestoreLog "Verifying SHA-256..."
    if (-not $Quiet) { Write-Host "[restore-snapshot] Verifying SHA-256..." }
    $actualHash = "sha256:$(Get-FileSha256Hex -Path $snapshotPath)"
    if ($actualHash -ne $snapshotMeta.sha256) {
        Write-Host "[restore-snapshot] ERROR: SHA-256 mismatch" -ForegroundColor Red
        Write-Host "  Expected: $($snapshotMeta.sha256)"
        Write-Host "  Actual:   $actualHash"
        Write-RestoreLog "  SHA-256 MISMATCH (expected=$($snapshotMeta.sha256) actual=$actualHash)"
        Write-Incident -Level 'ERROR' -Type 'restore-sha-mismatch' -Message "Snapshot $Name SHA-256 mismatch"
        exit 3
    }
    Write-RestoreLog "  SHA-256 ok"
}

# ---------------------------------------------------------------------------
# Acquire mutex
# ---------------------------------------------------------------------------
$mutex = $null
try {
    $mutex = Acquire-RuntimeMutex -TimeoutMs 10000
} catch {
    Write-Host "[restore-snapshot] ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

try {
    $state = Get-RuntimeState
    Write-RestoreLog "BEGIN restore $Name (active=$($state.active))"

    # Stop active runtime if -Force
    if ($state.active -ne 'none') {
        if (-not $Force) {
            Write-Host "[restore-snapshot] ERROR: Runtime is active ($($state.active)). Use -Force to stop first." -ForegroundColor Red
            Write-RestoreLog "  Refused: runtime active and -Force not specified"
            exit 2
        }
        if (-not $Quiet) { Write-Host "[restore-snapshot] Stopping active runtime ($($state.active))..." }
        Write-RestoreLog "  Stopping $($state.active)..."
        if ($state.active -eq 'docker') { $stopResult = Stop-DockerRuntime -Grace 120 }
        else { $stopResult = Stop-WindowsRuntime -Grace 120 }
        if (-not $stopResult.ok) {
            Write-Host "[restore-snapshot] ERROR: Stop failed: $($stopResult.error)" -ForegroundColor Red
            Write-RestoreLog "  Stop FAILED: $($stopResult.error)"
            exit 2
        }
        Update-RuntimeState -Active 'none' -PidValue $null -Switching $true
    } else {
        Update-RuntimeState -Switching $true
    }

    # Pre-restore safety snapshot
    if (-not $Quiet) { Write-Host "[restore-snapshot] Creating pre-restore safety snapshot..." }
    try {
        New-TemporaryLightSnapshot | Out-Null
    } catch {
        Write-Host "[restore-snapshot] ERROR: Pre-restore snapshot failed: $_" -ForegroundColor Red
        Write-RestoreLog "  Pre-restore snapshot FAILED: $_"
        Write-Incident -Level 'ERROR' -Type 'restore-pre-snapshot-failed' -Message "Pre-restore snapshot failed: $_"
        Update-RuntimeState -Switching $false
        exit 4
    }

    # Extract snapshot to temp
    $extractDir = Join-Path $env:TEMP "palworld-restore-extract-$PID"
    if (Test-Path -LiteralPath $extractDir) { Remove-Item -LiteralPath $extractDir -Recurse -Force }
    New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

    if (-not $Quiet) { Write-Host "[restore-snapshot] Extracting $Name..." }
    Write-RestoreLog "  Extracting to $extractDir"
    $tarArgs = "-xzf `"$snapshotPath`" -C `"$extractDir`""
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
    $proc.WaitForExit(120000)
    if ($proc.ExitCode -ne 0) {
        $stderr = $proc.StandardError.ReadToEnd()
        Write-Host "[restore-snapshot] ERROR: Extraction failed: $stderr" -ForegroundColor Red
        Write-RestoreLog "  Extraction FAILED: $stderr"
        Write-Incident -Level 'ERROR' -Type 'restore-extract-failed' -Message "Snapshot extraction failed: $stderr"
        Update-RuntimeState -Switching $false
        if (Test-Path -LiteralPath $extractDir) { Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue }
        exit 5
    }

    # Determine snapshot type
    $snapType = if ($snapshotMeta) { $snapshotMeta.type } else {
        # Infer from contents
        if (Test-Path -LiteralPath (Join-Path $extractDir 'SaveGames') -PathType Container) { 'Full' } else { 'Light' }
    }
    Write-RestoreLog "  Snapshot type: $snapType"

    # Backup current state to restore-backup
    $ts = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $currentBackup = Join-Path $restoreBackupDir $ts
    New-Item -ItemType Directory -Path $currentBackup -Force | Out-Null

    # Backup current .env and INI files
    if (Test-Path -LiteralPath (Join-Path $projectDir '.env')) {
        Copy-Item -Path (Join-Path $projectDir '.env') -Destination $currentBackup -Force
    }
    foreach ($platform in @('LinuxServer','WindowsServer')) {
        $platformDir = Get-RuntimeConfigDirectory -Platform $platform
        if (Test-Path -LiteralPath $platformDir -PathType Container) {
            $destDir = Join-Path $currentBackup "Config\$platform"
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            Copy-Item -Path (Join-Path $platformDir 'PalWorldSettings.ini') -Destination $destDir -ErrorAction SilentlyContinue
            Copy-Item -Path (Join-Path $platformDir 'Engine.ini') -Destination $destDir -ErrorAction SilentlyContinue
        }
    }

    if ($snapType -eq 'Full') {
        # Backup current SaveGames
        $saveGamesPath = Join-Path $projectDir 'data\Pal\Saved\SaveGames'
        if (Test-Path -LiteralPath $saveGamesPath -PathType Container) {
            Copy-Item -Path $saveGamesPath -Destination (Join-Path $currentBackup 'SaveGames') -Recurse -Force
            Write-RestoreLog "  Current SaveGames backed up to $currentBackup\SaveGames"
        }
    }
    Write-RestoreLog "  Current state backed up to $currentBackup"

    # Replace .env
    $envSrc = Join-Path $extractDir '.env'
    if (Test-Path -LiteralPath $envSrc -PathType Leaf) {
        Copy-Item -Path $envSrc -Destination (Join-Path $projectDir '.env') -Force
        Write-RestoreLog "  .env replaced"
    }

    # Replace INI files
    foreach ($platform in @('LinuxServer','WindowsServer')) {
        $srcIni = Join-Path $extractDir "Config\$platform\PalWorldSettings.ini"
        $dstIni = Join-Path (Get-RuntimeConfigDirectory -Platform $platform) 'PalWorldSettings.ini'
        if (Test-Path -LiteralPath $srcIni -PathType Leaf) {
            $parent = Split-Path -Parent $dstIni
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            Copy-Item -Path $srcIni -Destination $dstIni -Force
            Write-RestoreLog "  $platform PalWorldSettings.ini replaced"
        }
        $srcEngine = Join-Path $extractDir "Config\$platform\Engine.ini"
        $dstEngine = Join-Path (Get-RuntimeConfigDirectory -Platform $platform) 'Engine.ini'
        if (Test-Path -LiteralPath $srcEngine -PathType Leaf) {
            $parent = Split-Path -Parent $dstEngine
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            Copy-Item -Path $srcEngine -Destination $dstEngine -Force
            Write-RestoreLog "  $platform Engine.ini replaced"
        }
    }

    # Replace SaveGames (Full only)
    if ($snapType -eq 'Full') {
        $srcSaveGames = Join-Path $extractDir 'SaveGames'
        $dstSaveGames = Join-Path $projectDir 'data\Pal\Saved\SaveGames'
        if (Test-Path -LiteralPath $srcSaveGames -PathType Container) {
            # Remove current SaveGames (already backed up above)
            if (Test-Path -LiteralPath $dstSaveGames -PathType Container) {
                # If it's a junction (win-server), we don't touch the junction itself;
                # data\Pal\Saved\SaveGames is the real physical dir
                Remove-Item -LiteralPath $dstSaveGames -Recurse -Force -ErrorAction SilentlyContinue
            }
            Copy-Item -Path $srcSaveGames -Destination $dstSaveGames -Recurse -Force
            Write-RestoreLog "  SaveGames replaced (Full snapshot)"
        }
    }

    # Re-assert junction (in case win-server expects it)
    try {
        Assert-SaveGamesJunction | Out-Null
        Write-RestoreLog "  Junction re-asserted"
    } catch {
        Write-Warning "Junction re-assert failed: $_"
        Write-RestoreLog "  Junction re-assert FAILED: $_"
    }

    # Re-run compile-settings.ps1 to ensure consistency
    if (-not $Quiet) { Write-Host "[restore-snapshot] Recompiling INI..." }
    Write-RestoreLog "  Recompiling INI"
    try {
        & (Join-Path $PSScriptRoot 'compile-settings.ps1') -Quiet
        if ($LASTEXITCODE -ne 0) { throw "compile-settings.ps1 exit $LASTEXITCODE" }
    } catch {
        Write-Host "[restore-snapshot] ERROR: INI recompile failed: $_" -ForegroundColor Red
        Write-RestoreLog "  INI recompile FAILED: $_"
        Write-Incident -Level 'ERROR' -Type 'restore-ini-failed' -Message "INI recompile after restore failed: $_"
        Update-RuntimeState -Switching $false
        if (Test-Path -LiteralPath $extractDir) { Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue }
        exit 6
    }

    # Cleanup
    if (Test-Path -LiteralPath $extractDir) { Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue }

    # Leave active=none for user to manually start target runtime
    Update-RuntimeState -Active 'none' -PidValue $null -Switching $false

    Write-RestoreLog "END restore ok ($Name)"
    Write-Incident -Level 'INFO' -Type 'restore-completed' -Message "Restored from snapshot $Name (type=$snapType); current state backed up to $currentBackup"

    if (-not $Quiet) {
        Write-Host ""
        Write-Host "[restore-snapshot] ============================================" -ForegroundColor Green
        Write-Host "[restore-snapshot]   Restore complete: $Name" -ForegroundColor Green
        Write-Host "[restore-snapshot]   Type: $snapType" -ForegroundColor Green
        Write-Host "[restore-snapshot]   Pre-restore backup: $currentBackup" -ForegroundColor Green
        Write-Host "[restore-snapshot]   runtime.state active=none" -ForegroundColor Green
        Write-Host "[restore-snapshot] ============================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "[restore-snapshot] Next: start the target runtime manually:"
        Write-Host "    .\scripts\switch-runtime.ps1 -To docker"
        Write-Host "  or"
        Write-Host "    .\scripts\switch-runtime.ps1 -To windows"
    }
    exit 0

} finally {
    if ($mutex) {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
}
