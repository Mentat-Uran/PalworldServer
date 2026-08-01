# Measures REST /info and /save latency plus disk I/O baseline for the active runtime.
# Usage: .\scripts\measure-latency.ps1 -Label docker  or  -Label windows
param([Parameter(Mandatory)][string]$Label)

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot

# Read admin password for REST auth
$envPath = Join-Path $projectDir '.env'
$adminPwd = ''
if (Test-Path $envPath) {
    foreach ($line in Get-Content $envPath) {
        if ($line -match '^ADMIN_PASSWORD=(.*)$') {
            $adminPwd = $matches[1].Trim('"')
            break
        }
    }
}
$basic = "admin:$adminPwd"
$bytes = [System.Text.Encoding]::ASCII.GetBytes($basic)
$b64 = [System.Convert]::ToBase64String($bytes)
$headers = @{ "Authorization" = "Basic $b64" }

$baseUrl = 'http://127.0.0.1:8212/v1/api'
$saveGamesPath = Join-Path $projectDir 'data\Pal\Saved\SaveGames'

Write-Host "=== Latency Measurement: $Label ===" -ForegroundColor Cyan
Write-Host "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host ""

# 1. REST /info latency (10 samples)
Write-Host "[1] REST /info latency (10 samples)..." -ForegroundColor Cyan
$infoTimes = @()
for ($i = 1; $i -le 10; $i++) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Invoke-RestMethod -Uri "$baseUrl/info" -Method GET -Headers $headers -TimeoutSec 15 | Out-Null
        $sw.Stop()
        $infoTimes += $sw.Elapsed.TotalMilliseconds
        Write-Host "  Sample ${i}: $([math]::Round($sw.Elapsed.TotalMilliseconds, 1)) ms"
    } catch {
        $sw.Stop()
        Write-Host "  Sample ${i}: FAILED - $($_.Exception.Message)" -ForegroundColor Red
    }
    Start-Sleep -Milliseconds 500
}

# 2. REST /save latency (3 samples - save is heavier)
Write-Host ""
Write-Host "[2] REST /save latency (3 samples)..." -ForegroundColor Cyan
$saveTimes = @()
for ($i = 1; $i -le 3; $i++) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Invoke-RestMethod -Uri "$baseUrl/save" -Method POST -Headers $headers -TimeoutSec 60 | Out-Null
        $sw.Stop()
        $saveTimes += $sw.Elapsed.TotalMilliseconds
        Write-Host "  Sample ${i}: $([math]::Round($sw.Elapsed.TotalMilliseconds, 1)) ms"
    } catch {
        $sw.Stop()
        Write-Host "  Sample ${i}: FAILED - $($_.Exception.Message)" -ForegroundColor Red
    }
    Start-Sleep -Seconds 2
}

# 3. Disk I/O baseline: write + read 10MB temp file in SaveGames dir
Write-Host ""
Write-Host "[3] Disk I/O baseline (10MB write+read in SaveGames dir)..." -ForegroundColor Cyan
$tempFile = Join-Path $saveGamesPath ".latency-test-$PID.tmp"
$data = New-Object byte[] 10485760
(new-object Random).NextBytes($data)

$writeSw = [System.Diagnostics.Stopwatch]::StartNew()
[System.IO.File]::WriteAllBytes($tempFile, $data)
$writeSw.Stop()
$writeMs = $writeSw.Elapsed.TotalMilliseconds
$writeMBps = [math]::Round(10 / ($writeMs / 1000), 1)

$readSw = [System.Diagnostics.Stopwatch]::StartNew()
$null = [System.IO.File]::ReadAllBytes($tempFile)
$readSw.Stop()
$readMs = $readSw.Elapsed.TotalMilliseconds
$readMBps = [math]::Round(10 / ($readMs / 1000), 1)

Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
Write-Host "  Write: $([math]::Round($writeMs, 1)) ms ($writeMBps MB/s)"
Write-Host "  Read:  $([math]::Round($readMs, 1)) ms ($readMBps MB/s)"

# 4. Small file sync latency (simulates save file flush)
Write-Host ""
Write-Host "[4] Small file sync latency (100x 4KB write+fsync)..." -ForegroundColor Cyan
$syncFile = Join-Path $saveGamesPath ".sync-test-$PID.tmp"
$smallData = New-Object byte[] 4096
$syncSw = [System.Diagnostics.Stopwatch]::StartNew()
$fs = [System.IO.File]::Open($syncFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
for ($i = 1; $i -le 100; $i++) {
    $fs.Write($smallData, 0, $smallData.Length)
    $fs.Flush($true)
}
$fs.Close()
$syncSw.Stop()
$syncMs = $syncSw.Elapsed.TotalMilliseconds
Remove-Item -LiteralPath $syncFile -Force -ErrorAction SilentlyContinue
Write-Host "  100x 4KB sync writes: $([math]::Round($syncMs, 1)) ms ($([math]::Round($syncMs/100, 2)) ms/op)"

# Summary
Write-Host ""
Write-Host "=== Summary: $Label ===" -ForegroundColor Cyan
if ($infoTimes.Count -gt 0) {
    $infoAvg = [math]::Round(($infoTimes | Measure-Object -Average).Average, 1)
    $infoMax = [math]::Round(($infoTimes | Measure-Object -Maximum).Maximum, 1)
    Write-Host "  /info avg: ${infoAvg} ms, max: ${infoMax} ms"
}
if ($saveTimes.Count -gt 0) {
    $saveAvg = [math]::Round(($saveTimes | Measure-Object -Average).Average, 1)
    $saveMax = [math]::Round(($saveTimes | Measure-Object -Maximum).Maximum, 1)
    Write-Host "  /save avg: ${saveAvg} ms, max: ${saveMax} ms"
}
Write-Host "  Disk write: $writeMBps MB/s, read: $readMBps MB/s"
Write-Host "  Sync write: $([math]::Round($syncMs/100, 2)) ms/op"

# Output machine-readable line
Write-Host ""
Write-Host "RESULT|$Label|info_avg=$infoAvg|info_max=$infoMax|save_avg=$saveAvg|save_max=$saveMax|write_mbps=$writeMBps|read_mbps=$readMBps|sync_ms_per_op=$([math]::Round($syncMs/100, 2))"
