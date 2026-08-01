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

$common = Read-ProjectSource 'scripts\runtime-common.ps1'
Assert-FunctionSet 'scripts\runtime-common.ps1' @(
    'Get-RuntimeState', 'Update-RuntimeState', 'Test-RuntimeSwitching',
    'Acquire-RuntimeMutex', 'Sync-ModManifestRuntime', 'Test-PortsReleased', 'Test-RuntimePorts'
)
Assert-SourceTokens $common @(
    'System.Threading.Mutex', 'Global\PalworldServerRuntime', 'data\runtime.state'
) 'runtime-common'

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
    'Get-WindowsRuntimeHealth', 'Test-SaveGamesIntegrity', 'Invoke-WindowsRuntimeSave',
    'Get-WindowsRuntimeVersion', 'Get-WindowsRuntimePlayers', 'Get-WindowsRuntimeLogs',
    'Get-WindowsRuntimeSettings', 'Invoke-WindowsRuntimeBackup', 'Test-WindowsRuntimeDeps',
    'Get-WindowsRuntimeMetrics'
)
Assert-SourceTokens $windows @(
    'Authorization', 'Basic $b64', 'Invoke-WebRequest',
    'Palworld Block REST 8212 Public', 'Palworld Block RCON 25575 Public',
    'data\Pal\Saved\SaveGames'
) 'win-runtime'

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
    'Attempting rollback to', 'Sync-ModManifestRuntime'
) 'switch-runtime'

$restore = Read-ProjectSource 'scripts\restore-snapshot.ps1'
Assert-SourceTokens $restore @(
    'Get-FileSha256Hex', 'SHA256', 'pre-restore safety snapshot',
    'SaveGames replaced', 'Assert-SaveGamesJunction', 'compile-settings.ps1'
) 'restore-snapshot'

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
    'http://localhost:', 'http://127.0.0.1:', 'http://[::1]:'
) 'settings-panel'
Assert-SourceDoesNotContain $panel @(
    'http://+:', 'http://*:', 'http://0.0.0.0:'
) 'settings-panel'

$dockerLauncher = Read-ProjectSource 'start-docker.bat'
$windowsLauncher = Read-ProjectSource 'start-windows.bat'
Assert-SourceTokens $dockerLauncher @('scripts\switch-runtime.ps1', '-To docker', '-FullSnapshot') 'start-docker.bat'
Assert-SourceTokens $windowsLauncher @('scripts\switch-runtime.ps1', '-To windows', '-FullSnapshot') 'start-windows.bat'

Write-Output 'RUNTIME_ORCHESTRATION_CONTRACT=passed'
Write-Output 'RUNTIME_ORCHESTRATION_CONTRACT_SCOPE=source-only'
exit 0
