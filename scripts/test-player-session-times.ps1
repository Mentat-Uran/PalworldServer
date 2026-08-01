[CmdletBinding()]
param()

# Disposable source-only regression test for player-session-times.ps1.
# It never starts, stops, or contacts either Palworld runtime, and never reads
# or writes the live data\player-session-times.json file.

$ErrorActionPreference = 'Stop'
$sourceScript = Join-Path $PSScriptRoot 'player-session-times.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("Palworld-player-times-" + [guid]::NewGuid().ToString('N'))
$projectDir = $testRoot
$playerTimesFile = Join-Path $testRoot 'data\player-session-times.json'

function Assert-SessionTest {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "PLAYER_SESSION_TIMES_TEST_FAILED: $Message" }
}

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    . $sourceScript

    # A new online player creates one privacy-preserving record.
    $first = Update-PlayerSessionTimes -Runtime 'docker' -OnlinePlayers @(
        [pscustomobject]@{ playerUserId = 'synthetic-player-a'; name = 'Synthetic Player A' }
    )
    $firstPlayers = $first['players']
    Assert-SessionTest -Condition ($firstPlayers.Count -eq 1) -Message 'new player was not recorded'
    $firstKey = @($firstPlayers.Keys)[0]
    Assert-SessionTest -Condition ($firstKey -match '^[0-9a-f]{16}$') -Message 'stored player key is not a short hash'
    Assert-SessionTest -Condition ([bool]$firstPlayers[$firstKey]['currentSessionStart']) -Message 'online session has no start time'
    $freshView = Get-PlayerTimesView -StaleAfterSeconds 60
    Assert-SessionTest -Condition ($freshView.observationState -eq 'fresh') -Message 'new observation is not fresh'
    Assert-SessionTest -Condition ([bool]$freshView.players[0].isOnline) -Message 'fresh open session is not online'

    # A dead collector must never turn an old open session into a growing
    # online duration. It is explicitly unknown until the next REST sample.
    $first['lastObservedAt'] = (Get-Date).AddSeconds(-61).ToString('o')
    Save-PlayerTimesData $first
    $staleView = Get-PlayerTimesView -StaleAfterSeconds 60
    Assert-SessionTest -Condition ($staleView.observationState -eq 'stale') -Message 'old observation is not stale'
    Assert-SessionTest -Condition ($staleView.players[0].connectionState -eq 'unknown') -Message 'stale open session was not marked unknown'
    Assert-SessionTest -Condition (-not [bool]$staleView.players[0].isOnline -and [int]$staleView.players[0].currentSessionSeconds -eq 0) -Message 'stale session kept accumulating as online'

    # Simulate a collector gap. An offline observation must close at the last
    # positive player sample, not count the unobserved period as play time.
    $sampleStart = (Get-Date).AddSeconds(-65)
    $sampleEnd = $sampleStart.AddSeconds(5)
    $firstPlayers[$firstKey]['currentSessionStart'] = $sampleStart.ToString('o')
    $firstPlayers[$firstKey]['lastSeen'] = $sampleEnd.ToString('o')
    $first['lastObservedAt'] = $sampleEnd.ToString('o')
    Save-PlayerTimesData $first
    $offline = Update-PlayerSessionTimes -Runtime 'docker' -OnlinePlayers @()
    $offlineEntry = $offline['players'][$firstKey]
    Assert-SessionTest -Condition (-not [bool]$offlineEntry['currentSessionStart']) -Message 'offline player still has an active session'
    Assert-SessionTest -Condition ([int]$offlineEntry['totalSeconds'] -ge 5 -and [int]$offlineEntry['totalSeconds'] -le 6) -Message 'offline session was not capped at the last positive sample'

    # The alternative field spelling is accepted; a display name change does
    # not create a second identity. Records without any stable ID are ignored.
    $reconnectingPlayer = [pscustomobject]@{ playeruid = 'synthetic-player-a'; name = 'Synthetic Player A2' }
    $missingIdPlayer = [pscustomobject]@{ name = 'Player With No Stable Id' }
    $again = Update-PlayerSessionTimes -Runtime 'windows' -OnlinePlayers @($reconnectingPlayer; $missingIdPlayer)
    $againPlayers = $again['players']
    Assert-SessionTest -Condition ($againPlayers.Count -eq 1) -Message 'unstable display name created a player record'
    $againEntry = $again['players'][$firstKey]
    Assert-SessionTest -Condition ([int]$againEntry['sessionCount'] -eq 2) -Message 'reconnect did not increment the session count'
    Assert-SessionTest -Condition ($againEntry['name'] -eq 'Synthetic Player A2') -Message 'latest display name was not retained'
    Assert-SessionTest -Condition ($again['lastObservedRuntime'] -eq 'windows') -Message 'runtime observation was not retained'

    # A fresh display must use its most recent observation rather than growing
    # into the interval before the next collector poll.
    $displayStart = (Get-Date).AddSeconds(-65)
    $displayObserved = $displayStart.AddSeconds(5)
    $againEntry['currentSessionStart'] = $displayStart.ToString('o')
    $againEntry['lastSeen'] = $displayObserved.ToString('o')
    $again['lastObservedAt'] = $displayObserved.ToString('o')
    Save-PlayerTimesData $again
    $observedView = Get-PlayerTimesView
    Assert-SessionTest -Condition ([bool]$observedView.players[0].isOnline) -Message 'fresh sampled session is not marked online'
    Assert-SessionTest -Condition ([int]$observedView.players[0].currentSessionSeconds -ge 5 -and [int]$observedView.players[0].currentSessionSeconds -le 6) -Message 'fresh session display grew beyond the last observation'

    $raw = [System.IO.File]::ReadAllText($playerTimesFile)
    Assert-SessionTest -Condition ($raw.IndexOf('synthetic-player-a', [System.StringComparison]::Ordinal) -lt 0) -Message 'raw stable ID was persisted'
    Assert-SessionTest -Condition ($raw.IndexOf('Player With No Stable Id', [System.StringComparison]::Ordinal) -lt 0) -Message 'unstable display name was persisted'

    $view = Get-PlayerTimesView
    Assert-SessionTest -Condition (@($view.players).Count -eq 1) -Message 'read view does not return the retained record'
    Assert-SessionTest -Condition ([bool]$view.players[0].isOnline) -Message 'read view does not mark the reopened session online'
    Write-Output 'PLAYER_SESSION_TIMES_TEST=passed'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
