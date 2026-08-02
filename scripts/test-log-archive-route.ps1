[CmdletBinding()]
param()

# Source-level regression for the direct log-archive route. The route can be
# called outside Get-Dashboard, so Get-LogArchiveList must load its own env
# values instead of relying on a caller's local scope.
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot

function Assert-LogArchiveRoute {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "LOG_ARCHIVE_ROUTE_FAILED: $Message" }
}

$source = [System.IO.File]::ReadAllText((Join-Path $projectDir 'settings-panel.ps1'))
$start = $source.IndexOf('function Get-LogArchiveList()')
$end = $source.IndexOf('function Invoke-LogArchiveRefresh()', $start)
Assert-LogArchiveRoute ($start -ge 0 -and $end -gt $start) 'could not isolate Get-LogArchiveList.'
$functionText = $source.Substring($start, $end - $start)

$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('palworld-log-archive-' + [guid]::NewGuid().ToString('N'))
try {
    $logArchiveDir = Join-Path $fixtureRoot 'data\log-archive'
    New-Item -ItemType Directory -Path $logArchiveDir -Force | Out-Null
    $envFile = Join-Path $fixtureRoot '.env'
    [System.IO.File]::WriteAllText($envFile, "TZ=UTC`r`n", [System.Text.UTF8Encoding]::new($false))
    $archiveName = '2026-08-03.txt'
    [System.IO.File]::WriteAllText((Join-Path $logArchiveDir $archiveName), 'fixture', [System.Text.UTF8Encoding]::new($false))
    $logCollectorPidFile = Join-Path $fixtureRoot '.daily-log-collector.pid'

    function Get-EnvVars {
        param([string]$Path)
        return @{ TZ = 'UTC' }
    }

    . ([scriptblock]::Create($functionText))
    $result = Get-LogArchiveList
    Assert-LogArchiveRoute ([bool]$result.ok) 'route result was not marked ok.'
    Assert-LogArchiveRoute ([int]$result.count -eq 1) 'archive count was not returned.'
    Assert-LogArchiveRoute ([string]$result.timezone -eq 'UTC') 'timezone was not loaded from the environment.'
    Assert-LogArchiveRoute (@($result.archives).Count -eq 1 -and [string]$result.archives[0].name -eq $archiveName) 'archive metadata was not returned.'

    Write-Output 'LOG_ARCHIVE_ROUTE=passed'
    Write-Output 'LOG_ARCHIVE_ROUTE_SCOPE=isolated-source-fixture'
    exit 0
} finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
