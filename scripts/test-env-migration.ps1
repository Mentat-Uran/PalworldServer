[CmdletBinding()]
param()

# Disposable migration regression. It never reads or rewrites the repository's
# .env, never starts a runtime, and never contacts Docker, SteamCMD, or a tunnel.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('PalworldServer-env-migration-' + [guid]::NewGuid().ToString('N'))
$tempScripts = Join-Path $tempRoot 'scripts'
$tempEnv = Join-Path $tempRoot '.env'

function Assert-EnvMigration([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ENV_MIGRATION_TEST_FAILED: $Message" }
}

try {
    New-Item -ItemType Directory -Path $tempScripts -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'normalize-env.ps1') -Destination (Join-Path $tempScripts 'normalize-env.ps1')
    Copy-Item -LiteralPath (Join-Path $projectRoot '.env.example') -Destination (Join-Path $tempRoot '.env.example')

    $fixture = @'
ADMIN_PASSWORD=migration-test-password-1234567890
MAX_PLAYERS=12
SERVER_SETTINGS_EXP_RATE=3.0
NETWORK_MODE=tunnel
TUNNEL_PROVIDER=generic-process
TUNNEL_LOCAL_PORT=8211
TUNNEL_REMOTE_PORT=31234
CUSTOM_OPERATOR_SETTING=keep-me
'@
    [System.IO.File]::WriteAllText($tempEnv, $fixture.TrimStart(), (New-Object System.Text.UTF8Encoding($false)))

    & (Join-Path $tempScripts 'normalize-env.ps1') -Path $tempEnv
    Assert-EnvMigration ($LASTEXITCODE -eq 0) "Initial migration exited with code $LASTEXITCODE."
    $first = [System.IO.File]::ReadAllText($tempEnv)
    Assert-EnvMigration ($first -match '(?m)^PLAYERS=12\r?$') 'Legacy MAX_PLAYERS was not migrated.'
    Assert-EnvMigration ($first -match '(?m)^EXP_RATE=3\.0\r?$') 'Legacy EXP_RATE was not migrated.'
    Assert-EnvMigration ($first -match '(?m)^UPDATE_ON_BOOT=false\r?$') 'Missing update default is not safe.'
    Assert-EnvMigration ($first -match '(?m)^RCON_ENABLED=false\r?$') 'Missing RCON default is not disabled.'
    Assert-EnvMigration ($first -match '(?m)^ENABLE_LEGACY_RCON=false\r?$') 'Legacy RCON compatibility default is missing.'
    Assert-EnvMigration ($first -match '(?m)^NETWORK_MODE=tunnel\r?$' -and $first -match '(?m)^TUNNEL_PROVIDER=generic-process\r?$') 'Provider configuration was not preserved.'
    Assert-EnvMigration ($first -match '(?m)^CUSTOM_OPERATOR_SETTING=keep-me\r?$') 'Unknown operator setting was not preserved.'
    Assert-EnvMigration ($first -notmatch '(?m)^(MAX_PLAYERS|SERVER_SETTINGS_EXP_RATE)=') 'Legacy keys remain after migration.'

    Add-Content -LiteralPath $tempEnv -Value "UPDATE_ON_BOOT=true`nRCON_ENABLED=true"
    & (Join-Path $tempScripts 'normalize-env.ps1') -Path $tempEnv
    Assert-EnvMigration ($LASTEXITCODE -eq 0) "Explicit-value migration exited with code $LASTEXITCODE."
    $second = [System.IO.File]::ReadAllText($tempEnv)
    Assert-EnvMigration ($second -match '(?m)^UPDATE_ON_BOOT=true\r?$' -and $second -match '(?m)^RCON_ENABLED=true\r?$') 'Explicit operator choices were overwritten.'

    $backupDir = Join-Path $tempRoot 'data\diagnostics\env-migrations'
    $backups = @(Get-ChildItem -LiteralPath $backupDir -Filter '*.bak' -File)
    Assert-EnvMigration ($backups.Count -eq 2) 'Each migration did not leave a recoverable backup.'
    Write-Output 'ENV_MIGRATION=passed'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
exit 0
