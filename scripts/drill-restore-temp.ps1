# Temporary restore drill script — extracts a Full snapshot to a temp dir
# and verifies SaveGames fingerprint without touching the real SaveGames.
# Safe to delete after the drill.
param([string]$SnapshotName = '20260730-005010-Full-pre-windows-to-docker.tar.gz')

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$snapshotPath = Join-Path $projectDir "data\switch-snapshots\$SnapshotName"
$manifestPath = Join-Path $projectDir 'data\switch-snapshots\manifest.json'
# Resolve $env:TEMP to long path to avoid 8.3 short-name vs long-name mismatch
$tempBase = [System.IO.Path]::GetFullPath($env:TEMP)
$tempDir = Join-Path $tempBase "palworld-restore-drill-$PID"

Write-Host '=== Restore Drill (Temporary Copy) ===' -ForegroundColor Cyan
Write-Host "Snapshot: $SnapshotName"
Write-Host "Temp dir: $tempDir"
Write-Host ''

# 1. Read manifest
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
$snapshot = $manifest.snapshots | Where-Object { $_.name -eq $SnapshotName }
if (-not $snapshot) { throw "Snapshot not found in manifest: $SnapshotName" }

Write-Host "[1] Manifest record:"
Write-Host "  Type: $($snapshot.type)"
Write-Host "  Phase: $($snapshot.phase)"
Write-Host "  Expected SHA256: $($snapshot.sha256)"
Write-Host "  Expected SaveGames FP: $($snapshot.savegamesFingerprint)"
Write-Host ''

# 2. Verify snapshot file SHA-256
Write-Host '[2] Verifying snapshot SHA-256...' -ForegroundColor Cyan
$actualHash = (Get-FileHash -LiteralPath $snapshotPath -Algorithm SHA256).Hash.ToLowerInvariant()
$expectedHash = $snapshot.sha256 -replace '^sha256:', ''
if ($actualHash -eq $expectedHash) {
    Write-Host '  SHA-256 MATCH' -ForegroundColor Green
    $shaVerified = $true
} else {
    Write-Host "  SHA-256 MISMATCH: got=$actualHash expected=$expectedHash" -ForegroundColor Red
    throw 'SHA-256 mismatch'
}
Write-Host ''

# 3. Extract snapshot to temp dir
Write-Host '[3] Extracting snapshot to temp dir...' -ForegroundColor Cyan
if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
& tar.exe -xzf $snapshotPath -C $tempDir 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'tar extraction failed' }
$extractedSaveGames = Join-Path $tempDir 'SaveGames'
if (-not (Test-Path $extractedSaveGames)) { throw 'Extracted snapshot does not contain SaveGames (not a Full snapshot?)' }
$fileCount = (Get-ChildItem -LiteralPath $extractedSaveGames -Recurse -File).Count
Write-Host "  Extracted $fileCount files"
Write-Host ''

# 4. Compute fingerprint (same method as switch-runtime.ps1)
Write-Host '[4] Computing fingerprint of restored SaveGames...' -ForegroundColor Cyan
$sb = New-Object System.Text.StringBuilder
$files = Get-ChildItem -LiteralPath $extractedSaveGames -Recurse -File -ErrorAction SilentlyContinue | Sort-Object FullName
foreach ($f in $files) {
    $relPath = $f.FullName.Substring($extractedSaveGames.Length).TrimStart('\')
    [void]$sb.Append("$relPath|$($f.Length);")
}
$bytes = [System.Text.Encoding]::UTF8.GetBytes($sb.ToString())
$sha = [System.Security.Cryptography.SHA256]::Create()
$hash = $sha.ComputeHash($bytes)
$restoredFP = 'sha256:' + (($hash | ForEach-Object { $_.ToString('x2') }) -join '')

Write-Host "  Restored fingerprint:  $restoredFP"
Write-Host "  Expected fingerprint:  $($snapshot.savegamesFingerprint)"
$fpMatch = $restoredFP -eq $snapshot.savegamesFingerprint
if ($fpMatch) {
    Write-Host '  FINGERPRINT MATCH' -ForegroundColor Green
} else {
    Write-Host '  FINGERPRINT MISMATCH' -ForegroundColor Red
}
Write-Host ''

# 5. Compute Level.sav content hash
Write-Host '[5] Computing Level.sav content hash...' -ForegroundColor Cyan
$levelFiles = Get-ChildItem -LiteralPath $extractedSaveGames -Recurse -Filter 'Level*.sav' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.DirectoryName -notmatch '\\backup\\' } | Sort-Object FullName
$sb2 = New-Object System.Text.StringBuilder
foreach ($f in $levelFiles) {
    $relPath = $f.FullName.Substring($extractedSaveGames.Length).TrimStart('\','/')
    $fileHash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    [void]$sb2.Append("$relPath|sha256:$fileHash;")
    Write-Host "  $relPath : sha256:$($fileHash.Substring(0,24))..."
}
$bytes2 = [System.Text.Encoding]::UTF8.GetBytes($sb2.ToString())
$sha2 = [System.Security.Cryptography.SHA256]::Create()
$hash2 = $sha2.ComputeHash($bytes2)
$levelFP = 'sha256:' + (($hash2 | ForEach-Object { $_.ToString('x2') }) -join '')
Write-Host "  Level.sav composite hash: $levelFP"
Write-Host ''

# 6. Summary
Write-Host '=== Restore Drill Summary ===' -ForegroundColor Cyan
Write-Host "Snapshot SHA-256 verified: YES"
Write-Host "SaveGames fingerprint match: $(if ($fpMatch) { 'YES' } else { 'NO' })"
Write-Host "Level.sav files found: $($levelFiles.Count)"
$result = if ($shaVerified -and $fpMatch) { 'PASS' } else { 'FAIL' }
Write-Host "Result: $result" -ForegroundColor $(if ($result -eq 'PASS') {'Green'} else {'Red'})

# Cleanup
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
Write-Host 'Temp dir cleaned up.'
