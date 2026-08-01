# Shared, privacy-preserving player-session accounting.
#
# The tracker is called by daily-log-collector.ps1, so timing is independent
# from an open Web Console tab. This file stores only a short SHA-256-derived
# key, a display name, and aggregate timing; it never stores player IDs.

if (-not $projectDir) { $projectDir = Split-Path -Parent $PSScriptRoot }
if (-not $playerTimesFile) { $playerTimesFile = Join-Path $projectDir 'data\player-session-times.json' }

function Test-PlayerTimesKey($Dictionary, [string]$Key) {
    if ($null -eq $Dictionary) { return $false }
    if ($Dictionary -is [System.Collections.IDictionary]) { return (@($Dictionary.Keys) -contains $Key) }
    return $false
}

function Get-PlayerTimesField($Record, [string[]]$Names) {
    if ($null -eq $Record) { return $null }
    foreach ($name in $Names) {
        if ($Record -is [System.Collections.IDictionary] -and $Record.Contains($name)) {
            $value = $Record[$name]
            if ($null -ne $value -and [string]$value) { return $value }
        }
        if ($Record.PSObject.Properties.Name -contains $name) {
            $value = $Record.$name
            if ($null -ne $value -and [string]$value) { return $value }
        }
    }
    return $null
}

function Get-PlayerIdHash($UserId) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$UserId)
        $hash = $sha.ComputeHash($bytes)
        $hex = [BitConverter]::ToString($hash) -replace '-', ''
        return $hex.Substring(0, 16).ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function ConvertTo-PlayerTimesDictionary($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) {
        $dictionary = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $dictionary[[string]$key] = ConvertTo-PlayerTimesDictionary $Value[$key]
        }
        return $dictionary
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $items = New-Object System.Collections.Generic.List[object]
        foreach ($item in $Value) {
            [void]$items.Add((ConvertTo-PlayerTimesDictionary $item))
        }
        return ,$items.ToArray()
    }
    if ($Value.PSObject.Properties.Count -gt 0 -and $Value -isnot [string]) {
        $dictionary = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) {
            $dictionary[$property.Name] = ConvertTo-PlayerTimesDictionary $property.Value
        }
        return $dictionary
    }
    return $Value
}

function ConvertFrom-PlayerTimesJson([string]$Json) {
    $convertFromJson = Get-Command ConvertFrom-Json -CommandType Cmdlet -ErrorAction Stop
    if ($convertFromJson.Parameters.ContainsKey('AsHashtable')) {
        return ConvertFrom-Json -InputObject $Json -AsHashtable
    }
    return ConvertTo-PlayerTimesDictionary ($Json | ConvertFrom-Json)
}

function Get-PlayerTimesData {
    if (Test-Path -LiteralPath $playerTimesFile -PathType Leaf) {
        try {
            $data = ConvertFrom-PlayerTimesJson ([System.IO.File]::ReadAllText($playerTimesFile))
            if ($data -is [System.Collections.IDictionary]) { return $data }
        } catch {
            # Do not replace an unreadable accounting file. The next successful
            # observation leaves it intact for manual recovery.
            return $null
        }
    }
    return @{ players = @{}; lastUpdated = $null; lastObservedAt = $null; schemaVersion = 2 }
}

function Save-PlayerTimesData($Data) {
    $dir = Split-Path -Parent $playerTimesFile
    [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    $json = $Data | ConvertTo-Json -Depth 20 -Compress
    $tempPath = "$playerTimesFile.tmp.$PID"
    $backupPath = "$playerTimesFile.bak.$PID"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    try {
        [System.IO.File]::WriteAllText($tempPath, $json, $utf8NoBom)
        if (Test-Path -LiteralPath $playerTimesFile -PathType Leaf) {
            [System.IO.File]::Replace($tempPath, $playerTimesFile, $backupPath)
        } else {
            [System.IO.File]::Move($tempPath, $playerTimesFile)
        }
    } finally {
        if (Test-Path -LiteralPath $tempPath -PathType Leaf) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Convert-ToPlayerTimeArray($Value) {
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string]) -and -not ($Value -is [System.Collections.IDictionary])) {
        return @($Value | ForEach-Object { $_ })
    }
    return @($Value)
}

function Update-PlayerSessionTimes {
    param(
        [object[]]$OnlinePlayers,
        [string]$Runtime = 'unknown'
    )

    $mutex = New-Object System.Threading.Mutex($false, 'Local\PalworldPlayerSessionTimes')
    $locked = $false
    try {
        $locked = $mutex.WaitOne(15000)
        if (-not $locked) { throw 'Timed out waiting for player-session accounting lock.' }
        $now = Get-Date
        $data = Get-PlayerTimesData
        if ($null -eq $data) { throw 'Player-session accounting file is unreadable; preserved for manual recovery.' }
        if (-not (Test-PlayerTimesKey $data 'players') -or $data['players'] -isnot [System.Collections.IDictionary]) {
            $data['players'] = @{}
        }
        $players = $data['players']
        $onlineKeys = @{}

        foreach ($player in @(Convert-ToPlayerTimeArray $OnlinePlayers)) {
            if ($null -eq $player) { continue }
            # Palworld builds use different casing/names. Prefer stable IDs;
            # never fall back to a display name, which can collide or change.
            $stableId = [string](Get-PlayerTimesField $player @('playerUserId','playeruid','playerUid','userId','userid','steamId','steamid','playerId','playerid'))
            if (-not $stableId) { continue }
            $name = [string](Get-PlayerTimesField $player @('name','playerName','playername'))
            $key = Get-PlayerIdHash $stableId
            $onlineKeys[$key] = $true

            if (-not (Test-PlayerTimesKey $players $key) -or $players[$key] -isnot [System.Collections.IDictionary]) {
                $players[$key] = [ordered]@{
                    name = $name
                    totalSeconds = 0
                    currentSessionStart = $now.ToString('o')
                    sessionCount = 1
                    lastSeen = $now.ToString('o')
                }
                continue
            }

            $entry = $players[$key]
            if ($name) { $entry['name'] = $name }
            if (-not [string]$entry['currentSessionStart']) {
                $entry['currentSessionStart'] = $now.ToString('o')
                $entry['sessionCount'] = [int]$entry['sessionCount'] + 1
            }
            $entry['lastSeen'] = $now.ToString('o')
        }

        foreach ($key in @($players.Keys)) {
            $entry = $players[$key]
            if ($entry -isnot [System.Collections.IDictionary] -or $onlineKeys.ContainsKey($key)) { continue }
            $sessionStart = [string]$entry['currentSessionStart']
            if (-not $sessionStart) { continue }
            $startTime = [datetime]::MinValue
            if ([datetime]::TryParse($sessionStart, $null, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$startTime)) {
                # REST observes presence at discrete points; it cannot prove a
                # player stayed connected after the last positive sample. Close
                # at that sample (with the prior global observation as a legacy
                # fallback), rather than charging a collector outage as play.
                $endTime = $now
                foreach ($observedText in @([string]$entry['lastSeen'], [string]$data['lastObservedAt'])) {
                    $observedTime = [datetime]::MinValue
                    if (-not $observedText -or -not [datetime]::TryParse($observedText, $null, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$observedTime)) {
                        continue
                    }
                    if ($observedTime -ge $startTime) {
                        if ($observedTime -lt $endTime) { $endTime = $observedTime }
                        break
                    }
                }
                $seconds = [math]::Max(0, [int]($endTime - $startTime).TotalSeconds)
                $entry['totalSeconds'] = [int]$entry['totalSeconds'] + $seconds
            }
            $entry['currentSessionStart'] = $null
        }

        $data['schemaVersion'] = 2
        $data['players'] = $players
        $data['lastUpdated'] = $now.ToString('o')
        $data['lastObservedAt'] = $now.ToString('o')
        $data['lastObservedRuntime'] = $Runtime
        Save-PlayerTimesData $data
        return $data
    } finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function Get-PlayerTimesView {
    param(
        [ValidateRange(60, 86400)]
        [int]$StaleAfterSeconds = 180
    )

    $data = Get-PlayerTimesData
    if ($null -eq $data) {
        return [ordered]@{
            players = @()
            lastUpdated = $null
            lastObservedAt = $null
            observationState = 'unknown'
            observationAgeSeconds = $null
            staleAfterSeconds = $StaleAfterSeconds
            error = 'Player-session accounting file is unreadable.'
        }
    }
    $now = Get-Date
    $lastObservedAt = [string]$data['lastObservedAt']
    $observationAgeSeconds = $null
    $observationState = 'unknown'
    $observedAt = [datetime]::MinValue
    if ($lastObservedAt -and [datetime]::TryParse($lastObservedAt, $null, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$observedAt)) {
        $observationAgeSeconds = [math]::Max(0, [int]($now - $observedAt).TotalSeconds)
        $observationState = if ($observationAgeSeconds -le $StaleAfterSeconds) { 'fresh' } else { 'stale' }
    }
    $observationFresh = $observationState -eq 'fresh'
    $view = New-Object System.Collections.Generic.List[object]
    $source = if (Test-PlayerTimesKey $data 'players') { $data['players'] } else { @{} }
    if ($source -is [System.Collections.IDictionary]) {
        foreach ($key in $source.Keys) {
            $entry = $source[$key]
            if ($entry -isnot [System.Collections.IDictionary]) { continue }
            $currentSeconds = 0
            $isOnline = $false
            $connectionState = 'offline'
            $sessionStart = [string]$entry['currentSessionStart']
            if ($sessionStart) {
                $start = [datetime]::MinValue
                if ([datetime]::TryParse($sessionStart, $null, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$start)) {
                    if ($observationFresh) {
                        # Show only the duration confirmed by the most recent
                        # REST sample. A fresh sample still means "last observed
                        # online", not that the player is provably connected at
                        # this rendering instant.
                        $observedEnd = if ($observedAt -lt $now) { $observedAt } else { $now }
                        $currentSeconds = [math]::Max(0, [int]($observedEnd - $start).TotalSeconds)
                        $isOnline = $true
                        $connectionState = 'online'
                    } else {
                        # The last REST observation no longer proves the player
                        # is connected. Do not keep increasing the duration.
                        $connectionState = 'unknown'
                    }
                }
            }
            $view.Add([ordered]@{
                name = [string]$entry['name']
                totalSeconds = [int]$entry['totalSeconds'] + $currentSeconds
                currentSessionSeconds = $currentSeconds
                isOnline = $isOnline
                connectionState = $connectionState
                sessionCount = [int]$entry['sessionCount']
                lastSeen = [string]$entry['lastSeen']
            })
        }
    }
    return [ordered]@{
        players = @($view | Sort-Object @{ Expression = { $_.isOnline }; Descending = $true }, @{ Expression = { [int]$_.totalSeconds }; Descending = $true })
        lastUpdated = $data['lastUpdated']
        lastObservedAt = $lastObservedAt
        runtime = $data['lastObservedRuntime']
        observationState = $observationState
        observationAgeSeconds = $observationAgeSeconds
        staleAfterSeconds = $StaleAfterSeconds
    }
}

function Invoke-PlayerSessionTrackingPoll {
    if (-not (Get-Command Get-RuntimeState -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'runtime-common.ps1')
    }
    $state = Get-RuntimeState
    if ($state.switching) { return @{ ok = $false; transient = $true; detail = 'Runtime switch in progress; session state unchanged.' } }
    $runtime = [string]$state.active
    if ($runtime -eq 'none') {
        [void](Update-PlayerSessionTimes -OnlinePlayers @() -Runtime 'none')
        return @{ ok = $true; runtime = 'none'; players = 0 }
    }

    if ($runtime -eq 'docker') {
        if (-not (Get-Command Get-DockerRuntimePlayers -ErrorAction SilentlyContinue)) {
            . (Join-Path $PSScriptRoot 'docker-runtime.ps1')
        }
        $result = Get-DockerRuntimePlayers
    } elseif ($runtime -eq 'windows') {
        if (-not (Get-Command Get-WindowsRuntimePlayers -ErrorAction SilentlyContinue)) {
            . (Join-Path $PSScriptRoot 'win-runtime.ps1')
        }
        $result = Get-WindowsRuntimePlayers
    } else {
        return @{ ok = $false; transient = $false; detail = "Unknown runtime '$runtime'; session state unchanged." }
    }

    if (-not $result.ok) {
        # An unavailable management API does not prove everyone disconnected.
        return @{ ok = $false; transient = $true; runtime = $runtime; detail = [string]$result.error }
    }
    $payload = $result.players
    $records = Get-PlayerTimesField $payload @('players')
    $records = Convert-ToPlayerTimeArray $records
    [void](Update-PlayerSessionTimes -OnlinePlayers $records -Runtime $runtime)
    return @{ ok = $true; runtime = $runtime; players = $records.Count }
}
