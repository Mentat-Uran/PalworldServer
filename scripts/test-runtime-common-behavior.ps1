[CmdletBinding()]
param()

# Disposable behavioral regression for runtime-common.ps1. The source file is
# copied under a unique temporary project root before it is dot-sourced, so the
# test never reads or writes the live data directory and never starts, stops,
# saves, switches, restores, or contacts a Palworld runtime.
$ErrorActionPreference = 'Stop'
$sourceScript = Join-Path $PSScriptRoot 'runtime-common.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("Palworld-runtime-common-" + [guid]::NewGuid().ToString('N'))
$copiedScriptsDir = Join-Path $testRoot 'scripts'
$copiedCommon = Join-Path $copiedScriptsDir 'runtime-common.ps1'
$stateFile = Join-Path $testRoot 'data\runtime.state'
$manifestFile = Join-Path $testRoot 'mods\manifest.json'
$testMutexName = 'Local\PalworldRuntimeBehavior-' + [guid]::NewGuid().ToString('N')
$mutex = $null

function Assert-RuntimeCommonBehavior {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw "RUNTIME_COMMON_BEHAVIOR_FAILED: $Message"
    }
}

function Write-TestUtf8 {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

function Read-TestJson {
    param([string]$Path)
    return ([System.IO.File]::ReadAllText($Path) | ConvertFrom-Json)
}

try {
    Assert-RuntimeCommonBehavior (Test-Path -LiteralPath $sourceScript -PathType Leaf) 'runtime-common.ps1 is missing.'
    New-Item -ItemType Directory -Path $copiedScriptsDir -Force | Out-Null
    Copy-Item -LiteralPath $sourceScript -Destination $copiedCommon -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'management-api.ps1') -Destination (Join-Path $copiedScriptsDir 'management-api.ps1') -Force

    # Seed state before dot-sourcing so runtime-common's bootstrap path has no
    # reason to inspect Docker. Every write below remains under testRoot.
    $seedState = [ordered]@{
        active         = 'none'
        pid            = $null
        startedAt      = $null
        version        = $null
        switching      = $false
        lastSwitchAt   = $null
        lastSwitchFrom = $null
        lastSwitchTo   = $null
    } | ConvertTo-Json -Compress
    Write-TestUtf8 -Path $stateFile -Text $seedState

    $seedManifest = [ordered]@{
        schemaVersion  = 1
        managerEnabled = $false
        runtime        = 'linux-docker'
        mods           = @()
    } | ConvertTo-Json -Depth 5 -Compress
    Write-TestUtf8 -Path $manifestFile -Text $seedManifest

    . $copiedCommon

    $initial = Get-RuntimeState
    Assert-RuntimeCommonBehavior ($initial.active -eq 'none') 'seed state did not load as inactive.'
    Assert-RuntimeCommonBehavior (-not [bool]$initial.switching) 'seed state unexpectedly reports switching.'

    Update-RuntimeState -Active 'windows' -PidValue 4242 -StartedAt '2026-07-31T00:00:00+08:00' -Version 'test-version' -Switching $true -LastSwitchAt '2026-07-31T00:00:00+08:00' -LastSwitchFrom 'docker' -LastSwitchTo 'windows'
    $updated = Read-TestJson -Path $stateFile
    Assert-RuntimeCommonBehavior ($updated.active -eq 'windows') 'atomic state update did not persist active runtime.'
    Assert-RuntimeCommonBehavior ([int]$updated.pid -eq 4242) 'atomic state update did not persist PID.'
    Assert-RuntimeCommonBehavior ([bool]$updated.switching) 'atomic state update did not persist switching state.'
    Assert-RuntimeCommonBehavior ($updated.lastSwitchFrom -eq 'docker' -and $updated.lastSwitchTo -eq 'windows') 'atomic state update did not retain switch direction.'

    Update-RuntimeState -Switching $false
    $partial = Read-TestJson -Path $stateFile
    Assert-RuntimeCommonBehavior ($partial.active -eq 'windows' -and [int]$partial.pid -eq 4242) 'partial update unexpectedly discarded retained state.'
    Assert-RuntimeCommonBehavior (-not [bool]$partial.switching) 'partial update did not change switching state.'

    Update-RuntimeState -Switching $true -LastSwitchAt ((Get-Date).AddMinutes(-6).ToString('o'))
    $stuckSwitching = Test-RuntimeSwitching 3>$null
    Assert-RuntimeCommonBehavior (-not $stuckSwitching) 'stuck switching state was not reset.'
    $stuckReset = Read-TestJson -Path $stateFile
    Assert-RuntimeCommonBehavior (-not [bool]$stuckReset.switching) 'stuck switching reset was not persisted.'
    $incidentPath = Join-Path $testRoot 'data\diagnostics\incidents.jsonl'
    Assert-RuntimeCommonBehavior (Test-Path -LiteralPath $incidentPath -PathType Leaf) 'stuck switching reset did not write an incident.'
    Assert-RuntimeCommonBehavior ((Get-Content -LiteralPath $incidentPath -Raw) -match '"type":"switch-stuck"') 'stuck-switch incident type is missing.'

    Write-TestUtf8 -Path $stateFile -Text '{invalid-json'
    $invalid = Get-RuntimeState 3>$null
    Assert-RuntimeCommonBehavior ($invalid.active -eq 'unknown') 'malformed state did not fail closed as unknown.'

    Update-RuntimeState -Active 'none' -PidValue $null -StartedAt $null -Version $null -Switching $false -LastSwitchAt $null -LastSwitchFrom $null -LastSwitchTo $null 3>$null
    Sync-ModManifestRuntime -Runtime windows
    $windowsManifest = Read-TestJson -Path $manifestFile
    Assert-RuntimeCommonBehavior ($windowsManifest.runtime -eq 'windows-dedicated') 'manifest runtime did not switch to windows-dedicated.'
    Assert-RuntimeCommonBehavior (-not [bool]$windowsManifest.managerEnabled) 'empty Mod manifest was enabled automatically.'
    Sync-ModManifestRuntime -Runtime docker
    $dockerManifest = Read-TestJson -Path $manifestFile
    Assert-RuntimeCommonBehavior ($dockerManifest.runtime -eq 'linux-docker') 'manifest runtime did not switch back to linux-docker.'
    Assert-RuntimeCommonBehavior (-not [bool]$dockerManifest.managerEnabled) 'Docker manifest unexpectedly enables Mod management.'

    Write-Incident -Level 'WARN' -Type 'mask-test' -Message 'token=not-for-output password=also-not-for-output 10.0.0.42'
    $maskedLine = Get-Content -LiteralPath $incidentPath -Tail 1
    Assert-RuntimeCommonBehavior ($maskedLine -notmatch 'not-for-output|also-not-for-output|10\.0\.0\.42') 'incident masking leaked sensitive test text.'
    $maskedEntry = $maskedLine | ConvertFrom-Json
    Assert-RuntimeCommonBehavior ($maskedEntry.message -match 'token=<masked>|password=<masked>') 'incident masking did not mark sensitive fields.'

    $hostCommand = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if (-not $hostCommand) { $hostCommand = Get-Command pwsh.exe -ErrorAction SilentlyContinue }
    Assert-RuntimeCommonBehavior ($null -ne $hostCommand) 'no PowerShell host is available for the mutex contention probe.'
    $childScript = Join-Path $testRoot 'mutex-child.ps1'
    $childBody = @'
param([string]$CommonPath, [string]$MutexName)
. $CommonPath
try {
    $childMutex = Acquire-RuntimeMutex -TimeoutMs 250 -MutexName $MutexName
    try {
        Write-Error 'Child acquired a mutex that the parent holds.'
        exit 2
    } finally {
        $childMutex.ReleaseMutex()
        $childMutex.Dispose()
    }
} catch {
    if ($_.Exception.Message -match 'Failed to acquire runtime mutex') { exit 0 }
    Write-Error $_
    exit 3
}
'@
    Write-TestUtf8 -Path $childScript -Text $childBody

    $mutex = Acquire-RuntimeMutex -TimeoutMs 1000 -MutexName $testMutexName
    & $hostCommand.Source -NoProfile -ExecutionPolicy Bypass -File $childScript -CommonPath $copiedCommon -MutexName $testMutexName
    Assert-RuntimeCommonBehavior ($LASTEXITCODE -eq 0) 'a second process acquired or could not correctly contend for the runtime mutex.'
    $mutex.ReleaseMutex()
    $mutex.Dispose()
    $mutex = $null

    $afterRelease = Acquire-RuntimeMutex -TimeoutMs 1000 -MutexName $testMutexName
    try {
        Assert-RuntimeCommonBehavior ($null -ne $afterRelease) 'runtime mutex was not available after release.'
    } finally {
        if ($afterRelease) {
            $afterRelease.ReleaseMutex()
            $afterRelease.Dispose()
        }
    }

    Write-Output 'RUNTIME_COMMON_BEHAVIOR=passed'
    Write-Output 'RUNTIME_COMMON_BEHAVIOR_SCOPE=temporary-state-only'
    exit 0
}
finally {
    if ($mutex) {
        try { $mutex.ReleaseMutex() } catch { }
        $mutex.Dispose()
    }
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
