# win-runtime.ps1
#
# Windows native Palworld Dedicated Server runtime provider.
# Implements the same IRuntimeProvider interface as docker-runtime.ps1.
#
# Dot-source runtime-common.ps1 first.

if (-not (Get-Command Get-RuntimeState -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'runtime-common.ps1')
}
. (Join-Path $PSScriptRoot 'management-api.ps1')

$projectDir = Split-Path -Parent $PSScriptRoot
$winServerDir = Join-Path $projectDir 'win-server'
$palServerExe = Join-Path $winServerDir 'PalServer.exe'
$winConfigDir = Join-Path $winServerDir 'Pal\Saved\Config\WindowsServer'
$winIniPath = Join-Path $winConfigDir 'PalWorldSettings.ini'
$saveGamesTarget = Join-Path $projectDir 'data\Pal\Saved\SaveGames'
$saveGamesJunction = Join-Path $winServerDir 'Pal\Saved\SaveGames'
$logSourceDir = Join-Path $projectDir 'data\log-sources\windows-server'
$runtimeEventSourceDir = Join-Path $projectDir 'data\log-sources\windows-runtime'

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
        [System.Collections.IDictionary]$Body,
        [int]$TimeoutMs = 30000
    )
    return Invoke-ManagementRestRequest -ProjectDirectory $projectDir -Path $Path -Method $Method -Body $Body -TimeoutMs $TimeoutMs
}

# ---------------------------------------------------------------------------
# IRuntimeProvider implementation
# ---------------------------------------------------------------------------

function Test-WindowsManagementFirewall {
    <# Both management ports bind on the Windows runtime.  The named block
       rules are the fail-closed boundary that permits loopback management
       without allowing LAN/public connections. #>
    $missing = @()
    $management = Get-ManagementEndpointConfig -ProjectDirectory $projectDir
    $requiredRules = @()
    if ($management.restEnabled) { $requiredRules += @{ Name = "Palworld Block REST $($management.restPort) Public"; Port = $management.restPort } }
    if ($management.legacyRconEnabled) { $requiredRules += @{ Name = "Palworld Block RCON $($management.rconPort) Public"; Port = $management.rconPort } }
    foreach ($required in $requiredRules) {
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

function Get-WindowsRuntimeLaunchArguments {
    param(
        [Parameter(Mandatory)][object]$Management,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Environment,
        [Parameter(Mandatory)][string]$LogPath
    )

    $logFormat = if ($Environment.ContainsKey('LOG_FORMAT_TYPE') -and $Environment['LOG_FORMAT_TYPE']) {
        ([string]$Environment['LOG_FORMAT_TYPE']).ToLowerInvariant()
    } else { 'text' }
    if ($logFormat -notin @('text', 'json')) { $logFormat = 'text' }

    $flags = @("-port=$($Management.gamePort)", "-queryport=$($Management.queryPort)", "-logformat=$logFormat", '-log', "-abslog=`"$LogPath`"")
    if ($Management.restEnabled -and $Management.windowsRestCompatibilityMode -eq 'compat') {
        $flags += '-restapi'
    }
    $perfArgsEnabled = ConvertTo-ManagementBoolean $Environment['ENABLE_PERF_THREADING_ARGS'] $false
    if ($perfArgsEnabled) {
        $flags += @('-useperfthreads', '-NoAsyncLoadingThread', '-UseMultithreadForDS')
        $workerThreads = 0
        if ([int]::TryParse([string]$Environment['WORKER_THREADS_SERVER'], [ref]$workerThreads) -and $workerThreads -gt 0) {
            $flags += "-NumberOfWorkerThreadsServer=$workerThreads"
        }
    }
    return [pscustomobject]@{
        flags = @($flags)
        restMode = [string]$Management.windowsRestCompatibilityMode
        perfArgsEnabled = $perfArgsEnabled
    }
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
    $management = Get-ManagementEndpointConfig -ProjectDirectory $projectDir
    $environment = Read-ManagementEnv -ProjectDirectory $projectDir
    $launchArguments = Get-WindowsRuntimeLaunchArguments -Management $management -Environment $environment -LogPath $logPath
    $flags = @($launchArguments.flags)
    $perfArgsEnabled = [bool]$launchArguments.perfArgsEnabled
    $argString = $flags -join ' '
    Write-WindowsRuntimeEvent -Event 'start-requested' -Message "Launching PalServer.exe; restMode=$($management.windowsRestCompatibilityMode); REST/RCON settings are INI-controlled; perfArgs=$perfArgsEnabled; engine raw output path=$logPath (best-effort)."

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

    Write-WindowsRuntimeEvent -Event 'start-confirmed' -Message "PalServer.exe launcher PID=$($proc.Id) is running; REST or exact-process/game-port readiness is verified by the switch health check."
    return @{ ok = $true; pid = $proc.Id; method = 'windows'; process = $proc }
}

function Get-WindowsRuntimeProcessTree {
    param([Nullable[int]]$LauncherPid)

    $launcherPath = [System.IO.Path]::GetFullPath($palServerExe)
    $enginePath = [System.IO.Path]::GetFullPath((Join-Path $winServerDir 'Pal\Binaries\Win64\PalServer-Win64-Shipping-Cmd.exe'))
    $candidates = @()
    foreach ($processName in @('PalServer.exe', 'PalServer-Win64-Shipping-Cmd.exe')) {
        $candidates += @(Get-CimInstance -ClassName Win32_Process -Filter "Name='$processName'" -ErrorAction Stop)
    }

    $launchers = @($candidates | Where-Object {
        $_.Name -eq 'PalServer.exe' -and
        [string]::Equals([string]$_.ExecutablePath, $launcherPath, [System.StringComparison]::OrdinalIgnoreCase)
    })
    if ($null -ne $LauncherPid) {
        $scopedLaunchers = @($launchers | Where-Object { [int]$_.ProcessId -eq [int]$LauncherPid })
        if ($scopedLaunchers.Count -gt 0) { $launchers = $scopedLaunchers }
    }

    $launcherPids = @($launchers | ForEach-Object { [int]$_.ProcessId })
    $engines = @($candidates | Where-Object {
        $_.Name -eq 'PalServer-Win64-Shipping-Cmd.exe' -and
        [string]::Equals([string]$_.ExecutablePath, $enginePath, [System.StringComparison]::OrdinalIgnoreCase) -and
        (
            ($launcherPids -contains [int]$_.ParentProcessId) -or
            ($launcherPids.Count -eq 0 -and $null -ne $LauncherPid -and [int]$_.ParentProcessId -eq [int]$LauncherPid) -or
            ($launcherPids.Count -eq 0 -and $null -eq $LauncherPid)
        )
    })

    $targets = @()
    foreach ($launcher in $launchers) {
        $targets += [pscustomobject]@{
            role = 'launcher'
            pid = [int]$launcher.ProcessId
            parentPid = [int]$launcher.ParentProcessId
            expectedPath = $launcherPath
        }
    }
    foreach ($engine in $engines) {
        $targets += [pscustomobject]@{
            role = 'engine'
            pid = [int]$engine.ProcessId
            parentPid = [int]$engine.ParentProcessId
            expectedPath = $enginePath
        }
    }
    return @($targets)
}

function Get-WindowsRuntimeProcessStatus {
    param([Parameter(Mandatory)][object[]]$Targets)

    $remaining = @()
    $verificationFailed = $false
    foreach ($target in @($Targets)) {
        try {
            $process = @(Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$([int]$target.pid)" -ErrorAction Stop) | Select-Object -First 1
        } catch {
            $verificationFailed = $true
            continue
        }
        if (-not $process) { continue }
        if ([string]::IsNullOrWhiteSpace([string]$process.ExecutablePath)) {
            $verificationFailed = $true
            continue
        }
        if ([string]::Equals([string]$process.ExecutablePath, [string]$target.expectedPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            $remaining += $target
        }
        # A reused PID with another executable is not our process and is never
        # acted on. This is intentionally fail-closed for process termination.
    }
    return [pscustomobject]@{
        remaining = @($remaining)
        verificationFailed = $verificationFailed
    }
}

function Stop-WindowsRuntime {
    param([int]$Grace = 120)

    $state = Get-RuntimeState
    $statePid = $null
    if ($state -and $null -ne $state.pid -and [string]$state.pid -match '^\d+$') {
        $statePid = [int]$state.pid
    }

    try {
        $treeArgs = @{}
        if ($null -ne $statePid) { $treeArgs.LauncherPid = $statePid }
        $targets = @(Get-WindowsRuntimeProcessTree @treeArgs)
    } catch {
        Write-WindowsRuntimeEvent -Level 'ERROR' -Event 'stop-failed' -Message "Unable to inspect the Windows runtime process tree: $($_.Exception.Message)"
        return @{ ok = $false; error = 'Unable to verify the Windows runtime process tree.' }
    }

    if ($targets.Count -eq 0) {
        Write-WindowsRuntimeEvent -Event 'stop-noop' -Message 'No exact Windows runtime process tree found; nothing to stop.'
        return @{ ok = $true; detail = 'No exact Windows runtime process tree found; nothing to stop' }
    }

    $launcher = @($targets | Where-Object { $_.role -eq 'launcher' } | Select-Object -First 1)
    $pidValue = if ($launcher.Count -gt 0) { [int]$launcher[0].pid } elseif ($null -ne $statePid) { $statePid } else { $null }
    $targetSummary = (($targets | ForEach-Object { "$($_.role):$($_.pid)" }) -join ',')
    Write-WindowsRuntimeEvent -Event 'stop-requested' -Message "Stopping verified Windows runtime process tree ($targetSummary)."

    # 1. Try REST /shutdown when a verified launcher exists.
    $rest = @{ ok = $false }
    if ($null -ne $pidValue -and $launcher.Count -gt 0) {
        $rest = Invoke-WinRest -Path '/shutdown' -Method POST -Body ([ordered]@{ waittime = 30; message = 'Server shutdown requested by the local console.' }) -TimeoutMs 30000
    }
    if ($rest.ok) {
        $waited = 0
        do {
            $status = Get-WindowsRuntimeProcessStatus -Targets $targets
            if ($status.verificationFailed) {
                Write-WindowsRuntimeEvent -Level 'ERROR' -Event 'stop-failed' -Message 'Could not verify one or more Windows runtime PIDs after REST shutdown.'
                return @{ ok = $false; error = 'Could not verify Windows runtime process identity after REST shutdown.' }
            }
            if ($status.remaining.Count -eq 0) {
                Write-WindowsRuntimeEvent -Event 'stop-confirmed' -Message "Windows runtime stopped through REST; verified process tree=$targetSummary."
                return @{ ok = $true; method = 'rest' }
            }
            if ($waited -ge $Grace) { break }
            Start-Sleep -Seconds 2
            $waited += 2
        } while ($true)
    }

    # 2. Graceful window close, then force-stop only the exact verified PIDs.
    $status = Get-WindowsRuntimeProcessStatus -Targets $targets
    if ($status.verificationFailed) {
        Write-WindowsRuntimeEvent -Level 'ERROR' -Event 'stop-failed' -Message 'Could not verify one or more Windows runtime PIDs before process fallback.'
        return @{ ok = $false; error = 'Could not verify Windows runtime process identity before fallback.' }
    }
    foreach ($target in @($status.remaining | Where-Object { $_.role -eq 'launcher' })) {
        try {
            $p = Get-Process -Id ([int]$target.pid) -ErrorAction Stop
            $p.CloseMainWindow() | Out-Null
        } catch {
            # The process may have exited between the identity check and the
            # window call; final CIM verification below is authoritative.
        }
    }

    $waited = 0
    do {
        Start-Sleep -Seconds 1
        $status = Get-WindowsRuntimeProcessStatus -Targets $targets
        if ($status.verificationFailed) {
            Write-WindowsRuntimeEvent -Level 'ERROR' -Event 'stop-failed' -Message 'Could not verify one or more Windows runtime PIDs during process fallback.'
            return @{ ok = $false; error = 'Could not verify Windows runtime process identity during fallback.' }
        }
        if ($status.remaining.Count -eq 0) {
            Write-WindowsRuntimeEvent -Level 'WARN' -Event 'stop-fallback' -Message "Windows runtime stopped through graceful process-tree fallback; verified process tree=$targetSummary."
            return @{ ok = $true; method = 'process-tree-graceful' }
        }
        $waited++
    } while ($waited -lt 30)

    foreach ($target in @($status.remaining | Sort-Object @{ Expression = { if ($_.role -eq 'launcher') { 0 } else { 1 } } })) {
        $singleStatus = Get-WindowsRuntimeProcessStatus -Targets @($target)
        if ($singleStatus.verificationFailed) {
            Write-WindowsRuntimeEvent -Level 'ERROR' -Event 'stop-failed' -Message "Could not verify PID=$($target.pid) before force stop."
            return @{ ok = $false; error = "Could not verify Windows runtime PID=$($target.pid) before force stop." }
        }
        if ($singleStatus.remaining.Count -eq 0) { continue }
        try {
            Stop-Process -Id ([int]$target.pid) -Force -ErrorAction Stop
        } catch {
            $afterError = Get-WindowsRuntimeProcessStatus -Targets @($target)
            if ($afterError.verificationFailed -or $afterError.remaining.Count -gt 0) {
                Write-WindowsRuntimeEvent -Level 'ERROR' -Event 'stop-failed' -Message "Failed to stop verified $($target.role) PID=$($target.pid)."
                return @{ ok = $false; error = "Failed to stop Windows runtime PID=$($target.pid)." }
            }
        }
    }

    Start-Sleep -Seconds 2
    $finalStatus = Get-WindowsRuntimeProcessStatus -Targets $targets
    if ($finalStatus.verificationFailed -or $finalStatus.remaining.Count -gt 0) {
        $residual = ($finalStatus.remaining | ForEach-Object { "$($_.role):$($_.pid)" }) -join ','
        Write-WindowsRuntimeEvent -Level 'ERROR' -Event 'stop-failed' -Message "Windows runtime process tree still exists after fallback: $residual"
        Write-Incident -Level 'ERROR' -Type 'runtime-stop-incomplete' -Message "Verified Windows runtime process tree did not fully stop: $residual"
        return @{ ok = $false; error = "Windows runtime process tree did not fully stop: $residual"; residual = $finalStatus.remaining }
    }

    Write-WindowsRuntimeEvent -Level 'WARN' -Event 'stop-fallback' -Message "Windows runtime stopped through exact process-tree fallback; verified process tree=$targetSummary."
    return @{ ok = $true; method = 'process-tree-force' }
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

    $management = Get-ManagementEndpointConfig -ProjectDirectory $projectDir

    # Check REST — Windows Palworld server does not expose /health;
    # use /info (returns 200 with basic auth when ready, 401/404 otherwise).
    $rest = Invoke-WinRest -Path '/info' -Method GET -TimeoutMs 5000
    $targets = @()
    $processReady = $false
    $processDetail = 'exact PalServer process tree was not verified'
    try {
        $treeArgs = @{}
        if ($null -ne $pidValue) { $treeArgs.LauncherPid = [int]$pidValue }
        $targets = @(Get-WindowsRuntimeProcessTree @treeArgs)
        $launcherCount = @($targets | Where-Object { $_.role -eq 'launcher' }).Count
        $enginePids = @($targets | Where-Object { $_.role -eq 'engine' } | ForEach-Object { [int]$_.pid })
        $gameListeners = @()
        if ($enginePids.Count -gt 0) {
            $gameListeners = @(Get-NetUDPEndpoint -LocalPort $management.gamePort -ErrorAction SilentlyContinue |
                Where-Object { $enginePids -contains [int]$_.OwningProcess })
        }
        $processReady = ($launcherCount -gt 0 -and $enginePids.Count -gt 0 -and $gameListeners.Count -gt 0)
        $processDetail = "exact process tree=$($targets.Count), engine=$($enginePids.Count), gameUdpOwner=$($gameListeners.Count)"
    } catch {
        $processDetail = "exact process/game-port probe failed: $($_.Exception.Message)"
    }
    $runtimePids = @($targets | ForEach-Object { [int]$_.pid })
    $rconListeners = @(Get-NetTCPConnection -LocalPort $management.rconPort -State Listen -ErrorAction SilentlyContinue |
        Where-Object { $runtimePids -contains [int]$_.OwningProcess })
    $rconFallback = if ($rest.ok) {
        'none'
    } elseif ($management.legacyRconEnabled -and $rconListeners.Count -gt 0) {
        'rcon'
    } elseif ($management.legacyRconEnabled) {
        'rcon-unavailable'
    } else {
        'none'
    }
    $saveIntegrity = Test-SaveGamesIntegrity
    $restDetail = if ($rest.ok) {
        "REST /info responded at $($management.restBaseUrl)."
    } else {
        "REST /info failed at $($management.restBaseUrl): $($rest.error)"
    }
    $readiness = if ($rest.ok) {
        'REST'
    } elseif ($processReady) {
        'exact-process-and-game-udp'
    } else {
        'none'
    }
    $result = [ordered]@{
        status      = if ($rest.ok -or $processReady) { 'healthy' } else { 'degraded' }
        detail      = if ($rest.ok) { $restDetail } elseif ($processReady) {
            "REST unavailable; local game runtime is ready via $processDetail. Management fallback=$rconFallback."
        } else {
            "$restDetail; $processDetail."
        }
        readiness   = $readiness
        management  = [ordered]@{
            restEnabled = [bool]$management.restEnabled
            restPort = $management.restPort
            restAvailable = [bool]$rest.ok
            legacyRconEnabled = [bool]$management.legacyRconEnabled
            rconPort = $management.rconPort
            rconListening = ($rconListeners.Count -gt 0)
            fallback = $rconFallback
            managementAvailable = ($rest.ok -or $rconFallback -eq 'rcon')
        }
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
        $management = Get-ManagementEndpointConfig -ProjectDirectory $projectDir
        if (-not $management.legacyRconEnabled) { return @{ ok = $false; code = 'legacy-rcon-disabled'; error = 'Legacy RCON is disabled.' } }
        $connect = $client.BeginConnect($management.rconBindAddress, $management.rconPort, $null, $null)
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

function Get-WindowsRconFallbackCommand {
    <# Maps the small, validated management surface to Palworld RCON commands. #>
    param(
        [Parameter(Mandatory)][ValidateSet('announce','kick','ban','unban')][string]$Operation,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Payload
    )
    $getValue = {
        param([string]$Key, [bool]$Required)
        if (-not $Payload.Contains($Key)) {
            if ($Required) { throw "Management payload is missing $Key." }
            return ''
        }
        $value = [string]$Payload[$Key]
        if ($Required -and [string]::IsNullOrWhiteSpace($value)) { throw "Management payload $Key is required." }
        if ($value -match "[`r`n`0]") { throw "Management payload $Key contains unsupported control characters." }
        return $value.Trim()
    }

    switch ($Operation) {
        'announce' {
            $message = & $getValue 'message' $true
            if ($message.Length -gt 400) { throw 'Announcement message must be at most 400 characters.' }
            return "Broadcast $message"
        }
        'kick' {
            $userid = & $getValue 'userid' $true
            if ($userid -notmatch '^[A-Za-z0-9_.:-]+$') { throw 'Player ID contains unsupported characters.' }
            return "KickPlayer $userid"
        }
        'ban' {
            $userid = & $getValue 'userid' $true
            if ($userid -notmatch '^[A-Za-z0-9_.:-]+$') { throw 'Player ID contains unsupported characters.' }
            return "BanPlayer $userid"
        }
        'unban' {
            $userid = & $getValue 'userid' $true
            if ($userid -notmatch '^[A-Za-z0-9_.:-]+$') { throw 'Player ID contains unsupported characters.' }
            return "UnBanPlayer $userid"
        }
    }
}

function Invoke-WindowsRuntimeSave {
    param([int]$Timeout = 30)
    $r = Invoke-WinRest -Path '/save' -Method POST -TimeoutMs ($Timeout * 1000)
    if ($r.ok) {
        Start-Sleep -Seconds 2
        return @{ ok = $true; method = 'rest' }
    }
    $management = Get-ManagementEndpointConfig -ProjectDirectory $projectDir
    if (-not $management.legacyRconEnabled) {
        return @{ ok = $false; method = 'rest'; error = "REST save failed: $($r.error); legacy RCON fallback is disabled."; code = 'management-unavailable' }
    }
    $fallback = Invoke-WindowsRcon -Command 'Save' -Timeout $Timeout
    if ($fallback.ok) {
        Start-Sleep -Seconds 2
        return @{ ok = $true; method = 'rcon'; fallback = $true; restError = $r.error }
    }
    return @{ ok = $false; method = 'rcon'; fallback = $true; error = "REST save failed: $($r.error); RCON fallback failed: $($fallback.error)"; code = 'management-unavailable' }
}

function Invoke-WindowsRuntimeOperation {
    param(
        [Parameter(Mandatory)][ValidateSet('announce','kick','ban','unban')][string]$Operation,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Payload,
        [int]$Timeout = 30
    )
    $r = Invoke-ManagementOperation -ProjectDirectory $projectDir -Operation $Operation -Payload $Payload
    if ($r.ok) { return @{ ok = $true; method = 'rest'; operation = $Operation; content = $r.content } }
    $management = Get-ManagementEndpointConfig -ProjectDirectory $projectDir
    if (-not $management.legacyRconEnabled) {
        return @{ ok = $false; method = 'rest'; operation = $Operation; code = 'management-unavailable'; error = "REST operation failed: $($r.error); legacy RCON fallback is disabled." }
    }
    try {
        $command = Get-WindowsRconFallbackCommand -Operation $Operation -Payload $Payload
    } catch {
        return @{ ok = $false; method = 'rest'; operation = $Operation; code = 'invalid-management-request'; error = $_.Exception.Message }
    }
    $fallback = Invoke-WindowsRcon -Command $command -Timeout $Timeout
    if ($fallback.ok) {
        return @{ ok = $true; method = 'rcon'; fallback = $true; operation = $Operation; content = $fallback.output; restError = $r.error }
    }
    return @{ ok = $false; method = 'rcon'; fallback = $true; operation = $Operation; code = 'management-unavailable'; error = "REST operation failed: $($r.error); RCON fallback failed: $($fallback.error)" }
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
