[CmdletBinding()]
param()

# Disposable regression for per-project instance identity. It validates the
# names and creates two independent runtime mutexes; it never starts a server,
# changes the live environment, or contacts Docker.
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'management-api.ps1')

function Assert-InstanceIsolation {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "INSTANCE_ISOLATION_FAILED: $Message" }
}

$suffix = [guid]::NewGuid().ToString('N').Substring(0, 8)
$environmentA = @{ PROJECT_INSTANCE_ID = "palworld-isolation-a-$suffix" }
$environmentB = @{ PROJECT_INSTANCE_ID = "palworld-isolation-b-$suffix" }
$containerA = Get-ManagementContainerName -ProjectDirectory $projectDir -Environment $environmentA
$containerB = Get-ManagementContainerName -ProjectDirectory $projectDir -Environment $environmentB
$mutexNameA = Get-ManagementMutexName -ProjectDirectory $projectDir -Environment $environmentA
$mutexNameB = Get-ManagementMutexName -ProjectDirectory $projectDir -Environment $environmentB

Assert-InstanceIsolation ($containerA -ne $containerB) 'Two project identities must produce different container names.'
Assert-InstanceIsolation ($mutexNameA -ne $mutexNameB) 'Two project identities must produce different mutex names.'
Assert-InstanceIsolation ($mutexNameA -match [regex]::Escape($containerA)) 'Mutex A must be scoped to container A.'
Assert-InstanceIsolation ($mutexNameB -match [regex]::Escape($containerB)) 'Mutex B must be scoped to container B.'

$compose = Get-Content -LiteralPath (Join-Path $projectDir 'docker-compose.yml') -Raw -Encoding utf8
Assert-InstanceIsolation ($compose -match 'container_name:\s*\$\{PROJECT_INSTANCE_ID:-palworld-server\}') 'Compose must interpolate PROJECT_INSTANCE_ID.'

$mutexA = $null
$mutexB = $null
$heldA = $false
$heldB = $false
try {
    $mutexA = New-Object System.Threading.Mutex($false, $mutexNameA)
    $mutexB = New-Object System.Threading.Mutex($false, $mutexNameB)
    $heldA = $mutexA.WaitOne(1000)
    $heldB = $mutexB.WaitOne(1000)
    Assert-InstanceIsolation $heldA 'Instance A mutex could not be acquired.'
    Assert-InstanceIsolation $heldB 'Instance B mutex could not be acquired while A was held.'
} finally {
    if ($heldB) { $mutexB.ReleaseMutex() }
    if ($heldA) { $mutexA.ReleaseMutex() }
    if ($mutexB) { $mutexB.Dispose() }
    if ($mutexA) { $mutexA.Dispose() }
}

Write-Output 'INSTANCE_ISOLATION=passed'
Write-Output 'INSTANCE_ISOLATION_SCOPE=temporary-mutex-only'
