# Docker runtime provider.
# Wraps existing docker compose / docker inspect / REST calls behind the
# IRuntimeProvider interface shared with win-runtime.ps1.
#
# Dot-source runtime-common.ps1 first.

if (-not (Get-Command Get-RuntimeState -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'runtime-common.ps1')
}
. (Join-Path $PSScriptRoot 'management-api.ps1')

$projectDir = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $projectDir 'docker-compose.yml'
$containerName = 'palworld-server'

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

function Invoke-DockerProcess {
    param([string]$ArgString, [int]$TimeoutMs = 60000)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'docker.exe'
    $psi.Arguments = $ArgString
    $psi.WorkingDirectory = $projectDir
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()
    if (-not $proc.WaitForExit($TimeoutMs)) {
        try { $proc.Kill() } catch { }
        throw "docker command timed out after $([math]::Round($TimeoutMs / 1000))s: $ArgString"
    }
    $proc.WaitForExit()
    return @{
        ExitCode = $proc.ExitCode
        Stdout   = $stdoutTask.Result
        Stderr   = $stderrTask.Result
    }
}

function Invoke-Compose {
    param([string]$ArgString, [int]$TimeoutMs = 60000)
    return Invoke-DockerProcess "compose -f `"$composeFile`" $ArgString" $TimeoutMs
}

function Invoke-DockerRest {
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('GET','POST')][string]$Method = 'GET',
        [System.Collections.IDictionary]$Body,
        [int]$TimeoutMs = 30000
    )
    return Invoke-ManagementRestRequest -ProjectDirectory $projectDir -Path $Path -Method $Method -Body $Body -TimeoutMs $TimeoutMs
}

# ---------------------------------------------------------------------------
# IRuntimeProvider implementation
# ---------------------------------------------------------------------------

function Start-DockerRuntime {
    <# Starts the Docker container and waits for it to enter running state. #>
    $r = Invoke-Compose 'up -d' 120000
    if ($r.ExitCode -ne 0) {
        return @{ ok = $false; error = "docker compose up failed: $($r.Stderr.Trim())" }
    }

    # Wait for container running state (max 120s)
    $waitCount = 0
    while ($waitCount -lt 60) {
        $inspect = Invoke-DockerProcess 'inspect -f "{{.State.Running}}" palworld-server' 5000
        if ($inspect.ExitCode -eq 0 -and $inspect.Stdout.Trim() -eq 'true') { break }
        Start-Sleep -Seconds 2
        $waitCount++
    }

    if ($waitCount -ge 60) {
        return @{ ok = $false; error = 'Container did not enter running state within 120s' }
    }

    # Get PID
    $pidResult = Invoke-DockerProcess 'inspect -f "{{.State.Pid}}" palworld-server' 5000
    $containerPid = $null
    if ($pidResult.ExitCode -eq 0) {
        $pidStr = $pidResult.Stdout.Trim()
        [int]$containerPid = 0
        if ([int]::TryParse($pidStr, [ref]$containerPid) -and $containerPid -gt 0) {
            # containerPid is the host-side PID of the container process
        }
    }

    # Wait briefly for REST to come up; do not fail start if REST slow (health will report)
    Start-Sleep -Seconds 2

    return @{ ok = $true; pid = $containerPid; method = 'docker' }
}

function Stop-DockerRuntime {
    param([int]$Grace = 120)
    $r = Invoke-Compose "stop -t $Grace palworld-server" ([int]($Grace * 1000 + 30000))
    if ($r.ExitCode -ne 0) {
        return @{ ok = $false; error = "docker compose stop failed: $($r.Stderr.Trim())" }
    }
    return @{ ok = $true }
}

function Get-DockerRuntimeHealth {
    $inspect = Invoke-DockerProcess 'inspect -f "{{.State.Running}}|{{.State.Status}}|{{.State.Health.Status}}" palworld-server' 5000
    if ($inspect.ExitCode -ne 0) {
        return @{ status = 'unreachable'; detail = $inspect.Stderr.Trim() }
    }
    $parts = $inspect.Stdout.Trim() -split '\|'
    $running = ($parts[0] -eq 'true')
    $status = if ($parts.Length -gt 1) { $parts[1] } else { '' }
    $health = if ($parts.Length -gt 2) { $parts[2] } else { '' }

    if (-not $running) { return @{ status = 'unreachable'; detail = "container status: $status" } }

    # Probe the same loopback REST endpoint used by Windows native runtime.
    $rest = Invoke-DockerRest -Path '/info' -Method GET -TimeoutMs 8000
    if ($rest.ok) { return @{ status = 'healthy'; detail = $health } }
    if ($health -eq 'starting') { return @{ status = 'degraded'; detail = 'container health=starting, REST not ready' } }
    return @{ status = 'degraded'; detail = "REST unreachable, container health=$health" }
}

function Invoke-DockerRuntimeSave {
    param([int]$Timeout = 30)
    $r = Invoke-DockerRest -Path '/save' -Method POST -TimeoutMs ($Timeout * 1000)
    if ($r.ok) {
        # Give the server a moment to flush
        Start-Sleep -Seconds 2
        return @{ ok = $true; method = 'rest' }
    }
    return @{ ok = $false; error = "REST save failed: $($r.error)"; code = $r.code }
}

function Get-DockerRuntimeVersion {
    $r = Invoke-DockerRest -Path '/info' -Method GET -TimeoutMs 8000
    if ($r.ok) {
        try {
            $info = $r.content | ConvertFrom-Json -ErrorAction Stop
            return @{ ok = $true; version = [string]$info.version }
        } catch {
            return @{ ok = $false; error = "parse /info failed: $($_.Exception.Message)" }
        }
    }
    return @{ ok = $false; error = $r.error }
}

function Get-DockerRuntimePlayers {
    $r = Invoke-DockerRest -Path '/players' -Method GET -TimeoutMs 8000
    if ($r.ok) {
        try {
            $players = $r.content | ConvertFrom-Json -ErrorAction Stop
            return @{ ok = $true; players = $players }
        } catch {
            return @{ ok = $false; error = "parse /players failed: $($_.Exception.Message)" }
        }
    }
    return @{ ok = $false; error = $r.error }
}

function Get-DockerRuntimeLogs {
    param([int]$Lines = 300)
    $r = Invoke-Compose "logs --tail $Lines --no-color palworld-server" 30000
    if ($r.ExitCode -eq 0) {
        return @{ ok = $true; lines = $r.Stdout -split "`r?`n" }
    }
    return @{ ok = $false; error = $r.Stderr.Trim() }
}

function Get-DockerRuntimeSettings {
    $r = Invoke-DockerRest -Path '/settings' -Method GET -TimeoutMs 8000
    if ($r.ok) {
        try {
            $settings = $r.content | ConvertFrom-Json -ErrorAction Stop
            return @{ ok = $true; settings = $settings }
        } catch {
            return @{ ok = $false; error = "parse /settings failed: $($_.Exception.Message)" }
        }
    }
    return @{ ok = $false; error = $r.error }
}

function Invoke-DockerRuntimeOperation {
    param(
        [Parameter(Mandatory)][ValidateSet('announce','kick','ban','unban')][string]$Operation,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Payload,
        [int]$Timeout = 30
    )
    $r = Invoke-ManagementOperation -ProjectDirectory $projectDir -Operation $Operation -Payload $Payload
    if ($r.ok) { return @{ ok = $true; method = 'rest'; operation = $Operation; content = $r.content } }
    return @{ ok = $false; method = 'rest'; operation = $Operation; code = $r.code; error = $r.error }
}

function Invoke-DockerRuntimeBackup {
    $r = Invoke-Compose 'exec -T palworld-server backup' 300000
    if ($r.ExitCode -eq 0) {
        return @{ ok = $true; detail = $r.Stdout.Trim() }
    }
    return @{ ok = $false; error = $r.Stderr.Trim() }
}

# ---------------------------------------------------------------------------
# RCON helper (kept for fallback; REST is primary)
# ---------------------------------------------------------------------------

function Invoke-DockerRcon {
    param([Parameter(Mandatory)][string]$Command, [int]$Timeout = 10)
    # Use docker compose exec rcon-cli if available, else direct rcon via TCP
    # The community image ships rcon-cli; rely on it.
    $r = Invoke-Compose "exec -T palworld-server rcon-cli `"$Command`"" ($Timeout * 1000 + 5000)
    if ($r.ExitCode -eq 0) {
        return @{ ok = $true; output = $r.Stdout.Trim() }
    }
    return @{ ok = $false; error = $r.Stderr.Trim() }
}

# ---------------------------------------------------------------------------
# Test dependencies
# ---------------------------------------------------------------------------

function Test-DockerRuntimeDeps {
    $dockerExists = $false
    try {
        $null = Get-Command docker.exe -ErrorAction Stop
        $dockerExists = $true
    } catch { }

    if (-not $dockerExists) {
        return @{ ok = $false; missing = @('docker.exe') }
    }
    if (-not (Test-Path -LiteralPath $composeFile -PathType Leaf)) {
        return @{ ok = $false; missing = @('docker-compose.yml') }
    }
    # Check Docker daemon responsive
    $r = Invoke-DockerProcess 'version --format "{{.Server.Version}}"' 8000
    if ($r.ExitCode -ne 0) {
        return @{ ok = $false; missing = @('docker-daemon') }
    }
    return @{ ok = $true }
}

function Get-DockerRuntimeMetrics {
    <# Returns CPU/memory metrics for the container. #>
    $r = Invoke-DockerProcess 'stats --no-stream --format "{{.CPUPerc}}|{{.MemUsage}}|{{.MemPerc}}" palworld-server' 15000
    if ($r.ExitCode -ne 0) {
        return @{ ok = $false; error = $r.Stderr.Trim() }
    }
    $line = $r.Stdout.Trim()
    if ($line -match '([\d.]+)%\s*\|\s*([\d.]+)([A-Za-z]+)\s*/\s*([\d.]+)([A-Za-z]+)\s*\|\s*([\d.]+)%') {
        return @{
            ok = $true
            cpuPercent = [double]$matches[1]
            memUsed = [double]$matches[2]
            memUsedUnit = $matches[3]
            memLimit = [double]$matches[4]
            memLimitUnit = $matches[5]
            memPercent = [double]$matches[6]
        }
    }
    return @{ ok = $false; error = "could not parse docker stats output: $line" }
}
