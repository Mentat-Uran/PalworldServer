# Optional UDP tunnel provider lifecycle. Default provider is none.
# Only processes started by this project are stopped.

param(
    [ValidateSet('Status','Start','Stop')][string]$Action = 'Status',
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$pidFile = Join-Path $projectDir 'data\diagnostics\tunnel-provider.pid'
$envPath = Join-Path $projectDir '.env'
. (Join-Path $PSScriptRoot 'tunnel-provider-catalog.ps1')

function Read-ProviderEnv {
    $values = @{}
    if (-not (Test-Path -LiteralPath $envPath -PathType Leaf)) { return $values }
    foreach ($line in [System.IO.File]::ReadAllLines($envPath)) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
        $index = $trimmed.IndexOf('=')
        if ($index -le 0) { continue }
        $key = $trimmed.Substring(0, $index).Trim()
        $value = $trimmed.Substring($index + 1).Trim()
        if ($value.Length -ge 2 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'")))) { $value = $value.Substring(1, $value.Length - 2) }
        $values[$key] = $value
    }
    return $values
}

function Get-ProviderResult {
    param([hashtable]$Value)
    if ($Json) { $Value | ConvertTo-Json -Compress -Depth 5 } else { $Value }
}

function Find-ProviderExecutable([hashtable]$Environment) {
    if ($Environment['TUNNEL_EXECUTABLE']) { return [string]$Environment['TUNNEL_EXECUTABLE'] }
    $definition = Get-TunnelProviderDefinition -Provider ([string]$Environment['TUNNEL_PROVIDER']) -ProjectDirectory $projectDir
    if ($definition) {
        foreach ($name in @($definition.autoDiscoverExecutables)) {
            $command = Get-Command $name -ErrorAction SilentlyContinue
            if ($command) { return $command.Source }
        }
    }
    return $null
}

$environment = Read-ProviderEnv
$provider = if ($environment['TUNNEL_PROVIDER']) { [string]$environment['TUNNEL_PROVIDER'] } else { 'none' }
$providerDefinition = Get-TunnelProviderDefinition -Provider $provider -ProjectDirectory $projectDir
if (-not $providerDefinition) { throw "Unsupported tunnel provider: $provider" }

$result = [ordered]@{ ok = $true; provider = $provider; state = 'disabled'; pid = $null; detail = $null }
if ($provider -eq 'none') {
    $result.detail = 'No tunnel provider is configured. The project will not start or stop a third-party tunnel.'
    Get-ProviderResult $result
    exit 0
}

if ($Action -eq 'Status') {
    if (-not (Test-Path -LiteralPath $pidFile -PathType Leaf)) { $result.state = 'not-started'; Get-ProviderResult $result; exit 0 }
    $pidValue = 0
    [void][int]::TryParse((Get-Content -LiteralPath $pidFile -Raw).Trim(), [ref]$pidValue)
    $process = if ($pidValue -gt 0) { Get-Process -Id $pidValue -ErrorAction SilentlyContinue } else { $null }
    if ($process) { $result.state = 'running'; $result.pid = $pidValue } else { $result.state = 'stale-marker'; Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue }
    Get-ProviderResult $result
    exit 0
}

if ($Action -eq 'Stop') {
    if (-not (Test-Path -LiteralPath $pidFile -PathType Leaf)) { $result.state = 'not-started'; Get-ProviderResult $result; exit 0 }
    $pidValue = 0
    [void][int]::TryParse((Get-Content -LiteralPath $pidFile -Raw).Trim(), [ref]$pidValue)
    $process = if ($pidValue -gt 0) { Get-Process -Id $pidValue -ErrorAction SilentlyContinue } else { $null }
    if ($process) {
        $expected = Find-ProviderExecutable $environment
        $identity = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $pidValue) -ErrorAction SilentlyContinue
        if ($expected -and $identity -and $identity.ExecutablePath -and ([System.IO.Path]::GetFullPath($identity.ExecutablePath) -ne [System.IO.Path]::GetFullPath($expected))) {
            throw 'Tunnel PID marker does not match the configured executable; refusing to stop an unrelated process.'
        }
        Stop-Process -Id $pidValue -Force
        $result.state = 'stopped'; $result.pid = $pidValue
    } else { $result.state = 'already-stopped' }
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    Get-ProviderResult $result
    exit 0
}

$executable = Find-ProviderExecutable $environment
if (-not $executable -or -not (Test-Path -LiteralPath $executable -PathType Leaf)) {
    $result.ok = $false; $result.state = 'not-installed'; $result.detail = 'Set TUNNEL_EXECUTABLE to an installed provider launcher, or install the selected provider.'
    Get-ProviderResult $result
    exit 1
}
$arguments = if ($environment['TUNNEL_ARGUMENTS']) { [string]$environment['TUNNEL_ARGUMENTS'] } else { '' }
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $executable
$psi.Arguments = $arguments
$psi.WorkingDirectory = $projectDir
$psi.UseShellExecute = $true
$process = [System.Diagnostics.Process]::Start($psi)
if (-not $process) { throw 'Tunnel provider process could not be started.' }
New-Item -ItemType Directory -Path (Split-Path -Parent $pidFile) -Force | Out-Null
[System.IO.File]::WriteAllText($pidFile, [string]$process.Id, (New-Object System.Text.UTF8Encoding($false)))
$result.state = 'started'; $result.pid = $process.Id
Get-ProviderResult $result
