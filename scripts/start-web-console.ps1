[CmdletBinding()]
param(
    [ValidateRange(5, 60)]
    [int]$StartupTimeoutSeconds = 20
)

# Starts or discovers the local-only Web Console without touching Docker,
# PalServer, SakuraFrp, saves, or runtime state. It prints only the verified
# listening port to stdout so the batch launchers can open the correct URL.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$projectDir = Split-Path -Parent $PSScriptRoot
$panelScript = Join-Path $projectDir 'settings-panel.ps1'
$pidFile = Join-Path $projectDir '.settings-panel.pid'
$portFile = Join-Path $projectDir '.settings-panel.port'
# The panel records any dynamic fallback in .settings-panel.port. Before a new
# start, probing only the three historical ports avoids a long timeout sweep
# across unused loopback ports.
$candidatePorts = @(8213, 8214, 18213)

function Get-RecordedPort {
    if (-not (Test-Path -LiteralPath $portFile -PathType Leaf)) { return $null }
    try {
        $value = [int]([System.IO.File]::ReadAllText($portFile).Trim())
        if ($value -ge 1 -and $value -le 65535) { return $value }
    } catch { }
    return $null
}

function Test-ConsolePort {
    param([int]$Port)
    try {
        # /api/runtime is a small read-only response. Unlike the dashboard it
        # does not wait for Docker/REST/tunnel telemetry, so startup probing is
        # fast even when the game server is busy.
        $response = Invoke-WebRequest -Uri "http://localhost:$Port/api/runtime" -UseBasicParsing -TimeoutSec 2
        if ($response.StatusCode -ne 200) { return $false }
        $payload = $response.Content | ConvertFrom-Json -ErrorAction Stop
        return ($null -ne $payload -and $payload.PSObject.Properties.Name -contains 'ok')
    } catch {
        return $false
    }
}

function Find-ReachableConsolePort {
    $ports = New-Object System.Collections.Generic.List[int]
    $recordedPort = Get-RecordedPort
    if ($null -ne $recordedPort) { $ports.Add($recordedPort) }
    foreach ($candidatePort in $candidatePorts) {
        if (-not $ports.Contains($candidatePort)) { $ports.Add($candidatePort) }
    }
    foreach ($candidatePort in $ports) {
        if (Test-ConsolePort -Port $candidatePort) { return $candidatePort }
    }
    return $null
}

function Test-PanelProcess {
    param([int]$ProcessId)
    try {
        $process = Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction Stop
        return ($null -ne $process -and $process.CommandLine -match [regex]::Escape('settings-panel.ps1'))
    } catch {
        return $false
    }
}

if (-not (Test-Path -LiteralPath $panelScript -PathType Leaf)) {
    throw "Web Console script is missing: $panelScript"
}

$activePort = Find-ReachableConsolePort
if ($null -ne $activePort) {
    [System.IO.File]::WriteAllText($portFile, [string]$activePort, (New-Object System.Text.UTF8Encoding($false)))
    Write-Output $activePort
    exit 0
}

$recordedPid = 0
if (Test-Path -LiteralPath $pidFile -PathType Leaf) {
    [void][int]::TryParse(([System.IO.File]::ReadAllText($pidFile).Trim()), [ref]$recordedPid)
}
if ($recordedPid -gt 0 -and (Test-PanelProcess -ProcessId $recordedPid)) {
    throw "Existing Web Console process $recordedPid is not reachable; it was not replaced automatically. Inspect data\\log-sources\\panel."
}

# Neither the recorded endpoint nor process is live, so these are stale marker
# files. Removing only the markers is safe; no game or container state changes.
Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $portFile -Force -ErrorAction SilentlyContinue

$powershellExe = Join-Path $PSHOME 'powershell.exe'
$panelProcess = Start-Process -FilePath $powershellExe `
    -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $panelScript) `
    -WorkingDirectory $projectDir -WindowStyle Hidden -PassThru
$deadline = (Get-Date).AddSeconds($StartupTimeoutSeconds)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 250
    $activePort = Find-ReachableConsolePort
    if ($null -ne $activePort) {
        Write-Output $activePort
        exit 0
    }
    if ($panelProcess.HasExited) { break }
}

$lastLog = Join-Path $projectDir ('data\\log-sources\\panel\\' + (Get-Date).ToString('yyyy-MM-dd') + '.log')
$detail = if (Test-Path -LiteralPath $lastLog) { (Get-Content -LiteralPath $lastLog -Tail 3) -join ' ' } else { 'No panel log was written.' }
throw "Web Console did not become reachable within $StartupTimeoutSeconds seconds. $detail"
