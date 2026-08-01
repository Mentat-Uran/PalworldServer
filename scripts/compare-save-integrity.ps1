# Compares core save files (Level.sav, LevelMeta.sav) between a Full snapshot and live SaveGames.
# This verifies world data integrity across a runtime switch, ignoring backup/metadata file changes.
param([Parameter(Mandatory)][string]$SnapshotName)

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$snapshotPath = Join-Path $projectDir "data\switch-snapshots\$SnapshotName"
$liveSaveGames = Join-Path $projectDir 'data\Pal\Saved\SaveGames'

function Get-ActiveRuntimeForComparison {
    $statePath = Join-Path $projectDir 'data\runtime.state'
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return 'unknown' }
    try {
        $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        return [string]$state.active
    } catch {
        return 'unknown'
    }
}

if (-not (Test-Path $snapshotPath)) { throw "Snapshot not found: $snapshotPath" }

# Extract snapshot to temp
# Resolve $env:TEMP to long path to avoid 8.3 short-name vs long-name mismatch
# when computing relative paths via Substring (Get-ChildItem returns long names).
$tempBase = [System.IO.Path]::GetFullPath($env:TEMP)
$extractDir = Join-Path $tempBase "palworld-integrity-check-$PID"
if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

Write-Host "[integrity] Extracting $SnapshotName..." -ForegroundColor Cyan
& tar.exe -xzf $snapshotPath -C $extractDir 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw "tar extraction failed" }

$snapshotSaveGames = Join-Path $extractDir 'SaveGames'
if (-not (Test-Path $snapshotSaveGames)) { throw "Snapshot does not contain SaveGames (not a Full snapshot?)" }

# Excludes runtime-created or historical backup directories. They are not part
# of the active world state and may legitimately differ between Docker and
# Windows after a switch.
function Test-TransientSavePath {
    param([Parameter(Mandatory)][string]$Path)
    return $Path -match '(?i)(?:^|[\\/])(?:backup|world_save_bak)(?:[\\/]|$)'
}

# Compute fingerprint of core save files only (Level.sav, LevelMeta.sav, Players/*.sav).
function Get-CoreSaveFingerprint {
    param([string]$Path)
    $sb = New-Object System.Text.StringBuilder
    $files = Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { -not (Test-TransientSavePath -Path $_.FullName) } |
        Sort-Object FullName
    foreach ($f in $files) {
        $relPath = $f.FullName.Substring($Path.Length).TrimStart('\','/')
        [void]$sb.Append("$relPath|$($f.Length)|$($f.LastWriteTime.Ticks);")
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($sb.ToString())
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash($bytes)
    return 'sha256:' + (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Get-LevelSavFingerprint {
    param([string]$Path)
    # Only hash Level.sav and LevelMeta.sav files (the actual world state)
    $sb = New-Object System.Text.StringBuilder
    $files = Get-ChildItem -LiteralPath $Path -Recurse -Filter 'Level*.sav' -File -ErrorAction SilentlyContinue |
        Where-Object { -not (Test-TransientSavePath -Path $_.FullName) } |
        Sort-Object FullName
    foreach ($f in $files) {
        $relPath = $f.FullName.Substring($Path.Length).TrimStart('\','/')
        $fileHash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        [void]$sb.Append("$relPath|sha256:$fileHash;")
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($sb.ToString())
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash($bytes)
    return 'sha256:' + (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
}

$snapshotCore = Get-CoreSaveFingerprint -Path $snapshotSaveGames
$liveCore = Get-CoreSaveFingerprint -Path $liveSaveGames

$snapshotLevel = Get-LevelSavFingerprint -Path $snapshotSaveGames
$liveLevel = Get-LevelSavFingerprint -Path $liveSaveGames

$activeRuntime = Get-ActiveRuntimeForComparison
if ($activeRuntime -in @('docker', 'windows')) {
    Write-Warning "The $activeRuntime runtime is active. A byte mismatch against its live SaveGames can result from normal post-snapshot saves or world-time updates; it is not, by itself, corruption evidence."
}

Write-Host ""
Write-Host "=== Core Save Files (excluding backup/ and world_save_bak/) ===" -ForegroundColor Cyan
Write-Host "Snapshot core fingerprint: $snapshotCore"
Write-Host "Live core fingerprint:     $liveCore"
Write-Host "Match: $(if ($snapshotCore -eq $liveCore) { 'YES' } else { 'NO' })" -ForegroundColor $(if ($snapshotCore -eq $liveCore) {'Green'} else {'Yellow'})

Write-Host ""
Write-Host "=== Level.sav Content Hash ===" -ForegroundColor Cyan
Write-Host "Snapshot Level fingerprint: $snapshotLevel"
Write-Host "Live Level fingerprint:     $liveLevel"
Write-Host "Match: $(if ($snapshotLevel -eq $liveLevel) { 'YES' } else { 'NO' })" -ForegroundColor $(if ($snapshotLevel -eq $liveLevel) {'Green'} else {'Yellow'})

# Count files
$snapCount = (Get-ChildItem -LiteralPath $snapshotSaveGames -Recurse -File | Where-Object { -not (Test-TransientSavePath -Path $_.FullName) }).Count
$liveCount = (Get-ChildItem -LiteralPath $liveSaveGames -Recurse -File | Where-Object { -not (Test-TransientSavePath -Path $_.FullName) }).Count
Write-Host ""
Write-Host "Snapshot non-backup files: $snapCount"
Write-Host "Live non-backup files:     $liveCount"

# Cleanup
Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
