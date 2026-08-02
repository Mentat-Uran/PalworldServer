# Temporary verification script — uses runtime providers to check active runtime state.
# Usage: .\scripts\verify-runtime-state.ps1
# Safe to delete after the drill.

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot

. (Join-Path $PSScriptRoot 'runtime-common.ps1')
. (Join-Path $PSScriptRoot 'docker-runtime.ps1')
. (Join-Path $PSScriptRoot 'win-runtime.ps1')

# Inline fingerprint functions (copied from switch-runtime.ps1 to avoid re-executing it)
function Get-SaveGamesFingerprint {
    $saveGamesPath = Join-Path $projectDir 'data\Pal\Saved\SaveGames'
    if (-not (Test-Path -LiteralPath $saveGamesPath -PathType Container)) { return 'sha256:empty' }
    $sb = New-Object System.Text.StringBuilder
    $files = Get-ChildItem -LiteralPath $saveGamesPath -Recurse -File -ErrorAction SilentlyContinue | Sort-Object FullName
    foreach ($f in $files) {
        $relPath = $f.FullName.Substring($saveGamesPath.Length).TrimStart('\')
        [void]$sb.Append("$relPath|$($f.Length);")
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($sb.ToString())
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash($bytes)
    return 'sha256:' + (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Get-IniFingerprint {
    $iniPath = Join-Path $projectDir 'win-server\Pal\Saved\Config\WindowsServer\PalWorldSettings.ini'
    if (-not (Test-Path -LiteralPath $iniPath -PathType Leaf)) { return 'sha256:empty' }
    $bytes = [System.IO.File]::ReadAllBytes($iniPath)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash($bytes)
    return 'sha256:' + (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
}

$state = Get-RuntimeState
Write-Host "=== Runtime State ===" -ForegroundColor Cyan
$state | ConvertTo-Json | Write-Host
Write-Host ""

if ($state.active -eq 'none') {
    Write-Host "No active runtime." -ForegroundColor Yellow
    exit 0
}

$provider = if ($state.active -eq 'docker') { 'Docker' } else { 'Windows' }
Write-Host "=== Active Runtime: $provider ===" -ForegroundColor Cyan

# Health
$health = if ($state.active -eq 'docker') { Get-DockerRuntimeHealth } else { Get-WindowsRuntimeHealth }
Write-Host "Health: $($health.status)" -ForegroundColor $(if ($health.status -eq 'healthy') {'Green'} else {'Yellow'})
Write-Host ""

# Version
$ver = if ($state.active -eq 'docker') { Get-DockerRuntimeVersion } else { Get-WindowsRuntimeVersion }
Write-Host "Version: $(if ($ver.ok) { $ver.version } else { $ver.error })"

# Players
$players = if ($state.active -eq 'docker') { Get-DockerRuntimePlayers } else { Get-WindowsRuntimePlayers }
Write-Host "Players: $(if ($players.ok) { (@($players.players) | Measure-Object).Count.ToString() + ' online' } else { $players.error })"

# Settings
$settings = if ($state.active -eq 'docker') { Get-DockerRuntimeSettings } else { Get-WindowsRuntimeSettings }
Write-Host "Settings: $(if ($settings.ok) { 'ok' } else { $settings.error })"

# SaveGames fingerprint (from switch-runtime.ps1)
$fp = Get-SaveGamesFingerprint
Write-Host "SaveGames fingerprint: $fp"

# INI fingerprint
$iniFp = Get-IniFingerprint
Write-Host "INI fingerprint: $iniFp"

# Junction (always check)
try {
    $junctionOk = Assert-SaveGamesJunction
    Write-Host "Junction: ok" -ForegroundColor Green
} catch {
    Write-Host "Junction: FAILED - $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Snapshot Manifest (latest 5) ===" -ForegroundColor Cyan
$manifestPath = Join-Path $projectDir 'data\switch-snapshots\manifest.json'
if (Test-Path $manifestPath) {
    $m = Get-Content $manifestPath -Raw | ConvertFrom-Json
    $latest = $m.snapshots | Sort-Object createdAt -Descending | Select-Object -First 5
    foreach ($s in $latest) {
        Write-Host ("  {0} {1,-5} {2,-5} {3} -> {4}  fp={5}" -f $s.createdAt, $s.type, $s.phase, $s.from, $s.to, $s.savegamesFingerprint.Substring(0,20))
    }
}
