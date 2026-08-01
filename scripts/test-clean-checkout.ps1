[CmdletBinding()]
param(
    [string]$SourcePath,
    [switch]$KeepWorkspace
)

$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1 does not reliably populate $PSScriptRoot while it is
# evaluating a parameter default expression. Resolve the project root after
# binding instead, so this documented direct invocation remains portable.
if ([string]::IsNullOrWhiteSpace($SourcePath)) {
    $SourcePath = Split-Path -Parent $PSScriptRoot
}

function Copy-CleanSource {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $excluded = @(
        '.git', '.env', 'data', 'backups', 'output', '.playwright-cli', 'node_modules', 'steamcmd', 'win-server',
        '.settings-panel.pid', '.settings-panel.port', '.daily-log-collector.pid'
    )
    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        if ($excluded -contains $item.Name) { continue }
        if ($item.Name -like '_*' -or $item.Extension -in @('.log', '.tmp')) { continue }
        Copy-Item -LiteralPath $item.FullName -Destination $Destination -Recurse -Force
    }
}

$resolvedSource = (Resolve-Path -LiteralPath $SourcePath -ErrorAction Stop).Path
if (-not (Test-Path -LiteralPath (Join-Path $resolvedSource '.env.example') -PathType Leaf)) {
    throw "SourcePath does not contain .env.example: $resolvedSource"
}
if (-not (Test-Path -LiteralPath (Join-Path $resolvedSource 'scripts\verify-project.ps1') -PathType Leaf)) {
    throw "SourcePath does not contain scripts\\verify-project.ps1: $resolvedSource"
}

$workspace = Join-Path ([System.IO.Path]::GetTempPath()) ("PalworldServer-onboarding-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workspace -Force | Out-Null

try {
    Copy-CleanSource -Source $resolvedSource -Destination $workspace
    $envPath = Join-Path $workspace '.env'
    if (Test-Path -LiteralPath $envPath) {
        throw 'Clean onboarding workspace unexpectedly contains .env before template initialization.'
    }
    foreach ($localOnlyPath in @(
        'node_modules', '.playwright-cli', 'output',
        'desktop\PalworldConsole.Desktop\bin', 'desktop\PalworldConsole.Desktop\obj'
    )) {
        $localOnlyFullPath = Join-Path $workspace $localOnlyPath
        if (Test-Path -LiteralPath $localOnlyFullPath) {
            Remove-Item -LiteralPath $localOnlyFullPath -Recurse -Force
        }
    }
    foreach ($localOnlyPath in @(
        'node_modules', '.playwright-cli', 'output',
        'desktop\PalworldConsole.Desktop\bin', 'desktop\PalworldConsole.Desktop\obj'
    )) {
        if (Test-Path -LiteralPath (Join-Path $workspace $localOnlyPath)) {
            throw "Clean onboarding workspace unexpectedly contains local-only path: $localOnlyPath"
        }
    }

    $templatePath = Join-Path $workspace '.env.example'
    $envText = [System.IO.File]::ReadAllText($templatePath)
    $placeholder = 'ADMIN_PASSWORD=CHANGE_ME_WITH_A_LONG_RANDOM_PASSWORD'
    if ($envText.IndexOf($placeholder, [System.StringComparison]::Ordinal) -lt 0) {
        throw '.env.example does not contain the expected non-secret ADMIN_PASSWORD placeholder.'
    }
    $envText = $envText.Replace($placeholder, 'ADMIN_PASSWORD=onboarding-test-not-a-real-secret-2026')
    [System.IO.File]::WriteAllText($envPath, $envText, (New-Object System.Text.UTF8Encoding($false)))

    $dataPath = Join-Path $workspace 'data'
    New-Item -ItemType Directory -Path $dataPath -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $dataPath '.onboarding-disposable') -Value 'Disposable onboarding data. Do not use for a live server.' -NoNewline -Encoding utf8

    Write-Host "[onboarding] Disposable workspace: $workspace"
    & (Join-Path $workspace 'scripts\verify-project.ps1') -SkipDocker
    $validationSucceeded = $?
    $validationExit = $LASTEXITCODE
    if (-not $validationSucceeded) {
        throw "Static validation failed with exit code $validationExit."
    }
    $node = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($node) {
        foreach ($relativeTest in @(
            'scripts\test-player-command-picker.cjs',
            'scripts\test-console-guided-actions.cjs',
            'scripts\test-compare-save-integrity.cjs',
            'scripts\test-desktop-installer.ps1'
        )) {
            $testPath = Join-Path $workspace $relativeTest
            if ([System.IO.Path]::GetExtension($testPath) -eq '.ps1') {
                & (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $testPath
            } else {
                & $node.Source $testPath
            }
            if ($LASTEXITCODE -ne 0) {
                throw "Clean-checkout source contract failed: $relativeTest (exit $LASTEXITCODE)."
            }
        }
    } else {
        Write-Warning 'node.exe not found; skipped optional JavaScript source-contract checks.'
    }
    Write-Host '[onboarding] Clean-checkout source validation passed. No runtime was started.' -ForegroundColor Green
}
finally {
    if ($KeepWorkspace) {
        Write-Host "[onboarding] Workspace retained: $workspace" -ForegroundColor Yellow
    } elseif (Test-Path -LiteralPath $workspace) {
        Remove-Item -LiteralPath $workspace -Recurse -Force
    }
}
