[CmdletBinding()]
param(
    [switch]$Once,
    [ValidateRange(10, 3600)]
    [int]$IntervalSeconds = 60,
    [datetime]$ArchiveDate = [datetime]::MinValue
)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $projectDir "docker-compose.yml"
$archiveDir = Join-Path $projectDir "data\log-archive"
$gameSourceDir = Join-Path $projectDir "data\log-sources\game"
$windowsGameSourceDir = Join-Path $projectDir "data\log-sources\windows-server"
$windowsRuntimeSourceDir = Join-Path $projectDir "data\log-sources\windows-runtime"
$panelSourceDir = Join-Path $projectDir "data\log-sources\panel"
$incidentFile = Join-Path $projectDir "data\diagnostics\incidents.jsonl"
$sakuraLogDir = "C:\ProgramData\SakuraFrpService\Logs"
$pidFile = Join-Path $projectDir ".daily-log-collector.pid"
$containerName = "palworld-server"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# Player sessions are sampled by this independent collector rather than by an
# open browser tab. A failed REST poll leaves existing sessions unchanged.
. (Join-Path $PSScriptRoot 'player-session-times.ps1')

try {
    $archiveTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById("China Standard Time")
} catch {
    $archiveTimeZone = [System.TimeZoneInfo]::Local
}

function Convert-ToArchiveDay([datetime]$Value) {
    if ($Value -eq [datetime]::MinValue) {
        return [System.TimeZoneInfo]::ConvertTime((Get-Date), $archiveTimeZone).Date
    }
    return $Value.Date
}

function Convert-DayBoundaryToUtc([datetime]$Value) {
    $unspecified = [datetime]::SpecifyKind($Value, [System.DateTimeKind]::Unspecified)
    return [System.TimeZoneInfo]::ConvertTimeToUtc($unspecified, $archiveTimeZone)
}

function Invoke-CapturedProcess([string]$FileName, [string]$Arguments, [int]$TimeoutMs = 60000) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FileName
    $psi.Arguments = $Arguments
    $psi.WorkingDirectory = $projectDir
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutMs)) {
        try { $process.Kill() } catch { }
        throw "Process timed out: $FileName"
    }
    $process.WaitForExit()
    return [ordered]@{
        ExitCode = $process.ExitCode
        Stdout = $stdoutTask.Result
        Stderr = $stderrTask.Result
    }
}

function Read-SharedLines([string]$Path) {
    $stream = New-Object System.IO.FileStream(
        $Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
    )
    $reader = New-Object System.IO.StreamReader($stream, $true)
    $result = New-Object System.Collections.Generic.List[string]
    try {
        while (-not $reader.EndOfStream) { $result.Add($reader.ReadLine()) }
    } finally {
        $reader.Dispose()
        $stream.Dispose()
    }
    return @($result)
}

function Write-AtomicLines([string]$Path, [string[]]$Lines) {
    $directory = Split-Path -Parent $Path
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
    $tempPath = "$Path.$PID.tmp"
    $backupPath = "$Path.$PID.bak"
    try {
        [System.IO.File]::WriteAllLines($tempPath, $Lines, $utf8NoBom)
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            [System.IO.File]::Replace($tempPath, $Path, $backupPath)
        } else {
            [System.IO.File]::Move($tempPath, $Path)
        }
    } finally {
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force }
        if (Test-Path -LiteralPath $backupPath) { Remove-Item -LiteralPath $backupPath -Force }
    }
}

function Add-ArchiveSection(
    [System.Collections.Generic.List[string]]$Lines,
    [string]$Title,
    [string[]]$Content
) {
    $Lines.Add("")
    $Lines.Add("================================================================================")
    $Lines.Add("[$Title] Entries: $($Content.Count)")
    $Lines.Add("================================================================================")
    if ($Content.Count -eq 0) {
        $Lines.Add("(No entries for this day)")
    } else {
        foreach ($line in $Content) { $Lines.Add([string]$line) }
    }
}

function Get-ContainerLogLines([datetime]$Day) {
    $startUtc = Convert-DayBoundaryToUtc $Day
    $endUtc = Convert-DayBoundaryToUtc $Day.AddDays(1)
    $since = $startUtc.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $until = $endUtc.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $arguments = "compose -f `"$composeFile`" logs --since `"$since`" --until `"$until`" --timestamps --no-color $containerName"
    try {
        $result = Invoke-CapturedProcess "docker.exe" $arguments 90000
        if ($result.ExitCode -ne 0) {
            return @("[COLLECTOR ERROR] Docker log query failed: $($result.Stderr.Trim())")
        }
        $normalized = New-Object System.Collections.Generic.List[string]
        foreach ($rawLine in @($result.Stdout -split "\r?\n" | Where-Object { $_ -ne "" })) {
            $line = $rawLine -replace "\x1B\[[0-9;?]*[ -/]*[@-~]", ""
            if ($line -match "^[^|]+\|\s+(\S+)\s+(.*)$") {
                try {
                    $stamp = [datetimeoffset]::Parse($matches[1])
                    $localStamp = [System.TimeZoneInfo]::ConvertTime($stamp, $archiveTimeZone)
                    $normalized.Add("[$($localStamp.ToString('yyyy-MM-dd HH:mm:ss.fff zzz'))][GAME] $($matches[2])")
                    continue
                } catch { }
            }
            $normalized.Add("[GAME] $line")
        }
        return @($normalized)
    } catch {
        return @("[COLLECTOR ERROR] Docker log query failed: $($_.Exception.Message)")
    }
}

function Get-MergedContainerLogLines([datetime]$Day) {
    $sourcePath = Join-Path $gameSourceDir "$($Day.ToString('yyyy-MM-dd')).log"
    $existing = if (Test-Path -LiteralPath $sourcePath -PathType Leaf) {
        @(Read-SharedLines $sourcePath)
    } else {
        @()
    }
    $current = @(Get-ContainerLogLines $Day)
    $seen = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::Ordinal)
    $merged = New-Object System.Collections.Generic.List[string]
    foreach ($line in @($existing) + @($current)) {
        if ($seen.Add([string]$line)) { $merged.Add([string]$line) }
    }
    Write-AtomicLines $sourcePath ([string[]]$merged)
    return @($merged)
}

function Get-SakuraLogLines([datetime]$Day) {
    if (-not (Test-Path -LiteralPath $sakuraLogDir -PathType Container)) { return @() }
    $compactDate = $Day.ToString("yyyyMMdd")
    $slashDate = $Day.ToString("yyyy/MM/dd")
    $dashDate = $Day.ToString("yyyy-MM-dd")
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($file in @(Get-ChildItem -LiteralPath $sakuraLogDir -File -ErrorAction SilentlyContinue)) {
        $isDailyFile = $file.Name -like "*$compactDate*"
        if (-not $isDailyFile -and $file.Name -ne "Update.log") { continue }
        foreach ($line in @(Read-SharedLines $file.FullName)) {
            if ($isDailyFile -or $line.Contains($slashDate) -or $line.Contains($dashDate)) {
                $result.Add("[$($file.Name)] $line")
            }
        }
    }
    return @($result)
}

function Get-PanelLogLines([datetime]$Day) {
    $path = Join-Path $panelSourceDir "$($Day.ToString('yyyy-MM-dd')).log"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @() }
    return @(Read-SharedLines $path)
}

function Get-LocalSourceLogLines([string]$SourceDir, [datetime]$Day) {
    $path = Join-Path $SourceDir "$($Day.ToString('yyyy-MM-dd')).log"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @() }
    return @(Read-SharedLines $path)
}

function Get-IncidentLines([datetime]$Day) {
    if (-not (Test-Path -LiteralPath $incidentFile -PathType Leaf)) { return @() }
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($line in @(Read-SharedLines $incidentFile)) {
        if (-not $line.Trim()) { continue }
        try {
            $entry = $line | ConvertFrom-Json
            $stampText = if ($entry.loggedAt) { [string]$entry.loggedAt } else { [string]$entry.observedAt }
            if (-not $stampText) { continue }
            $stamp = [datetimeoffset]::Parse($stampText)
            $localStamp = [System.TimeZoneInfo]::ConvertTime($stamp, $archiveTimeZone)
            if ($localStamp.Date -eq $Day.Date) { $result.Add($line) }
        } catch {
            # A malformed incident line remains in its source file for manual inspection.
        }
    }
    return @($result)
}

function Write-DailyArchive([datetime]$Day) {
    [System.IO.Directory]::CreateDirectory($archiveDir) | Out-Null
    $dayValue = $Day.Date
    $mutex = New-Object System.Threading.Mutex($false, "Local\PalworldDailyLogArchive")
    $locked = $false
    try {
        $locked = $mutex.WaitOne(30000)
        if (-not $locked) { throw "Timed out waiting for the daily archive lock." }

        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add("Palworld Server Daily Log Archive")
        $lines.Add("Date (Asia/Shanghai): $($dayValue.ToString('yyyy-MM-dd')) 00:00:00 - 24:00:00")
        $lines.Add("Generated at: $([System.TimeZoneInfo]::ConvertTime((Get-Date), $archiveTimeZone).ToString('yyyy-MM-dd HH:mm:ss zzz'))")
        $lines.Add("Sources: Docker game container / Windows native lifecycle / Windows engine best-effort output / Web Console operations / SakuraFrp service / incident journal")
        $lines.Add("Sensitive: this file may contain player names, identifiers, IP addresses, or other local data. Do not publish it directly.")

        Add-ArchiveSection $lines "GAME CONTAINER" @(Get-MergedContainerLogLines $dayValue)
        Add-ArchiveSection $lines "WINDOWS NATIVE RUNTIME" @(Get-LocalSourceLogLines $windowsRuntimeSourceDir $dayValue)
        Add-ArchiveSection $lines "WINDOWS NATIVE ENGINE (BEST-EFFORT)" @(Get-LocalSourceLogLines $windowsGameSourceDir $dayValue)
        Add-ArchiveSection $lines "WEB CONSOLE" @(Get-PanelLogLines $dayValue)
        Add-ArchiveSection $lines "SAKURAFRP" @(Get-SakuraLogLines $dayValue)
        Add-ArchiveSection $lines "INCIDENTS" @(Get-IncidentLines $dayValue)

        $archivePath = Join-Path $archiveDir "$($dayValue.ToString('yyyy-MM-dd')).txt"
        Write-AtomicLines $archivePath ([string[]]$lines)
        return $archivePath
    } finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function Update-PlayerSessionTimesSafely {
    try {
        [void](Invoke-PlayerSessionTrackingPoll)
    } catch {
        # Never stop archival or turn an unknown REST state into a disconnect.
        Write-Warning "Player-session tracking poll failed: $($_.Exception.Message)"
    }
}

if ($Once) {
    $targetDay = Convert-ToArchiveDay $ArchiveDate
    Update-PlayerSessionTimesSafely
    $writtenPath = Write-DailyArchive $targetDay
    Write-Output "ARCHIVE_PATH=$writtenPath"
    exit 0
}

if (Test-Path -LiteralPath $pidFile -PathType Leaf) {
    $existingPidText = [System.IO.File]::ReadAllText($pidFile).Trim()
    $existingPid = 0
    if ([int]::TryParse($existingPidText, [ref]$existingPid)) {
        $existing = Get-CimInstance Win32_Process -Filter "ProcessId=$existingPid" -ErrorAction SilentlyContinue
        if ($existing -and $existing.CommandLine -like "*daily-log-collector.ps1*") {
            Write-Output "COLLECTOR_ALREADY_RUNNING=$existingPid"
            exit 0
        }
    }
}

[System.IO.File]::WriteAllText($pidFile, [string]$PID, $utf8NoBom)
try {
    $currentDay = Convert-ToArchiveDay ([datetime]::MinValue)
    Update-PlayerSessionTimesSafely
    [void](Write-DailyArchive $currentDay.AddDays(-1))
    while ($true) {
        $nowDay = Convert-ToArchiveDay ([datetime]::MinValue)
        if ($nowDay -ne $currentDay) {
            [void](Write-DailyArchive $currentDay)
            $currentDay = $nowDay
        }
        Update-PlayerSessionTimesSafely
        [void](Write-DailyArchive $currentDay)
        Start-Sleep -Seconds $IntervalSeconds
    }
} finally {
    if (Test-Path -LiteralPath $pidFile -PathType Leaf) {
        $recordedPid = [System.IO.File]::ReadAllText($pidFile).Trim()
        if ($recordedPid -eq [string]$PID) { Remove-Item -LiteralPath $pidFile -Force }
    }
}
