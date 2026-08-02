[CmdletBinding()]
param(
    [switch]$SkipDocker
)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Add-Error([string]$Message) { $errors.Add($Message) }
function Add-Warning([string]$Message) { $warnings.Add($Message) }
. (Join-Path $projectDir 'scripts\management-api.ps1')
$verificationContainerName = 'palworld-server'
try { $verificationContainerName = Get-ManagementContainerName -ProjectDirectory $projectDir } catch { Add-Error $_.Exception.Message }

$requiredFiles = @(
    ".env", ".env.example", "version.json", "docker-compose.yml", "FIRST_RUN.bat", "start-docker.bat", "start-windows.bat", "install-windows-server.bat",
    "settings-panel.ps1", "web\index.html", "web\styles.css", "web\app.js", "package.json", "package-lock.json", "README.md", "README.en.md", "AGENTS.md",
    "desktop\PalworldConsole.Desktop\PalworldConsole.Desktop.csproj", "desktop\PalworldConsole.Desktop\Program.cs", "desktop\PalworldConsole.Desktop\packages.lock.json", "installer\PalworldServerConsole.wxs", "docs\desktop-app.md", "docs\quick-start.md", "docs\social-media-copy.md",
    "CHANGELOG.md", "docs\versioning-and-releases.md", "docs\compatibility.md",
    "docs\clean-checkout-onboarding.md", "docs\maintenance-window-runbook.md",
    "docs\maintenance-evidence.synthetic.json", "scripts\test-clean-checkout.ps1",
    "scripts\test-maintenance-readiness.ps1", "scripts\verify-maintenance-evidence.ps1",
    "scripts\compare-save-integrity.ps1",
    "scripts\settings-catalog.ps1", "scripts\ensure-win-management-firewall.ps1", "scripts\ui-smoke.cjs", "scripts\test-i18n-parity.cjs", "scripts\build-desktop-app.ps1", "scripts\test-desktop-host.ps1", "scripts\test-desktop-installer.ps1", "scripts\test-windows-installer-bat.ps1", "scripts\test-first-run-bat.ps1", "scripts\test-powershell-encoding.ps1",
    "scripts\test-player-command-picker.cjs", "scripts\test-console-guided-actions.cjs", "scripts\test-compare-save-integrity.cjs", "scripts\test-runtime-orchestration-contract.ps1", "scripts\test-runtime-common-behavior.ps1", "scripts\test-recover-runtime-state-behavior.ps1", "scripts\test-env-migration.ps1",
    "scripts\test-management-network-contract.ps1", "scripts\test-instance-isolation.ps1", "scripts\test-windows-rest-compatibility.ps1", "scripts\validate-launch-config.ps1", "scripts\test-launch-config.ps1", "scripts\test-tunnel-provider-catalog.ps1", "scripts\test-log-archive-route.ps1", "scripts\publish-local-release.ps1", "scripts\test-release-policy.ps1",
    "scripts\daily-log-collector.ps1", "scripts\player-session-times.ps1", "scripts\test-player-session-times.ps1",
    "scripts\audit-public-release.ps1", "scripts\test-host-prerequisites.ps1", "scripts\test-web-console-boundary.ps1", "scripts\test-powershell-encoding.ps1", "scripts\test-win-installer-preflight.ps1",
    "scripts\management-api.ps1", "scripts\networking.ps1", "scripts\tunnel-provider.ps1", "scripts\apply-preset.ps1",
    "scripts\bootstrap-first-run.ps1", "scripts\export-support-bundle.ps1", "scripts\build-release-bundle.ps1",
    "scripts\get-project-version.ps1", "scripts\test-version-consistency.ps1", "scripts\bump-version.ps1",
    "scripts\mod-manager.ps1", "mods\manifest.json",
    "mods\manifest.schema.json", "mods\README.md",
    "docs\official-palworld-server-standards.md", "docs\web-console-capabilities.md", "docs\operator-workflows.md", "docs\public-release-readiness.md",
    "docs\log-and-tunnel-diagnostics.md", "docs\architecture.md", "docs\getting-started\install.md",
    "docs\getting-started\networking.md", "docs\getting-started\saves.md", "docs\user-guide\daily-operations.md",
    "docs\troubleshooting\README.md", "presets\vanilla.env", "presets\casual-small-server.env", "presets\performance-conservative.env",
    "providers\none\README.md", "providers\none\provider.json", "providers\generic-process\README.md", "providers\generic-process\provider.json", "providers\sakurafrp\README.md", "providers\sakurafrp\provider.json", "scripts\tunnel-provider-catalog.ps1"
)
foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $projectDir $relativePath) -PathType Leaf)) {
        Add-Error "Missing file: $relativePath"
    }
}

$envPath = Join-Path $projectDir ".env"
if (Test-Path -LiteralPath $envPath -PathType Leaf) {
    $envBytes = [System.IO.File]::ReadAllBytes($envPath)
    if ($envBytes.Length -ge 3 -and $envBytes[0] -eq 0xEF -and $envBytes[1] -eq 0xBB -and $envBytes[2] -eq 0xBF) {
        Add-Error ".env contains a UTF-8 BOM; the first key may be misread."
    }

    $envKeys = @{}
    $envValues = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($envPath)) {
        if ($line -match "^\s*([^#=]+)=(.*)$") {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            if ($value.Length -ge 2 -and
                (($value.StartsWith("'") -and $value.EndsWith("'")) -or
                 ($value.StartsWith('"') -and $value.EndsWith('"')))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            $envKeys[$key] = $true
            $envValues[$key] = $value
        }
    }
    foreach ($key in @("PORT", "PLAYERS", "ADMIN_PASSWORD", "EXP_RATE", "DAYTIME_SPEEDRATE",
        "COOP_PLAYER_MAX_NUM", "DELETE_OLD_BACKUPS", "OLD_BACKUP_DAYS")) {
        if (-not $envKeys.ContainsKey($key)) { Add-Error ".env is missing required key: $key" }
    }
    foreach ($legacyKey in @("MAX_PLAYERS", "BACKUP_RETENTION_DAYS", "RCON_PASSWORD", "ALLOW_CONNECT_PLATFORM")) {
        if ($envKeys.ContainsKey($legacyKey)) { Add-Error ".env still contains unsupported key: $legacyKey" }
    }
    foreach ($key in $envKeys.Keys) {
        if ($key.StartsWith("SERVER_SETTINGS_")) {
            Add-Error ".env still contains unsupported legacy key: $key"
        }
    }
    foreach ($key in @("PLAYERS", "COOP_PLAYER_MAX_NUM", "PORT", "RCON_PORT", "REST_API_PORT")) {
        $parsed = 0
        if (-not [int]::TryParse([string]$envValues[$key], [ref]$parsed) -or $parsed -lt 1 -or $parsed -gt 65535) {
            Add-Error ".env $key must be a positive integer in its structural range."
        }
    }
    if ([int]$envValues["PLAYERS"] -gt 32 -or [int]$envValues["COOP_PLAYER_MAX_NUM"] -gt [int]$envValues["PLAYERS"]) {
        Add-Error ".env player limits are inconsistent or exceed the supported cap."
    }
    foreach ($key in @("EXP_RATE", "DAYTIME_SPEEDRATE", "NIGHTTIME_SPEEDRATE")) {
        $parsed = 0.0
        if (-not [double]::TryParse(
            [string]$envValues[$key],
            [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$parsed
        ) -or [double]::IsNaN($parsed) -or [double]::IsInfinity($parsed) -or $parsed -lt 0) {
            Add-Error ".env $key must be a finite non-negative number."
        }
    }
    if ($envValues["DEATH_PENALTY"] -notin @("None", "Item", "ItemAndEquipment", "All")) {
        Add-Error ".env DEATH_PENALTY is unsupported."
    }
    if ($envValues["LOG_FORMAT_TYPE"] -notin @("Text", "Json")) {
        Add-Error ".env LOG_FORMAT_TYPE must be Text or Json."
    }
    if ($envValues["RCON_PORT"] -eq $envValues["REST_API_PORT"]) {
        Add-Error ".env RCON_PORT and REST_API_PORT must differ."
    }
    if ($envValues.ContainsKey("ADMIN_PASSWORD")) {
        if ($envValues["ADMIN_PASSWORD"].Length -lt 16 -or
            $envValues["ADMIN_PASSWORD"] -like "CHANGE_ME*") {
            Add-Error "ADMIN_PASSWORD is missing, weak, or still a placeholder."
        }
    }
}

foreach ($relativeScript in @("settings-panel.ps1", "scripts\settings-catalog.ps1",
    "scripts\normalize-env.ps1", "scripts\mod-manager.ps1", "scripts\daily-log-collector.ps1", "scripts\player-session-times.ps1", "scripts\start-web-console.ps1", "scripts\test-player-session-times.ps1", "scripts\test-runtime-orchestration-contract.ps1", "scripts\test-runtime-common-behavior.ps1", "scripts\test-recover-runtime-state-behavior.ps1",
    "scripts\audit-public-release.ps1", "scripts\test-host-prerequisites.ps1", "scripts\test-web-console-boundary.ps1", "scripts\build-desktop-app.ps1", "scripts\test-desktop-host.ps1", "scripts\test-desktop-installer.ps1", "scripts\test-windows-installer-bat.ps1", "scripts\test-first-run-bat.ps1", "scripts\test-powershell-encoding.ps1", "scripts\test-win-installer-preflight.ps1",
    "scripts\management-api.ps1", "scripts\networking.ps1", "scripts\tunnel-provider-catalog.ps1", "scripts\tunnel-provider.ps1", "scripts\apply-preset.ps1", "scripts\bootstrap-first-run.ps1", "scripts\export-support-bundle.ps1", "scripts\build-release-bundle.ps1", "scripts\publish-local-release.ps1", "scripts\test-release-policy.ps1", "scripts\get-project-version.ps1", "scripts\test-version-consistency.ps1", "scripts\bump-version.ps1", "scripts\test-management-network-contract.ps1", "scripts\test-instance-isolation.ps1", "scripts\test-windows-rest-compatibility.ps1", "scripts\validate-launch-config.ps1", "scripts\test-launch-config.ps1", "scripts\test-tunnel-provider-catalog.ps1", "scripts\test-log-archive-route.ps1",
    "scripts\runtime-common.ps1", "scripts\docker-runtime.ps1", "scripts\compile-settings.ps1", "scripts\measure-latency.ps1",
    "scripts\win-runtime.ps1", "scripts\install-win-server.ps1",
    "scripts\switch-runtime.ps1", "scripts\restore-snapshot.ps1",
    "scripts\compare-save-integrity.ps1",
    "scripts\recover-runtime-state.ps1", "scripts\test-clean-checkout.ps1",
    "scripts\test-maintenance-readiness.ps1", "scripts\verify-maintenance-evidence.ps1")) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $projectDir $relativeScript), [ref]$tokens, [ref]$parseErrors
    )
    foreach ($parseError in $parseErrors) {
        Add-Error "PowerShell syntax in ${relativeScript}: $($parseError.Message)"
    }
}

$catalogScript = Join-Path $projectDir "scripts\settings-catalog.ps1"
if (Test-Path -LiteralPath $catalogScript -PathType Leaf) {
    try {
        . $catalogScript
        $catalog = New-SettingsCatalog
        if ($catalog.Count -lt 200) { Add-Error "Settings catalog unexpectedly contains fewer than 200 fields." }
        $gameMapped = @($catalog.Keys | Where-Object {
            $catalog[$_].source -eq "game" -or $_ -eq "PLAYERS"
        }).Count
        if ($gameMapped -ne 118) {
            Add-Error "Settings catalog must cover all 118 pinned-image PalWorldSettings mappings."
        }
        foreach ($key in $catalog.Keys) {
            if (-not $catalog[$key].type -or -not $catalog[$key].group -or -not $catalog[$key].source) {
                Add-Error "Settings catalog metadata is incomplete: $key"
            }
        }
        if ($catalog["DIFFICULTY"].type -ne "choice" -or
            @($catalog["DIFFICULTY"].options).Count -ne 3) {
            Add-Error "DIFFICULTY must expose the documented choices."
        }
        if ($catalog["RANDOMIZER_TYPE"].type -ne "choice" -or
            @($catalog["RANDOMIZER_TYPE"].options).Count -ne 3) {
            Add-Error "RANDOMIZER_TYPE must expose None, Region, and All."
        }
        if ([int]$catalog["BASE_CAMP_MAX_NUM_IN_GUILD"].max -ne 10 -or
            [int]$catalog["BASE_CAMP_WORKER_MAX_NUM"].max -ne 50) {
            Add-Error "Official base and worker limits are not enforced by the catalog."
        }
        $templatePath = Join-Path $projectDir ".env.example"
        $templateValues = @{}
        foreach ($line in [System.IO.File]::ReadAllLines($templatePath)) {
            if ($line -match "^\s*([^#=]+)=(.*)$") {
                $templateValues[$matches[1].Trim()] = $matches[2].Trim().Trim('"').Trim("'")
            }
        }
        foreach ($key in @("TZ", "UPDATE_ON_BOOT", "BACKUP_CRON_EXPRESSION", "OLD_BACKUP_DAYS", "REST_API_ENABLED", "RCON_ENABLED", "WINDOWS_REST_COMPATIBILITY_MODE")) {
            if (-not $templateValues.ContainsKey($key)) {
                Add-Error ".env.example is missing catalog default key: $key"
            } elseif ([string]$templateValues[$key] -cne [string]$catalog[$key].default) {
                Add-Error ".env.example and settings catalog defaults differ for $key."
            }
        }
    } catch {
        Add-Error "Settings catalog could not be loaded: $($_.Exception.Message)"
    }
}

$manifestPath = Join-Path $projectDir "mods\manifest.json"
$schemaPath = Join-Path $projectDir "mods\manifest.schema.json"
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($property in @("schemaVersion", "managerEnabled", "runtime", "sourceRoot",
            "workshopRoot", "settingsPath", "statePath", "backupRoot", "mods")) {
            if ($manifest.PSObject.Properties.Name -notcontains $property) {
                Add-Error "Mod manifest is missing property: $property"
            }
        }
        if ([int]$manifest.schemaVersion -ne 1) { Add-Error "Mod manifest schemaVersion must be 1." }
        # managerEnabled must remain false unless the user has explicitly approved Mod management
        if ([bool]$manifest.managerEnabled -and @($manifest.mods).Count -eq 0) {
            Add-Error "Mod manager is enabled but no Mods are configured; either disable manager or add Mods."
        }
        # Match the manifest only to an active runtime. When the server is
        # intentionally offline, the disabled manager has no live runtime to
        # synchronize against.
        $runtimeStatePath = Join-Path $projectDir "data\runtime.state"
        $expectedManifestRuntime = $null
        if (Test-Path -LiteralPath $runtimeStatePath -PathType Leaf) {
            try {
                $rtState = Get-Content -LiteralPath $runtimeStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ([string]$rtState.active -eq 'windows') { $expectedManifestRuntime = 'windows-dedicated' }
                elseif ([string]$rtState.active -eq 'docker') { $expectedManifestRuntime = 'linux-docker' }
            } catch { }
        }
        if ([string]$manifest.runtime -notin @('linux-docker','windows-dedicated')) {
            Add-Error "Mod manifest runtime must be 'linux-docker' or 'windows-dedicated' (got: $($manifest.runtime))."
        } elseif ($expectedManifestRuntime -and [string]$manifest.runtime -ne $expectedManifestRuntime) {
            Add-Warning "Mod manifest runtime ($($manifest.runtime)) does not match runtime.state.active (expected $expectedManifestRuntime); run switch-runtime.ps1 or Sync-ModManifestRuntime to sync."
        }
        if (@($manifest.mods).Count -ne 0 -and -not [bool]$manifest.managerEnabled) {
            Add-Error "Mod manifest has Mods but managerEnabled is false; mods cannot be synced."
        }
    } catch {
        Add-Error "Mod manifest is not valid JSON: $($_.Exception.Message)"
    }
}
if (Test-Path -LiteralPath $schemaPath -PathType Leaf) {
    try {
        [void](Get-Content -LiteralPath $schemaPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        Add-Error "Mod manifest schema is not valid JSON: $($_.Exception.Message)"
    }
}
foreach ($relativePath in @("data\Mods", "data\mod-manager", "data\Pal\Content\Paks\~mods")) {
    if (Test-Path -LiteralPath (Join-Path $projectDir $relativePath)) {
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            Add-Error "Unexpected Mod runtime path exists without a manifest: $relativePath"
            continue
        }
        try {
            $manifestForCheck = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if (-not [bool]$manifestForCheck.managerEnabled) {
                Add-Error "Unexpected Mod runtime path exists while the manager is disabled: $relativePath"
            }
        } catch {
            Add-Error "Unexpected Mod runtime path exists and manifest is unreadable: $relativePath"
        }
    }
}

$composePath = Join-Path $projectDir "docker-compose.yml"
if (Test-Path -LiteralPath $composePath) {
    $composeText = [System.IO.File]::ReadAllText($composePath)
    if ($composeText -notmatch "thijsvanloef/palworld-server-docker@sha256:[0-9a-f]{64}") {
        Add-Error "Container image is not pinned by digest."
    }
    if ($composeText -notmatch "target:\s*\$\{REST_API_PORT:-8212\}" -or
        $composeText -notmatch "host_ip:\s*127\.0\.0\.1") {
        Add-Error "REST management port is not explicitly bound to 127.0.0.1."
    }
    if ($composeText -notmatch 'target:\s*\$\{PORT:-8211\}') {
        Add-Error "Compose game port mapping does not follow the editable PORT setting."
    }
    if ($composeText -notmatch 'container_name:\s*\$\{PROJECT_INSTANCE_ID:-palworld-server\}') {
        Add-Error "Compose container identity does not follow PROJECT_INSTANCE_ID with the backward-compatible default."
    }
    if ($composeText -match 'target:\s*\$\{RCON_PORT:-25575\}' -and
        $composeText -notmatch 'host_ip:\s*127\.0\.0\.1') {
        Add-Error "Any Compose RCON mapping must be explicitly bound to 127.0.0.1."
    }
    if ($composeText -notmatch "stop_grace_period:\s*2m") {
        Add-Error "stop_grace_period is not set to 2m."
    }
}

if (-not $SkipDocker) {
    $docker = Get-Command docker.exe -ErrorAction SilentlyContinue
    if (-not $docker) {
        Add-Warning "docker.exe not found; skipped compose validation."
    } else {
        $process = Start-Process -FilePath $docker.Source `
            -ArgumentList @("compose", "-f", $composePath, "config", "--quiet") `
            -WorkingDirectory $projectDir -Wait -PassThru -NoNewWindow
        if ($process.ExitCode -ne 0) { Add-Error "docker compose config --quiet failed." }
    }
}

$node = Get-Command node.exe -ErrorAction SilentlyContinue
$packageManifestPath = Join-Path $projectDir 'package.json'
$packageLockPath = Join-Path $projectDir 'package-lock.json'
if (Test-Path -LiteralPath $packageManifestPath -PathType Leaf) {
    try {
        $packageManifest = Get-Content -LiteralPath $packageManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $devDependencies = $packageManifest.PSObject.Properties['devDependencies'].Value
        $playwrightCore = if ($devDependencies) { $devDependencies.PSObject.Properties['playwright-core'] } else { $null }
        if ($null -eq $playwrightCore -or [string]::IsNullOrWhiteSpace([string]$playwrightCore.Value)) {
            Add-Error 'package.json must declare playwright-core for the portable browser smoke test.'
        }
    } catch {
        Add-Error "package.json is not valid JSON: $($_.Exception.Message)"
    }
}
if (Test-Path -LiteralPath $packageLockPath -PathType Leaf) {
    try {
        # Windows PowerShell 5.1 cannot ConvertFrom-Json a normal npm lockfile
        # because npm uses an empty-string key for the project package.
        $packageLockText = Get-Content -LiteralPath $packageLockPath -Raw -Encoding UTF8
        $lockedPlaywright = [regex]::Match(
            $packageLockText,
            '(?s)"node_modules/playwright-core"\s*:\s*\{\s*"version"\s*:\s*"(?<version>[^"]+)"\s*,\s*"resolved"\s*:\s*"(?<resolved>[^"]+)"'
        )
        if (-not $lockedPlaywright.Success) {
            Add-Error 'package-lock.json must lock playwright-core for the portable browser smoke test.'
        } elseif ([string]$lockedPlaywright.Groups['version'].Value -ne [string]$playwrightCore.Value) {
            Add-Error 'package-lock.json playwright-core version must match package.json exactly.'
        } else {
            $expectedPlaywrightResolved = "https://registry.npmjs.org/playwright-core/-/playwright-core-$([string]$playwrightCore.Value).tgz"
            if ([string]$lockedPlaywright.Groups['resolved'].Value -ne $expectedPlaywrightResolved) {
                Add-Error 'package-lock.json must use the public npm registry for playwright-core.'
            }
        }
    } catch {
        Add-Error "package-lock.json could not be read: $($_.Exception.Message)"
    }
}
if ($node) {
    $html = [System.IO.File]::ReadAllText((Join-Path $projectDir "web\index.html"))
    $stylesPath = Join-Path $projectDir "web\styles.css"
    $appPath = Join-Path $projectDir "web\app.js"
    $app = if (Test-Path -LiteralPath $appPath -PathType Leaf) {
        [System.IO.File]::ReadAllText($appPath)
    } else {
        Add-Error "Web Console JavaScript bundle is missing: web\\app.js"
        ""
    }
    if ($html -notmatch '<link\s+rel="stylesheet"\s+href="styles\.css"\s*/?>') {
        Add-Error "Web Console must load its external stylesheet: web\\styles.css"
    }
    if ($html -notmatch '<script\s+src="app\.js"\s*></script>') {
        Add-Error "Web Console must load its external JavaScript bundle: web\\app.js"
    }
    if ($html -notmatch 'id="panel-mods"') { Add-Error "Web Console Mod panel is missing." }
    foreach ($id in @("settingsSummary", "groupFilter", "saveDock", "playerTableWrap",
        "dashboardWarnings", "tunnelProof", "btnCheckTunnel", "smartLogs", "incidentList", "logSummary",
        "statCpuRing", "statCpuRingValue", "statMemRing", "statMemRingValue",
        "logArchiveList", "btnRefreshArchives", "playerTimesWrap", "btnRefreshPlayerTimes")) {
        if ($html -notmatch "id=`"$id`"") { Add-Error "Web Console expanded UI element is missing: $id" }
    }
    if ($html -notmatch 'id="statCpuCapacity"' -or
        $app -notmatch 'rawCpuPct\s*/\s*cpuLimit') {
        Add-Error "CPU display must normalize Docker CPU percent against the allocated multi-core capacity."
    }
    if ($app -notmatch "data-setting-help" -or
        $app -notmatch [regex]::Escape("https://docs.palworldgame.com/settings-and-operation/configuration/")) {
        Add-Error "Per-setting help or its official documentation link is missing."
    }
    if ($html -and -not ([System.IO.File]::ReadAllText((Join-Path $projectDir "README.md")) -match '\[[^\]]+\]\(README\.en\.md\)')) {
        Add-Error "README.md must link to the English self-hosting guide."
    }
    if ([regex]::Matches($app, 'function\s+formatDuration\s*\(').Count -ne 1) {
        Add-Error "Web Console must define exactly one shared formatDuration function."
    }
    $backend = [System.IO.File]::ReadAllText((Join-Path $projectDir "settings-panel.ps1"))
    if ($backend -match 'remotePanelOrigin|PANEL_ADMIN_PASSWORD|http://\+:') {
        Add-Error "Web Console must not contain a remote-management origin, password path, or wildcard listener."
    }
    foreach ($requiredLoopbackPrefix in @('http://localhost:', 'http://127.0.0.1:', 'http://[::1]:')) {
        if ($backend -notmatch [regex]::Escape($requiredLoopbackPrefix)) {
            Add-Error "Web Console loopback listener prefix is missing: $requiredLoopbackPrefix"
        }
    }
    if ($backend -notmatch 'Test-LoopbackRequest' -or $backend -notmatch 'Mutating requests require a loopback Host and a matching Origin when supplied') {
        Add-Error "Web Console local-only and same-origin request gates are incomplete."
    }
    foreach ($publicFile in @('CODE_OF_CONDUCT.md', 'GOVERNANCE.md', 'SUPPORT.md', 'docs\public-release-readiness.md',
        '.github\ISSUE_TEMPLATE\config.yml', '.github\dependabot.yml', 'docker-compose.override.example.yml')) {
        if (-not (Test-Path -LiteralPath (Join-Path $projectDir $publicFile) -PathType Leaf)) {
            Add-Error "Open-source maintenance file is missing: $publicFile"
        }
    }
    $ciWorkflowPath = Join-Path $projectDir '.github\workflows\validate.yml'
    if (-not (Test-Path -LiteralPath $ciWorkflowPath -PathType Leaf)) {
        Add-Error 'Windows CI workflow is missing.'
    } else {
        $ciWorkflow = [System.IO.File]::ReadAllText($ciWorkflowPath)
        if ($ciWorkflow -notmatch [regex]::Escape('.\scripts\test-player-session-times.ps1')) {
            Add-Error 'Windows CI must run the disposable player-session accounting regression.'
        }
        if ($ciWorkflow -notmatch [regex]::Escape('.\scripts\test-runtime-orchestration-contract.ps1')) {
            Add-Error 'Windows CI must run the source-only dual-runtime orchestration contract.'
        }
        if ($ciWorkflow -notmatch [regex]::Escape('.\scripts\test-runtime-common-behavior.ps1')) {
            Add-Error 'Windows CI must run the disposable runtime-common behavior regression.'
        }
        if ($ciWorkflow -notmatch [regex]::Escape('.\scripts\test-recover-runtime-state-behavior.ps1')) {
            Add-Error 'Windows CI must run the disposable stale runtime-state recovery regression.'
        }
        if ($ciWorkflow -notmatch [regex]::Escape('.\scripts\test-log-archive-route.ps1')) {
            Add-Error 'Windows CI must run the direct log-archive route regression.'
        }
        if ($ciWorkflow -notmatch [regex]::Escape('npm ci --ignore-scripts --no-audit --no-fund') -or
            $ciWorkflow -notmatch [regex]::Escape("require.resolve('playwright-core')")) {
            Add-Error 'Windows CI must install and resolve the declared browser-smoke library without running browser scripts.'
        }
        foreach ($forbiddenCiToken in @('actions/setup-dotnet@', 'dotnet restore', 'dotnet build', 'dotnet publish', 'signtool', 'actions/upload-artifact', 'gh release', 'softprops/action-gh-release')) {
            if ($ciWorkflow.Contains($forbiddenCiToken)) {
                Add-Error "Windows CI must not build, sign, upload, or publish release artifacts: $forbiddenCiToken"
            }
        }
        if ($ciWorkflow -notmatch [regex]::Escape('.\scripts\test-release-policy.ps1') -or
            $ciWorkflow -notmatch [regex]::Escape('.\scripts\audit-public-release.ps1 -Strict')) {
            Add-Error 'Windows CI must run the source-only release-policy and publication-audit checks.'
        }
        if ($ciWorkflow -notmatch [regex]::Escape('node scripts/test-player-command-picker.cjs') -or
            $ciWorkflow -notmatch [regex]::Escape('node scripts/test-console-guided-actions.cjs') -or
            $ciWorkflow -notmatch [regex]::Escape('node scripts/test-compare-save-integrity.cjs') -or
            $ciWorkflow -notmatch [regex]::Escape('.\scripts\test-desktop-installer.ps1') -or
            $ciWorkflow -notmatch [regex]::Escape('.\scripts\test-windows-installer-bat.ps1')) {
            Add-Error 'Windows CI must run the player-command-picker, guided-action, and save-integrity source contracts.'
        }
    }
    if ($backend -notmatch 'lastErrorAgeMinutes' -or
        $backend -notmatch 'activeErrorWindowMinutes\s*=\s*15') {
        Add-Error "Tunnel status must distinguish active errors from historical incidents."
    }
    foreach ($route in @("/api/dashboard", "/api/settings", "/api/logs/insights", "/api/incidents",
        "/api/log-archives", "/api/log-archives/refresh", "/api/log-archives/download",
        "/api/tunnel", "/api/tunnel/check", "/api/player-times", "/api/mods", "/api/mods/check", "/api/mods/sync")) {
        if ($backend -notmatch [regex]::Escape($route)) { Add-Error "Web Console backend route is missing: $route" }
    }
    if (Test-Path -LiteralPath $appPath -PathType Leaf) {
        $process = Start-Process -FilePath $node.Source -ArgumentList @("--check", $appPath) `
            -Wait -PassThru -NoNewWindow
        if ($process.ExitCode -ne 0) { Add-Error "Web Console JavaScript syntax check failed." }
    }
    $uiSmokePath = Join-Path $projectDir "scripts\ui-smoke.cjs"
    if (Test-Path -LiteralPath $uiSmokePath -PathType Leaf) {
        $uiSmokeSource = [System.IO.File]::ReadAllText($uiSmokePath)
        if ($uiSmokeSource -notmatch [regex]::Escape("require('playwright-core')") -or
            $uiSmokeSource -notmatch 'DevToolsActivePort' -or
            $uiSmokeSource -notmatch 'PALWORLD_UI_SMOKE_CHROME') {
            Add-Error 'Browser smoke must use its declared portable Playwright/Chrome prerequisites and an ephemeral DevTools endpoint.'
        }
        $process = Start-Process -FilePath $node.Source -ArgumentList @("--check", $uiSmokePath) `
            -Wait -PassThru -NoNewWindow
        if ($process.ExitCode -ne 0) { Add-Error "UI smoke JavaScript syntax check failed." }
    }
    $i18nParityPath = Join-Path $projectDir "scripts\test-i18n-parity.cjs"
    if (Test-Path -LiteralPath $i18nParityPath -PathType Leaf) {
        $process = Start-Process -FilePath $node.Source -ArgumentList @("--check", $i18nParityPath) `
            -Wait -PassThru -NoNewWindow
        if ($process.ExitCode -ne 0) { Add-Error "I18N parity JavaScript syntax check failed." }
        $process = Start-Process -FilePath $node.Source -ArgumentList @($i18nParityPath) `
            -Wait -PassThru -NoNewWindow
        if ($process.ExitCode -ne 0) { Add-Error "Chinese and English I18N key sets differ." }
    }
    foreach ($sourceContractPath in @(
        (Join-Path $projectDir "scripts\test-player-command-picker.cjs"),
        (Join-Path $projectDir "scripts\test-console-guided-actions.cjs"),
        (Join-Path $projectDir "scripts\test-compare-save-integrity.cjs")
    )) {
        if (-not (Test-Path -LiteralPath $sourceContractPath -PathType Leaf)) { continue }
        $process = Start-Process -FilePath $node.Source -ArgumentList @("--check", $sourceContractPath) `
            -Wait -PassThru -NoNewWindow
        if ($process.ExitCode -ne 0) { Add-Error "JavaScript syntax check failed: $([System.IO.Path]::GetFileName($sourceContractPath))"; continue }
        $process = Start-Process -FilePath $node.Source -ArgumentList @($sourceContractPath) `
            -Wait -PassThru -NoNewWindow
        if ($process.ExitCode -ne 0) { Add-Error "Web Console source contract failed: $([System.IO.Path]::GetFileName($sourceContractPath))" }
    }
} else {
    Add-Warning "node.exe not found; skipped JavaScript syntax validation."
}

$desktopHostTest = Join-Path $projectDir 'scripts\test-desktop-host.ps1'
if (Test-Path -LiteralPath $desktopHostTest -PathType Leaf) {
    try {
        # Reset $LASTEXITCODE so a non-zero leftover from an earlier native
        # command cannot be mistaken for this script's result. test-desktop-host.ps1
        # throws on failure (handled by catch) and exits 0 on success; PowerShell
        # leaves $LASTEXITCODE as $null when a script never calls a native command,
        # so treat $null as success.
        $LASTEXITCODE = 0
        & $desktopHostTest
        if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) { Add-Error "Desktop host source contract failed with exit code $LASTEXITCODE." }
    } catch {
        Add-Error "Desktop host source contract failed: $($_.Exception.Message)"
    }
}

$desktopInstallerTest = Join-Path $projectDir 'scripts\test-desktop-installer.ps1'
if (Test-Path -LiteralPath $desktopInstallerTest -PathType Leaf) {
    try {
        $LASTEXITCODE = 0
        & $desktopInstallerTest
        if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            Add-Error "Desktop installer source contract failed with exit code $LASTEXITCODE."
        }
    } catch {
        Add-Error "Desktop installer source contract failed: $($_.Exception.Message)"
    }
}

$windowsInstallerBatTest = Join-Path $projectDir 'scripts\test-windows-installer-bat.ps1'
if (Test-Path -LiteralPath $windowsInstallerBatTest -PathType Leaf) {
    try {
        $LASTEXITCODE = 0
        & $windowsInstallerBatTest
        if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            Add-Error "Windows installer BAT contract failed with exit code $LASTEXITCODE."
        }
    } catch {
        Add-Error "Windows installer BAT contract failed: $($_.Exception.Message)"
    }
}

$firstRunBatTest = Join-Path $projectDir 'scripts\test-first-run-bat.ps1'
if (Test-Path -LiteralPath $firstRunBatTest -PathType Leaf) {
    try {
        $LASTEXITCODE = 0
        & $firstRunBatTest
        if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            Add-Error "First-run BAT contract failed with exit code $LASTEXITCODE."
        }
    } catch {
        Add-Error "First-run BAT contract failed: $($_.Exception.Message)"
    }
}

$envMigrationTest = Join-Path $projectDir 'scripts\test-env-migration.ps1'
if (Test-Path -LiteralPath $envMigrationTest -PathType Leaf) {
    try {
        $LASTEXITCODE = 0
        & $envMigrationTest
        if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            Add-Error "Environment migration contract failed with exit code $LASTEXITCODE."
        }
    } catch {
        Add-Error "Environment migration contract failed: $($_.Exception.Message)"
    }
}

$winInstallerPreflightTest = Join-Path $projectDir 'scripts\test-win-installer-preflight.ps1'
if (Test-Path -LiteralPath $winInstallerPreflightTest -PathType Leaf) {
    try {
        $LASTEXITCODE = 0
        & $winInstallerPreflightTest
        if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            Add-Error "Windows installer preflight contract failed with exit code $LASTEXITCODE."
        }
    } catch {
        Add-Error "Windows installer preflight contract failed: $($_.Exception.Message)"
    }
}

$powershellEncodingTest = Join-Path $projectDir 'scripts\test-powershell-encoding.ps1'
if (Test-Path -LiteralPath $powershellEncodingTest -PathType Leaf) {
    try {
        $LASTEXITCODE = 0
        & $powershellEncodingTest
        if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            Add-Error "PowerShell encoding contract failed with exit code $LASTEXITCODE."
        }
    } catch {
        Add-Error "PowerShell encoding contract failed: $($_.Exception.Message)"
    }
}

$runtimeOrchestrationContract = Join-Path $projectDir 'scripts\test-runtime-orchestration-contract.ps1'
if (Test-Path -LiteralPath $runtimeOrchestrationContract -PathType Leaf) {
    try {
        $LASTEXITCODE = 0
        & $runtimeOrchestrationContract
        if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            Add-Error "Dual-runtime orchestration source contract failed with exit code $LASTEXITCODE."
        }
    } catch {
        Add-Error "Dual-runtime orchestration source contract failed: $($_.Exception.Message)"
    }
}

$runtimeCommonBehaviorTest = Join-Path $projectDir 'scripts\test-runtime-common-behavior.ps1'
if (Test-Path -LiteralPath $runtimeCommonBehaviorTest -PathType Leaf) {
    try {
        $LASTEXITCODE = 0
        & $runtimeCommonBehaviorTest
        if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            Add-Error "Runtime-common behavior regression failed with exit code $LASTEXITCODE."
        }
    } catch {
        Add-Error "Runtime-common behavior regression failed: $($_.Exception.Message)"
    }
}

$recoverRuntimeStateBehaviorTest = Join-Path $projectDir 'scripts\test-recover-runtime-state-behavior.ps1'
if (Test-Path -LiteralPath $recoverRuntimeStateBehaviorTest -PathType Leaf) {
    try {
        $LASTEXITCODE = 0
        & $recoverRuntimeStateBehaviorTest
        if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            Add-Error "Stale runtime-state recovery regression failed with exit code $LASTEXITCODE."
        }
    } catch {
        Add-Error "Stale runtime-state recovery regression failed: $($_.Exception.Message)"
    }
}

$logArchiveRouteTest = Join-Path $projectDir 'scripts\test-log-archive-route.ps1'
if (Test-Path -LiteralPath $logArchiveRouteTest -PathType Leaf) {
    try {
        $LASTEXITCODE = 0
        & $logArchiveRouteTest
        if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            Add-Error "Direct log-archive route regression failed with exit code $LASTEXITCODE."
        }
    } catch {
        Add-Error "Direct log-archive route regression failed: $($_.Exception.Message)"
    }
}

$managementNetworkContract = Join-Path $projectDir 'scripts\test-management-network-contract.ps1'
if (Test-Path -LiteralPath $managementNetworkContract -PathType Leaf) {
    try {
        $LASTEXITCODE = 0
        & $managementNetworkContract
        if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            Add-Error "Management/network source contract failed with exit code $LASTEXITCODE."
        }
    } catch {
        Add-Error "Management/network source contract failed: $($_.Exception.Message)"
    }
}

$instanceIsolationTest = Join-Path $projectDir 'scripts\test-instance-isolation.ps1'
if (Test-Path -LiteralPath $instanceIsolationTest -PathType Leaf) {
    try {
        $LASTEXITCODE = 0
        & $instanceIsolationTest
        if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            Add-Error "Instance isolation regression failed with exit code $LASTEXITCODE."
        }
    } catch {
        Add-Error "Instance isolation regression failed: $($_.Exception.Message)"
    }
}

$windowsRestCompatibilityTest = Join-Path $projectDir 'scripts\test-windows-rest-compatibility.ps1'
if (Test-Path -LiteralPath $windowsRestCompatibilityTest -PathType Leaf) {
    try {
        $LASTEXITCODE = 0
        & $windowsRestCompatibilityTest
        if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            Add-Error "Windows REST compatibility regression failed with exit code $LASTEXITCODE."
        }
    } catch {
        Add-Error "Windows REST compatibility regression failed: $($_.Exception.Message)"
    }
}

$launchConfigTest = Join-Path $projectDir 'scripts\test-launch-config.ps1'
if (Test-Path -LiteralPath $launchConfigTest -PathType Leaf) {
    try {
        $LASTEXITCODE = 0
        & $launchConfigTest
        if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            Add-Error "Launch configuration contract failed with exit code $LASTEXITCODE."
        }
    } catch {
        Add-Error "Launch configuration contract failed: $($_.Exception.Message)"
    }
}

$releasePolicyTest = Join-Path $projectDir 'scripts\test-release-policy.ps1'
if (Test-Path -LiteralPath $releasePolicyTest -PathType Leaf) {
    try {
        $LASTEXITCODE = 0
        & $releasePolicyTest
        if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            Add-Error "Release policy contract failed with exit code $LASTEXITCODE."
        }
    } catch {
        Add-Error "Release policy contract failed: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------
# Runtime state validation (M1)
# ---------------------------------------------------------------------------
$runtimeStatePath = Join-Path $projectDir "data\runtime.state"
if (Test-Path -LiteralPath $runtimeStatePath -PathType Leaf) {
    try {
        $rtState = Get-Content -LiteralPath $runtimeStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($field in @("active","switching")) {
            if ($rtState.PSObject.Properties.Name -notcontains $field) {
                Add-Error "runtime.state missing required field: $field"
            }
        }
        $activeVal = [string]$rtState.active
        if ($activeVal -notin @("docker","windows","none","unknown")) {
            Add-Error "runtime.state active field has invalid value: $activeVal"
        }
    } catch {
        Add-Error "runtime.state is not valid JSON: $($_.Exception.Message)"
    }
} else {
    Add-Warning "runtime.state not found; will be auto-created on next runtime-common.ps1 load"
}

# ---------------------------------------------------------------------------
# Dual INI validation (M2)
# ---------------------------------------------------------------------------
function ConvertTo-CanonicalOptionSettings {
    param([Parameter(Mandatory)][string]$IniText)

    # The Docker image rewrites booleans and numeric literals (for example
    # True -> true and 1.0 -> 1.000000).  Compare parsed OptionSettings values
    # rather than reporting a false drift warning for that formatting-only
    # rewrite.  Commas within CrossplayPlatforms are protected by nesting and
    # quoted strings are kept intact.
    $match = [regex]::Match($IniText, 'OptionSettings=\((?<body>.*)\)', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $match.Success) { return $null }

    $parts = New-Object System.Collections.Generic.List[string]
    $buffer = New-Object System.Text.StringBuilder
    $depth = 0
    $quoted = $false
    foreach ($ch in $match.Groups['body'].Value.ToCharArray()) {
        if ($ch -eq '"') { $quoted = -not $quoted }
        if (-not $quoted) {
            if ($ch -eq '(') { $depth++ }
            elseif ($ch -eq ')' -and $depth -gt 0) { $depth-- }
            elseif ($ch -eq ',' -and $depth -eq 0) {
                $parts.Add($buffer.ToString())
                [void]$buffer.Clear()
                continue
            }
        }
        [void]$buffer.Append($ch)
    }
    $parts.Add($buffer.ToString())

    $values = @{}
    foreach ($part in $parts) {
        $separator = $part.IndexOf('=')
        if ($separator -lt 1) { return $null }
        $key = $part.Substring(0, $separator).Trim()
        $value = $part.Substring($separator + 1).Trim()
        if ($value -match '^(?i:true|false)$') {
            $value = $value.ToLowerInvariant()
        } elseif ($value -match '^-?\d+(?:\.\d+)?$') {
            try {
                $number = [decimal]::Parse($value, [System.Globalization.CultureInfo]::InvariantCulture)
                $value = $number.ToString('0.############################', [System.Globalization.CultureInfo]::InvariantCulture)
            } catch { }
        }
        $values[$key] = $value
    }
    return $values
}

function Test-EquivalentOptionSettings {
    param([Parameter(Mandatory)][string]$Left, [Parameter(Mandatory)][string]$Right)
    $leftValues = ConvertTo-CanonicalOptionSettings $Left
    $rightValues = ConvertTo-CanonicalOptionSettings $Right
    if ($null -eq $leftValues -or $null -eq $rightValues -or $leftValues.Count -ne $rightValues.Count) { return $false }
    foreach ($key in $leftValues.Keys) {
        if (-not $rightValues.ContainsKey($key) -or $leftValues[$key] -cne $rightValues[$key]) { return $false }
    }
    return $true
}

$linuxIniPath = Join-Path $projectDir "data\Pal\Saved\Config\LinuxServer\PalWorldSettings.ini"
$windowsIniPath = Join-Path $projectDir "win-server\Pal\Saved\Config\WindowsServer\PalWorldSettings.ini"

if ((Test-Path -LiteralPath $linuxIniPath -PathType Leaf) -and `
    (Test-Path -LiteralPath $windowsIniPath -PathType Leaf)) {
    $linuxIniRaw = Get-Content -LiteralPath $linuxIniPath -Raw
    $windowsIniRaw = Get-Content -LiteralPath $windowsIniPath -Raw
    # Normalize line endings for content comparison
    $linuxNorm = $linuxIniRaw -replace "`r`n", "`n"
    $windowsNorm = $windowsIniRaw -replace "`r`n", "`n"
    if ($linuxNorm -ne $windowsNorm -and -not (Test-EquivalentOptionSettings $linuxNorm $windowsNorm)) {
        Add-Warning "PalWorldSettings.ini semantic content differs between Linux and Windows; run compile-settings.ps1 and inspect the generated values."
    }

    # Check critical fields exist in both
    foreach ($key in @("ServerPlayerMaxNum","CoopPlayerMaxNum","ExpRate","ServerName","RCONEnabled","AdminPassword")) {
        if ($windowsIniRaw -notmatch "$key=") {
            Add-Error "Windows runtime PalWorldSettings.ini missing critical key: $key"
        }
    }

    # Drift detection: .env mtime vs INI mtime
    $envMtime = (Get-Item -LiteralPath $envPath).LastWriteTime
    $iniMtime = (Get-Item -LiteralPath $windowsIniPath).LastWriteTime
    if ($envMtime -gt $iniMtime) {
        Add-Warning "Config drift: .env was modified after INI compilation; run compile-settings.ps1"
    }
} else {
    if (-not (Test-Path -LiteralPath $linuxIniPath -PathType Leaf)) {
        Add-Warning "LinuxServer PalWorldSettings.ini not found; will be generated by container or compile-settings.ps1"
    }
    if (-not (Test-Path -LiteralPath $windowsIniPath -PathType Leaf)) {
        Add-Warning "Windows runtime PalWorldSettings.ini not found; run scripts\compile-settings.ps1"
    }
}

# Compile log existence
$compileLogPath = Join-Path $projectDir "data\diagnostics\ini-compile.log"
if (-not (Test-Path -LiteralPath $compileLogPath -PathType Leaf)) {
    Add-Warning "INI compile log not found; run scripts\compile-settings.ps1 at least once"
}

# ---------------------------------------------------------------------------
# Junction validation (M4 precondition): only check if win-server exists
# ---------------------------------------------------------------------------
$winServerSaveGames = Join-Path $projectDir "win-server\Pal\Saved\SaveGames"
$saveGamesTarget = Join-Path $projectDir "data\Pal\Saved\SaveGames"
if (Test-Path -LiteralPath $winServerSaveGames -PathType Container) {
    $item = Get-Item -LiteralPath $winServerSaveGames -Force -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType -eq 'Junction') {
        # Use Target property (Resolve-Path returns the junction itself in some PS versions)
        $currentTarget = $null
        if ($item.PSObject.Properties.Name -contains 'Target') {
            $currentTarget = [string]$item.Target
            if ($currentTarget -is [System.Array]) { $currentTarget = $currentTarget[0] }
        }
        $currentNorm = if ($currentTarget) { $currentTarget.TrimEnd('\') } else { '' }
        $expectedNorm = $saveGamesTarget.TrimEnd('\')
        if ($currentNorm -ne $expectedNorm) {
            Add-Error "win-server SaveGames junction points to wrong target: $currentNorm (expected $expectedNorm)"
        }
    } elseif ($item -and $item.LinkType -ne 'Junction') {
        Add-Warning "win-server\Pal\Saved\SaveGames exists but is not a junction; run switch-runtime.ps1 -To windows to create it"
    }
}

# ---------------------------------------------------------------------------
# Disaster recovery validation (M10)
# ---------------------------------------------------------------------------

# recover-runtime-state.ps1 must exist and parse cleanly
$recoverScriptPath = Join-Path $projectDir "scripts\recover-runtime-state.ps1"
if (-not (Test-Path -LiteralPath $recoverScriptPath -PathType Leaf)) {
    Add-Error "Disaster recovery script missing: scripts\recover-runtime-state.ps1"
}

# restore-snapshot.ps1 must exist
$restoreScriptPath = Join-Path $projectDir "scripts\restore-snapshot.ps1"
if (-not (Test-Path -LiteralPath $restoreScriptPath -PathType Leaf)) {
    Add-Error "Snapshot restore script missing: scripts\restore-snapshot.ps1"
}

# switch-runtime.ps1 must exist
$switchScriptPath = Join-Path $projectDir "scripts\switch-runtime.ps1"
if (-not (Test-Path -LiteralPath $switchScriptPath -PathType Leaf)) {
    Add-Error "Runtime switch script missing: scripts\switch-runtime.ps1"
}

# runtime.state consistency: if active=docker, container should be running;
# if active=windows, PalServer.exe should be running. Cross-check helps detect
# a stale/corrupt state file that would otherwise surprise the next switch.
if (Test-Path -LiteralPath $runtimeStatePath -PathType Leaf) {
    try {
        $rtStateForDr = Get-Content -LiteralPath $runtimeStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $activeForDr = [string]$rtStateForDr.active
        $switchingForDr = [bool]$rtStateForDr.switching

        # Stuck switching flag detection (design §9.1)
        if ($switchingForDr -and $rtStateForDr.lastSwitchAt) {
            try {
                $lastSwitch = [datetime]$rtStateForDr.lastSwitchAt
                $elapsed = (Get-Date) - $lastSwitch
                if ($elapsed.TotalMinutes -gt 5) {
                    Add-Warning "runtime.state switching flag stuck for $([int]$elapsed.TotalMinutes) min; run recover-runtime-state.ps1 or Test-RuntimeSwitching will auto-reset"
                }
            } catch {
                Add-Warning "runtime.state lastSwitchAt is not parseable: $($rtStateForDr.lastSwitchAt)"
            }
        }

        # Cross-check active runtime against actual processes
        $dockerRunning = $false
        try {
            $inspect = & docker.exe inspect -f '{{.State.Running}}' $verificationContainerName 2>$null
            if ($LASTEXITCODE -eq 0 -and $inspect -eq 'true') { $dockerRunning = $true }
        } catch { }

        $winRunning = $false
        if (Get-Process -Name 'PalServer' -ErrorAction SilentlyContinue) { $winRunning = $true }

        if ($activeForDr -eq 'docker' -and -not $dockerRunning -and -not $switchingForDr) {
            Add-Warning "runtime.state active=docker but container is not running; run start-docker.bat or recover-runtime-state.ps1"
        }
        if ($activeForDr -eq 'windows' -and -not $winRunning -and -not $switchingForDr) {
            Add-Warning "runtime.state active=windows but PalServer.exe is not running; run switch-runtime.ps1 -To windows or recover-runtime-state.ps1"
        }
        if ($activeForDr -eq 'none' -and ($dockerRunning -or $winRunning)) {
            Add-Warning "runtime.state active=none but a runtime process is running; run recover-runtime-state.ps1 to reconcile"
        }
        if ($dockerRunning -and $winRunning) {
            Add-Error "Both Docker container and PalServer.exe are running; this violates runtime mutex. Run recover-runtime-state.ps1 and stop one runtime."
        }
    } catch {
        Add-Error "runtime.state is not valid JSON for disaster recovery check: $($_.Exception.Message)"
    }
}

# Snapshot directory sanity (if any snapshots exist, manifest.json must exist)
$snapshotDir = Join-Path $projectDir "data\switch-snapshots"
if (Test-Path -LiteralPath $snapshotDir -PathType Container) {
    $snapshotFiles = @(Get-ChildItem -LiteralPath $snapshotDir -Filter '*.tar.gz' -File -ErrorAction SilentlyContinue)
    if ($snapshotFiles.Count -gt 0) {
        $snapshotManifest = Join-Path $snapshotDir 'manifest.json'
        if (-not (Test-Path -LiteralPath $snapshotManifest -PathType Leaf)) {
            Add-Warning "Snapshots exist but manifest.json is missing; restore-snapshot.ps1 may not be able to verify them"
        } else {
            try {
                $snapManifest = Get-Content -LiteralPath $snapshotManifest -Raw -Encoding UTF8 | ConvertFrom-Json
                if (-not $snapManifest.snapshots) {
                    Add-Warning "Snapshot manifest.json has no snapshots array"
                }
            } catch {
                Add-Error "Snapshot manifest.json is not valid JSON: $($_.Exception.Message)"
            }
        }
        # Total size warning over 2 GB (design §3.4)
        $totalBytes = ($snapshotFiles | Measure-Object -Property Length -Sum).Sum
        if ($totalBytes -gt 2147483648) {
            Add-Warning "Switch snapshots total $([math]::Round($totalBytes / 1GB, 2)) GB exceed 2 GB; consider running retention cleanup"
        }
    }
}

foreach ($warning in $warnings) { Write-Host "[WARN] $warning" -ForegroundColor Yellow }
foreach ($errorMessage in $errors) { Write-Host "[FAIL] $errorMessage" -ForegroundColor Red }

if ($errors.Count -gt 0) {
    Write-Host "VERIFY_ERRORS=$($errors.Count)"
    exit 1
}

Write-Host "[OK] Project static validation passed." -ForegroundColor Green
Write-Host "VERIFY_ERRORS=0"
exit 0
