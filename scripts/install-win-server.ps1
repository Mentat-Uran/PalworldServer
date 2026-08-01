# install-win-server.ps1
#
# Installs the Windows-native Palworld Dedicated Server via SteamCMD.
# Idempotent: re-running without -Force only validates the existing install.
#
# Usage:
#   .\scripts\install-win-server.ps1              # Install or validate
#   .\scripts\install-win-server.ps1 -Force       # Reinstall
#   .\scripts\install-win-server.ps1 -UpdateOnly  # Just run app_update
#   .\scripts\install-win-server.ps1 -FirewallOnly # Only enforce REST/RCON inbound blocks

param(
    [switch]$Force,
    [switch]$UpdateOnly,
    [switch]$SkipFirewall,
    [switch]$FirewallOnly
)

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$steamcmdDir = Join-Path $projectDir 'steamcmd'
$winServerDir = Join-Path $projectDir 'win-server'
$steamcmdExe = Join-Path $steamcmdDir 'steamcmd.exe'
$palServerExe = Join-Path $winServerDir 'PalServer.exe'
$versionFile = Join-Path $winServerDir 'version.txt'
$steamcmdZip = Join-Path $env:TEMP 'steamcmd.zip'
$steamcmdUrl = 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip'

# Palworld Dedicated Server Steam App ID
$appId = 2394010

# Load runtime-common for incident logging
. (Join-Path $PSScriptRoot 'runtime-common.ps1')
$firewallScript = Join-Path $PSScriptRoot 'ensure-win-management-firewall.ps1'

if ($FirewallOnly) {
    if ($SkipFirewall) {
        Write-StepError '-FirewallOnly cannot be combined with -SkipFirewall.'
        exit 1
    }
    & $firewallScript
    exit $LASTEXITCODE
}

function Write-Step([string]$Msg) { Write-Host "[install-win-server] $Msg" }
function Write-StepError([string]$Msg) { Write-Host "[install-win-server] ERROR: $Msg" -ForegroundColor Red }

# ---------------------------------------------------------------------------
# Step 0: Check existing install
# ---------------------------------------------------------------------------
if (-not $UpdateOnly) {
    if ((Test-Path -LiteralPath $palServerExe -PathType Leaf) -and -not $Force) {
        Write-Step "PalServer.exe already exists at: $winServerDir"
        Write-Step "Validating existing install (use -Force to reinstall)..."

        # Try to read version
        if (Test-Path -LiteralPath $versionFile -PathType Leaf) {
            $ver = Get-Content -LiteralPath $versionFile -Raw
            Write-Step "Installed version: $($ver.Trim())"
        }

        # Ensure WindowsServer config dir exists
        $winConfigDir = Join-Path $winServerDir 'Pal\Saved\Config\WindowsServer'
        if (-not (Test-Path -LiteralPath $winConfigDir -PathType Container)) {
            New-Item -ItemType Directory -Path $winConfigDir -Force | Out-Null
            Write-Step "Created WindowsServer config directory"
        }

        # Compile INI
        Write-Step "Compiling INI..."
        & (Join-Path $PSScriptRoot 'compile-settings.ps1') -Quiet
        if ($LASTEXITCODE -ne 0) {
            Write-StepError "INI compilation failed"
            exit 1
        }

        # Create junction
        Write-Step "Ensuring SaveGames junction..."
        . (Join-Path $PSScriptRoot 'win-runtime.ps1')
        try {
            Assert-SaveGamesJunction
            Write-Step "Junction OK"
        } catch {
            Write-StepError "Junction failed: $_"
            exit 1
        }

        Write-Step "Validation complete. Use -UpdateOnly to check for updates."
        exit 0
    }

    if ($Force -and (Test-Path -LiteralPath $winServerDir -PathType Container)) {
        Write-Step "Force reinstall: backing up config and removing win-server..."
        $backupDir = Join-Path $projectDir "data\win-server-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        $configBackup = Join-Path $winServerDir 'Pal\Saved\Config'
        if (Test-Path -LiteralPath $configBackup -PathType Container) {
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
            Copy-Item -Path $configBackup -Destination $backupDir -Recurse -Force
            Write-Step "Config backed up to: $backupDir"
        }
        # Remove win-server (junction will be recreated later)
        Remove-Item -LiteralPath $winServerDir -Recurse -Force
        Write-Step "win-server removed"
    }
}

# ---------------------------------------------------------------------------
# Step 1: Download SteamCMD
# ---------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $steamcmdExe -PathType Leaf)) {
    Write-Step "Downloading SteamCMD from: $steamcmdUrl"
    try {
        Invoke-WebRequest -Uri $steamcmdUrl -OutFile $steamcmdZip -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-StepError "Failed to download SteamCMD: $($_.Exception.Message)"
        Write-Incident -Level 'ERROR' -Type 'win-install-failed' -Message "SteamCMD download failed: $($_.Exception.Message)"
        exit 1
    }

    if (-not (Test-Path -LiteralPath $steamcmdDir -PathType Container)) {
        New-Item -ItemType Directory -Path $steamcmdDir -Force | Out-Null
    }
    Write-Step "Extracting SteamCMD to: $steamcmdDir"
    Expand-Archive -Path $steamcmdZip -DestinationPath $steamcmdDir -Force
    Remove-Item -LiteralPath $steamcmdZip -Force -ErrorAction SilentlyContinue
} else {
    Write-Step "SteamCMD already installed at: $steamcmdDir"
}

# ---------------------------------------------------------------------------
# Step 2: Run SteamCMD to install/update Palworld Dedicated Server
# ---------------------------------------------------------------------------
Write-Step "Running SteamCMD to install/update app $appId..."
Write-Step "This will download ~5 GB. Please wait..."

$steamcmdArgs = "+force_install_dir `"$winServerDir`" +login anonymous +app_update $appId validate +quit"
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $steamcmdExe
$psi.Arguments = $steamcmdArgs
$psi.WorkingDirectory = $steamcmdDir
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $false  # SteamCMD needs a console window for some operations

$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi
[void]$proc.Start()

# Stream output to console
$stdoutTask = $proc.StandardOutput.ReadToEndAsync()
$stderrTask = $proc.StandardError.ReadToEndAsync()

# Wait for exit (no timeout — SteamCMD download can take a long time)
$proc.WaitForExit()
$stdout = $stdoutTask.Result
$stderr = $stderrTask.Result

if ($proc.ExitCode -ne 0) {
    Write-StepError "SteamCMD exited with code $($proc.ExitCode)"
    Write-StepError "STDOUT (last 500 chars): $($stdout.Substring([Math]::Max(0, $stdout.Length - 500)))"
    Write-StepError "STDERR: $stderr"
    Write-Incident -Level 'ERROR' -Type 'win-install-failed' -Message "SteamCMD app_update failed (exit=$($proc.ExitCode))"
    exit 1
}

Write-Step "SteamCMD completed."

# ---------------------------------------------------------------------------
# Step 3: Verify PalServer.exe exists
# ---------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $palServerExe -PathType Leaf)) {
    Write-StepError "PalServer.exe not found after SteamCMD install: $palServerExe"
    Write-Incident -Level 'ERROR' -Type 'win-install-failed' -Message "PalServer.exe missing after install"
    exit 1
}
Write-Step "PalServer.exe verified."

# ---------------------------------------------------------------------------
# Step 4: Write version file (Steam build id from appmanifest)
# ---------------------------------------------------------------------------
$manifestPath = Join-Path $winServerDir "steamapps\appmanifest_${appId}.acf"
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw
    if ($manifest -match '"buildid"\s+"(\d+)"') {
        $buildId = $matches[1]
        Set-Content -LiteralPath $versionFile -Value $buildId -Encoding UTF8 -NoNewline
        Write-Step "Version (build $buildId) written to: $versionFile"
    }
}

# ---------------------------------------------------------------------------
# Step 5: Create WindowsServer config directory and compile INI
# ---------------------------------------------------------------------------
$winConfigDir = Join-Path $winServerDir 'Pal\Saved\Config\WindowsServer'
if (-not (Test-Path -LiteralPath $winConfigDir -PathType Container)) {
    New-Item -ItemType Directory -Path $winConfigDir -Force | Out-Null
    Write-Step "Created WindowsServer config directory"
}

Write-Step "Compiling INI..."
& (Join-Path $PSScriptRoot 'compile-settings.ps1') -Quiet
if ($LASTEXITCODE -ne 0) {
    Write-StepError "INI compilation failed"
    exit 1
}

# ---------------------------------------------------------------------------
# Step 6: Create SaveGames junction
# ---------------------------------------------------------------------------
Write-Step "Creating SaveGames junction..."
. (Join-Path $PSScriptRoot 'win-runtime.ps1')
try {
    Assert-SaveGamesJunction
    Write-Step "Junction OK"
} catch {
    Write-StepError "Junction failed: $_"
    exit 1
}

# ---------------------------------------------------------------------------
# Step 7: Create firewall rules to block inbound REST/RCON access
# ---------------------------------------------------------------------------
if (-not $SkipFirewall) {
    Write-Step "Enforcing firewall blocks for inbound REST/RCON..."
    & $firewallScript
    if ($LASTEXITCODE -ne 0) {
        Write-Incident -Level 'ERROR' -Type 'win-firewall-gate-failed' -Message 'Windows REST/RCON firewall blocks are missing; refusing install success.'
        Write-StepError 'Windows management firewall gate failed. Run the -FirewallOnly command from an elevated Administrator PowerShell.'
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
Write-Step ""
Write-Step "============================================"
Write-Step "  Windows Palworld Dedicated Server installed."
Write-Step "  Location: $winServerDir"
Write-Step "  Config:   $winConfigDir\PalWorldSettings.ini"
Write-Step "  Junction: $winServerDir\Pal\Saved\SaveGames -> data\Pal\Saved\SaveGames"
Write-Step "============================================"
Write-Step ""
Write-Step "To start: switch-runtime.ps1 -To windows"
Write-Step "To verify: scripts\verify-project.ps1"

Write-Incident -Level 'INFO' -Type 'win-installed' -Message "Windows dedicated server installed at $winServerDir"
exit 0
