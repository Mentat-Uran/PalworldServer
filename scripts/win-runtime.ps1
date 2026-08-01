# win-runtime.ps1
#
# Windows native Palworld Dedicated Server runtime provider.
# Implements the same IRuntimeProvider interface as docker-runtime.ps1.
#
# Dot-source runtime-common.ps1 first.

if (-not (Get-Command Get-RuntimeState -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'runtime-common.ps1')
}

$projectDir = Split-Path -Parent $PSScriptRoot
$winServerDir = Join-Path $projectDir 'win-server'
$palServerExe = Join-Path $winServerDir 'PalServer.exe'
$winConfigDir = Join-Path $winServerDir 'Pal\Saved\Config\WindowsServer'
$winIniPath = Join-Path $winConfigDir 'PalWorldSettings.ini'
$saveGamesTarget = Join-Path $projectDir 'data\Pal\Saved\SaveGames'
$saveGamesJunction = Join-Path $winServerDir 'Pal\Saved\SaveGames'
$logSourceDir = Join-Path $projectDir 'data\log-sources\windows-server'
$runtimeEventSourceDir = Join-Path $projectDir 'data\log-sources\windows-runtime'

# REST base URL (Windows server binds 0.0.0.0:8212 by default;
# we call it via 127.0.0.1 since we're on the same host)
$restBaseUrl = 'http://127.0.0.1:8212/v1/api'

# ---------------------------------------------------------------------------
# Junction management (M4)
# ---------------------------------------------------------------------------

function Assert-SaveGamesJunction {
    <#
        Ensures win-server\Pal\Saved\SaveGames is a junction pointing to
        data\Pal\Saved\SaveGames. Creates or repairs as needed.

        Throws if:
        - The junction location contains a non-empty real directory (user data risk)
        - The physical target directory doesn't exist and can't be created
    #>

    # 1. Ensure physical save directory exists
    if (-not (Test-Path -LiteralPath $saveGamesTarget -PathType Container)) {
        # Check if there's content in the junction location that we'd lose
        if (Test-Path -LiteralPath $saveGamesJunction -PathType Container) {
            $junctionItem = Get-Item -LiteralPath $saveGamesJunction -Force
            if ($junctionItem.LinkType -ne 'Junction') {
                # Real directory with content — don't auto-delete
                $childCount = (Get-ChildItem -LiteralPath $saveGamesJunction -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count
                if ($childCount -gt 0) {
                    throw "Physical SaveGames target ($saveGamesTarget) is missing, but junction location ($saveGamesJunction) contains $childCount items in a real directory. Manual confirmation required before proceeding."
                }
            }
        }
        New-Item -ItemType Directory -Path $saveGamesTarget -Force | Out-Null
    }

    $targetNorm = $saveGamesTarget.TrimEnd('\')

    # 2. Check junction state
    $item = Get-Item -LiteralPath $saveGamesJunction -Force -ErrorAction SilentlyContinue
    if ($item) {
        if ($item.LinkType -eq 'Junction') {
            # Use Target property to get the actual junction target
            $currentTarget = $null
            if ($item.PSObject.Properties.Name -contains 'Target') {
                $currentTarget = [string]$item.Target
            }
            # Target may be an array; take first element
            if ($currentTarget -is [System.Array]) { $currentTarget = $currentTarget[0] }
            $currentTarget = $currentTarget.TrimEnd('\')

            if ($currentTarget -eq $targetNorm) {
                return $true  # Already correct
            }
            # Points to wrong target — remove and recreate
            cmd /c rmdir "$saveGamesJunction" 2>$null
        } else {
            # Real directory or file — check if empty
            if ($item.PSIsContainer) {
                $childCount = (Get-ChildItem -LiteralPath $saveGamesJunction -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object).Count
                if ($childCount -gt 0) {
                    throw "SaveGames junction location contains a non-empty real directory ($childCount items): $saveGamesJunction. Manual merge required."
                }
                Remove-Item -LiteralPath $saveGamesJunction -Force
            } else {
                Remove-Item -LiteralPath $saveGamesJunction -Force
            }
        }
    }

    # 3. Ensure parent directory exists
    $parent = Split-Path -Parent $saveGamesJunction
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    # 4. Create junction
    $result = cmd /c mklink /J "$saveGamesJunction" "$saveGamesTarget" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create junction: $result"
    }

    # 5. Verify
    $verifyItem = Get-Item -LiteralPath $saveGamesJunction -Force -ErrorAction SilentlyContinue
    if (-not $verifyItem -or $verifyItem.LinkType -ne 'Junction') {
        throw "Junction creation appeared to succeed but verification failed"
    }

    Write-Incident -Level 'INFO' -Type 'junction-created' -Message "SaveGames junction created: $saveGamesJunction -> $saveGamesTarget"
    return $true
}

function Test-SaveGamesJunction {
    <# Returns hashtable with junction status details. #>
    $result = [ordered]@{
        exists   = $false
        ok       = $false
        linkType = $null
        target   = $saveGamesTarget
        resolved = $null
        error    = $null
    }
    $item = Get-Item -LiteralPath $saveGamesJunction -Force -ErrorAction SilentlyContinue
    if (-not $item) { return $result }
    $result.exists = $true
    $result.linkType = $item.LinkType
    if ($item.LinkType -eq 'Junction') {
        $currentTarget = $null
        if ($item.PSObject.Properties.Name -contains 'Target') {
            $currentTarget = [string]$item.Target
        }
        if ($currentTarget -is [System.Array]) { $currentTarget = $currentTarget[0] }
        $result.resolved = $currentTarget
        $targetNorm = $saveGamesTarget.TrimEnd('\')
        $currentNorm = if ($currentTarget) { $currentTarget.TrimEnd('\') } else { '' }
        $result.ok = ($currentNorm -eq $targetNorm)
        if (-not $result.ok) { $result.error = "Points to $currentNorm, expected $targetNorm" }
    } else {
        $result.error = "Not a junction (LinkType=$($item.LinkType))"
    }
    return $result
}

# ---------------------------------------------------------------------------
# Mod drift detection (design §7.5)
# ---------------------------------------------------------------------------

function Get-DirectorySha256Win([string]$Directory) {
    <# Computes a deterministic SHA-256 over a directory tree (file path + content). #>
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        return $null
    }
    $rootItem = Get-Item -LiteralPath $Directory -Force
    if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Directory root is a reparse point: $Directory"
    }
    $root = [System.IO.Path]::GetFullPath($Directory).TrimEnd("\", "/")
    $lines = New-Object System.Collections.Generic.List[string]
    $files = @(Get-ChildItem -LiteralPath $root -Recurse -Force -File | Sort-Object FullName)
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($root.Length + 1).Replace("\", "/")
        $fileHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $lines.Add("$relative`t$fileHash")
    }
    $canonical = [string]::Join("`n", $lines.ToArray())
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($canonical)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Test-ModDrift {
    <#
        Scans installed Workshop Mods and compares their hashes against the
        manifest's expectedSha256. Returns a hashtable:
          ok         = $true if no drift detected (or manager disabled / no mods)
          drift      = $true if any enabled Mod's installed hash mismatches
          details    = array of per-Mod findings
        Design §7.5: refuses Windows runtime Start on drift.
    #>
    $manifestPath = Join-Path $projectDir 'mods\manifest.json'
    $result = [ordered]@{
        ok      = $true
        drift   = $false
        details = @()
        skipped = $false
    }
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        $result.skipped = $true
        return $result
    }
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        $result.ok = $false
        $result.drift = $true
        $result.details = @("Manifest parse failed: $($_.Exception.Message)")
        return $result
    }
    if (-not [bool]$manifest.managerEnabled) {
        $result.skipped = $true
        return $result
    }
    $mods = @($manifest.mods)
    if ($mods.Count -eq 0) {
        $result.skipped = $true
        return $result
    }

    # Resolve workshopRoot (may be relative to project or absolute)
    $workshopRootRaw = [string]$manifest.workshopRoot
    if ([System.IO.Path]::IsPathRooted($workshopRootRaw)) {
        $workshopRoot = $workshopRootRaw
    } else {
        $workshopRoot = Join-Path $projectDir $workshopRootRaw
    }

    foreach ($mod in $mods) {
        if (-not [bool]$mod.enabled) { continue }
        $expected = [string]$mod.expectedSha256
        if (-not $expected) {
            # No approved hash — mod-manager.ps1 Sync would refuse; treat as drift
            $result.details += [ordered]@{
                workshopId = [string]$mod.workshopId
                status     = 'no-approved-hash'
                expected   = $null
                actual     = $null
            }
            $result.drift = $true
            $result.ok = $false
            continue
        }
        $installedPath = Join-Path $workshopRoot ([string]$mod.workshopId)
        if (-not (Test-Path -LiteralPath $installedPath -PathType Container)) {
            # Not installed; mod-manager Sync will install. Not drift per se.
            $result.details += [ordered]@{
                workshopId = [string]$mod.workshopId
                status     = 'not-installed'
                expected   = $expected
                actual     = $null
            }
            continue
        }
        try {
            $actualHash = Get-DirectorySha256Win $installedPath
        } catch {
            $result.details += [ordered]@{
                workshopId = [string]$mod.workshopId
                status     = 'hash-error'
                expected   = $expected
                actual     = $null
                error      = $_.Exception.Message
            }
            $result.drift = $true
            $result.ok = $false
            continue
        }
        if ($actualHash -ne $expected.ToLowerInvariant()) {
            $result.details += [ordered]@{
                workshopId = [string]$mod.workshopId
                status     = 'drift'
                expected   = $expected
                actual     = $actualHash
            }
            $result.drift = $true
            $result.ok = $false
        } else {
            $result.details += [ordered]@{
                workshopId = [string]$mod.workshopId
                status     = 'ok'
                expected   = $expected
                actual     = $actualHash
            }
        }
    }
    return $result
}

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

function Get-WinLogPath {
    param([string]$Date = (Get-Date).ToString('yyyy-MM-dd'))
    if (-not (Test-Path -LiteralPath $logSourceDir -PathType Container)) {
        New-Item -ItemType Directory -Path $logSourceDir -Force | Out-Null
    }
    return Join-Path $logSourceDir "$Date.log"
}

function Get-WinRuntimeEventLogPath {
    param([string]$Date = (Get-Date).ToString('yyyy-MM-dd'))
    if (-not (Test-Path -LiteralPath $runtimeEventSourceDir -PathType Container)) {
        New-Item -ItemType Directory -Path $runtimeEventSourceDir -Force | Out-Null
    }
    return Join-Path $runtimeEventSourceDir "$Date.log"
}

function Write-WindowsRuntimeEvent {
    <# Lifecycle events are our own evidence, kept separate from engine output.
       Unreal's -abslog is best-effort and must not prevent runtime control. #>
    param(
        [Parameter(Mandatory)][string]$Event,
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )
    $line = "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff zzz'))][WINDOWS-RUNTIME][$Level][$Event] $Message"
    try {
        Add-Content -LiteralPath (Get-WinRuntimeEventLogPath) -Value $line -Encoding UTF8 -ErrorAction Stop
    } catch {
        # Lifecycle logging is observability only; never leave runtime state half-switched because it failed.
        Write-Warning "Windows runtime event log write failed: $($_.Exception.Message)"
    }
}

function Invoke-WinRest {
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('GET','POST')][string]$Method = 'GET',
        [int]$TimeoutMs = 30000
    )
    $url = $restBaseUrl + $Path
    # Palworld REST API requires HTTP Basic auth with admin:password
    $envVars = @{}
    $envPath = Join-Path $projectDir '.env'
    if (Test-Path -LiteralPath $envPath -PathType Leaf) {
        Get-Content -LiteralPath $envPath | ForEach-Object {
            $line = $_.Trim()
            if ($line -eq "" -or $line.StartsWith("#")) { return }
            $idx = $line.IndexOf("=")
            if ($idx -le 0) { return }
            $k = $line.Substring(0, $idx).Trim()
            $v = $line.Substring($idx + 1).Trim()
            if ($v.Length -ge 2 -and $v.StartsWith('"') -and $v.EndsWith('"')) { $v = $v.Substring(1, $v.Length - 2) }
            $envVars[$k] = $v
        }
    }
    $adminPwd = [string]$envVars["ADMIN_PASSWORD"]
    $basic = "admin:" + $adminPwd
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($basic)
    $b64 = [System.Convert]::ToBase64String($bytes)
    $headers = @{ "Authorization" = "Basic $b64" }
    try {
        if ($Method -eq 'GET') {
            $response = Invoke-WebRequest -Uri $url -Method GET -Headers $headers -TimeoutSec ([int]($TimeoutMs/1000)) -UseBasicParsing -ErrorAction Stop
        } else {
            $response = Invoke-WebRequest -Uri $url -Method POST -Headers $headers -TimeoutSec ([int]($TimeoutMs/1000)) -UseBasicParsing -ErrorAction Stop
        }
        return @{ ok = $true; statusCode = $response.StatusCode; content = $response.Content }
    } catch {
        return @{ ok = $false; error = $_.Exception.Message }
    }
}

# ---------------------------------------------------------------------------
# IRuntimeProvider implementation
# ---------------------------------------------------------------------------

function Test-WindowsManagementFirewall {
    <# Both management ports bind on the Windows runtime.  The named block
       rules are the fail-closed boundary that permits loopback management
       without allowing LAN/public connections. #>
    $missing = @()
    foreach ($required in @(
        @{ Name = 'Palworld Block REST 8212 Public'; Port = 8212 },
        @{ Name = 'Palworld Block RCON 25575 Public'; Port = 25575 }
    )) {
        $matches = @()
        try {
            $rules = @(Get-NetFirewallRule -DisplayName $required.Name -ErrorAction SilentlyContinue |
                Where-Object { $_.Enabled -eq 'True' -and $_.Direction -eq 'Inbound' -and $_.Action -eq 'Block' })
            foreach ($rule in $rules) {
                $filters = @(Get-NetFirewallPortFilter -AssociatedNetFirewallRule $rule -ErrorAction SilentlyContinue)
                if ($filters | Where-Object { $_.Protocol -eq 'TCP' -and [string]$_.LocalPort -eq [string]$required.Port }) {
                    $matches += $rule
                }
            }
        } catch { }
        if ($matches.Count -eq 0) { $missing += "$($required.Name) (TCP $($required.Port))" }
    }
    return @{ ok = ($missing.Count -eq 0); missing = $missing }
}

function Start-WindowsRuntime {
    <# Starts the Windows native Palworld server. #>

    # 1. Fail closed until REST/RCON have explicit inbound blocks.  Palworld
    # binds its Windows management services on all interfaces by default.
    $firewall = Test-WindowsManagementFirewall
    if (-not $firewall.ok) {
        $detail = $firewall.missing -join ', '
        Write-Incident -Level 'ERROR' -Type 'win-firewall-gate-failed' -Message "Windows runtime start refused: missing $detail"
        return @{ ok = $false; error = "Windows management firewall gate failed: $detail. Run scripts\\install-win-server.ps1 -FirewallOnly from an elevated Administrator PowerShell." }
    }

    # 2. Assert junction
    try { Assert-SaveGamesJunction }
    catch {
        return @{ ok = $false; error = "Junction assertion failed: $_" }
    }

    # 3. Check PalServer.exe
    if (-not (Test-Path -LiteralPath $palServerExe -PathType Leaf)) {
        return @{ ok = $false; error = "PalServer.exe not found at: $palServerExe (double-click install-windows-server.bat first)" }
    }

    # 4. Check INI
    if (-not (Test-Path -LiteralPath $winIniPath -PathType Leaf)) {
        # Try to compile
        try {
            & (Join-Path $PSScriptRoot 'compile-settings.ps1') -Quiet
        } catch {
            return @{ ok = $false; error = "INI missing and compilation failed: $_" }
        }
    }

    # 4b. Mod drift detection (design §7.5)
    $modDrift = Test-ModDrift
    if (-not $modDrift.ok) {
        $summary = ($modDrift.details | Where-Object { $_.status -in @('drift','no-approved-hash','hash-error') } |
                    ForEach-Object { "$($_.workshopId)=$($_.status)" }) -join ','
        Write-Incident -Level 'ERROR' -Type 'mod-drift' -Message "Mod drift detected; refusing Windows runtime start: $summary" -Detail ($modDrift.details | ConvertTo-Json -Compress -Depth 5)
        return @{ ok = $false; error = "Mod drift detected; run mod-manager.ps1 -Action Check. Details: $summary"; modDrift = $modDrift }
    }

    # 5. Start PalServer.exe. Do not use Register-ObjectEvent here: the
    # switching PowerShell process exits after this function returns, which
    # silently drops its stdout subscriptions. -abslog is an engine-owned,
    # best-effort raw-log path; lifecycle evidence is written separately.
    $logPath = Get-WinLogPath
    $argString = "-port=8211 -queryport=27015 -useperfthreads -NoAsyncLoadingThread -UseMultithreadForLoad -rcon -rpc -restapi -log -abslog=`"$logPath`""
    Write-WindowsRuntimeEvent -Event 'start-requested' -Message "Launching PalServer.exe; engine raw output path=$logPath (best-effort)."

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $palServerExe
    $psi.Arguments = $argString
    $psi.WorkingDirectory = $winServerDir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $false
    $psi.RedirectStandardError = $false
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    try {
        [void]$proc.Start()
    } catch {
        Write-WindowsRuntimeEvent -Level 'ERROR' -Event 'start-failed' -Message "PalServer.exe failed to launch: $($_.Exception.Message)"
        return @{ ok = $false; error = "Failed to start PalServer.exe: $($_.Exception.Message)" }
    }

    # 6. Wait briefly and check the launcher did not exit immediately.
    Start-Sleep -Seconds 3
    if ($proc.HasExited) {
        $lastLog = if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Tail 10 } else { @('no log') }
        Write-WindowsRuntimeEvent -Level 'ERROR' -Event 'start-failed' -Message "PalServer.exe exited immediately (code=$($proc.ExitCode))."
        Write-Incident -Level 'ERROR' -Type 'runtime-start-failed' -Message "Windows PalServer.exe exited immediately (code=$($proc.ExitCode)). Last log: $($lastLog -join '; ')"
        return @{ ok = $false; error = "PalServer.exe exited immediately (code=$($proc.ExitCode))"; log = $lastLog }
    }

    Write-WindowsRuntimeEvent -Event 'start-confirmed' -Message "PalServer.exe launcher PID=$($proc.Id) is running; REST readiness is verified by the switch health check."
    return @{ ok = $true; pid = $proc.Id; method = 'windows'; process = $proc }
}

function Stop-WindowsRuntime {
    param([int]$Grace = 120)

    $state = Get-RuntimeState
    $pidValue = $state.pid

    if (-not $pidValue) {
        # Try to find PalServer.exe by process name
        $procs = Get-Process -Name 'PalServer' -ErrorAction SilentlyContinue
        if ($procs) { $pidValue = $procs[0].Id }
    }

    if (-not $pidValue) {
        Write-WindowsRuntimeEvent -Event 'stop-noop' -Message 'No Windows runtime PID found; nothing to stop.'
        return @{ ok = $true; detail = 'No Windows runtime PID found; nothing to stop' }
    }

    # 1. Try REST /stop
    Write-WindowsRuntimeEvent -Event 'stop-requested' -Message "Requesting graceful REST stop for launcher PID=$pidValue."
    $rest = Invoke-WinRest -Path '/stop' -Method POST -TimeoutMs 30000
    if ($rest.ok) {
        # Wait for process to exit
        $waited = 0
        while ($waited -lt $Grace) {
            $p = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
            if (-not $p) { break }
            Start-Sleep -Seconds 2
            $waited += 2
        }
        $p = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
        if (-not $p) {
            Write-WindowsRuntimeEvent -Event 'stop-confirmed' -Message "Windows runtime stopped through REST; launcher PID=$pidValue."
            return @{ ok = $true; method = 'rest' }
        }
    }

    # 2. Try Stop-Process (graceful first, then force)
    try {
        $p = Get-Process -Id $pidValue -ErrorAction Stop
        $p.CloseMainWindow() | Out-Null
        $waited = 0
        while ($waited -lt 30 -and -not $p.HasExited) {
            Start-Sleep -Seconds 1
            $waited++
        }
        if (-not $p.HasExited) {
            Stop-Process -Id $pidValue -Force
            $p.WaitForExit(10000) | Out-Null
        }
        Write-WindowsRuntimeEvent -Level 'WARN' -Event 'stop-fallback' -Message "Windows runtime stopped through process fallback; launcher PID=$pidValue."
        return @{ ok = $true; method = 'process-kill' }
    } catch {
        # Process already gone
        Write-WindowsRuntimeEvent -Event 'stop-confirmed' -Message "Windows runtime launcher PID=$pidValue was already absent."
        return @{ ok = $true; detail = "Process $pidValue not found (already exited)" }
    }
}

function Get-WindowsRuntimeHealth {
    # Check if process is running
    $state = Get-RuntimeState
    $pidValue = $state.pid
    if ($pidValue) {
        $p = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
        if (-not $p) {
            return @{ status = 'unreachable'; detail = "Process $pidValue not running" }
        }
    }

    # Check REST — Windows Palworld server does not expose /health;
    # use /info (returns 200 with basic auth when ready, 401/404 otherwise).
    $rest = Invoke-WinRest -Path '/info' -Method GET -TimeoutMs 5000
    $saveIntegrity = Test-SaveGamesIntegrity
    $result = [ordered]@{
        status      = if ($rest.ok) { 'healthy' } else { 'degraded' }
        detail      = if ($rest.ok) { 'REST /info responded' } else { "REST unreachable: $($rest.error)" }
        saveGames   = $saveIntegrity
    }
    if ($saveIntegrity.corrupted) {
        # Don't downgrade healthy->degraded solely on backup staleness, but
        # flag corruption (missing Level.sav) as degraded.
        if ($saveIntegrity.levelSavPresent -eq $false) {
            $result.status = 'degraded'
            $result.detail = "SaveGames corruption: $($saveIntegrity.error)"
        }
        Write-Incident -Level 'WARN' -Type 'savegames-integrity' -Message "SaveGames integrity check flagged: $($saveIntegrity.error)"
    }
    return $result
}

function Test-SaveGamesIntegrity {
    <#
        Design §9.3.1: checks SaveGames integrity.
        - data\Pal\Saved\SaveGames\0\<GUID>\Level.sav exists and is > 0 bytes
        - Most recent auto-backup under <GUID>\backup\ is within 1 hour (warning if not)
        Returns a hashtable with detailed status. `corrupted=true` only when
        Level.sav is missing or zero-byte; stale backup is a warning only.
    #>
    $result = [ordered]@{
        ok               = $true
        corrupted        = $false
        levelSavPresent  = $false
        levelSavSize     = 0L
        worldGuid        = $null
        backupNewestAt   = $null
        backupStale      = $false
        error            = $null
    }

    $saveGamesRoot = Join-Path $projectDir 'data\Pal\Saved\SaveGames'
    if (-not (Test-Path -LiteralPath $saveGamesRoot -PathType Container)) {
        $result.ok = $false
        $result.corrupted = $true
        $result.error = "SaveGames root missing: $saveGamesRoot"
        return $result
    }

    # Locate world GUID directory under 0\
    $worldsParent = Join-Path $saveGamesRoot '0'
    if (-not (Test-Path -LiteralPath $worldsParent -PathType Container)) {
        # No worlds yet — fresh install, not corruption
        $result.error = "No worlds directory yet (fresh install)"
        return $result
    }

    $worldDirs = @(Get-ChildItem -LiteralPath $worldsParent -Directory -ErrorAction SilentlyContinue)
    if ($worldDirs.Count -eq 0) {
        $result.error = "No world GUID directory yet (fresh install)"
        return $result
    }
    # Pick the most recently modified world directory
    $worldDir = $worldDirs | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $result.worldGuid = $worldDir.Name

    $levelSav = Join-Path $worldDir.FullName 'Level.sav'
    if (Test-Path -LiteralPath $levelSav -PathType Leaf) {
        $fileInfo = Get-Item -LiteralPath $levelSav
        $result.levelSavSize = $fileInfo.Length
        if ($fileInfo.Length -gt 0) {
            $result.levelSavPresent = $true
        } else {
            $result.ok = $false
            $result.corrupted = $true
            $result.error = "Level.sav is zero bytes in world $($worldDir.Name)"
            return $result
        }
    } else {
        $result.ok = $false
        $result.corrupted = $true
        $result.error = "Level.sav missing in world $($worldDir.Name)"
        return $result
    }

    # Check auto-backup freshness (warning only)
    $backupDir = Join-Path $worldDir.FullName 'backup'
    if (Test-Path -LiteralPath $backupDir -PathType Container) {
        $backupItems = @(Get-ChildItem -LiteralPath $backupDir -Directory -ErrorAction SilentlyContinue |
                         Sort-Object LastWriteTime -Descending)
        if ($backupItems.Count -gt 0) {
            $newest = $backupItems[0]
            $result.backupNewestAt = $newest.LastWriteTime.ToString('o')
            $age = (Get-Date) - $newest.LastWriteTime
            if ($age.TotalHours -gt 1) {
                $result.backupStale = $true
                # Stale backup is a warning, not corruption
            }
        }
    }

    return $result
}

function Read-WindowsRconExact {
    param([System.IO.Stream]$Stream, [int]$Count)
    $buffer = New-Object byte[] $Count
    $offset = 0
    while ($offset -lt $Count) {
        $read = $Stream.Read($buffer, $offset, $Count - $offset)
        if ($read -le 0) { throw 'RCON connection closed before a complete packet was received.' }
        $offset += $read
    }
    return $buffer
}

function Write-WindowsRconPacket {
    param(
        [System.IO.Stream]$Stream,
        [int]$RequestId,
        [int]$Type,
        [string]$Body
    )
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $payloadLength = 10 + $bodyBytes.Length
    $packet = New-Object byte[] (4 + $payloadLength)
    [System.Buffer]::BlockCopy([BitConverter]::GetBytes($payloadLength), 0, $packet, 0, 4)
    [System.Buffer]::BlockCopy([BitConverter]::GetBytes($RequestId), 0, $packet, 4, 4)
    [System.Buffer]::BlockCopy([BitConverter]::GetBytes($Type), 0, $packet, 8, 4)
    if ($bodyBytes.Length -gt 0) { [System.Buffer]::BlockCopy($bodyBytes, 0, $packet, 12, $bodyBytes.Length) }
    $Stream.Write($packet, 0, $packet.Length)
    $Stream.Flush()
}

function Read-WindowsRconPacket {
    param([System.IO.Stream]$Stream)
    $lengthBytes = Read-WindowsRconExact -Stream $Stream -Count 4
    $payloadLength = [BitConverter]::ToInt32($lengthBytes, 0)
    if ($payloadLength -lt 10 -or $payloadLength -gt 1MB) {
        throw "Invalid RCON packet length: $payloadLength"
    }
    $payload = Read-WindowsRconExact -Stream $Stream -Count $payloadLength
    return [ordered]@{
        id = [BitConverter]::ToInt32($payload, 0)
        type = [BitConverter]::ToInt32($payload, 4)
        body = if ($payloadLength -gt 10) { [System.Text.Encoding]::UTF8.GetString($payload, 8, $payloadLength - 10) } else { '' }
    }
}

function Get-WindowsAdminPassword {
    $envPath = Join-Path $projectDir '.env'
    if (-not (Test-Path -LiteralPath $envPath -PathType Leaf)) { return $null }
    foreach ($rawLine in Get-Content -LiteralPath $envPath) {
        $line = $rawLine.Trim()
        if ($line -notmatch '^ADMIN_PASSWORD=(.*)$') { continue }
        $value = $matches[1].Trim()
        if ($value.Length -ge 2 -and $value.StartsWith('"') -and $value.EndsWith('"')) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        return $value
    }
    return $null
}

function Invoke-WindowsRcon {
    <# Compatibility fallback only. REST remains the primary management path. #>
    param([Parameter(Mandatory)][string]$Command, [int]$Timeout = 10)
    if (-not $Command -or $Command.Length -gt 512 -or $Command -match "[`r`n`0]") {
        return @{ ok = $false; error = 'RCON command must be one line and at most 512 characters.' }
    }
    $password = Get-WindowsAdminPassword
    if (-not $password) { return @{ ok = $false; error = 'ADMIN_PASSWORD is unavailable for local RCON fallback.' } }

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $connect = $client.BeginConnect('127.0.0.1', 25575, $null, $null)
        if (-not $connect.AsyncWaitHandle.WaitOne($Timeout * 1000)) {
            throw 'Local RCON connection timed out.'
        }
        $client.EndConnect($connect)
        $stream = $client.GetStream()
        $stream.ReadTimeout = $Timeout * 1000
        $stream.WriteTimeout = $Timeout * 1000

        $authId = 2147000001
        Write-WindowsRconPacket -Stream $stream -RequestId $authId -Type 3 -Body $password
        $authenticated = $false
        # Source RCON implementations can emit an empty RESPONSE_VALUE before
        # AUTH_RESPONSE. Do not mistake that packet for authentication success.
        for ($attempt = 0; $attempt -lt 4; $attempt++) {
            $auth = Read-WindowsRconPacket -Stream $stream
            if ($auth.id -eq -1) { throw 'Local RCON authentication failed.' }
            if ($auth.id -eq $authId -and $auth.type -eq 2) {
                $authenticated = $true
                break
            }
        }
        if (-not $authenticated) { throw 'Local RCON authentication response was not received.' }

        $commandId = 2147000002
        Write-WindowsRconPacket -Stream $stream -RequestId $commandId -Type 2 -Body $Command
        $response = $null
        # Some servers flush an additional auth RESPONSE_VALUE after the auth
        # response. Palworld's RCON implementation currently sends command
        # RESPONSE_VALUE packets with ID 0 rather than echoing the request ID.
        # Accept that documented runtime behavior only for a response-value
        # packet, still bounded by the stream timeout and attempt count.
        for ($attempt = 0; $attempt -lt 4; $attempt++) {
            $candidate = Read-WindowsRconPacket -Stream $stream
            if ($candidate.id -eq -1) { throw 'Local RCON command was rejected.' }
            if ($candidate.id -eq $commandId -or ($candidate.id -eq 0 -and $candidate.type -eq 0)) {
                $response = $candidate
                break
            }
        }
        if ($null -eq $response) { throw 'Local RCON did not return a response for this command.' }
        return @{ ok = $true; output = ([string]$response.body).Trim([char]0); method = 'rcon' }
    } catch {
        return @{ ok = $false; error = "Local RCON fallback failed: $($_.Exception.Message)" }
    } finally {
        if ($stream) { $stream.Dispose() }
        $client.Dispose()
    }
}

function Invoke-WindowsRuntimeSave {
    param([int]$Timeout = 30)
    $r = Invoke-WinRest -Path '/save' -Method POST -TimeoutMs ($Timeout * 1000)
    if ($r.ok) {
        Start-Sleep -Seconds 2
        return @{ ok = $true; method = 'rest' }
    }
    $rcon = Invoke-WindowsRcon -Command 'Save' -Timeout ([math]::Min(15, [math]::Max(5, $Timeout)))
    if ($rcon.ok) {
        Start-Sleep -Seconds 2
        return @{ ok = $true; method = 'rcon' }
    }
    return @{ ok = $false; error = "REST save failed: $($r.error); RCON fallback failed: $($rcon.error)" }
}

function Get-WindowsRuntimeVersion {
    $r = Invoke-WinRest -Path '/info' -Method GET -TimeoutMs 8000
    if ($r.ok) {
        try {
            $info = $r.content | ConvertFrom-Json -ErrorAction Stop
            return @{ ok = $true; version = [string]$info.version }
        } catch {
            return @{ ok = $false; error = "parse /info failed: $($_.Exception.Message)" }
        }
    }
    # Fallback: read version.txt
    $versionFile = Join-Path $winServerDir 'version.txt'
    if (Test-Path -LiteralPath $versionFile -PathType Leaf) {
        $buildId = (Get-Content -LiteralPath $versionFile -Raw).Trim()
        return @{ ok = $true; version = "build:$buildId"; fallback = $true }
    }
    return @{ ok = $false; error = $r.error }
}

function Get-WindowsRuntimePlayers {
    $r = Invoke-WinRest -Path '/players' -Method GET -TimeoutMs 8000
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

function Get-WindowsRuntimeLogs {
    param([int]$Lines = 300)
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($source in @(
        @{ path = (Get-WinRuntimeEventLogPath); label = 'WINDOWS-RUNTIME' },
        @{ path = (Get-WinLogPath); label = 'WINDOWS-ENGINE' }
    )) {
        if (-not (Test-Path -LiteralPath $source.path -PathType Leaf)) { continue }
        foreach ($line in @(Get-Content -LiteralPath $source.path -Tail $Lines -ErrorAction SilentlyContinue)) {
            $result.Add("[$($source.label)] $line")
        }
    }
    return @{ ok = $true; lines = @($result | Select-Object -Last $Lines) }
}

function Get-WindowsRuntimeSettings {
    $r = Invoke-WinRest -Path '/settings' -Method GET -TimeoutMs 8000
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

function Invoke-WindowsRuntimeBackup {
    # 1. REST save
    $save = Invoke-WindowsRuntimeSave -Timeout 30
    if (-not $save.ok) {
        return @{ ok = $false; error = "Save before backup failed; archive was not created: $($save.error)" }
    }

    # 2. Wait for flush
    Start-Sleep -Seconds 5

    # 3. tar SaveGames + Config
    $timestamp = (Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')
    $backupDir = Join-Path $projectDir 'data\backups'
    [System.IO.Directory]::CreateDirectory($backupDir) | Out-Null
    $backupPath = Join-Path $backupDir "palworld-win-save-$timestamp.tar.gz"

    $saveGamesPath = Join-Path $projectDir 'data\Pal\Saved\SaveGames'
    $configPath = Join-Path $projectDir 'data\Pal\Saved\Config'
    if (-not (Test-Path -LiteralPath $saveGamesPath -PathType Container) -or
        -not (Test-Path -LiteralPath $configPath -PathType Container)) {
        return @{ ok = $false; error = 'SaveGames or Config source directory is missing; archive was not created.' }
    }

    # Use tar (available on Windows 10+)
    $tarArgs = "-czf `"$backupPath`" -C `"$projectDir\data\Pal\Saved`" SaveGames Config"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'tar.exe'
    $psi.Arguments = $tarArgs
    $psi.WorkingDirectory = $projectDir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    if (-not $proc.WaitForExit(120000)) {
        try { $proc.Kill() } catch { }
        return @{ ok = $false; error = 'tar timed out after 120 seconds; archive result is not trusted.' }
    }

    if ($proc.ExitCode -ne 0) {
        $stderr = $proc.StandardError.ReadToEnd()
        return @{ ok = $false; error = "tar failed: $stderr" }
    }
    if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf) -or
        (Get-Item -LiteralPath $backupPath).Length -le 0) {
        return @{ ok = $false; error = 'tar returned success but no non-empty archive was created.' }
    }

    # 4. Apply retention (DELETE_OLD_BACKUPS / OLD_BACKUP_DAYS)
    . (Join-Path $PSScriptRoot '..\scripts\settings-catalog.ps1')
    # Read .env for retention settings
    $envFile = Join-Path $projectDir '.env'
    $deleteOld = $false
    $oldDays = 5
    if (Test-Path -LiteralPath $envFile -PathType Leaf) {
        foreach ($line in [System.IO.File]::ReadAllLines($envFile)) {
            if ($line -match '^\s*DELETE_OLD_BACKUPS=(.*)$') { $deleteOld = ($matches[1].Trim() -match '^(?i:true|1)') }
            if ($line -match '^\s*OLD_BACKUP_DAYS=(.*)$') { [int]::TryParse($matches[1].Trim(), [ref]$oldDays) | Out-Null }
        }
    }

    if ($deleteOld -and $oldDays -gt 0) {
        $cutoff = (Get-Date).AddDays(-$oldDays)
        Get-ChildItem -LiteralPath $backupDir -Filter 'palworld-*.tar.gz' |
            Where-Object { $_.LastWriteTime -lt $cutoff } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }

    return @{ ok = $true; path = $backupPath; method = 'windows-tar'; saveMethod = $save.method }
}

# ---------------------------------------------------------------------------
# Test dependencies
# ---------------------------------------------------------------------------

function Test-WindowsRuntimeDeps {
    $missing = @()

    if (-not (Test-Path -LiteralPath $palServerExe -PathType Leaf)) {
        $missing += 'PalServer.exe'
    }
    if (-not (Test-Path -LiteralPath $winIniPath -PathType Leaf)) {
        $missing += 'WindowsServer\PalWorldSettings.ini'
    }

    $firewall = Test-WindowsManagementFirewall
    if (-not $firewall.ok) {
        $missing += "Windows management firewall blocks: $($firewall.missing -join ', ')"
    }

    # Check tar.exe
    $tar = Get-Command tar.exe -ErrorAction SilentlyContinue
    if (-not $tar) { $missing += 'tar.exe' }

    if ($missing.Count -gt 0) {
        return @{ ok = $false; missing = $missing }
    }
    return @{ ok = $true }
}

function Get-WindowsRuntimeMetrics {
    <# Returns CPU/memory metrics for the Windows PalServer process. #>
    $state = Get-RuntimeState
    $pidValue = $state.pid
    if (-not $pidValue) {
        $procs = Get-Process -Name 'PalServer' -ErrorAction SilentlyContinue
        if ($procs) { $pidValue = $procs[0].Id }
    }
    if (-not $pidValue) {
        return @{ ok = $false; error = 'No PalServer process found' }
    }

    $p = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
    if (-not $p) {
        return @{ ok = $false; error = "Process $pidValue not found" }
    }

    # CPU percent: process.TotalProcessorTime as a fraction of (elapsed * cores)
    # This is a rough approximation
    $cpuTime = $p.TotalProcessorTime.TotalSeconds
    $elapsed = ((Get-Date) - $p.StartTime).TotalSeconds
    $cores = [Environment]::ProcessorCount
    $cpuPercent = if ($elapsed -gt 0) { ($cpuTime / ($elapsed * $cores)) * 100 } else { 0 }

    # Memory in MB
    $memUsed = [math]::Round($p.WorkingSet64 / 1MB, 1)
    # Memory limit: read from .env or default to 8192 MB (matching Docker)
    $memLimit = 8192
    $memPercent = [math]::Round(($memUsed / $memLimit) * 100, 1)

    return @{
        ok = $true
        cpuPercent = [math]::Round($cpuPercent, 1)
        memUsed = $memUsed
        memUsedUnit = 'MB'
        memLimit = $memLimit
        memLimitUnit = 'MB'
        memPercent = $memPercent
        processId = $pidValue
    }
}
