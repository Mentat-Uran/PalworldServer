[CmdletBinding()]
param(
    [ValidateSet('docker', 'windows')]
    [string]$Runtime = 'docker',
    [switch]$RequireTunnel
)

# Read-only local prerequisite check for a new self-hosting machine. It never
# starts Docker, Palworld, SakuraFrp, SteamCMD, or a Web Console process.
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Add-HostError([string]$Message) { $errors.Add($Message) }
function Add-HostWarning([string]$Message) { $warnings.Add($Message) }

if (-not $IsWindows -and $env:OS -ne 'Windows_NT') {
    Add-HostError 'This repository currently supports Windows hosts only.'
}
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Add-HostError "PowerShell 5.1 or newer is required (found $($PSVersionTable.PSVersion))."
}

try {
    $systemDrive = [System.IO.Path]::GetPathRoot($projectDir)
    $drive = Get-PSDrive -Name $systemDrive.TrimEnd(':', '\') -ErrorAction Stop
    $freeGb = [math]::Round($drive.Free / 1GB, 1)
    if ($freeGb -lt 25) { Add-HostWarning "Only $freeGb GB is free on $systemDrive; allow substantial headroom for game files, worlds and backups." }
} catch {
    Add-HostWarning "Could not determine free disk space: $($_.Exception.Message)"
}
try {
    $memoryGiB = [math]::Round((Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory / 1GB, 1)
    Write-Output "HOST_MEMORY_GIB=$memoryGiB"
    if ($memoryGiB -lt 16) {
        Add-HostWarning "Host memory is $memoryGiB GiB, below Pocketpair's published 16 GiB dedicated-server baseline. Do not treat this configuration as capacity-qualified."
    }
} catch {
    Add-HostWarning "Could not determine physical memory: $($_.Exception.Message)"
}

$envPath = Join-Path $projectDir '.env'
if (-not (Test-Path -LiteralPath $envPath -PathType Leaf)) {
    Add-HostError 'Missing .env. Copy .env.example to .env and set a strong ADMIN_PASSWORD.'
} else {
    $envText = [System.IO.File]::ReadAllText($envPath)
    if ($envText -match '(?m)^\s*ADMIN_PASSWORD\s*=\s*(?:CHANGE_ME|\s*$)') {
        Add-HostError 'ADMIN_PASSWORD is blank or still a template value.'
    }
}

if ($Runtime -eq 'docker') {
    $docker = Get-Command docker.exe -ErrorAction SilentlyContinue
    if (-not $docker) {
        Add-HostError 'docker.exe was not found. Install Docker Desktop with the WSL2 backend.'
    } else {
        try {
            $composeVersion = & $docker.Source compose version 2>$null
            if ($LASTEXITCODE -ne 0 -or -not $composeVersion) { Add-HostError 'Docker Compose v2 is unavailable.' }
            else { Write-Output "HOST_DOCKER_COMPOSE=$composeVersion" }
        } catch { Add-HostError "Docker Compose check failed: $($_.Exception.Message)" }
    }
    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if (-not $wsl) { Add-HostError 'wsl.exe was not found. Docker runtime requires WSL2.' }
} else {
    $palServer = Join-Path $projectDir 'win-server\PalServer.exe'
    if (-not (Test-Path -LiteralPath $palServer -PathType Leaf)) {
        Add-HostError 'Windows dedicated server is not installed. Double-click install-windows-server.bat first.'
    }
}

if ($RequireTunnel) {
    $launcherCandidates = @(
        'C:\Program Files\SakuraFrpLauncher\SakuraLauncher.exe',
        'C:\Program Files\SakuraFrp\SakuraLauncher.exe'
    )
    if (-not (@($launcherCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }).Count)) {
        Add-HostError 'SakuraFrp Launcher was not found in a known default location. Configure a UDP tunnel separately before remote play.'
    }
}

foreach ($message in $warnings) { Write-Warning $message }
foreach ($message in $errors) { Write-Error $message }
Write-Output "HOST_PREREQUISITE_RUNTIME=$Runtime"
Write-Output "HOST_PREREQUISITE_WARNINGS=$($warnings.Count)"
Write-Output "HOST_PREREQUISITE_ERRORS=$($errors.Count)"
if ($errors.Count -gt 0) { exit 1 }
