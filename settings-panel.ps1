# Palworld Server Console - Backend
# Prefers http://localhost:8213/ and falls back locally if that port is occupied.
# API: /api/dashboard, /api/settings, /api/env (POST), /api/restart (POST),
#      /api/stop (POST), /api/save (POST), /api/logs, /api/logs/insights,
#      /api/incidents, /api/tunnel/check (POST), /api/rcon (POST),
#      /api/backup (POST), /api/backups, /api/backups/download,
#      /api/player-times, /api/mods,
#      /api/mods/check (POST), /api/mods/sync (POST),
#      /api/runtime (GET), /api/runtime/switch (POST), /api/runtime/snapshot (POST),
#      /api/runtime/restore (POST), /api/runtime/task (GET), /api/snapshots (GET)

$ErrorActionPreference = "Stop"
$preferredPort = 8213
# 8214 is sometimes reserved by HTTP.sys on Windows. Keep the historical
# fallbacks, then try a small local-only range so the console can still start.
$fallbackPorts = @(8214, 18213) + @(18214..18233)
$projectDir = $PSScriptRoot
$envFile = "$projectDir\.env"
$composeFile = "$projectDir\docker-compose.yml"
$htmlFile = "$projectDir\web\index.html"
$backupDir = "$projectDir\data\backups"
$pidFile = "$projectDir\.settings-panel.pid"
$portFile = "$projectDir\.settings-panel.port"
$modManagerScript = "$projectDir\scripts\mod-manager.ps1"
$settingsCatalogScript = "$projectDir\scripts\settings-catalog.ps1"
$composeServiceName = "palworld-server"
$containerName = "palworld-server"
$diagnosticsDir = "$projectDir\data\diagnostics"
$incidentFile = "$diagnosticsDir\incidents.jsonl"
$logArchiveDir = "$projectDir\data\log-archive"
$panelLogDir = "$projectDir\data\log-sources\panel"
$logCollectorScript = "$projectDir\scripts\daily-log-collector.ps1"
$logCollectorPidFile = "$projectDir\.daily-log-collector.pid"
$playerTimesFile = "$projectDir\data\player-session-times.json"
$maxRequestBytes = 64KB
$processTimeoutMs = 120000
$playerCache = @{ value = 0; checkedAt = [datetime]::MinValue }
$playerTimesCache = @{ value = $null; checkedAt = [datetime]::MinValue }
$dashboardCache = @{ value = $null; checkedAt = [datetime]::MinValue }
$updateStatusCache = @{ value = $null; checkedAt = [datetime]::MinValue }
$tunnelCache = @{ value = $null; checkedAt = [datetime]::MinValue }
$logInsightCache = @{ value = $null; checkedAt = [datetime]::MinValue; lines = 0 }
$incidentFingerprints = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)

# Runtime switch task registry (in-memory; persisted to data/diagnostics/tasks/<id>.json)
$runtimeTasks = @{}

if (-not (Test-Path $envFile)) { Write-Host "[FATAL] .env not found"; exit 1 }
if (-not (Test-Path $htmlFile)) { Write-Host "[FATAL] index.html not found"; exit 1 }
if (-not (Test-Path $settingsCatalogScript)) { Write-Host "[FATAL] settings catalog not found"; exit 1 }

Add-Type -AssemblyName System.Web.Extensions
$jsonSerializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$jsonSerializer.MaxJsonLength = 1MB

# The catalog is checked in and tied to the pinned image. It is the single
# source of truth for both backend validation and frontend rendering.
. $settingsCatalogScript
$editableFields = New-SettingsCatalog

# Load runtime providers (M8). These add Get-RuntimeState, Start/Stop-DockerRuntime,
# Start/Stop-WindowsRuntime, Assert-SaveGamesJunction, Test-SaveGamesJunction, etc.
. (Join-Path $projectDir 'scripts\runtime-common.ps1')
. (Join-Path $projectDir 'scripts\management-api.ps1')
. (Join-Path $projectDir 'scripts\networking.ps1')
. (Join-Path $projectDir 'scripts\docker-runtime.ps1')
. (Join-Path $projectDir 'scripts\win-runtime.ps1')
$containerName = Get-ManagementContainerName -ProjectDirectory $projectDir

# ===== Helpers =====

function Write-PanelEvent([string]$level, [string]$message) {
    $stamp = Get-Date
    $safeMessage = ($message -replace "[\r\n]+", " ").Trim()
    if (-not (Test-Path -LiteralPath $panelLogDir -PathType Container)) {
        New-Item -ItemType Directory -Path $panelLogDir -Force | Out-Null
    }
    $line = "[$($stamp.ToString('yyyy-MM-dd HH:mm:ss.fff zzz'))][$($level.ToUpperInvariant())][WEB] $safeMessage"
    $path = Join-Path $panelLogDir "$($stamp.ToString('yyyy-MM-dd')).log"
    [System.IO.File]::AppendAllText(
        $path,
        $line + [Environment]::NewLine,
        (New-Object System.Text.UTF8Encoding($false))
    )
    Write-Host "[$($level.ToUpperInvariant())] $safeMessage"
}

function Get-EnvVars($path) {
    $vars = @{}
    [System.IO.File]::ReadAllLines($path) | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq "" -or $line.StartsWith("#")) { return }
        $idx = $line.IndexOf("=")
        if ($idx -le 0) { return }
        $key = $line.Substring(0, $idx).Trim()
        $val = $line.Substring($idx + 1).Trim()
        if ($val.Length -ge 2) {
            if ($val.StartsWith('"') -and $val.EndsWith('"')) {
                $val = $val.Substring(1, $val.Length - 2)
            } elseif ($val.StartsWith("'") -and $val.EndsWith("'")) {
                $val = $val.Substring(1, $val.Length - 2).Replace("\'", "'")
            }
        }
        $vars[$key] = $val
    }
    return $vars
}

function Get-EditableEnvVars() {
    $allVars = Get-EnvVars $envFile
    $result = [ordered]@{}
    foreach ($key in $editableFields.Keys) {
        $schema = $editableFields[$key]
        if ([bool]$schema.secret) {
            # Secrets are write-only. The UI gets a separate configured flag.
            $result[$key] = ""
        } elseif ($allVars.ContainsKey($key)) {
            $result[$key] = $allVars[$key]
        } else {
            $result[$key] = [string]$schema.default
        }
    }
    return $result
}

function Get-SettingsPayload() {
    $allVars = Get-EnvVars $envFile
    $explicit = @()
    $configuredSecrets = @()
    foreach ($key in $editableFields.Keys) {
        if ($allVars.ContainsKey($key)) {
            $explicit += $key
            if ([bool]$editableFields[$key].secret -and [string]$allVars[$key]) {
                $configuredSecrets += $key
            }
        }
    }
    $schema = @()
    foreach ($key in $editableFields.Keys) { $schema += $editableFields[$key] }
    return [ordered]@{
        ok = $true
        supportedCount = $editableFields.Count
        schema = $schema
        values = Get-EditableEnvVars
        explicit = $explicit
        configuredSecrets = $configuredSecrets
        exclusions = @(
            [ordered]@{
                scope = "ARM64/Box64"
                reason = "Not applicable to the current amd64 host."
                keys = @(
                    "ARM64_DEVICE", "BOX64_DYNAREC_BIGBLOCK", "BOX64_DYNAREC_FASTNAN",
                    "BOX64_DYNAREC_FASTROUND", "BOX64_DYNAREC_SAFEFLAGS",
                    "BOX64_DYNAREC_STRONGMEM", "BOX64_DYNAREC_X87DOUBLE"
                )
            }
        )
    }
}

function Format-EnvValue([string]$value) {
    if ($null -eq $value) { return "" }
    if ($value -match "[`r`n`0]") { throw "Values cannot contain control characters." }
    if ($value -match "[\s#`"']" -or $value.Contains('$')) {
        return "'" + $value.Replace("'", "\'") + "'"
    }
    return $value
}

function Convert-ValidatedUpdates($updates) {
    if (-not ($updates -is [System.Collections.IDictionary])) {
        throw "JSON body must be an object."
    }
    if ($updates.Count -lt 1 -or $updates.Count -gt $editableFields.Count) {
        throw "Update must contain between 1 and $($editableFields.Count) settings."
    }

    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $numberStyle = [System.Globalization.NumberStyles]::Float
    $integerStyle = [System.Globalization.NumberStyles]::Integer
    $validated = [ordered]@{}
    foreach ($keyObject in $updates.Keys) {
        $key = [string]$keyObject
        if (-not $editableFields.Contains($key)) { throw "Setting is not editable: $key" }
        $schema = $editableFields[$key]
        $raw = [string]$updates[$keyObject]
        if ($raw -match "[`r`n`0]") { throw "$key contains a control character." }

        switch ([string]$schema.type) {
            { $_ -in @("string", "secret") } {
                if ($raw.Length -lt $schema.MinLength -or $raw.Length -gt $schema.MaxLength) {
                    throw "$key length must be $($schema.MinLength)-$($schema.MaxLength)."
                }
                $validated[$key] = $raw
            }
            "integer" {
                $parsed = 0
                if (-not [int]::TryParse($raw, $integerStyle, $culture, [ref]$parsed)) {
                    throw "$key must be an integer."
                }
                if (($schema.Contains("min") -and $parsed -lt [double]$schema.min) -or
                    ($schema.Contains("max") -and $parsed -gt [double]$schema.max)) {
                    throw "$key is outside its supported range."
                }
                $validated[$key] = $parsed.ToString($culture)
            }
            "number" {
                $parsed = 0.0
                if (-not [double]::TryParse($raw, $numberStyle, $culture, [ref]$parsed) -or
                    [double]::IsNaN($parsed) -or [double]::IsInfinity($parsed)) {
                    throw "$key must be a finite number."
                }
                if (($schema.Contains("min") -and $parsed -lt [double]$schema.min) -or
                    ($schema.Contains("max") -and $parsed -gt [double]$schema.max)) {
                    throw "$key is outside its supported range."
                }
                $validated[$key] = $parsed.ToString("G", $culture)
            }
            "boolean" {
                if ($raw -notmatch "^(?i:true|false)$") { throw "$key must be true or false." }
                $validated[$key] = $raw.ToLowerInvariant()
            }
            "choice" {
                if ($raw -notin @($schema.options)) { throw "$key has an unsupported value." }
                $validated[$key] = $raw
            }
            default { throw "Unknown schema type for $key." }
        }

        if ($key -match "(?:^|_)CRON_EXPRESSION$" -and
            ($raw.Trim() -split "\s+").Count -ne 5) {
            throw "$key must be a five-field cron expression."
        }
        if ($key -eq "CROSSPLAY_PLATFORMS" -and
            $raw -notmatch "^\((Steam|Xbox|PS5|Mac)(,(Steam|Xbox|PS5|Mac))*\)$") {
            throw "CROSSPLAY_PLATFORMS must look like (Steam,Xbox,PS5,Mac)."
        }
        if ($key -eq "PUBLIC_IP" -and $raw) {
            $parsedAddress = $null
            if (-not [System.Net.IPAddress]::TryParse($raw, [ref]$parsedAddress)) {
                throw "PUBLIC_IP must be blank or a valid IP address."
            }
        }
        if ($key -match "(?:URL|WEBHOOK_URL)$" -and $raw) {
            $parsedUri = $null
            if (-not [System.Uri]::TryCreate($raw, [System.UriKind]::Absolute, [ref]$parsedUri) -or
                $parsedUri.Scheme -notin @("http", "https")) {
                throw "$key must be blank or an absolute HTTP(S) URL."
            }
        }
    }

    # Validate relationships using the effective post-update configuration.
    $current = Get-EnvVars $envFile
    $effective = @{}
    foreach ($key in $editableFields.Keys) {
        if ($current.ContainsKey($key)) { $effective[$key] = [string]$current[$key] }
        else { $effective[$key] = [string]$editableFields[$key].default }
    }
    foreach ($key in $validated.Keys) { $effective[$key] = [string]$validated[$key] }

    if ($effective["REST_API_PORT"] -eq $effective["RCON_PORT"]) {
        throw "REST_API_PORT and RCON_PORT must be different TCP ports."
    }
    $network = Test-NetworkConfiguration -Environment $effective
    if (-not $network.ok) { throw ($network.errors -join ' ') }
    if ([double]$effective["SMOOTH_FRAME_RATE_LOWER_LIMIT"] -ge
        [double]$effective["SMOOTH_FRAME_RATE_UPPER_LIMIT"]) {
        throw "SMOOTH_FRAME_RATE_LOWER_LIMIT must be lower than SMOOTH_FRAME_RATE_UPPER_LIMIT."
    }
    if ([int]$effective["COOP_PLAYER_MAX_NUM"] -gt [int]$effective["PLAYERS"]) {
        throw "COOP_PLAYER_MAX_NUM cannot exceed PLAYERS."
    }
    if ([double]$effective["VOICE_CHAT_MAX_VOLUME_DISTANCE"] -gt
        [double]$effective["VOICE_CHAT_ZERO_VOLUME_DISTANCE"]) {
        throw "VOICE_CHAT_MAX_VOLUME_DISTANCE cannot exceed VOICE_CHAT_ZERO_VOLUME_DISTANCE."
    }
    if ($effective["IS_PVP"] -match "^(?i:true)$" -and
        ($effective["ENABLE_PLAYER_TO_PLAYER_DAMAGE"] -notmatch "^(?i:true)$" -or
         $effective["ENABLE_DEFENSE_OTHER_GUILD_PLAYER"] -notmatch "^(?i:true)$")) {
        throw "PvP requires IS_PVP, ENABLE_PLAYER_TO_PLAYER_DAMAGE, and ENABLE_DEFENSE_OTHER_GUILD_PLAYER to all be true."
    }
    return $validated
}

function Update-EnvFile($path, $updates) {
    $lines = [System.IO.File]::ReadAllLines($path)
    $result = @()
    $seen = @{}
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -eq "" -or $trimmed.StartsWith("#")) {
            $result += $line; continue
        }
        $idx = $line.IndexOf("=")
        if ($idx -le 0) { $result += $line; continue }
        $key = $line.Substring(0, $idx).Trim()
        if ($updates.Contains($key)) {
            $val = Format-EnvValue ([string]$updates[$key])
            $result += "$key=$val"
            $seen[$key] = $true
        } else {
            $result += $line
        }
    }
    foreach ($key in $updates.Keys) {
        if (-not $seen.ContainsKey($key)) {
            $val = Format-EnvValue ([string]$updates[$key])
            $result += "$key=$val"
        }
    }

    $fullPath = [System.IO.Path]::GetFullPath($path)
    $tempPath = "$fullPath.tmp.$PID"
    $rollbackPath = "$fullPath.rollback.$PID"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    try {
        [System.IO.File]::WriteAllLines($tempPath, [string[]]$result, $utf8NoBom)
        [System.IO.File]::Replace($tempPath, $fullPath, $rollbackPath)
    } finally {
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force }
        if (Test-Path -LiteralPath $rollbackPath) { Remove-Item -LiteralPath $rollbackPath -Force }
    }
}

# Run docker via System.Diagnostics.Process (avoids cmd.exe pipe char issues
# and PowerShell CLIXML stderr serialization problems)
function Invoke-Process($fileName, $argString, $timeoutMs = $processTimeoutMs) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $fileName
    $psi.Arguments = $argString
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
    if (-not $proc.WaitForExit($timeoutMs)) {
        try { $proc.Kill() } catch { }
        throw "Process timed out after $([math]::Round($timeoutMs / 1000)) seconds: $fileName"
    }
    $proc.WaitForExit()
    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    return @{
        ExitCode = $proc.ExitCode
        Stdout = $stdout
        Stderr = $stderr
    }
}

function Invoke-Docker($argString, $timeoutMs = $processTimeoutMs) {
    return Invoke-Process "docker.exe" $argString $timeoutMs
}

function Invoke-Compose($argString, $timeoutMs = $processTimeoutMs) {
    return Invoke-Process "docker.exe" "compose -f `"$composeFile`" $argString" $timeoutMs
}

function Find-JsonSerializationFailure($value, [string]$path = "$") {
    try {
        [void]$jsonSerializer.Serialize($value)
        return ""
    } catch { }
    if ($value -is [System.Collections.IDictionary]) {
        $partial = [ordered]@{}
        foreach ($keyObject in $value.Keys) {
            $childPath = "$path.$([string]$keyObject)"
            $failure = Find-JsonSerializationFailure $value[$keyObject] $childPath
            if ($failure) { return $failure }
            $partial[[string]$keyObject] = $value[$keyObject]
            try {
                [void]$jsonSerializer.Serialize($partial)
            } catch {
                return "$path combination fails after $([string]$keyObject)"
            }
        }
    } elseif ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
        $index = 0
        foreach ($item in $value) {
            $failure = Find-JsonSerializationFailure $item "$path[$index]"
            if ($failure) { return $failure }
            $index++
        }
    }
    return "$path ($($value.GetType().FullName))"
}

function Find-JsonDuplicateReference($value, [string]$path, $seen) {
    if ($null -eq $value -or $value -is [string] -or $value.GetType().IsValueType) { return "" }
    foreach ($entry in $seen) {
        if ([object]::ReferenceEquals($entry.value, $value)) {
            return "$path duplicates $($entry.path) ($($value.GetType().FullName))"
        }
    }
    [void]$seen.Add([pscustomobject]@{ value = $value; path = $path })
    if ($value -is [System.Collections.IDictionary]) {
        foreach ($keyObject in $value.Keys) {
            $duplicate = Find-JsonDuplicateReference $value[$keyObject] "$path.$([string]$keyObject)" $seen
            if ($duplicate) { return $duplicate }
        }
    } elseif ($value -is [System.Collections.IEnumerable]) {
        $index = 0
        foreach ($item in $value) {
            $duplicate = Find-JsonDuplicateReference $item "$path[$index]" $seen
            if ($duplicate) { return $duplicate }
            $index++
        }
    }
    return ""
}

function Encode-Json($obj) {
    try {
        return $jsonSerializer.Serialize($obj)
    } catch {
        $primaryError = $_.Exception.Message
        try {
            # JavaScriptSerializer can mis-handle PowerShell's adapted player
            # dictionaries when they are nested with other REST objects.
            return ConvertTo-Json -InputObject $obj -Depth 20 -Compress
        } catch {
            $failurePath = Find-JsonSerializationFailure $obj
            $duplicate = Find-JsonDuplicateReference $obj "$" (New-Object System.Collections.ArrayList)
            throw "$primaryError Failure path: $failurePath Duplicate: $duplicate"
        }
    }
}

function Parse-Json($json) {
    return $jsonSerializer.DeserializeObject($json)
}

function Read-JsonBody($req) {
    if ($req.ContentLength64 -gt $maxRequestBytes) { throw "Request body is too large." }
    if (-not $req.ContentType -or -not $req.ContentType.StartsWith("application/json")) {
        throw "Content-Type must be application/json."
    }
    $reader = New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)
    try { $body = $reader.ReadToEnd() } finally { $reader.Close() }
    if ([System.Text.Encoding]::UTF8.GetByteCount($body) -gt $maxRequestBytes) {
        throw "Request body is too large."
    }
    if (-not $body) { throw "Request body is empty." }
    return Parse-Json $body
}

function Test-RequestOrigin($req) {
    $hostName = $req.Url.Host.ToLowerInvariant()
    if ($hostName -notin @("localhost", "127.0.0.1", "::1")) { return $false }
    $origin = $req.Headers["Origin"]
    if (-not $origin) { return $true }
    return $origin -in @(
        "http://localhost:$port",
        "http://127.0.0.1:$port",
        "http://[::1]:$port"
    )
}

function Test-LoopbackRequest($req) {
    if ($req.Url.Host.ToLowerInvariant() -notin @("localhost", "127.0.0.1", "::1")) { return $false }
    $remote = $req.RemoteEndPoint
    if ($null -eq $remote) { return $false }
    return [System.Net.IPAddress]::IsLoopback($remote.Address)
}

function Send-Json($res, $obj) {
    $json = Encode-Json $obj
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $res.ContentType = "application/json; charset=utf-8"
    $res.Headers["Cache-Control"] = "no-store"
    $res.ContentLength64 = $bytes.Length
    $res.OutputStream.Write($bytes, 0, $bytes.Length)
}

function Send-Text($res, $text, $contentType = "text/plain; charset=utf-8") {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    $res.ContentType = $contentType
    $res.ContentLength64 = $bytes.Length
    $res.OutputStream.Write($bytes, 0, $bytes.Length)
}

function Send-FileDownload($res, [string]$path, [string]$downloadName, [string]$contentType = "text/plain; charset=utf-8") {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $res.ContentType = $contentType
    $res.Headers["Cache-Control"] = "no-store"
    $res.Headers["Content-Disposition"] = "attachment; filename=`"$downloadName`""
    $res.ContentLength64 = $bytes.Length
    $res.OutputStream.Write($bytes, 0, $bytes.Length)
}

function Set-SecurityHeaders($res) {
    $res.Headers["X-Content-Type-Options"] = "nosniff"
    $res.Headers["X-Frame-Options"] = "DENY"
    $res.Headers["Referrer-Policy"] = "no-referrer"
    $res.Headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
}

# ===== API handlers =====

function Get-ActiveRuntime() {
    <# Returns the active runtime string from runtime.state ('docker','windows','none','unknown'). #>
    $state = Get-RuntimeState
    return [string]$state.active
}

function Get-RuntimeStateInfo() {
    <# Returns the full runtime.state plus junction and iniCompile status for the dashboard. #>
    $state = Get-RuntimeState
    $info = [ordered]@{
        active          = [string]$state.active
        switching       = [bool]$state.switching
        pid             = $state.pid
        startedAt       = $state.startedAt
        version         = $state.version
        lastSwitchAt    = $state.lastSwitchAt
        lastSwitchFrom  = $state.lastSwitchFrom
        lastSwitchTo    = $state.lastSwitchTo
    }

    # INI compile status (last entry in ini-compile.log)
    $iniCompile = [ordered]@{ lastRun = $null; status = 'unknown'; driftDetected = $false }
    $compileLog = Join-Path $diagnosticsDir 'ini-compile.log'
    if (Test-Path -LiteralPath $compileLog -PathType Leaf) {
        try {
            $lastLine = (Get-Content -LiteralPath $compileLog -Tail 1 -Encoding UTF8) -as [string]
            if ($lastLine) {
                $entry = Parse-Json $lastLine
                if ($entry -is [System.Collections.IDictionary]) {
                    if ($entry.ContainsKey('ts')) { $iniCompile.lastRun = $entry['ts'] }
                    if ($entry.ContainsKey('validation')) { $iniCompile.status = [string]$entry['validation'] }
                    if ($entry.ContainsKey('errors') -and @($entry['errors']).Count -gt 0) {
                        $iniCompile.status = 'errors'
                        # drift is detected when .env mtime > INI mtime
                        foreach ($err in @($entry['errors'])) {
                            if ([string]$err -match 'Drift') { $iniCompile.driftDetected = $true }
                        }
                    }
                }
            }
        } catch { }
    }

    # Junction status (always check; meaningful for windows)
    $junction = $null
    try {
        $j = Test-SaveGamesJunction
        $junction = [ordered]@{
            exists   = [bool]$j.exists
            ok       = [bool]$j.ok
            linkType = [string]$j.linkType
            target   = [string]$j.target
            resolved = [string]$j.resolved
            error    = [string]$j.error
        }
    } catch {
        $junction = [ordered]@{ exists = $false; ok = $false; error = $_.Exception.Message }
    }

    # Snapshot summary
    $snapshots = Get-SnapshotSummary

    return [ordered]@{
        ok         = $true
        runtime    = $info
        iniCompile = $iniCompile
        junction   = $junction
        snapshots  = $snapshots
    }
}

function Get-SnapshotSummary() {
    $snapshotDir = Join-Path $projectDir 'data\switch-snapshots'
    $manifestPath = Join-Path $snapshotDir 'manifest.json'
    $result = [ordered]@{
        total       = 0
        totalBytes  = 0L
        lastFull    = $null
        lastLight   = $null
        fullCount   = 0
        lightCount  = 0
    }
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return $result }
    try {
        $m = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $snaps = @($m.snapshots)
        $result.total = $snaps.Count
        $totalBytes = 0L
        foreach ($s in $snaps) {
            $totalBytes += [long]$s.sizeBytes
            if ($s.type -eq 'Full') {
                $result.fullCount++
                if (-not $result.lastFull -or ([datetime]$s.createdAt) -gt ([datetime]$result.lastFull)) {
                    $result.lastFull = $s.createdAt
                }
            } elseif ($s.type -eq 'Light') {
                $result.lightCount++
                if (-not $result.lastLight -or ([datetime]$s.createdAt) -gt ([datetime]$result.lastLight)) {
                    $result.lastLight = $s.createdAt
                }
            }
        }
        $result.totalBytes = $totalBytes
    } catch { }
    return $result
}

function Get-SnapshotList() {
    $snapshotDir = Join-Path $projectDir 'data\switch-snapshots'
    $manifestPath = Join-Path $snapshotDir 'manifest.json'
    $result = [ordered]@{ ok = $true; snapshots = @(); total = 0; totalBytes = 0L }
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return $result }
    try {
        $m = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $snaps = @($m.snapshots)
        # Newest first
        $snaps = $snaps | Sort-Object createdAt -Descending
        $result.snapshots = $snaps
        $result.total = $snaps.Count
        $totalBytes = 0L
        foreach ($s in $snaps) { $totalBytes += [long]$s.sizeBytes }
        $result.totalBytes = $totalBytes
    } catch {
        $result.ok = $false
        $result.error = $_.Exception.Message
    }
    return $result
}

function Get-RuntimeLogs([int]$lines = 300) {
    $runtime = Get-ActiveRuntime
    if ($runtime -eq 'windows') {
        $r = Get-WindowsRuntimeLogs -Lines $lines
        if ($r.ok) { return @{ ok = $true; logs = ($r.lines -join "`n") } }
        return @{ ok = $false; error = $r.error }
    }
    # Docker (default path)
    return Get-Logs $lines
}

function Invoke-RuntimeSaveAction() {
    $runtime = Get-ActiveRuntime
    if ($runtime -eq 'windows') {
        $r = Invoke-WindowsRuntimeSave -Timeout 30
        return @{ ok = [bool]$r.ok; method = $r.method; fallback = [bool]$r.fallback; restError = $r.restError; code = $r.code; error = $r.error }
    }
    if ($runtime -eq 'docker') { return Invoke-DockerRuntimeSave -Timeout 30 }
    return @{ ok = $false; error = "No active runtime" }
}

function Invoke-RuntimeManagementOperation {
    param(
        [Parameter(Mandatory)][ValidateSet('announce','kick','ban','unban','shutdown')][string]$Operation,
        [System.Collections.IDictionary]$Payload
    )
    $runtime = Get-ActiveRuntime
    if ($runtime -notin @('docker','windows')) { return @{ ok = $false; code = 'no-active-runtime'; error = 'No active runtime.' } }
    if ($runtime -eq 'windows' -and $Operation -ne 'shutdown') {
        $result = Invoke-WindowsRuntimeOperation -Operation $Operation -Payload $Payload
        $result.runtime = $runtime
        return $result
    }
    $result = Invoke-ManagementOperation -ProjectDirectory $projectDir -Operation $Operation -Payload $Payload
    if ($result.ok) {
        return @{ ok = $true; method = 'rest'; runtime = $runtime; operation = $Operation; content = $result.content }
    }
    return @{ ok = $false; method = 'rest'; runtime = $runtime; operation = $Operation; code = $result.code; error = $result.error }
}

function Invoke-RuntimeBackupAction() {
    $runtime = Get-ActiveRuntime
    if ($runtime -eq 'windows') {
        $r = Invoke-WindowsRuntimeBackup
        return @{ ok = [bool]$r.ok; output = $r.path; error = $r.error; method = 'windows-tar' }
    }
    if ($runtime -eq 'docker') { return Invoke-Backup }
    return @{ ok = $false; error = "No active runtime" }
}

function Stop-RuntimeServer() {
    $runtime = Get-ActiveRuntime
    if ($runtime -eq 'windows') {
        $r = Stop-WindowsRuntime -Grace 120
        return @{ ok = [bool]$r.ok; output = $r.detail; error = $r.error; method = $r.method }
    }
    if ($runtime -eq 'docker') { return Stop-Server }
    return @{ ok = $false; error = "No active runtime" }
}

function Restart-RuntimeServer() {
    $runtime = Get-ActiveRuntime
    if ($runtime -eq 'windows') {
        $stop = Stop-WindowsRuntime -Grace 120
        if (-not $stop.ok) { return @{ ok = $false; error = "Stop failed: $($stop.error)" } }
        Start-Sleep -Seconds 2
        $start = Start-WindowsRuntime
        if (-not $start.ok) { return @{ ok = $false; error = "Start failed: $($start.error)" } }
        $version = ''
        $v = Get-WindowsRuntimeVersion
        if ($v.ok) { $version = $v.version }
        Update-RuntimeState -Active 'windows' -PidValue $start.pid -StartedAt (Get-RuntimeIsoTimestamp) -Version $version
        return @{ ok = $true; output = "Windows runtime restarted (PID=$($start.pid))" }
    }
    if ($runtime -eq 'docker') { return Restart-Server }
    return @{ ok = $false; error = "No active runtime" }
}

function Start-RuntimeSwitchTask([string]$To, [switch]$Force, [switch]$FullSnapshot) {
    <# Spawns switch-runtime.ps1 as a background process and returns a task id. #>
    $taskId = [guid]::NewGuid().ToString('N')
    $tasksDir = Join-Path $diagnosticsDir 'tasks'
    if (-not (Test-Path -LiteralPath $tasksDir -PathType Container)) {
        New-Item -ItemType Directory -Path $tasksDir -Force | Out-Null
    }

    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File', (Join-Path $projectDir 'scripts\switch-runtime.ps1'), '-To', $To, '-Quiet')
    if ($Force) { $argList += '-Force' }
    if ($FullSnapshot) { $argList += '-FullSnapshot' }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = ($argList | ForEach-Object {
        if ($_ -match '\s') { "`"$_`"" } else { $_ }
    }) -join ' '
    $psi.WorkingDirectory = $projectDir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()

    $task = [ordered]@{
        id        = $taskId
        type      = 'switch'
        target    = $To
        status    = 'running'
        startedAt = (Get-Date).ToString('o')
        pid       = $proc.Id
        exitCode  = $null
        endedAt   = $null
        stdout    = ''
        stderr    = ''
    }
    $runtimeTasks[$taskId] = @{ process = $proc; info = $task }
    Save-TaskState $taskId $task
    Write-PanelEvent "INFO" "Runtime switch task started: id=$taskId, target=$To, pid=$($proc.Id)"
    return $task
}

function Start-RuntimeRestoreTask([string]$Name, [switch]$Force) {
    $taskId = [guid]::NewGuid().ToString('N')
    $tasksDir = Join-Path $diagnosticsDir 'tasks'
    if (-not (Test-Path -LiteralPath $tasksDir -PathType Container)) {
        New-Item -ItemType Directory -Path $tasksDir -Force | Out-Null
    }

    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File', (Join-Path $projectDir 'scripts\restore-snapshot.ps1'), '-Name', $Name, '-Quiet')
    if ($Force) { $argList += '-Force' }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = ($argList | ForEach-Object {
        if ($_ -match '\s') { "`"$_`"" } else { $_ }
    }) -join ' '
    $psi.WorkingDirectory = $projectDir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()

    $task = [ordered]@{
        id        = $taskId
        type      = 'restore'
        snapshot  = $Name
        status    = 'running'
        startedAt = (Get-Date).ToString('o')
        pid       = $proc.Id
        exitCode  = $null
        endedAt   = $null
        stdout    = ''
        stderr    = ''
    }
    $runtimeTasks[$taskId] = @{ process = $proc; info = $task }
    Save-TaskState $taskId $task
    Write-PanelEvent "INFO" "Runtime restore task started: id=$taskId, snapshot=$Name, pid=$($proc.Id)"
    return $task
}

function Save-TaskState([string]$TaskId, $Info) {
    $tasksDir = Join-Path $diagnosticsDir 'tasks'
    if (-not (Test-Path -LiteralPath $tasksDir -PathType Container)) {
        New-Item -ItemType Directory -Path $tasksDir -Force | Out-Null
    }
    $path = Join-Path $tasksDir "$TaskId.json"
    $json = $Info | ConvertTo-Json -Depth 10 -Compress
    $tmp = "$path.tmp.$PID"
    [System.IO.File]::WriteAllText($tmp, $json, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $path -Force
}

function Get-RuntimeTask([string]$TaskId) {
    if ($runtimeTasks.ContainsKey($TaskId)) {
        $entry = $runtimeTasks[$TaskId]
        $proc = $entry.process
        $info = $entry.info
        # Refresh state if still running
        if ($info.status -eq 'running') {
            if ($proc.HasExited) {
                $info.exitCode = $proc.ExitCode
                $info.endedAt = (Get-Date).ToString('o')
                $info.status = if ($proc.ExitCode -eq 0) { 'completed' } else { 'failed' }
                $info.stdout = $proc.StandardOutput.ReadToEnd()
                $info.stderr = $proc.StandardError.ReadToEnd()
                Save-TaskState $TaskId $info
            } else {
                # Try to read any available output without blocking
                try {
                    $availOut = $proc.StandardOutput.BaseStream
                    # leave the stream alone; report running
                } catch { }
            }
        }
        return $info
    }
    # Fallback: load from disk
    $path = Join-Path $diagnosticsDir "tasks\$TaskId.json"
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        try {
            $info = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            return $info
        } catch { }
    }
    return $null
}

function Invoke-SnapshotCreate([string]$Type = 'Light') {
    <# Triggers a manual snapshot via switch-runtime.ps1 helper. We invoke the
       New-SwitchSnapshot function directly by dot-sourcing switch-runtime.ps1
       helpers. To avoid double-loading providers, we inline the call via a
       separate PowerShell child process. #>
    $taskId = [guid]::NewGuid().ToString('N')
    $tasksDir = Join-Path $diagnosticsDir 'tasks'
    if (-not (Test-Path -LiteralPath $tasksDir -PathType Container)) {
        New-Item -ItemType Directory -Path $tasksDir -Force | Out-Null
    }

    # Inline PowerShell that dot-sources switch-runtime.ps1 helpers is complex;
    # instead, run a small script that calls New-SwitchSnapshot.
    $script = @"
param([string]`$Type, [string]`$ProjectDir)
. (Join-Path `$ProjectDir 'scripts\runtime-common.ps1')
. (Join-Path `$ProjectDir 'scripts\docker-runtime.ps1')
. (Join-Path `$ProjectDir 'scripts\win-runtime.ps1')
# Re-define snapshot helpers from switch-runtime.ps1 by dot-sourcing its functions
. (Join-Path `$ProjectDir 'scripts\switch-runtime.ps1' -ErrorAction SilentlyContinue) 2>`$null | Out-Null
# switch-runtime.ps1 executes its main flow on dot-source, which we don't want.
# Instead, replicate the snapshot creation inline:
`$snapshotDir = Join-Path `$ProjectDir 'data\switch-snapshots'
`$manifestPath = Join-Path `$snapshotDir 'manifest.json'
if (-not (Test-Path -LiteralPath `$snapshotDir -PathType Container)) {
    New-Item -ItemType Directory -Path `$snapshotDir -Force | Out-Null
}
`$timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
`$name = "`$timestamp-`$Type-manual.tar.gz"
`$archivePath = Join-Path `$snapshotDir `$name
`$tempStaging = Join-Path `$env:TEMP "palworld-snap-`$PID"
if (Test-Path -LiteralPath `$tempStaging) { Remove-Item -LiteralPath `$tempStaging -Recurse -Force }
New-Item -ItemType Directory -Path `$tempStaging -Force | Out-Null
try {
    `\$configBase = Join-Path `$ProjectDir 'data\Pal\Saved\Config'
    foreach (`$platform in @('LinuxServer','WindowsServer')) {
        `\$platformDir = Join-Path `\$configBase `$platform
        if (Test-Path -LiteralPath `\$platformDir -PathType Container) {
            `\$destDir = Join-Path `$tempStaging "Config\`$platform"
            New-Item -ItemType Directory -Path `\$destDir -Force | Out-Null
            Copy-Item -Path (Join-Path `\$platformDir 'PalWorldSettings.ini') -Destination `\$destDir -ErrorAction SilentlyContinue
            Copy-Item -Path (Join-Path `\$platformDir 'Engine.ini') -Destination `\$destDir -ErrorAction SilentlyContinue
        }
    }
    Copy-Item -Path (Join-Path `$ProjectDir '.env') -Destination `$tempStaging -ErrorAction SilentlyContinue
    Copy-Item -Path (Join-Path `$ProjectDir 'data\runtime.state') -Destination `$tempStaging -ErrorAction SilentlyContinue
    if (`$Type -eq 'Full') {
        `\$saveGamesPath = Join-Path `$ProjectDir 'data\Pal\Saved\SaveGames'
        if (Test-Path -LiteralPath `\$saveGamesPath -PathType Container) {
            Copy-Item -Path `\$saveGamesPath -Destination (Join-Path `$tempStaging 'SaveGames') -Recurse -Force
        }
    }
    & tar.exe -czf `"`$archivePath`" -C `"`$tempStaging`" .
    if (`$LASTEXITCODE -ne 0) { throw "tar failed" }
    `\$bytes = [System.IO.File]::ReadAllBytes(`$archivePath)
    `\$sha = [System.Security.Cryptography.SHA256]::Create()
    `\$hash = `\$sha.ComputeHash(`\$bytes)
    `\$hex = (`\$hash | ForEach-Object { `$_.ToString('x2') }) -join ''
    `\$sha256 = "sha256:`$hex"
    `\$size = (Get-Item -LiteralPath `$archivePath).Length
    `\$manifest = @{ snapshots = @(); retentionPolicy = @{ maxFullCount = 3; maxFullTotalBytes = 1073741824; maxLightCount = 10; minFullKeepHours = 24 } }
    if (Test-Path -LiteralPath `$manifestPath -PathType Leaf) {
        try { `\$manifest = Get-Content -LiteralPath `$manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable -ErrorAction Stop } catch { }
    }
    `\$entry = [ordered]@{
        name = `$name; type = `$Type; phase = 'manual'; createdAt = (Get-Date).ToString('o')
        trigger = 'manual'; from = `$null; to = `$null; sizeBytes = `$size; sha256 = `$sha256
    }
    `\$snapList = [System.Collections.ArrayList]@(`$manifest.snapshots)
    `\$snapList.Add(`$entry) | Out-Null
    `$manifest.snapshots = `\$snapList.ToArray()
    `\$json = `$manifest | ConvertTo-Json -Depth 10 -Compress
    `\$tmpM = "`$manifestPath.tmp.`$PID"
    [System.IO.File]::WriteAllText(`$tmpM, `$json, [System.Text.UTF8Encoding]::new(`$false))
    Move-Item -LiteralPath `$tmpM -Destination `$manifestPath -Force
    Write-Output (ConvertTo-Json -InputObject @{ ok = `$true; name = `$name; sizeBytes = `$size; sha256 = `$sha256 } -Compress)
} finally {
    if (Test-Path -LiteralPath `$tempStaging) { Remove-Item -LiteralPath `$tempStaging -Recurse -Force -ErrorAction SilentlyContinue }
}
"@
    $tempScript = Join-Path $env:TEMP "palworld-snap-create-$PID.ps1"
    [System.IO.File]::WriteAllText($tempScript, $script, [System.Text.UTF8Encoding]::new($false))

    $argString = "-NoProfile -ExecutionPolicy Bypass -File `"$tempScript`" -Type $Type -ProjectDir `"$projectDir`""
    $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $argString -PassThru -NoNewWindow -RedirectStandardOutput "$tempScript.out" -RedirectStandardError "$tempScript.err"

    $task = [ordered]@{
        id        = $taskId
        type      = 'snapshot'
        snapshotType = $Type
        status    = 'running'
        startedAt = (Get-Date).ToString('o')
        pid       = $proc.Id
        exitCode  = $null
        endedAt   = $null
    }
    $runtimeTasks[$taskId] = @{ process = $proc; info = $task; tempScript = $tempScript }
    Save-TaskState $taskId $task
    Write-PanelEvent "INFO" "Snapshot create task started: id=$taskId, type=$Type, pid=$($proc.Id)"
    return $task
}

function Get-PlayerCount($status) {
    if ($status -ne "running") {
        $playerCache.value = 0
        return 0
    }
    if (((Get-Date) - $playerCache.checkedAt).TotalSeconds -lt 15) {
        return [int]$playerCache.value
    }

    try {
        $restOut = Invoke-Compose "exec -T $composeServiceName rest-cli players" 15000
        if ($restOut.ExitCode -eq 0 -and $restOut.Stdout) {
            $data = Parse-Json $restOut.Stdout
            if ($data -is [System.Collections.IDictionary] -and $data.ContainsKey("players")) {
                $playerCache.value = @($data["players"]).Count
            }
        }
    } catch {
        # Keep the last successful count. State polling must remain best-effort.
    }
    $playerCache.checkedAt = Get-Date
    return [int]$playerCache.value
}

function Get-CollectionCount($value) {
    <# JavaScriptSerializer and ConvertFrom-Json return different empty-array
       shapes. Count the actual collection, never the wrapper object's fields. #>
    if ($null -eq $value) { return 0 }
    if ($value -is [System.Collections.ICollection]) { return [int]$value.Count }
    if ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
        return [int]@($value | ForEach-Object { $_ }).Count
    }
    return 1
}

# ===== Player session time tracking =====
# The daily collector owns polling. The Web Console only reads the resulting
# privacy-preserving aggregate, so closing a browser cannot stop accounting.
. (Join-Path $PSScriptRoot 'scripts\player-session-times.ps1')

function Get-ContainerState() {
    $ps = Invoke-Docker "ps -a --filter name=$containerName --format `"{{.Status}}`""
    $statusLine = ($ps.Stdout -split "`n" | Where-Object { $_ -ne "" }) -join ""
    $status = "unknown"
    $health = "unknown"
    $uptime = ""
    if ($statusLine -match "Up (.+?)\s*\((\w+)\)") {
        $status = "running"
        $uptime = $matches[1].Trim()
        $health = $matches[2]
        if ($health -eq "starting") { $status = "starting" }
    } elseif ($statusLine -match "Up (.+)") {
        $status = "running"
        $uptime = $matches[1].Trim()
        $health = "none"
    } elseif ($statusLine -match "Exited") {
        $status = "stopped"
    } elseif ($statusLine -match "Restarting") {
        $status = "restarting"
    } elseif ($statusLine -eq "") {
        $status = "absent"
    }

    # Resource usage (only if running)
    $cpu = 0.0
    $mem = 0.0
    $memPct = 0.0
    $cpuLimit = [Environment]::ProcessorCount
    $memLimit = 0
    try {
        $resourceConfig = Invoke-Docker "inspect $containerName --format `"{{.HostConfig.NanoCpus}}|{{.HostConfig.Memory}}`""
        if ($resourceConfig.ExitCode -eq 0 -and $resourceConfig.Stdout -match '^([0-9]+)\|([0-9]+)') {
            $nanoCpus = [double]$matches[1]
            $memoryBytes = [double]$matches[2]
            if ($nanoCpus -gt 0) { $cpuLimit = [math]::Max(1, [math]::Round($nanoCpus / 1000000000.0, 2)) }
            if ($memoryBytes -gt 0) { $memLimit = $memoryBytes / 1MB }
        }
    } catch { }
    if ($memLimit -le 0) {
        try { $memLimit = [math]::Round((Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory / 1MB, 0) } catch { $memLimit = 0 }
    }
    if ($status -in @("running", "starting")) {
        $stats = Invoke-Docker "stats $containerName --no-stream --format `"{{.CPUPerc}}|{{.MemUsage}}|{{.MemPerc}}`""
        $line = ($stats.Stdout -split "`n" | Where-Object { $_ -ne "" }) -join ""
        # Format: "15.92%|940.9MiB / 16GiB|11.49%"
        if ($line -match "([\d.]+)%\|([\d.]+)([A-Za-z]+)\s*/\s*([\d.]+)([A-Za-z]+)\|([\d.]+)%") {
            # Extract all values BEFORE any -match calls (which overwrite $matches)
            $cpu = [double]$matches[1]
            $mem = [double]$matches[2]
            $memUnit = $matches[3]
            $memLimitVal = [double]$matches[4]
            $memLimitUnit = $matches[5]
            $memPct = [double]$matches[6]
            # Unit conversion using -like instead of -match to preserve $matches
            if ($memUnit -like "GiB" -or $memUnit -like "GB") { $mem = $mem * 1024 }
            if ($memLimitUnit -like "GiB" -or $memLimitUnit -like "GB") { $memLimitVal = $memLimitVal * 1024 }
            $memLimit = $memLimitVal
        }
    }

    # Player count is cached because rcon-cli can block and pollutes container logs.
    $players = Get-PlayerCount $status

    $envVars = Get-EnvVars $envFile
    $maxPlayers = 8
    if ($envVars.ContainsKey("PLAYERS")) { $maxPlayers = [int]$envVars["PLAYERS"] }

    return @{
        status = $status
        health = $health
        uptime = $uptime
        cpu = $cpu
        memMb = [math]::Round($mem, 0)
        memLimitMb = [math]::Round($memLimit, 0)
        memPct = $memPct
        cpuLimit = $cpuLimit
        players = $players
        maxPlayers = $maxPlayers
    }
}

function Get-WindowsContainerState() {
    <# Returns the same shape as Get-ContainerState but sourced from the
       Windows-native PalServer process. Used by /api/state when active=windows.
       CPU and memory limits reflect the host hardware, not Docker caps.
       PalServer.exe is a launcher that spawns PalServer-Win64-Shipping-Cmd.exe;
       the shipping process is the actual game server and is the one we monitor. #>
    $state = Get-RuntimeState
    $status = 'stopped'
    $health = 'unknown'
    $uptime = ''
    $cpu = 0.0
    $mem = 0.0
    $memPct = 0.0
    # Windows native has no container cap; use host hardware totals
    $memLimit = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB, 0)
    $cpuLimit = [Environment]::ProcessorCount
    $players = 0

    $envVars = Get-EnvVars $envFile
    $maxPlayers = 8
    if ($envVars.ContainsKey("PLAYERS")) { $maxPlayers = [int]$envVars["PLAYERS"] }

    $pidValue = $state.pid
    if ($pidValue) {
        # The launcher PID is in runtime.state. The actual game server is the
        # child process PalServer-Win64-Shipping-Cmd.exe. Prefer the child if it
        # exists; fall back to the launcher for health/uptime if not yet spawned.
        $launcherProc = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
        $gameProc = $null
        if ($launcherProc) {
            try {
                $children = Get-CimInstance Win32_Process -Filter "ParentProcessId=$pidValue" -ErrorAction SilentlyContinue
                foreach ($child in $children) {
                    if ($child.Name -like 'PalServer-Win64-Shipping*') {
                        $gameProc = Get-Process -Id $child.ProcessId -ErrorAction SilentlyContinue
                        if ($gameProc) { break }
                    }
                }
            } catch { }
        }
        $proc = $gameProc
        if (-not $proc) { $proc = $launcherProc }

        if ($proc) {
            $status = 'running'
            $elapsed = (Get-Date) - $proc.StartTime
            if ($elapsed.TotalHours -ge 1) {
                $uptime = "{0}h{1}m" -f [int][math]::Floor($elapsed.TotalHours), $elapsed.Minutes
            } elseif ($elapsed.TotalMinutes -ge 1) {
                $uptime = "{0}m{1}s" -f [int][math]::Floor($elapsed.TotalMinutes), $elapsed.Seconds
            } else {
                $uptime = "{0}s" -f [int][math]::Floor($elapsed.TotalSeconds)
            }
            $cpuTime = $proc.TotalProcessorTime.TotalSeconds
            if ($elapsed.TotalSeconds -gt 0) {
                $cpu = ($cpuTime / ($elapsed.TotalSeconds * $cpuLimit)) * 100
            }
            $mem = [math]::Round($proc.WorkingSet64 / 1MB, 0)
            $memPct = [math]::Round(($mem / $memLimit) * 100, 1)

            # Health via REST /info, or exact process/game-UDP readiness when
            # the current Windows build does not expose native REST.
            $h = Get-WindowsRuntimeHealth
            if ($h.status -eq 'healthy') { $health = 'healthy' }
            elseif ($h.status -eq 'degraded') { $health = 'unhealthy' }
            else { $health = 'unknown' }

            # Player count via REST /players (cached 15s)
            if (((Get-Date) - $playerCache.checkedAt).TotalSeconds -ge 15) {
                $pr = Get-WindowsRuntimePlayers
                if ($pr.ok) {
                    $rawPlayers = $null
                    try {
                        if ($pr.players -is [System.Collections.IDictionary]) {
                            $rawPlayers = $pr.players['players']
                        } elseif ($pr.players.PSObject.Properties.Name -contains 'players') {
                            $rawPlayers = $pr.players.players
                        }
                        $playerCache.value = Get-CollectionCount $rawPlayers
                    } catch { }
                }
                $playerCache.checkedAt = Get-Date
            }
            $players = [int]$playerCache.value
        } else {
            $status = 'stopped'
        }
    }

    return @{
        status = $status
        health = $health
        uptime = $uptime
        cpu = $cpu
        cpuLimit = $cpuLimit
        memMb = [math]::Round($mem, 0)
        memLimitMb = [math]::Round($memLimit, 0)
        memPct = $memPct
        players = $players
        maxPlayers = $maxPlayers
    }
}

function Get-RuntimeContainerState() {
    <# Routes to Get-ContainerState (docker) or Get-WindowsContainerState (windows).
       Adds a 'runtime' field for the dashboard. #>
    $runtime = Get-ActiveRuntime
    if ($runtime -eq 'windows') {
        $s = Get-WindowsContainerState
        $s['runtime'] = 'windows'
        return $s
    }
    $s = Get-ContainerState
    $s['runtime'] = if ($runtime -eq 'docker') { 'docker' } else { 'none' }
    return $s
}

function Get-RestData([string]$command) {
    try {
        $result = Invoke-Compose "exec -T $composeServiceName rest-cli $command" 15000
        if ($result.ExitCode -ne 0 -or -not $result.Stdout.Trim()) {
            return @{ ok = $false; error = ($result.Stderr + " " + $result.Stdout).Trim() }
        }
        return @{ ok = $true; data = Parse-Json $result.Stdout.Trim() }
    } catch {
        return @{ ok = $false; error = $_.Exception.Message }
    }
}

function Get-DirectorySummary([string]$path) {
    $files = @()
    if (Test-Path -LiteralPath $path) {
        $files = @(Get-ChildItem -LiteralPath $path -File -Recurse -ErrorAction SilentlyContinue)
    }
    $bytes = 0L
    $latest = $null
    foreach ($file in $files) {
        $bytes += $file.Length
        if ($null -eq $latest -or $file.LastWriteTime -gt $latest) { $latest = $file.LastWriteTime }
    }
    return [ordered]@{
        fileCount = $files.Count
        sizeMb = [math]::Round($bytes / 1MB, 2)
        latestWrite = $(if ($null -ne $latest) { $latest.ToString("yyyy-MM-dd HH:mm:ss") } else { "" })
    }
}

function Convert-ToSafeDiagnosticText([string]$text) {
    if (-not $text) { return "" }
    $safe = $text
    $safe = $safe -replace '(?i)(password|token|secret|api[_-]?key|access key)(\s*[:=]\s*)[^\s,;]+', '$1$2***'
    $safe = $safe -replace '(?i)(discord(?:app)?\.com/api/webhooks/)[^\s>]+', '$1***'
    $safe = $safe -replace '\b(\d{1,3}\.\d{1,3}\.\d{1,3})\.\d{1,3}\b', '$1.xxx'
    return $safe
}

function Convert-LogTimestamp([string]$line) {
    $candidate = ""
    $format = ""
    if ($line -match '(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2})') {
        $candidate = $matches[1]; $format = "yyyy/MM/dd HH:mm:ss"
    } elseif ($line -match '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') {
        $candidate = $matches[1]; $format = "yyyy-MM-dd HH:mm:ss"
    }
    if (-not $candidate) { return $null }
    try {
        return [datetime]::ParseExact(
            $candidate,
            $format,
            [System.Globalization.CultureInfo]::InvariantCulture
        )
    } catch {
        return $null
    }
}

function Get-TunnelNetworkProbeFromNetstat([int[]]$FrpcPids, [int]$GamePort, [string]$primaryError = '') {
    <#
       `netstat.exe` is a low-level, local-only fallback for hosts where the
       NetTCPIP provider is stalled. It supplies the same two bounded facts:
       a listener on the game UDP port and an established TCP socket owned by
       a current frpc process. It cannot prove a remote Palworld join.
    #>
    try {
        $tcpResult = Invoke-Process 'netstat.exe' '-ano -p tcp' 2500
        $udpResult = Invoke-Process 'netstat.exe' '-ano -p udp' 2500
        if ($tcpResult.ExitCode -ne 0 -or $udpResult.ExitCode -ne 0) {
            $detail = ($tcpResult.Stderr + ' ' + $udpResult.Stderr).Trim()
            return @{ ok = $false; error = "NetTCPIP probe failed: $primaryError Netstat fallback failed: $detail".Trim(); controlObserved = $false; udpObserved = $false; controlConnections = @(); localUdpReady = $false; source = 'none' }
        }

        $safePids = @($FrpcPids | Where-Object { $_ -gt 0 } | Select-Object -Unique)
        $connections = @()
        foreach ($line in ($tcpResult.Stdout -split "`r?`n")) {
            if ($line -match '^\s*TCP\s+\S+\s+(\S+)\s+ESTABLISHED\s+(\d+)\s*$') {
                $ownerPid = [int]$matches[2]
                if ($ownerPid -in $safePids) {
                    $connections += [ordered]@{ remote = [string]$matches[1]; state = 'Established' }
                    if ($connections.Count -ge 8) { break }
                }
            }
        }
        $escapedPort = [regex]::Escape([string]$GamePort)
        $localUdpReady = [regex]::IsMatch($udpResult.Stdout, "(?m)^\s*UDP\s+\S*:$escapedPort\s+")
        return @{ ok = $true; controlObserved = $true; udpObserved = $true; controlConnections = @($connections); localUdpReady = $localUdpReady; source = 'netstat-fallback'; primaryError = $primaryError }
    } catch {
        return @{ ok = $false; error = "NetTCPIP probe failed: $primaryError Netstat fallback failed: $($_.Exception.Message)".Trim(); controlObserved = $false; udpObserved = $false; controlConnections = @(); localUdpReady = $false; source = 'none' }
    }
}

function Get-TunnelNetworkProbe([int[]]$FrpcPids, [int]$GamePort) {
    <#
       The NetTCPIP cmdlets can occasionally block behind an unhealthy WMI/CIM
       provider. The panel itself is single-threaded, so run this noncritical
       evidence probe in a bounded child process rather than allowing one
       dashboard refresh to block every local management request.
    #>
    $safePids = @($FrpcPids | Where-Object { $_ -gt 0 } | Select-Object -Unique)
    $pidLiteral = if ($safePids.Count -gt 0) { $safePids -join ',' } else { '' }
    $probeScript = @"
`$frpcPids = @($pidLiteral)
`$gamePort = $GamePort
`$controlObserved = `$true
`$udpObserved = `$true
`$connections = @()
try {
    if (`$frpcPids.Count -gt 0) {
        `$rawConnections = @(foreach (`$frpcPid in `$frpcPids) {
            Get-NetTCPConnection -OwningProcess `$frpcPid -State Established -ErrorAction Stop
        })
        `$connections = @(`$rawConnections |
            Select-Object -First 8 |
            ForEach-Object {
                [ordered]@{ remote = "`$(`$_.RemoteAddress):`$(`$_.RemotePort)"; state = [string]`$_.State }
            })
    }
} catch { `$controlObserved = `$false }
`$udpReady = `$false
try {
    `$udpReady = (@(Get-NetUDPEndpoint -LocalPort `$gamePort -ErrorAction Stop).Count -gt 0)
} catch { `$udpObserved = `$false }
[ordered]@{
    controlObserved = `$controlObserved
    udpObserved = `$udpObserved
    controlConnections = `$connections
    localUdpReady = `$udpReady
} | ConvertTo-Json -Depth 4 -Compress
"@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($probeScript))
    try {
        $result = Invoke-Process 'powershell.exe' "-NoProfile -NonInteractive -EncodedCommand $encoded" 2500
        if ($result.ExitCode -ne 0 -or -not $result.Stdout.Trim()) {
            return Get-TunnelNetworkProbeFromNetstat -FrpcPids $safePids -GamePort $GamePort -primaryError ($result.Stderr + ' ' + $result.Stdout).Trim()
        }
        $parsed = Parse-Json $result.Stdout.Trim()
        return @{ ok = $true; controlObserved = [bool]$parsed.controlObserved; udpObserved = [bool]$parsed.udpObserved; controlConnections = @($parsed.controlConnections); localUdpReady = [bool]$parsed.localUdpReady; source = 'nettcpip' }
    } catch {
        return Get-TunnelNetworkProbeFromNetstat -FrpcPids $safePids -GamePort $GamePort -primaryError $_.Exception.Message
    }
}

function Get-TunnelStatus([bool]$force = $false) {
    # Local network evidence was not observed within the bounded probe timeout.
    if (-not $force -and $null -ne $tunnelCache.value -and
        ((Get-Date) - $tunnelCache.checkedAt).TotalSeconds -lt 10) {
        return $tunnelCache.value
    }
    $envVars = Get-EnvVars $envFile
    $provider = if ($envVars['TUNNEL_PROVIDER']) { [string]$envVars['TUNNEL_PROVIDER'] } else { 'none' }
    $gamePort = if ($envVars['PORT']) { [int]$envVars['PORT'] } else { 8211 }
    if ($provider -eq 'none') {
        $result = [ordered]@{
            ok = $true; checkedAt = (Get-Date).ToString('o'); provider = 'none'; state = 'disabled'; level = 'warn'
            processDetected = $false; processes = @(); localUdpReady = $false; localPort = $gamePort
            controlConnected = $false; proxyReady = $false; verifiedConnected = $false; externalEndpoint = ''
            verificationNote = 'No tunnel provider is configured. External connectivity is not verified.'
        }
        $tunnelCache.value = $result; $tunnelCache.checkedAt = Get-Date; return $result
    }
    $providerScript = Join-Path $projectDir 'scripts\tunnel-provider.ps1'
    $providerResult = @{ ok = $false; state = 'unknown'; pid = $null; detail = '' }
    try {
        $raw = Invoke-Process 'powershell.exe' "-NoProfile -ExecutionPolicy Bypass -File `"$providerScript`" -Action Status -Json" 10000
        if ($raw.ExitCode -eq 0 -and $raw.Stdout.Trim()) { $providerResult = Parse-Json $raw.Stdout.Trim() }
    } catch { $providerResult.detail = $_.Exception.Message }
    $providerPid = if ($providerResult.pid) { [int]$providerResult.pid } else { 0 }
    $networkProbe = Get-TunnelNetworkProbe -FrpcPids @($providerPid) -GamePort $gamePort
    $activeErrorWindowMinutes = 15
    $lastErrorAgeMinutes = $null
    if ([string]$providerResult.state -in @('error', 'failed', 'degraded')) {
        $lastErrorAgeMinutes = 0
    }
    $localUdpReady = [bool]$networkProbe.localUdpReady
    if (-not $localUdpReady -and (Get-ActiveRuntime) -eq 'docker') {
        try {
            $dockerPort = Invoke-Docker "port $containerName $gamePort/udp" 10000
            if ($dockerPort.ExitCode -eq 0 -and $dockerPort.Stdout -match ":$gamePort(?:\s|$)") { $localUdpReady = $true }
        } catch { }
    }
    $running = ([string]$providerResult.state -eq 'running')
    $state = if (-not $running) { [string]$providerResult.state } elseif (-not $localUdpReady) { 'local-not-ready' } else { 'ready' }
    $result = [ordered]@{
        ok = [bool]$providerResult.ok; checkedAt = (Get-Date).ToString('o'); provider = $provider
        state = $state; level = if ($state -eq 'ready') { 'warn' } else { 'danger' }
        processDetected = $running; processes = @(); localUdpReady = $localUdpReady; localPort = $gamePort
        localUdpEvidence = if ($localUdpReady) { 'The game UDP listener is present locally.' } else { 'The game UDP listener was not observed.' }
        controlConnected = $false; controlConnections = @(); proxyReady = $running; verifiedConnected = $false
        activeErrorWindowMinutes = $activeErrorWindowMinutes; lastErrorAgeMinutes = $lastErrorAgeMinutes
        externalEndpoint = ''; externalAttemptDetected = $false; recentExternalTraffic = $false
        providerDetail = [string]$providerResult.detail
        verificationNote = 'Provider readiness and a local UDP listener do not prove that an external player can connect. Perform an external player test.'
    }
    $tunnelCache.value = $result; $tunnelCache.checkedAt = Get-Date; return $result
}

function Clear-DashboardCache() {
    $dashboardCache.value = $null
    $dashboardCache.checkedAt = [datetime]::MinValue
    $updateStatusCache.value = $null
    $updateStatusCache.checkedAt = [datetime]::MinValue
}

function Get-Dashboard {
    if ($null -ne $dashboardCache.value -and
        ((Get-Date) - $dashboardCache.checkedAt).TotalSeconds -lt 8) {
        return $dashboardCache.value
    }

    $activeRuntime = Get-ActiveRuntime
    $state = Get-RuntimeContainerState
    $envVars = Get-EnvVars $envFile
    $warnings = @()
    $inspectState = @{}
    $restartCount = 0
    $image = ""
    $portBindings = @{}

    if ($activeRuntime -eq 'windows') {
        # Windows runtime: skip Docker inspect; pull pid/startedAt from process
        $rtState = Get-RuntimeState
        if ($rtState.pid) {
            $inspectState["Pid"] = [int]$rtState.pid
            $p = Get-Process -Id $rtState.pid -ErrorAction SilentlyContinue
            if ($p) {
                $inspectState["StartedAt"] = $p.StartTime.ToString("o")
            }
        }
        $inspectState["OOMKilled"] = $false
        $inspectState["ExitCode"] = $null
        $image = "windows-native"
    } else {
        try {
            $inspect = Invoke-Docker "inspect $containerName --format `"{{json .State}}|{{.RestartCount}}|{{json .Config.Image}}|{{json .HostConfig.PortBindings}}`"" 15000
            if ($inspect.ExitCode -eq 0 -and $inspect.Stdout.Trim()) {
                $parts = $inspect.Stdout.Trim().Split(@("|"), 4, [System.StringSplitOptions]::None)
                $inspectState = Parse-Json $parts[0]
                $restartCount = [int]$parts[1]
                $image = [string](Parse-Json $parts[2])
                $portBindings = Parse-Json $parts[3]
            }
        } catch {
            $warnings += "Docker inspect failed: $($_.Exception.Message)"
        }
    }

    $info = @{ ok = $false; error = "Container is not running." }
    $metrics = @{ ok = $false; error = "Container is not running." }
    $playersResult = @{ ok = $false; error = "Container is not running." }
    $windowsHealth = $null
    if ($state.status -in @("running", "starting")) {
        if ($activeRuntime -eq 'windows') {
            # Windows native: use HTTP REST with Basic auth (no docker exec)
            $info = Invoke-WinRest -Path '/info' -Method GET -TimeoutMs 8000
            if ($info.ok) { $info.data = Parse-Json $info.content }
            $metrics = Invoke-WinRest -Path '/metrics' -Method GET -TimeoutMs 8000
            if ($metrics.ok) { $metrics.data = Parse-Json $metrics.content }
            $playersResult = Invoke-WinRest -Path '/players' -Method GET -TimeoutMs 8000
            if ($playersResult.ok) {
                $parsed = Parse-Json $playersResult.content
                # Normalize to hashtable shape expected by downstream code
                $playersResult.data = @{ players = @($parsed.players) }
            }
            $windowsHealth = Get-WindowsRuntimeHealth
        } else {
            $info = Get-RestData "info"
            $metrics = Get-RestData "metrics"
            $playersResult = Get-RestData "players"
        }
    }

    # Cache mod manager report once per dashboard refresh
    $modReport = @{ managerEnabled = $false; installedMods = 0; operational = $false }
    try {
        $mr = Invoke-ModManagerAction "Status"
        if ($mr) {
            $modReport.managerEnabled = [bool]$mr.managerEnabled
            $modReport.installedMods = [int]$mr.installedMods
            $modReport.operational = [bool]$mr.operational
        }
    } catch { }

    $players = New-Object System.Collections.ArrayList
    if ($playersResult.ok -and $playersResult.data.ContainsKey("players")) {
        $playerLimit = 0
        foreach ($player in @($playersResult.data["players"])) {
            if ($playerLimit -ge 64) { break }
            $playerView = [ordered]@{}
            if ($player -is [System.Collections.IDictionary]) {
                foreach ($playerKey in $player.Keys) {
                    $playerView[[string]$playerKey] = $player[$playerKey]
                }
            }
            [void]$players.Add($playerView)
            $playerLimit++
        }
    }

    # Session accounting is polled independently by daily-log-collector.ps1.
    # A dashboard read must never create, extend, or close a player session.
    if ($metrics.ok) {
        $playerCache.value = [int]$metrics.data["currentplayernum"]
        $playerCache.checkedAt = Get-Date
        $state.players = $playerCache.value
        $state.maxPlayers = [int]$metrics.data["maxplayernum"]
    }

    $backupList = Get-BackupList
    $backups = @($backupList.backups)
    $backupBytes = 0L
    if (Test-Path -LiteralPath $backupDir) {
        Get-ChildItem -LiteralPath $backupDir -Filter "*.tar.gz" -File -ErrorAction SilentlyContinue |
            ForEach-Object { $backupBytes += $_.Length }
    }
    $saveSummary = Get-DirectorySummary "$projectDir\data\Pal\Saved\SaveGames"
    $updateStatus = Get-StartupUpdateStatus $envVars $activeRuntime $state
    $tunnelStatus = Get-TunnelStatus
    $management = Get-ManagementEndpointConfig -ProjectDirectory $projectDir -Environment $envVars
    $networkStatus = Test-NetworkConfiguration -Environment $envVars
    $logInsights = Get-LogInsights 150
    $incidentSummary = Get-IncidentList 20
    $archiveStatus = Get-LogArchiveList

    if ($state.status -ne "running") {
        $warnings += if ($activeRuntime -eq 'windows') { "Windows runtime is not running." } else { "Container is not fully running." }
    }
    if ($state.health -notin @("healthy", "none")) { $warnings += "Runtime health is $($state.health)." }
    if (-not $info.ok -or -not $metrics.ok) {
        if ($activeRuntime -eq 'windows' -and $null -ne $windowsHealth -and $windowsHealth.management.managementAvailable) {
            $warnings += "Palworld REST is unavailable; local management fallback is $($windowsHealth.management.fallback)."
        } elseif ($activeRuntime -eq 'windows' -and $null -ne $windowsHealth) {
            $warnings += "Palworld REST is unavailable and no confirmed local management fallback is enabled."
        } else {
            $warnings += "Palworld REST status is unavailable."
        }
    }
    if ($inspectState.ContainsKey("OOMKilled") -and [bool]$inspectState["OOMKilled"]) {
        $warnings += "The container was OOM-killed."
    }
    if ($envVars.ContainsKey("LOG_FORMAT_TYPE") -and
        $envVars["LOG_FORMAT_TYPE"] -notin @("Text", "Json")) {
        $warnings += "LOG_FORMAT_TYPE is invalid for Palworld and should be Text or Json."
    }
    if ($envVars.ContainsKey("BACKUP_ENABLED") -and $envVars["BACKUP_ENABLED"] -match "^(?i:true)$" -and
        $backups.Count -eq 0) {
        $warnings += "Scheduled backups are enabled but no backup archive is present."
    }
    if ($envVars.ContainsKey("REST_API_ENABLED") -and $envVars["REST_API_ENABLED"] -notmatch "^(?i:true)$") {
        $warnings += "REST API is disabled; dashboard and primary management actions will be limited."
    }
    if (-not $networkStatus.ok) {
        $warnings += "Network configuration is invalid: $($networkStatus.errors -join ' ')"
    }
    if ($tunnelStatus.state -eq "degraded") {
        $warnings += "The configured tunnel provider reported a recent data-connection error."
    } elseif ($tunnelStatus.state -notin @("ready", "verified")) {
        $warnings += "The configured tunnel provider is not ready: $($tunnelStatus.state)."
    }
    if ($logInsights.ok -and ([int]$logInsights.summary.critical -gt 0 -or [int]$logInsights.summary.error -gt 0)) {
        $warnings += "Recent container logs contain $($logInsights.summary.critical) critical and $($logInsights.summary.error) error entries."
    }
    if (-not $archiveStatus.collectorRunning) {
        $warnings += "Daily log archive collector is not running."
    }

    $dashboard = [ordered]@{
        ok = $true
        generatedAt = (Get-Date).ToString("o")
        container = [ordered]@{
            status = $state.status
            health = $state.health
            uptimeText = $state.uptime
            cpuPct = $state.cpu
            cpuLimit = if ($state.ContainsKey('cpuLimit')) { [int]$state.cpuLimit } else { 6 }
            memoryMb = $state.memMb
            memoryLimitMb = $state.memLimitMb
            memoryPct = $state.memPct
            startedAt = $(if ($inspectState.ContainsKey("StartedAt")) { $inspectState["StartedAt"] } else { "" })
            restartCount = $restartCount
            oomKilled = $(if ($inspectState.ContainsKey("OOMKilled")) { [bool]$inspectState["OOMKilled"] } else { $false })
            exitCode = $(if ($inspectState.ContainsKey("ExitCode")) { [int]$inspectState["ExitCode"] } else { $null })
            pid = $(if ($inspectState.ContainsKey("Pid")) { [int]$inspectState["Pid"] } else { 0 })
            image = $image
            ports = $portBindings
        }
        server = $(if ($info.ok) { $info.data } else { @{} })
        metrics = $(if ($metrics.ok) { $metrics.data } else {
            [ordered]@{
                currentplayernum = $state.players
                maxplayernum = $state.maxPlayers
                serverfps = 0
                serverfpsaverage = 0
                serverframetime = 0
                days = 0
                basecampnum = 0
                uptime = 0
            }
        })
        players = $players
        services = [ordered]@{
            update = $updateStatus
            rest = [ordered]@{
                configured = ($envVars["REST_API_ENABLED"] -match "^(?i:true)$")
                reachable = [bool]$info.ok
                port = $envVars["REST_API_PORT"]
                compatibilityMode = [string]$management.windowsRestCompatibilityMode
                readiness = if ($null -ne $windowsHealth) { [string]$windowsHealth.readiness } else { if ($info.ok) { 'REST' } else { 'unavailable' } }
            }
            rcon = [ordered]@{
                configured = [bool]$management.legacyRconEnabled
                port = $management.rconPort
                exposure = "127.0.0.1 only"
                deprecated = $true
                listening = if ($null -ne $windowsHealth) { [bool]$windowsHealth.management.rconListening } else { $false }
            }
            management = [ordered]@{
                restEnabled = [bool]$management.restEnabled
                restPort = $management.restPort
                windowsRestCompatibilityMode = [string]$management.windowsRestCompatibilityMode
                legacyRconEnabled = [bool]$management.legacyRconEnabled
                fallback = if ($null -ne $windowsHealth) { [string]$windowsHealth.management.fallback } else { 'none' }
                managementAvailable = if ($null -ne $windowsHealth) { [bool]$windowsHealth.management.managementAvailable } else { [bool]$info.ok }
                networkMode = $networkStatus.mode
                tunnelProvider = $networkStatus.provider
            }
            tunnel = $tunnelStatus
            backup = [ordered]@{
                configured = ($envVars["BACKUP_ENABLED"] -match "^(?i:true)$")
                count = $backups.Count
                totalSizeMb = [math]::Round($backupBytes / 1MB, 2)
                latest = $(if ($backups.Count -gt 0) { $backups[0] } else { $null })
            }
            dailyLogArchive = [ordered]@{
                running = [bool]$archiveStatus.collectorRunning
                count = [int]$archiveStatus.count
                directory = [string]$archiveStatus.directory
                timezone = [string]$archiveStatus.timezone
            }
            modManager = [ordered]@{
                enabled = [bool]$modReport.managerEnabled
                installed = [int]$modReport.installedMods
                operational = [bool]$modReport.operational
            }
        }
        storage = [ordered]@{
            saves = $saveSummary
            backups = [ordered]@{
                count = $backups.Count
                totalSizeMb = [math]::Round($backupBytes / 1MB, 2)
            }
        }
        diagnostics = [ordered]@{
            logSummary = $(if ($logInsights.ok) { $logInsights.summary } else { @{} })
            incidentCountShown = $(if ($incidentSummary.ok) { $incidentSummary.count } else { 0 })
            incidentFile = "data/diagnostics/incidents.jsonl"
            explanationMode = "rules"
        }
        runtime = (Get-RuntimeStateInfo)
        warnings = $warnings
    }
    $dashboardCache.value = $dashboard
    $dashboardCache.checkedAt = Get-Date
    return $dashboard
}

function Get-Logs($lines = 300) {
    $lines = [math]::Max(1, [math]::Min(2000, [int]$lines))
    if ((Get-ActiveRuntime) -eq 'windows') {
        try {
            $windowsLogs = Get-WindowsRuntimeLogs -Lines $lines
            if (-not $windowsLogs.ok) {
                return @{ ok = $false; error = [string]$windowsLogs.error; source = 'windows native runtime' }
            }
            return @{ ok = $true; logs = (@($windowsLogs.lines) -join "`n"); source = 'windows native runtime' }
        } catch {
            return @{ ok = $false; error = "Windows runtime logs could not be read: $($_.Exception.Message)"; source = 'windows native runtime' }
        }
    }
    $r = Invoke-Compose "logs --tail $lines --no-color palworld-server"
    if ($r.ExitCode -ne 0) { return @{ ok = $false; error = $r.Stderr } }
    # Strip docker compose prefix "palworld-server  | "
    $cleaned = ($r.Stdout -split "`n" | ForEach-Object { $_ -replace "^palworld-server\s+\|\s+", "" }) -join "`n"
    return @{ ok = $true; logs = $cleaned; source = 'docker compose logs' }
}

function Get-StartupUpdateStatus($envVars, [string]$activeRuntime, $containerState) {
    <#
    Reads only the current container's SteamCMD output.  SteamCMD's successful
    startup check is evidence that the installed branch was current at that
    time; it is not a live upstream-version query after the server is running.
    #>
    $now = Get-Date
    if ($null -ne $updateStatusCache.value) {
        $cachedState = [string]$updateStatusCache.value.state
        $ttl = if ($cachedState -eq "updating") { 3 } else { 60 }
        if (($now - $updateStatusCache.checkedAt).TotalSeconds -lt $ttl) {
            return $updateStatusCache.value
        }
    }

    $autoUpdate = ($envVars.ContainsKey("UPDATE_ON_BOOT") -and
        [string]$envVars["UPDATE_ON_BOOT"] -match "^(?i:true)$")
    $result = [ordered]@{
        supported = ($activeRuntime -ne "windows")
        automaticOnBoot = $autoUpdate
        state = "not-observed"
        phase = ""
        progressPercent = $null
        downloadedBytes = $null
        totalBytes = $null
        gameVersion = ""
        evidence = ""
    }

    if ($activeRuntime -eq "windows") {
        $result.state = "not-applicable"
        $result.evidence = "Windows runtime does not use the Docker image startup updater."
        $updateStatusCache.value = $result
        $updateStatusCache.checkedAt = $now
        return $result
    }
    if (-not $autoUpdate) {
        $result.state = "disabled"
        $result.evidence = "UPDATE_ON_BOOT is disabled."
        $updateStatusCache.value = $result
        $updateStatusCache.checkedAt = $now
        return $result
    }
    if ($containerState.status -notin @("running", "starting")) {
        $result.state = "waiting"
        $result.evidence = "The Docker runtime is not running, so no startup update check is active."
        $updateStatusCache.value = $result
        $updateStatusCache.checkedAt = $now
        return $result
    }

    $logs = Get-Logs 1200
    if (-not $logs.ok) {
        $result.state = "unavailable"
        $result.evidence = "Container logs could not be read."
        $updateStatusCache.value = $result
        $updateStatusCache.checkedAt = $now
        return $result
    }

    $lastActiveIndex = -1
    $lastSuccessIndex = -1
    $lastErrorIndex = -1
    $lineIndex = 0
    foreach ($lineObject in @($logs.logs -split "`n")) {
        $line = ([string]$lineObject).TrimEnd("`r")
        if ($line -match "Update state \((0x[0-9A-Fa-f]+)\) ([^,]+), progress:\s*([\d.]+)\s*\(([\d,]+)\s*/\s*([\d,]+)\)") {
            $lastActiveIndex = $lineIndex
            $result.phase = $matches[2].Trim()
            $result.progressPercent = [double]::Parse($matches[3], [System.Globalization.CultureInfo]::InvariantCulture)
            $downloaded = 0L
            $total = 0L
            if ([long]::TryParse(($matches[4] -replace ",", ""), [ref]$downloaded)) { $result.downloadedBytes = $downloaded }
            if ([long]::TryParse(($matches[5] -replace ",", ""), [ref]$total)) { $result.totalBytes = $total }
        }
        if ($line -match "Success! App '2394010' fully installed\.") { $lastSuccessIndex = $lineIndex }
        if ($line -match "(?i)(steamcmd|update).*(error|failed)|(?i)(error|failed).*steamcmd") { $lastErrorIndex = $lineIndex }
        if ($line -match "Game version is (v[^\s]+)") { $result.gameVersion = $matches[1] }
        $lineIndex++
    }

    if ($lastActiveIndex -gt $lastSuccessIndex) {
        $result.state = "updating"
        $result.evidence = "SteamCMD is reporting an active update phase in the current container logs."
    } elseif ($lastSuccessIndex -ge 0) {
        $result.state = "completed"
        $result.evidence = "SteamCMD completed the automatic update check for this container startup."
    } elseif ($lastErrorIndex -ge 0) {
        $result.state = "failed"
        $result.evidence = "The retained container logs contain a SteamCMD update failure."
    } else {
        $result.evidence = "No current startup update result appears in the retained container logs."
    }
    $updateStatusCache.value = $result
    $updateStatusCache.checkedAt = $now
    return $result
}

function Get-LogArchiveList() {
    $envVars = Get-EnvVars $envFile
    $archives = @()
    if (Test-Path -LiteralPath $logArchiveDir -PathType Container) {
        Get-ChildItem -LiteralPath $logArchiveDir -Filter "*.txt" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match "^\d{4}-\d{2}-\d{2}\.txt$" } |
            Sort-Object Name -Descending |
            Select-Object -First 400 |
            ForEach-Object {
                $archives += [ordered]@{
                    name = $_.Name
                    date = $_.BaseName
                    sizeKb = [math]::Round($_.Length / 1KB, 1)
                    updatedAt = $_.LastWriteTime.ToString("o")
                }
            }
    }
    $collectorPid = 0
    $collectorRunning = $false
    if (Test-Path -LiteralPath $logCollectorPidFile -PathType Leaf) {
        $pidText = [System.IO.File]::ReadAllText($logCollectorPidFile).Trim()
        if ([int]::TryParse($pidText, [ref]$collectorPid)) {
            $collectorProcess = Get-CimInstance Win32_Process -Filter "ProcessId=$collectorPid" -ErrorAction SilentlyContinue
            $collectorRunning = ($null -ne $collectorProcess -and
                $collectorProcess.CommandLine -like "*daily-log-collector.ps1*")
        }
    }
    return [ordered]@{
        ok = $true
        timezone = if ($envVars['TZ']) { [string]$envVars['TZ'] } else { 'UTC' }
        range = "00:00:00-24:00:00"
        retention = "unlimited"
        directory = "data/log-archive"
        collectorRunning = $collectorRunning
        collectorPid = $(if ($collectorRunning) { $collectorPid } else { 0 })
        count = $archives.Count
        archives = $archives
    }
}

function Invoke-LogArchiveRefresh() {
    if (-not (Test-Path -LiteralPath $logCollectorScript -PathType Leaf)) {
        return @{ ok = $false; error = "Daily log collector script is missing." }
    }
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$logCollectorScript`" -Once"
    $result = Invoke-Process "powershell.exe" $arguments 120000
    if ($result.ExitCode -ne 0) {
        return @{ ok = $false; error = ($result.Stderr + " " + $result.Stdout).Trim() }
    }
    Write-PanelEvent "INFO" "Daily log archive refreshed manually."
    return Get-LogArchiveList
}

function Get-LogInsightForLine([string]$line) {
    $safe = Convert-ToSafeDiagnosticText $line
    $code = "activity"
    $severity = "info"
    $known = $false
    $actionCode = "none"

    # Verbose HTTP response headers may be captured beside container logs. A
    # header named x-sentry-error is metadata, not a server error.
    if ($safe -match '^\s*<\s*(?i:(access-control-|content-|server:|date:|via:|x-[a-z0-9-]+:))') {
        $code = "httpResponseHeader"; $known = $true
    } elseif ($safe -match '(?i)(setting breakpad minidump|steamworks.*initialized|logpakfile|mounted pak|server started|listening on)') {
        $code = "startupActivity"; $known = $true
    } elseif ($safe -match '(?i)REST accessed endpoint .+ OK') {
        $code = "restAccess"; $known = $true
    } elseif ($safe -match '(?i)(caught signal 15|sigterm|graceful.+shutdown|shutdown complete)') {
        $code = "gracefulStop"; $known = $true
    } elseif ($safe -match '(?i)(backup).*(complete|success|created)') {
        $code = "backupComplete"; $known = $true
    } elseif ($safe -match '(?i)(backup).*(fail|error|cannot)') {
        $code = "backupFailed"; $severity = "error"; $known = $true; $actionCode = "checkBackup"
    } elseif ($safe -match '(?i)(no space left|disk.+full|insufficient disk)') {
        $code = "diskFull"; $severity = "critical"; $known = $true; $actionCode = "freeDisk"
    } elseif ($safe -match '(?i)(out of memory|oom.?kill|oomkilled|cannot allocate memory)') {
        $code = "outOfMemory"; $severity = "critical"; $known = $true; $actionCode = "checkMemory"
    } elseif ($safe -match '(?i)(address already in use|failed to bind|bind.+failed)') {
        $code = "portInUse"; $severity = "error"; $known = $true; $actionCode = "checkPorts"
    } elseif ($safe -match '(?i)(permission denied|access is denied|operation not permitted)') {
        $code = "permissionDenied"; $severity = "error"; $known = $true; $actionCode = "checkPermissions"
    } elseif ($safe -match '(?i)(corrupt|corruption|invalid save|failed to load.+save)') {
        $code = "saveProblem"; $severity = "critical"; $known = $true; $actionCode = "protectSave"
    } elseif ($safe -match '(?i)(connection refused|actively refused)') {
        $code = "connectionRefused"; $severity = "error"; $known = $true; $actionCode = "checkDependency"
    } elseif ($safe -match '(?i)(i/o timeout|timed out|timeout waiting)') {
        $code = "timeout"; $severity = "error"; $known = $true; $actionCode = "checkNetwork"
    } elseif ($safe -match '(?i)(steamcmd|update).*(download|install|progress|available)') {
        $code = "updateActivity"; $known = $true
    } elseif ($safe -match '(?i)(player).*(joined|connected|login)') {
        $code = "playerJoined"; $known = $true
    } elseif ($safe -match '(?i)(player).*(left|disconnected|logout)') {
        $code = "playerLeft"; $known = $true
    } elseif ($safe -match '(?i)(deprecated)') {
        $code = "deprecated"; $severity = "warning"; $known = $true; $actionCode = "reviewSetting"
    } elseif ($safe -match '(?i)(fatal|segmentation fault|segfault|unhandled exception|crash)') {
        $code = "serverCrash"; $severity = "critical"; $known = $true; $actionCode = "checkCrash"
    } elseif ($safe -match '(?i)(error|exception|failed|cannot|could not)') {
        $code = "genericError"; $severity = "error"; $actionCode = "inspectContext"
    } elseif ($safe -match '(?i)(warn|warning)') {
        $code = "genericWarning"; $severity = "warning"; $actionCode = "inspectContext"
    }

    $loggedAt = ""
    $parsedStamp = Convert-LogTimestamp $safe
    if ($null -ne $parsedStamp) { $loggedAt = $parsedStamp.ToString("o") }
    return [ordered]@{
        raw = $safe
        severity = $severity
        code = $code
        actionCode = $actionCode
        known = $known
        loggedAt = $loggedAt
    }
}

function Get-IncidentFingerprint([string]$text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Initialize-IncidentFingerprints {
    if ($incidentFingerprints.Count -gt 0 -or -not (Test-Path -LiteralPath $incidentFile)) { return }
    foreach ($line in @(Get-Content -LiteralPath $incidentFile -Tail 1000 -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        try {
            $item = Parse-Json ([string]$line)
            if ($item -is [System.Collections.IDictionary] -and $item.ContainsKey("fingerprint")) {
                [void]$incidentFingerprints.Add([string]$item["fingerprint"])
            }
        } catch { }
    }
}

function Add-Incident($entry) {
    Initialize-IncidentFingerprints
    $fingerprint = Get-IncidentFingerprint "$($entry.code)|$($entry.loggedAt)|$($entry.raw)"
    if ($incidentFingerprints.Contains($fingerprint)) { return $false }
    [void]$incidentFingerprints.Add($fingerprint)
    if (-not (Test-Path -LiteralPath $diagnosticsDir)) {
        New-Item -ItemType Directory -Path $diagnosticsDir -Force | Out-Null
    }
    $record = [ordered]@{
        fingerprint = $fingerprint
        observedAt = (Get-Date).ToString("o")
        loggedAt = $entry.loggedAt
        severity = $entry.severity
        code = $entry.code
        actionCode = $entry.actionCode
        raw = $entry.raw
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $writer = New-Object System.IO.StreamWriter($incidentFile, $true, $utf8NoBom)
    try { $writer.WriteLine((Encode-Json $record)) } finally { $writer.Dispose() }
    return $true
}

function Get-IncidentList($limit = 100) {
    $limit = [math]::Max(1, [math]::Min(500, [int]$limit))
    $items = @()
    if (Test-Path -LiteralPath $incidentFile) {
        foreach ($line in @(Get-Content -LiteralPath $incidentFile -Tail $limit -Encoding UTF8 -ErrorAction SilentlyContinue)) {
            try { $items += ,(Parse-Json ([string]$line)) } catch { }
        }
        [array]::Reverse($items)
    }
    return [ordered]@{
        ok = $true
        count = $items.Count
        file = "data/diagnostics/incidents.jsonl"
        incidents = $items
    }
}

function Get-LogInsights($lines = 300, [bool]$force = $false) {
    $lines = [math]::Max(1, [math]::Min(1000, [int]$lines))
    if (-not $force -and $null -ne $logInsightCache.value -and
        $logInsightCache.lines -ge $lines -and
        ((Get-Date) - $logInsightCache.checkedAt).TotalSeconds -lt 10) {
        return $logInsightCache.value
    }

    $logResult = Get-Logs $lines
    if (-not $logResult.ok) { return $logResult }
    $entries = @()
    $summary = [ordered]@{ critical = 0; error = 0; warning = 0; info = 0; recorded = 0 }
    foreach ($lineObject in @($logResult.logs -split "`n")) {
        $line = ([string]$lineObject).TrimEnd("`r")
        if (-not $line) { continue }
        $entry = Get-LogInsightForLine $line
        $entries += ,$entry
        $summary[$entry.severity] = [int]$summary[$entry.severity] + 1
        if ($entry.severity -in @("critical", "error")) {
            if (Add-Incident $entry) { $summary.recorded = [int]$summary.recorded + 1 }
        }
    }
    $result = [ordered]@{
        ok = $true
        generatedAt = (Get-Date).ToString("o")
        mode = "rules"
        source = $(if ($logResult.source) { [string]$logResult.source } else { 'unknown' })
        entries = $entries
        summary = $summary
        incidentFile = "data/diagnostics/incidents.jsonl"
    }
    $logInsightCache.value = $result
    $logInsightCache.checkedAt = Get-Date
    $logInsightCache.lines = $lines
    return $result
}

function Invoke-Rcon([string]$cmd) {
    if (-not $cmd) { return @{ ok = $false; error = "Empty command" } }
    if ($cmd.Length -gt 512 -or $cmd -match "[`r`n`0]") {
        return @{ ok = $false; error = "Command must be one line and at most 512 characters." }
    }

    $runtime = Get-ActiveRuntime
    if ($runtime -eq 'windows') {
        # Windows exposes its own loopback RCON listener. Do not attempt a
        # docker compose exec when Windows is the active runtime.
        return Invoke-WindowsRcon -Command $cmd -Timeout 10
    }
    if ($runtime -ne 'docker') {
        return @{ ok = $false; error = "No active runtime" }
    }

    $escaped = $cmd -replace '"','\"'
    $r = Invoke-Compose "exec -T $composeServiceName rcon-cli ""$escaped"""
    if ($r.ExitCode -ne 0) {
        return @{ ok = $false; error = ($r.Stderr + " " + $r.Stdout).Trim() }
    }
    return @{ ok = $true; output = $r.Stdout.Trim() }
}

function Invoke-Save() {
    return Invoke-DockerRuntimeSave -Timeout 30
}

function Invoke-Backup() {
    $r = Invoke-Compose "exec -T $composeServiceName backup" 180000
    if ($r.ExitCode -ne 0) {
        return @{ ok = $false; error = ($r.Stderr + " " + $r.Stdout).Trim() }
    }
    return @{ ok = $true; output = $r.Stdout.Trim() }
}

function Stop-Server() {
    $r = Invoke-Compose "stop -t 120 $composeServiceName" 150000
    if ($r.ExitCode -ne 0) {
        return @{ ok = $false; error = ($r.Stderr + " " + $r.Stdout).Trim() }
    }
    return @{ ok = $true; output = ($r.Stdout + $r.Stderr).Trim() }
}

function Restart-Server() {
    # Recreate applies env changes without an explicit down window and preserves the volume.
    $r = Invoke-Compose "up -d --force-recreate --remove-orphans $composeServiceName" 240000
    if ($r.ExitCode -ne 0) {
        return @{ ok = $false; error = ($r.Stderr + " " + $r.Stdout).Trim() }
    }
    return @{ ok = $true; output = ($r.Stdout + $r.Stderr).Trim() }
}

function Invoke-ModManagerAction([string]$action) {
    if ($action -notin @("Status", "Check", "Sync")) {
        return @{ ok = $false; error = "Unsupported Mod manager action." }
    }
    if (-not (Test-Path -LiteralPath $modManagerScript -PathType Leaf)) {
        return @{ ok = $false; error = "Mod manager script is missing." }
    }
    $arguments = "-NoProfile -File `"$modManagerScript`" -Action $action -Json"
    $result = Invoke-Process "powershell.exe" $arguments 300000
    if (-not $result.Stdout.Trim()) {
        return @{ ok = $false; error = "Mod manager returned no JSON output." }
    }
    try {
        return Parse-Json $result.Stdout.Trim()
    } catch {
        return @{ ok = $false; error = "Mod manager returned invalid JSON." }
    }
}

function Get-BackupList() {
    $backups = @()
    if (Test-Path $backupDir) {
        Get-ChildItem $backupDir -Filter "*.tar.gz" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 30 | ForEach-Object {
            $backups += @{
                name = $_.Name
                sizeMb = [math]::Round($_.Length / 1MB, 2)
                time = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            }
        }
    }
    return @{ ok = $true; backups = $backups }
}

# ===== HTTP server =====

# The desktop host and either batch launcher may attempt to start the panel at
# nearly the same time. A named mutex makes that race harmless: the first
# process owns the listener and later attempts exit without overwriting its
# port/PID marker files.
$mutexBytes = [System.Text.Encoding]::UTF8.GetBytes($projectDir.ToLowerInvariant())
$mutexHash = [System.Security.Cryptography.SHA256]::Create()
try {
    $mutexSuffix = ([System.BitConverter]::ToString($mutexHash.ComputeHash($mutexBytes))).Replace('-', '').Substring(0, 24)
} finally {
    $mutexHash.Dispose()
}
$panelMutexCreated = $false
$panelMutex = [System.Threading.Mutex]::new($true, "Local\PalworldServer.WebConsole.$mutexSuffix", [ref]$panelMutexCreated)
if (-not $panelMutexCreated) {
    Write-PanelEvent 'INFO' 'Web Console is already running or starting; duplicate start request ignored.'
    $panelMutex.Dispose()
    exit 0
}

$listener = $null
$port = $null
$bindErrors = @()
try {
foreach ($candidatePort in @($preferredPort) + $fallbackPorts) {
    $candidateListener = New-Object System.Net.HttpListener
    # Bind only loopback interfaces. The console handles sensitive settings,
    # player records and backups and must never be reachable through a tunnel,
    # reverse proxy or LAN address.
    $candidateListener.Prefixes.Add("http://localhost:$candidatePort/")
    $candidateListener.Prefixes.Add("http://127.0.0.1:$candidatePort/")
    $candidateListener.Prefixes.Add("http://[::1]:$candidatePort/")
    try {
        $candidateListener.Start()
        $listener = $candidateListener
        $port = $candidatePort
        break
    } catch {
        $bindErrors += "${candidatePort}: $($_.Exception.Message)"
        $candidateListener.Close()
    }
}
if ($null -eq $listener) {
    Write-PanelEvent "FATAL" "Cannot bind a Web Console port: $($bindErrors -join ' | ')"
    throw 'Cannot bind a Web Console port.'
}
if ($port -ne $preferredPort) {
    Write-PanelEvent "WARN" "Preferred port $preferredPort is occupied; using localhost:$port."
}
[System.IO.File]::WriteAllText(
    $pidFile,
    [string]$PID,
    (New-Object System.Text.UTF8Encoding($false))
)
[System.IO.File]::WriteAllText(
    $portFile,
    [string]$port,
    (New-Object System.Text.UTF8Encoding($false))
)

Write-PanelEvent "INFO" "Web Console listening only on loopback at http://localhost:$port/."

while ($listener.IsListening) {
    try { $ctx = $listener.GetContext() } catch { break }
    $req = $ctx.Request
    $res = $ctx.Response

    try {
        Set-SecurityHeaders $res
        $path = $req.Url.LocalPath
        $method = $req.HttpMethod

        if (-not (Test-LoopbackRequest $req)) {
            $res.StatusCode = 403
            Send-Json $res @{ ok = $false; error = "Web Console is restricted to localhost." }
            continue
        }
        if ($method -notin @("GET", "HEAD", "OPTIONS") -and -not (Test-RequestOrigin $req)) {
            $res.StatusCode = 403
            Send-Json $res @{ ok = $false; error = "Mutating requests require a loopback Host and a matching Origin when supplied." }
            continue
        }

        if ($method -eq "GET" -and $path -eq "/") {
            $bytes = [System.IO.File]::ReadAllBytes($htmlFile)
            $res.ContentType = "text/html; charset=utf-8"
            $res.Headers["Cache-Control"] = "no-store"
            $res.ContentLength64 = $bytes.Length
            $res.OutputStream.Write($bytes, 0, $bytes.Length)
        }
        elseif ($method -eq "GET" -and $path -eq "/favicon.ico") {
            $res.StatusCode = 204
            $res.ContentLength64 = 0
        }
        elseif ($method -eq "GET" -and ($path -eq "/styles.css" -or $path -eq "/app.js")) {
            # Serve the split frontend assets from the web/ directory.
            $fileName = [System.IO.Path]::GetFileName($path)
            $assetPath = Join-Path $projectDir "web\$fileName"
            if (-not (Test-Path -LiteralPath $assetPath -PathType Leaf)) {
                $res.StatusCode = 404
                $res.ContentLength64 = 0
            } else {
                $bytes = [System.IO.File]::ReadAllBytes($assetPath)
                if ($fileName -eq "styles.css") {
                    $res.ContentType = "text/css; charset=utf-8"
                } else {
                    $res.ContentType = "application/javascript; charset=utf-8"
                }
                $res.Headers["Cache-Control"] = "no-store"
                $res.ContentLength64 = $bytes.Length
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
            }
        }
        elseif ($method -eq "GET" -and $path -eq "/api/state") {
            Send-Json $res (Get-RuntimeContainerState)
        }
        elseif ($method -eq "GET" -and $path -eq "/api/dashboard") {
            Send-Json $res (Get-Dashboard)
        }
        elseif ($method -eq "GET" -and $path -eq "/api/settings") {
            Send-Json $res (Get-SettingsPayload)
        }
        elseif ($method -eq "GET" -and $path -eq "/api/env") {
            Send-Json $res (Get-EditableEnvVars)
        }
        elseif ($method -eq "POST" -and $path -eq "/api/env") {
            try {
                $updates = Convert-ValidatedUpdates (Read-JsonBody $req)
            } catch {
                $res.StatusCode = 400
                Send-Json $res @{ ok = $false; error = $_.Exception.Message }
                continue
            }
            $currentVars = Get-EnvVars $envFile
            $changedUpdates = [ordered]@{}
            foreach ($key in $updates.Keys) {
                if (-not $currentVars.ContainsKey($key) -or
                    [string]$currentVars[$key] -cne [string]$updates[$key]) {
                    $changedUpdates[$key] = $updates[$key]
                }
            }
            if ($changedUpdates.Count -gt 0) {
                Update-EnvFile $envFile $changedUpdates
                Clear-DashboardCache
                Write-PanelEvent "INFO" "Updated $($changedUpdates.Count) validated .env setting(s): $(@($changedUpdates.Keys) -join ', ')."
            }
            Send-Json $res @{ ok = $true; changed = @($changedUpdates.Keys) }
        }
        elseif ($method -eq "POST" -and $path -eq "/api/restart") {
            Write-PanelEvent "WARN" "Runtime restart requested from Web Console (runtime=$(Get-ActiveRuntime))."
            $result = Restart-RuntimeServer
            Clear-DashboardCache
            if ($result.ok) { Write-PanelEvent "INFO" "Runtime restart completed." }
            Send-Json $res $result
        }
        elseif ($method -eq "POST" -and $path -eq "/api/stop") {
            Write-PanelEvent "WARN" "Graceful runtime stop requested from Web Console (runtime=$(Get-ActiveRuntime))."
            $result = Stop-RuntimeServer
            Clear-DashboardCache
            Send-Json $res $result
        }
        elseif ($method -eq "POST" -and $path -eq "/api/save") {
            $result = Invoke-RuntimeSaveAction
            Write-PanelEvent $(if ($result.ok) { "INFO" } else { "ERROR" }) "World save requested; ok=$($result.ok)."
            if (-not $result.ok -and $result.code -eq 'management-unavailable') { $res.StatusCode = 409 }
            Send-Json $res $result
        }
        elseif ($method -eq "GET" -and $path -eq "/api/logs") {
            $lines = 300
            if ($req.QueryString["lines"]) { $lines = [int]$req.QueryString["lines"] }
            Send-Json $res (Get-RuntimeLogs $lines)
        }
        elseif ($method -eq "GET" -and $path -eq "/api/logs/insights") {
            $lines = 300
            if ($req.QueryString["lines"]) { $lines = [int]$req.QueryString["lines"] }
            Send-Json $res (Get-LogInsights $lines $false)
        }
        elseif ($method -eq "GET" -and $path -eq "/api/log-archives") {
            Send-Json $res (Get-LogArchiveList)
        }
        elseif ($method -eq "POST" -and $path -eq "/api/log-archives/refresh") {
            Send-Json $res (Invoke-LogArchiveRefresh)
        }
        elseif ($method -eq "GET" -and $path -eq "/api/log-archives/download") {
            $archiveName = [string]$req.QueryString["name"]
            if ($archiveName -notmatch "^\d{4}-\d{2}-\d{2}\.txt$") {
                $res.StatusCode = 400
                Send-Json $res @{ ok = $false; error = "Invalid archive name." }
                continue
            }
            $archivePath = Join-Path $logArchiveDir $archiveName
            if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
                $res.StatusCode = 404
                Send-Json $res @{ ok = $false; error = "Archive not found." }
                continue
            }
            Send-FileDownload $res $archivePath $archiveName
        }
        elseif ($method -eq "GET" -and $path -eq "/api/incidents") {
            $limit = 100
            if ($req.QueryString["limit"]) { $limit = [int]$req.QueryString["limit"] }
            Send-Json $res (Get-IncidentList $limit)
        }
        elseif ($method -eq "GET" -and $path -eq "/api/tunnel") {
            Send-Json $res (Get-TunnelStatus $false)
        }
        elseif ($method -eq "POST" -and $path -eq "/api/tunnel/check") {
            $tunnel = Get-TunnelStatus $true
            Clear-DashboardCache
            Send-Json $res $tunnel
        }
        elseif ($method -eq "POST" -and $path -eq "/api/management") {
            try {
                $data = Read-JsonBody $req
                if (-not ($data -is [System.Collections.IDictionary]) -or -not $data.ContainsKey('operation')) { throw 'JSON body must contain operation.' }
                $operation = [string]$data.operation
                if ($operation -notin @('announce','kick','ban','unban','shutdown')) { throw 'Unsupported REST management operation.' }
                $payload = [ordered]@{}
                if ($operation -eq 'announce') {
                    $message = [string]$data.message
                    if ($message.Length -lt 1 -or $message.Length -gt 400 -or $message -match '[`r`n`0]') { throw 'Announcement message must be 1-400 characters without control characters.' }
                    $payload.message = $message
                } elseif ($operation -in @('kick','ban','unban')) {
                    $userId = [string]$data.userid
                    if ($userId.Length -lt 1 -or $userId.Length -gt 256 -or $userId -match '[`r`n`0]') { throw 'Player ID must be 1-256 characters without control characters.' }
                    if ($userId -notmatch '^[A-Za-z0-9_.:-]+$') { throw 'Player ID contains unsupported characters.' }
                    $payload.userid = $userId
                    if ($operation -in @('kick','ban') -and $data.ContainsKey('message')) {
                        $message = [string]$data.message
                        if ($message.Length -gt 400 -or $message -match '[`r`n`0]') { throw 'Player message must be at most 400 characters without control characters.' }
                        $payload.message = $message
                    }
                } elseif ($operation -eq 'shutdown') {
                    $waittime = 30
                    if ($data.ContainsKey('waittime')) { $waittime = [int]$data.waittime }
                    if ($waittime -lt 0 -or $waittime -gt 600) { throw 'Shutdown waittime must be between 0 and 600 seconds.' }
                    $message = if ($data.ContainsKey('message')) { [string]$data.message } else { 'Server shutdown requested by the local console.' }
                    if ($message.Length -gt 400 -or $message -match '[`r`n`0]') { throw 'Shutdown message must be at most 400 characters without control characters.' }
                    $payload.waittime = $waittime
                    $payload.message = $message
                }
            } catch {
                $res.StatusCode = 400
                Send-Json $res @{ ok = $false; code = 'invalid-management-request'; error = $_.Exception.Message }
                continue
            }
            $result = Invoke-RuntimeManagementOperation -Operation $operation -Payload $payload
            Write-PanelEvent $(if ($result.ok) { 'INFO' } else { 'ERROR' }) "REST management operation completed: operation=$operation; runtime=$(Get-ActiveRuntime); ok=$($result.ok)."
            if (-not $result.ok -and $result.code -in @('rest-disabled','management-unavailable')) { $res.StatusCode = 409 }
            Send-Json $res $result
        }
        elseif ($method -eq "POST" -and $path -eq "/api/rcon") {
            $managementConfig = Get-ManagementEndpointConfig -ProjectDirectory $projectDir
            if (-not $managementConfig.legacyRconEnabled) {
                $res.StatusCode = 410
                Send-Json $res @{ ok = $false; code = 'legacy-rcon-disabled'; error = 'Legacy RCON is disabled. Use the REST management operations.' }
                continue
            }
            try {
                $data = Read-JsonBody $req
                if (-not ($data -is [System.Collections.IDictionary]) -or -not $data.ContainsKey("cmd")) {
                    throw "JSON body must contain cmd."
                }
                if ($data["cmd"] -isnot [string]) {
                    throw "cmd must be a string."
                }
            } catch {
                $res.StatusCode = 400
                Send-Json $res @{ ok = $false; error = $_.Exception.Message }
                continue
            }
            $result = Invoke-Rcon $data.cmd
            # Commands can contain player identifiers or message text. Keep
            # only the verb in the local operational log; the browser already
            # displays the full command in its ephemeral terminal output.
            $commandVerb = (([string]$data.cmd).Trim() -split '\s+', 2)[0]
            if (-not $commandVerb) { $commandVerb = 'empty' }
            elseif ($commandVerb -notmatch '^[A-Za-z][A-Za-z0-9_-]{0,63}$') { $commandVerb = 'custom' }
            else { $commandVerb = $commandVerb.ToLowerInvariant() }
            Write-PanelEvent $(if ($result.ok) { "INFO" } else { "ERROR" }) "RCON command executed: runtime=$(Get-ActiveRuntime); verb=$commandVerb; ok=$($result.ok)."
            Send-Json $res $result
        }
        elseif ($method -eq "POST" -and $path -eq "/api/backup") {
            $result = Invoke-RuntimeBackupAction
            Write-PanelEvent $(if ($result.ok) { "INFO" } else { "ERROR" }) "Manual backup requested (runtime=$(Get-ActiveRuntime)); ok=$($result.ok)."
            Clear-DashboardCache
            Send-Json $res $result
        }
        elseif ($method -eq "GET" -and $path -eq "/api/backups") {
            Send-Json $res (Get-BackupList)
        }
        elseif ($method -eq "GET" -and $path -eq "/api/backups/download") {
            $backupName = [string]$req.QueryString["name"]
            if ($backupName -notmatch "^[A-Za-z0-9._-]+\.tar\.gz$" -or $backupName.Contains("..") -or $backupName.Contains("/") -or $backupName.Contains("\")) {
                $res.StatusCode = 400
                Send-Json $res @{ ok = $false; error = "Invalid backup name." }
                continue
            }
            $backupPath = Join-Path $backupDir $backupName
            $fullBackupPath = [System.IO.Path]::GetFullPath($backupPath)
            $fullBackupDir = [System.IO.Path]::GetFullPath($backupDir)
            if (-not $fullBackupPath.StartsWith($fullBackupDir, [System.StringComparison]::OrdinalIgnoreCase)) {
                $res.StatusCode = 400
                Send-Json $res @{ ok = $false; error = "Path traversal denied." }
                continue
            }
            if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
                $res.StatusCode = 404
                Send-Json $res @{ ok = $false; error = "Backup not found." }
                continue
            }
            Write-PanelEvent "INFO" "Backup download requested: $backupName"
            Send-FileDownload $res $backupPath $backupName "application/gzip"
        }
        elseif ($method -eq "GET" -and $path -eq "/api/mods") {
            Send-Json $res (Invoke-ModManagerAction "Status")
        }
        elseif ($method -eq "GET" -and $path -eq "/api/player-times") {
            $view = Get-PlayerTimesView
            Send-Json $res @{
                ok = $true
                players = $view.players
                lastUpdated = $view.lastUpdated
                lastObservedAt = $view.lastObservedAt
                runtime = $view.runtime
                observationState = $view.observationState
                observationAgeSeconds = $view.observationAgeSeconds
                staleAfterSeconds = $view.staleAfterSeconds
                error = $view.error
            }
        }
        elseif ($method -eq "POST" -and $path -eq "/api/mods/check") {
            Send-Json $res (Invoke-ModManagerAction "Check")
        }
        elseif ($method -eq "POST" -and $path -eq "/api/mods/sync") {
            Send-Json $res (Invoke-ModManagerAction "Sync")
        }
        elseif ($method -eq "GET" -and $path -eq "/api/runtime") {
            Send-Json $res (Get-RuntimeStateInfo)
        }
        elseif ($method -eq "POST" -and $path -eq "/api/runtime/switch") {
            try {
                $data = Read-JsonBody $req
                if (-not ($data -is [System.Collections.IDictionary]) -or -not $data.ContainsKey("to")) {
                    throw "JSON body must contain 'to' (docker|windows)."
                }
                $target = [string]$data.to
                if ($target -notin @("docker","windows")) {
                    throw "Runtime target must be 'docker' or 'windows'."
                }
            } catch {
                $res.StatusCode = 400
                Send-Json $res @{ ok = $false; error = $_.Exception.Message }
                continue
            }
            if (Test-RuntimeSwitching) {
                $res.StatusCode = 409
                Send-Json $res @{ ok = $false; error = "A runtime switch is already in progress." }
                continue
            }
            $force = [bool]$data.force
            $fullSnapshot = [bool]$data.fullSnapshot
            $currentRuntime = Get-RuntimeState
            if ($currentRuntime.active -eq $target -and -not $force) {
                $res.StatusCode = 409
                Send-Json $res @{ ok = $false; code = "runtime-already-active"; active = $currentRuntime.active; error = "The requested runtime is already active. No switch task was created." }
                continue
            }
            $task = Start-RuntimeSwitchTask -To $target -Force:$force -FullSnapshot:$fullSnapshot
            Write-PanelEvent "INFO" "Runtime switch task created: id=$($task.id), to=$target, force=$force, fullSnapshot=$fullSnapshot."
            Send-Json $res @{ ok = $true; taskId = $task.id; status = $task.status }
        }
        elseif ($method -eq "POST" -and $path -eq "/api/runtime/snapshot") {
            if (Test-RuntimeSwitching) {
                $res.StatusCode = 409
                Send-Json $res @{ ok = $false; error = "A runtime switch is already in progress." }
                continue
            }
            try {
                $data = Read-JsonBody $req
            } catch { $data = @{} }
            $snapType = if ($data -and ($data -is [System.Collections.IDictionary]) -and $data.ContainsKey("type")) {
                [string]$data.type
            } else { "Light" }
            if ($snapType -notin @("Light","Full")) {
                $res.StatusCode = 400
                Send-Json $res @{ ok = $false; error = "Snapshot type must be 'Light' or 'Full'." }
                continue
            }
            $task = Invoke-SnapshotCreate -Type $snapType
            Write-PanelEvent "INFO" "Manual snapshot task created: id=$($task.id), type=$snapType."
            Send-Json $res @{ ok = $true; taskId = $task.id; status = $task.status }
        }
        elseif ($method -eq "POST" -and $path -eq "/api/runtime/restore") {
            if (Test-RuntimeSwitching) {
                $res.StatusCode = 409
                Send-Json $res @{ ok = $false; error = "A runtime switch is already in progress." }
                continue
            }
            try {
                $data = Read-JsonBody $req
                if (-not ($data -is [System.Collections.IDictionary]) -or -not $data.ContainsKey("name")) {
                    throw "JSON body must contain 'name'."
                }
                $snapName = [string]$data.name
                if ($snapName -notmatch "^[0-9A-Za-z._-]+\.tar\.gz$") {
                    throw "Invalid snapshot name."
                }
            } catch {
                $res.StatusCode = 400
                Send-Json $res @{ ok = $false; error = $_.Exception.Message }
                continue
            }
            $active = Get-ActiveRuntime
            if ($active -ne 'none' -and -not [bool]$data.force) {
                $res.StatusCode = 409
                Send-Json $res @{ ok = $false; error = "Runtime is active ($active); stop it before restore or pass force=true." }
                continue
            }
            $task = Start-RuntimeRestoreTask -Name $snapName -Force:([bool]$data.force)
            Write-PanelEvent "WARN" "Snapshot restore task created: id=$($task.id), snapshot=$snapName."
            Send-Json $res @{ ok = $true; taskId = $task.id; status = $task.status }
        }
        elseif ($method -eq "GET" -and $path -eq "/api/runtime/task") {
            $taskId = [string]$req.QueryString["id"]
            if (-not $taskId) {
                $res.StatusCode = 400
                Send-Json $res @{ ok = $false; error = "Missing 'id' query parameter." }
                continue
            }
            $task = Get-RuntimeTask -TaskId $taskId
            if (-not $task) {
                $res.StatusCode = 404
                Send-Json $res @{ ok = $false; error = "Task not found." }
                continue
            }
            Send-Json $res $task
        }
        elseif ($method -eq "GET" -and $path -eq "/api/snapshots") {
            Send-Json $res (Get-SnapshotList)
        }
        else {
            $res.StatusCode = 404
            Send-Text $res "404 Not Found"
        }
    } catch {
        Write-PanelEvent "ERROR" "HTTP $method $path failed: $($_.Exception.Message)"
        try {
            if ($res.StatusCode -eq 200) { $res.StatusCode = 500 }
            Send-Json $res @{ ok = $false; error = $_.Exception.Message }
        } catch { }
    } finally {
        $res.Close()
    }
}
} finally {
    if ($null -ne $listener) {
        try { $listener.Stop() } catch { }
        try { $listener.Close() } catch { }
    }
    if (Test-Path -LiteralPath $pidFile) {
        $recordedPid = [System.IO.File]::ReadAllText($pidFile).Trim()
        if ($recordedPid -eq [string]$PID) { Remove-Item -LiteralPath $pidFile -Force }
    }
    if ($null -ne $port -and (Test-Path -LiteralPath $portFile)) {
        $recordedPort = [System.IO.File]::ReadAllText($portFile).Trim()
        if ($recordedPort -eq [string]$port) { Remove-Item -LiteralPath $portFile -Force }
    }
    try { $panelMutex.ReleaseMutex() } catch { }
    $panelMutex.Dispose()
}
