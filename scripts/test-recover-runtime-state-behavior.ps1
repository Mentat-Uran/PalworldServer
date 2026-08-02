[CmdletBinding()]
param()

# Disposable regression for stale switching recovery. The production scripts
# are copied under a unique temporary project root; no live runtime state,
# save, process, port, or Docker container is changed by this test.
$ErrorActionPreference = 'Stop'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('Palworld-recover-state-' + [guid]::NewGuid().ToString('N'))
$scriptsDir = Join-Path $testRoot 'scripts'
$dataDir = Join-Path $testRoot 'data'
$statePath = Join-Path $dataDir 'runtime.state'
$fakeBin = Join-Path $testRoot 'fake-bin'
$originalPath = $env:PATH

function Assert-RecoverBehavior {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "RECOVER_RUNTIME_STATE_BEHAVIOR_FAILED: $Message" }
}

function Write-TestUtf8 {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}

try {
    New-Item -ItemType Directory -Path $scriptsDir, $fakeBin -Force | Out-Null
    foreach ($name in @('runtime-common.ps1', 'management-api.ps1', 'recover-runtime-state.ps1')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $scriptsDir $name) -Force
    }

    # Make the copied recovery script observe no real Docker installation or
    # container. cmd.exe is only a harmless command shim and receives the
    # inspect arguments, which makes docker inspection fail closed.
    $cmdPath = Join-Path $env:WINDIR 'System32\cmd.exe'
    Copy-Item -LiteralPath $cmdPath -Destination (Join-Path $fakeBin 'docker.exe') -Force
    $env:PATH = "$fakeBin;$originalPath"

    $staleState = [ordered]@{
        active = 'none'
        pid = $null
        startedAt = $null
        version = $null
        switching = $true
        lastSwitchAt = (Get-Date).AddMinutes(-10).ToString('o')
        lastSwitchFrom = 'docker'
        lastSwitchTo = 'windows'
    } | ConvertTo-Json -Compress
    Write-TestUtf8 -Path $statePath -Text $staleState
    Write-TestUtf8 -Path (Join-Path $dataDir 'Pal\Saved\SaveGames\0\fixture\Level.sav') -Text 'fixture'

    $hostCommand = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if (-not $hostCommand) { $hostCommand = Get-Command pwsh.exe -ErrorAction SilentlyContinue }
    Assert-RecoverBehavior ($null -ne $hostCommand) 'no PowerShell host is available.'

    & $hostCommand.Source -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsDir 'recover-runtime-state.ps1') -Quiet
    Assert-RecoverBehavior ($LASTEXITCODE -eq 0) 'recovery process did not complete successfully.'

    $recovered = [System.IO.File]::ReadAllText($statePath) | ConvertFrom-Json
    Assert-RecoverBehavior ($recovered.active -eq 'none') 'recovery changed the detected inactive runtime.'
    Assert-RecoverBehavior (-not [bool]$recovered.switching) 'stale switching=true was not cleared.'

    Write-Output 'RECOVER_RUNTIME_STATE_BEHAVIOR=passed'
    Write-Output 'RECOVER_RUNTIME_STATE_BEHAVIOR_SCOPE=temporary-state-only'
    exit 0
} finally {
    $env:PATH = $originalPath
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
