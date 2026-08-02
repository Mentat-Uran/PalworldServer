[CmdletBinding()]
param()

# Disposable source-level test for the launch configuration gate. It copies the
# read-only validator and its dependencies into a temporary fixture, so this
# test never reads or changes the real .env, runtime state, or server files.
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('palworld-launch-config-' + [guid]::NewGuid().ToString('N'))
$fixtureScripts = Join-Path $fixtureRoot 'scripts'
$fixtureProviders = Join-Path $fixtureRoot 'providers'

function Assert-LaunchConfigTest {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "LAUNCH_CONFIG_TEST_FAILED: $Message" }
}

function Invoke-FixtureValidator {
    param([Parameter(Mandatory)][string]$ValidatorPath)
    $powershell = Join-Path $PSHOME 'powershell.exe'
    $stdoutPath = Join-Path $fixtureRoot ('.validator-' + [guid]::NewGuid().ToString('N') + '.out')
    $stderrPath = Join-Path $fixtureRoot ('.validator-' + [guid]::NewGuid().ToString('N') + '.err')
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $ValidatorPath), '-Summary')
    $process = Start-Process -FilePath $powershell -ArgumentList $arguments -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw } else { '' }
    $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw } else { '' }
    return [ordered]@{
        exitCode = [int]$process.ExitCode
        output = (($stdout, $stderr) -join "`n").Trim()
    }
}

try {
    New-Item -ItemType Directory -Path $fixtureScripts -Force | Out-Null
    foreach ($name in @('validate-launch-config.ps1', 'management-api.ps1', 'networking.ps1', 'tunnel-provider-catalog.ps1')) {
        Copy-Item -LiteralPath (Join-Path $projectDir "scripts\$name") -Destination (Join-Path $fixtureScripts $name)
    }
    foreach ($provider in @('none', 'generic-process', 'sakurafrp')) {
        $destination = Join-Path $fixtureProviders $provider
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $projectDir "providers\$provider\provider.json") -Destination (Join-Path $destination 'provider.json')
    }

    $envText = @'
ADMIN_PASSWORD=launch-test-password-1234567890
PORT=9001
QUERY_PORT=9002
REST_API_ENABLED=true
REST_API_PORT=9012
RCON_ENABLED=false
ENABLE_LEGACY_RCON=false
RCON_PORT=9025
    NETWORK_MODE=direct
    TUNNEL_PROVIDER=none
PROJECT_INSTANCE_ID=palworld-server
WINDOWS_REST_COMPATIBILITY_MODE=compat
TUNNEL_LOCAL_PORT=9001
PUBLIC_IP=
PUBLIC_PORT=
'@
    [System.IO.File]::WriteAllText((Join-Path $fixtureRoot '.env'), $envText, [System.Text.UTF8Encoding]::new($false))

    $validator = Join-Path $fixtureScripts 'validate-launch-config.ps1'
    $result = Invoke-FixtureValidator -ValidatorPath $validator
    Assert-LaunchConfigTest ($result.exitCode -eq 0) "direct configuration was rejected: $($result.output)"
    foreach ($expected in @(
        'GAME_PORT=9001', 'CONTAINER_NAME=palworld-server', 'WINDOWS_REST_COMPATIBILITY_MODE=compat', 'QUERY_PORT=9002', 'REST_API_PORT=9012',
        'REST_ENABLED=true', 'RCON_PORT=9025', 'RCON_ENABLED=false',
        'NETWORK_MODE=direct', 'TUNNEL_PROVIDER=none'
    )) {
        Assert-LaunchConfigTest ($result.output -match [regex]::Escape($expected)) "validator output omitted $expected"
    }
    Assert-LaunchConfigTest ($result.output -notmatch '(?i)launch-test-password') 'validator output leaked fixture credentials'

    $isolatedEnv = $envText -replace 'PROJECT_INSTANCE_ID=palworld-server', 'PROJECT_INSTANCE_ID=palworld-test-a'
    [System.IO.File]::WriteAllText((Join-Path $fixtureRoot '.env'), $isolatedEnv, [System.Text.UTF8Encoding]::new($false))
    $result = Invoke-FixtureValidator -ValidatorPath $validator
    Assert-LaunchConfigTest ($result.exitCode -eq 0 -and $result.output -match 'CONTAINER_NAME=palworld-test-a') 'configured instance identity was not propagated by the launch validator.'

    $invalidRestModeEnv = $envText -replace 'WINDOWS_REST_COMPATIBILITY_MODE=compat', 'WINDOWS_REST_COMPATIBILITY_MODE=invalid'
    [System.IO.File]::WriteAllText((Join-Path $fixtureRoot '.env'), $invalidRestModeEnv, [System.Text.UTF8Encoding]::new($false))
    $result = Invoke-FixtureValidator -ValidatorPath $validator
    Assert-LaunchConfigTest ($result.exitCode -ne 0) "invalid Windows REST compatibility mode was accepted (exit=$($result.exitCode); output=$($result.output))"

    $tunnelEnv = $isolatedEnv -replace 'NETWORK_MODE=direct', 'NETWORK_MODE=tunnel'
    [System.IO.File]::WriteAllText((Join-Path $fixtureRoot '.env'), $tunnelEnv, [System.Text.UTF8Encoding]::new($false))
    $result = Invoke-FixtureValidator -ValidatorPath $validator
    Assert-LaunchConfigTest ($result.exitCode -ne 0) "invalid tunnel/provider combination was accepted (exit=$($result.exitCode); output=$($result.output))"

    Write-Output 'LAUNCH_CONFIG_TEST=passed'
    Write-Output 'LAUNCH_CONFIG_TEST_SCOPE=disposable-fixture'
    exit 0
} finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
