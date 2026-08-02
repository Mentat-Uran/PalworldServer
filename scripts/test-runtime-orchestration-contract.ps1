[CmdletBinding()]
param()

# Source-only regression contract for the Docker <-> Windows runtime
# orchestration. It parses and reads source files only; it never starts,
# stops, saves, switches, restores, or contacts either Palworld runtime.
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot

function Assert-OrchestrationContract {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw "RUNTIME_ORCHESTRATION_CONTRACT_FAILED: $Message"
    }
}

function Read-ProjectSource {
    param([string]$RelativePath)
    $fullPath = Join-Path $projectDir $RelativePath
    Assert-OrchestrationContract (Test-Path -LiteralPath $fullPath -PathType Leaf) "Missing source file: $RelativePath"
    return [System.IO.File]::ReadAllText($fullPath)
}

function Get-SourceFunctions {
    param([string]$RelativePath)
    $fullPath = Join-Path $projectDir $RelativePath
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($fullPath, [ref]$tokens, [ref]$parseErrors)
    Assert-OrchestrationContract (@($parseErrors).Count -eq 0) "PowerShell syntax failed: $RelativePath"
    return @(
        $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
        }, $true) | ForEach-Object { $_.Name.ToLowerInvariant() }
    )
}

function Assert-FunctionSet {
    param([string]$RelativePath, [string[]]$Required)
    $defined = @(Get-SourceFunctions -RelativePath $RelativePath)
    foreach ($name in $Required) {
        Assert-OrchestrationContract ($defined -contains $name.ToLowerInvariant()) "$RelativePath is missing function $name"
    }
}

function Assert-SourceTokens {
    param([string]$Text, [string[]]$Tokens, [string]$Label)
    foreach ($token in $Tokens) {
        Assert-OrchestrationContract (
            $Text.IndexOf($token, [System.StringComparison]::Ordinal) -ge 0
        ) "$Label is missing required source token: $token"
    }
}

function Assert-SourceDoesNotContain {
    param([string]$Text, [string[]]$Tokens, [string]$Label)
    foreach ($token in $Tokens) {
        Assert-OrchestrationContract (
            $Text.IndexOf($token, [System.StringComparison]::OrdinalIgnoreCase) -lt 0
        ) "$Label contains forbidden source token: $token"
    }
}

function Assert-SourceOrder {
    param([string]$Text, [string[]]$Tokens, [string]$Label)
    $cursor = -1
    foreach ($token in $Tokens) {
        $position = $Text.IndexOf($token, [System.StringComparison]::Ordinal)
        Assert-OrchestrationContract ($position -gt $cursor) "$Label has an unsafe source order around: $token"
        $cursor = $position
    }
}

$common = Read-ProjectSource 'scripts\runtime-common.ps1'
Assert-FunctionSet 'scripts\runtime-common.ps1' @(
    'Get-RuntimeState', 'Update-RuntimeState', 'Test-RuntimeSwitching',
    'Acquire-RuntimeMutex', 'Sync-ModManifestRuntime', 'Test-PortsReleased', 'Test-RuntimePorts'
)
Assert-SourceTokens $common @(
    'System.Threading.Mutex', 'Get-ManagementMutexName', 'data\runtime.state'
) 'runtime-common'

$managementContract = Read-ProjectSource 'scripts\management-api.ps1'
Assert-SourceTokens $managementContract @(
    'Get-ManagementContainerName', 'Get-ManagementMutexName', 'PROJECT_INSTANCE_ID', 'Global\PalworldServerRuntime_'
) 'management instance identity'

$docker = Read-ProjectSource 'scripts\docker-runtime.ps1'
Assert-FunctionSet 'scripts\docker-runtime.ps1' @(
    'Start-DockerRuntime', 'Stop-DockerRuntime', 'Get-DockerRuntimeHealth',
    'Invoke-DockerRuntimeSave', 'Get-DockerRuntimeVersion', 'Get-DockerRuntimePlayers',
    'Get-DockerRuntimeLogs', 'Get-DockerRuntimeSettings', 'Invoke-DockerRuntimeBackup',
    'Test-DockerRuntimeDeps', 'Get-DockerRuntimeMetrics'
)

$windows = Read-ProjectSource 'scripts\win-runtime.ps1'
Assert-FunctionSet 'scripts\win-runtime.ps1' @(
    'Assert-SaveGamesJunction', 'Test-SaveGamesJunction', 'Invoke-WinRest',
    'Test-WindowsManagementFirewall', 'Start-WindowsRuntime', 'Stop-WindowsRuntime',
    'Get-WindowsRuntimeLaunchArguments',
    'Get-WindowsRuntimeProcessTree', 'Get-WindowsRuntimeProcessStatus',
    'Get-WindowsRuntimeHealth', 'Test-SaveGamesIntegrity', 'Invoke-WindowsRcon',
    'Get-WindowsRconFallbackCommand', 'Invoke-WindowsRuntimeSave',
    'Get-WindowsRuntimeVersion', 'Get-WindowsRuntimePlayers', 'Get-WindowsRuntimeLogs',
    'Get-WindowsRuntimeSettings', 'Invoke-WindowsRuntimeBackup', 'Test-WindowsRuntimeDeps',
    'Get-WindowsRuntimeMetrics'
)
Assert-SourceTokens $windows @(
    'Invoke-ManagementOperation', 'Get-ManagementEndpointConfig',
    'Test-WindowsManagementFirewall', 'data\Pal\Saved\SaveGames',
    'Get-CimInstance', 'ExecutablePath',
    'PalServer-Win64-Shipping-Cmd.exe', 'Stop-Process -Id',
    'runtime-stop-incomplete', 'Read-ManagementEnv',
    '-UseMultithreadForDS',
    'windowsRestCompatibilityMode', "if (`$Management.restEnabled -and `$Management.windowsRestCompatibilityMode -eq 'compat')", "`$flags += '-restapi'",
    'restMode=', 'restDetail', 'restAvailable', 'fallback = $rconFallback',
    'exact-process-and-game-udp', 'management  = [ordered]@'
) 'win-runtime'
Assert-SourceDoesNotContain $windows @('Stop-Process -Name') 'win-runtime exact process stop'
Assert-SourceDoesNotContain $windows @("'-rcon'", "'-rpc'", "'-UseMultithreadForLoad'") 'win-runtime current official arguments'

$switchHealth = Read-ProjectSource 'scripts\switch-runtime.ps1'
Assert-SourceTokens $switchHealth @('healthDetail', 'runtime-health-failed', '-Detail $healthDetail') 'switch-runtime health diagnostics'

$management = Read-ProjectSource 'scripts\management-api.ps1'
Assert-SourceTokens $management @(
    'Authorization', 'basicBytes', 'ToBase64String', 'Invoke-WebRequest', 'Get-WindowsRestCompatibilityMode',
    '/announce', '/kick', '/ban', '/unban', '/save', '/shutdown'
) 'management-api'

$switch = Read-ProjectSource 'scripts\switch-runtime.ps1'
Assert-FunctionSet 'scripts\switch-runtime.ps1' @(
    'Get-SaveGamesFingerprint', 'New-SwitchSnapshot', 'Invoke-SnapshotRetention',
    'Sync-DedicatedServerName'
)
Assert-SourceTokens $switch @(
    'Acquire-RuntimeMutex', 'recover-runtime-state.ps1',
    'Invoke-DockerRuntimeSave', 'Invoke-WindowsRuntimeSave', 'New-SwitchSnapshot',
    'Stop-DockerRuntime -Grace 120', 'Stop-WindowsRuntime -Grace 120',
    'Test-PortsReleased', 'Assert-SaveGamesJunction', 'compile-settings.ps1',
    'Start-DockerRuntime', 'Start-WindowsRuntime',
    'Get-DockerRuntimeHealth', 'Get-WindowsRuntimeHealth',
    'Management save FAILED', 'refusing to stop',
    'Attempting rollback to', 'Sync-ModManifestRuntime'
) 'switch-runtime'

$restore = Read-ProjectSource 'scripts\restore-snapshot.ps1'
Assert-SourceTokens $restore @(
    'Get-FileSha256Hex', 'SHA256', 'pre-restore safety snapshot',
    'SaveGames replaced', 'Assert-SaveGamesJunction', 'compile-settings.ps1'
) 'restore-snapshot'

$recover = Read-ProjectSource 'scripts\recover-runtime-state.ps1'
Assert-SourceTokens $recover @(
    'management-api.ps1', 'Get-ManagementEndpointConfig', 'restBaseUrl.TrimEnd', '/info',
    '-not [bool]$currentState.switching'
) 'recover-runtime-state dynamic management endpoint'
Assert-SourceDoesNotContain $recover @("'http://127.0.0.1:8212/v1/api/info'") 'recover-runtime-state'

$latency = Read-ProjectSource 'scripts\measure-latency.ps1'
Assert-SourceTokens $latency @(
    'management-api.ps1', 'Get-ManagementEndpointConfig', 'Get-ManagementAdminPassword',
    'restBaseUrl.TrimEnd'
) 'measure-latency dynamic management endpoint'
Assert-SourceDoesNotContain $latency @("'http://127.0.0.1:8212/v1/api'") 'measure-latency'

$compiler = Read-ProjectSource 'scripts\compile-settings.ps1'
Assert-FunctionSet 'scripts\compile-settings.ps1' @(
    'Get-EnvVars', 'Build-PalWorldSettings', 'Build-EngineIni', 'Write-IniFile'
)
Assert-SourceTokens $compiler @(
    '.env', 'LinuxServer', 'WindowsServer', 'PalWorldSettings.ini', 'Engine.ini'
) 'compile-settings'

$collector = Read-ProjectSource 'scripts\daily-log-collector.ps1'
Assert-FunctionSet 'scripts\daily-log-collector.ps1' @(
    'Get-ContainerLogLines', 'Get-LocalSourceLogLines', 'Write-DailyArchive',
    'Update-PlayerSessionTimesSafely'
)
Assert-SourceTokens $collector @(
    'data\log-sources\game', 'data\log-sources\windows-server',
    'data\log-sources\windows-runtime', 'China Standard Time'
) 'daily-log-collector'

$mods = Read-ProjectSource 'scripts\mod-manager.ps1'
Assert-FunctionSet 'scripts\mod-manager.ps1' @(
    'Read-Manifest', 'Get-DirectorySha256', 'Get-ModInspection', 'Set-ModEnabled', 'Invoke-Sync'
)
Assert-SourceTokens $mods @(
    'windows-dedicated', 'managerEnabled', 'IsServer', 'hashApproved', 'expectedSha256'
) 'mod-manager'

$panel = Read-ProjectSource 'settings-panel.ps1'
Assert-FunctionSet 'settings-panel.ps1' @(
    'Get-ActiveRuntime', 'Get-RuntimeLogs', 'Invoke-RuntimeSaveAction',
    'Invoke-RuntimeBackupAction', 'Stop-RuntimeServer', 'Restart-RuntimeServer',
    'Start-RuntimeSwitchTask', 'Start-RuntimeRestoreTask', 'Get-RuntimeContainerState',
    'Get-Dashboard', 'Test-LoopbackRequest', 'Test-RequestOrigin'
)
Assert-SourceTokens $panel @(
    '/api/runtime', '/api/runtime/switch', '/api/runtime/snapshot',
    '/api/runtime/restore', '/api/runtime/task', '/api/snapshots',
    '/api/save', '/api/backup', '/api/logs', '/api/mods',
    'http://localhost:', 'http://127.0.0.1:', 'http://[::1]:',
    'Invoke-WindowsRuntimeOperation', 'management-unavailable', 'fallback ='
) 'settings-panel'
Assert-SourceDoesNotContain $panel @(
    'http://+:', 'http://*:', 'http://0.0.0.0:'
) 'settings-panel'

$dockerLauncher = Read-ProjectSource 'start-docker.bat'
$windowsLauncher = Read-ProjectSource 'start-windows.bat'
$compose = Read-ProjectSource 'docker-compose.yml'
Assert-SourceTokens $compose @('container_name: ${PROJECT_INSTANCE_ID:-palworld-server}') 'docker-compose instance identity'
Assert-SourceTokens $dockerLauncher @('scripts\switch-runtime.ps1', '-To docker', '-FullSnapshot') 'start-docker.bat'
Assert-SourceTokens $windowsLauncher @('scripts\switch-runtime.ps1', '-To windows', '-FullSnapshot') 'start-windows.bat'
Assert-SourceTokens $dockerLauncher @(
    'scripts\validate-launch-config.ps1', 'scripts\test-host-prerequisites.ps1', '-Runtime docker', 'CONTAINER_NAME', '-Summary', '%GAME_PORT%', '%REST_PORT%',
    '%NETWORK_MODE%', '%TUNNEL_PROVIDER%'
) 'start-docker.bat launch configuration'
Assert-SourceTokens $windowsLauncher @(
    'scripts\validate-launch-config.ps1', 'scripts\test-host-prerequisites.ps1', '-Runtime windows', '-Summary', '%GAME_PORT%', '%REST_PORT%',
    '%NETWORK_MODE%', '%TUNNEL_PROVIDER%'
) 'start-windows.bat launch configuration'
Assert-SourceOrder $dockerLauncher @(
    'scripts\test-host-prerequisites.ps1', '-Runtime docker', 'scripts\switch-runtime.ps1'
) 'start-docker.bat preflight'
Assert-SourceOrder $windowsLauncher @(
    'scripts\test-host-prerequisites.ps1', '-Runtime windows', 'scripts\switch-runtime.ps1'
) 'start-windows.bat preflight'
Assert-SourceDoesNotContain $dockerLauncher @('Game: 127.0.0.1:8211') 'start-docker.bat'
Assert-SourceDoesNotContain $windowsLauncher @('Game: 127.0.0.1:8211') 'start-windows.bat'

$launchConfig = Read-ProjectSource 'scripts\validate-launch-config.ps1'
Assert-SourceTokens $launchConfig @(
    'Get-ManagementEndpointConfig', 'Test-NetworkConfiguration',
    'GAME_PORT=', 'WINDOWS_REST_COMPATIBILITY_MODE=', 'REST_API_PORT=', 'RCON_PORT=', 'NETWORK_MODE=', 'TUNNEL_PROVIDER='
) 'validate-launch-config'
Assert-SourceDoesNotContain $launchConfig @('ADMIN_PASSWORD=', 'TUNNEL_ARGUMENTS=') 'validate-launch-config'

Write-Output 'RUNTIME_ORCHESTRATION_CONTRACT=passed'
Write-Output 'RUNTIME_ORCHESTRATION_CONTRACT_SCOPE=source-only'
exit 0
