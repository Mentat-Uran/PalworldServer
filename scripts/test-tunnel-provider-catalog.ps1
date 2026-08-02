[CmdletBinding()]
param()

# Disposable provider-catalog and lifecycle regression. It uses a temporary
# custom provider and cmd.exe only; it never reads the real .env or starts a
# Palworld, Docker, Web Console, or third-party tunnel process.
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('palworld-provider-' + [guid]::NewGuid().ToString('N'))
$fixtureScripts = Join-Path $fixtureRoot 'scripts'
$fixtureProviders = Join-Path $fixtureRoot 'providers'
$startedPid = 0

function Assert-ProviderTest {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "TUNNEL_PROVIDER_CATALOG_FAILED: $Message" }
}

function Invoke-Provider {
    param([Parameter(Mandatory)][string]$Script, [Parameter(Mandatory)][string[]]$Arguments)
    $powershell = Join-Path $PSHOME 'powershell.exe'
    $output = @(& $powershell -NoProfile -ExecutionPolicy Bypass -File $Script @Arguments 2>&1)
    return [pscustomobject]@{
        exitCode = [int]$LASTEXITCODE
        text = (($output | ForEach-Object { [string]$_ }) -join "`n").Trim()
    }
}

try {
    New-Item -ItemType Directory -Path $fixtureScripts -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fixtureProviders 'none') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fixtureProviders 'custom-loopback') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectDir 'scripts\tunnel-provider.ps1') -Destination (Join-Path $fixtureScripts 'tunnel-provider.ps1')
    Copy-Item -LiteralPath (Join-Path $projectDir 'scripts\tunnel-provider-catalog.ps1') -Destination (Join-Path $fixtureScripts 'tunnel-provider-catalog.ps1')

    $noneManifest = '{"id":"none","displayName":"No tunnel provider","kind":"none","autoDiscoverExecutables":[]}'
    $customManifest = '{"id":"custom-loopback","displayName":"Custom loopback provider","kind":"process","autoDiscoverExecutables":[]}'
    [System.IO.File]::WriteAllText((Join-Path $fixtureProviders 'none\provider.json'), $noneManifest, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $fixtureProviders 'custom-loopback\provider.json'), $customManifest, [System.Text.UTF8Encoding]::new($false))

    $cmdPath = Join-Path $env:SystemRoot 'System32\cmd.exe'
    $envText = @"
TUNNEL_PROVIDER=custom-loopback
TUNNEL_EXECUTABLE=$cmdPath
TUNNEL_ARGUMENTS=/c ping -n 30 127.0.0.1 >nul
"@
    [System.IO.File]::WriteAllText((Join-Path $fixtureRoot '.env'), $envText.Trim() + "`r`n", [System.Text.UTF8Encoding]::new($false))

    $providerScript = Join-Path $fixtureScripts 'tunnel-provider.ps1'
    $status = Invoke-Provider -Script $providerScript -Arguments @('-Action', 'Status', '-Json')
    Assert-ProviderTest ($status.exitCode -eq 0) "custom provider status failed: $($status.text)"
    $statusObject = $status.text | ConvertFrom-Json
    Assert-ProviderTest ([string]$statusObject.provider -eq 'custom-loopback' -and [string]$statusObject.state -eq 'not-started') 'custom provider was not loaded from provider.json.'

    $start = Invoke-Provider -Script $providerScript -Arguments @('-Action', 'Start', '-Json')
    Assert-ProviderTest ($start.exitCode -eq 0) "custom provider start failed: $($start.text)"
    $startObject = $start.text | ConvertFrom-Json
    $startedPid = [int]$startObject.pid
    Assert-ProviderTest ($startedPid -gt 0 -and [string]$startObject.state -eq 'started') 'custom provider did not return a started PID.'
    Assert-ProviderTest ($null -ne (Get-Process -Id $startedPid -ErrorAction SilentlyContinue)) 'custom provider process is not running.'

    $stop = Invoke-Provider -Script $providerScript -Arguments @('-Action', 'Stop', '-Json')
    Assert-ProviderTest ($stop.exitCode -eq 0) "custom provider stop failed: $($stop.text)"
    $stopObject = $stop.text | ConvertFrom-Json
    Assert-ProviderTest ([string]$stopObject.state -eq 'stopped') 'custom provider did not report a clean stop.'
    Start-Sleep -Milliseconds 200
    Assert-ProviderTest ($null -eq (Get-Process -Id $startedPid -ErrorAction SilentlyContinue)) 'custom provider process remained after stop.'
    $startedPid = 0

    Write-Output 'TUNNEL_PROVIDER_CATALOG=passed'
    Write-Output 'TUNNEL_PROVIDER_CATALOG_SCOPE=temporary-provider-only'
    exit 0
} finally {
    if ($startedPid -gt 0) {
        $leftover = Get-Process -Id $startedPid -ErrorAction SilentlyContinue
        if ($leftover) { Stop-Process -Id $startedPid -Force -ErrorAction SilentlyContinue }
    }
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
