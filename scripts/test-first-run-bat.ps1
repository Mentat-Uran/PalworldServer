[CmdletBinding()]
param()

# Source and launcher-contract test. /self-test never creates .env, changes
# firewall rules, starts a runtime, or starts PalServer.
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$batPath = Join-Path $projectDir 'FIRST_RUN.bat'

function Assert-FirstRunBat([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FIRST_RUN_BAT_TEST_FAILED: $Message" }
}

Assert-FirstRunBat (Test-Path -LiteralPath $batPath -PathType Leaf) 'FIRST_RUN.bat is missing.'
$bytes = [System.IO.File]::ReadAllBytes($batPath)
Assert-FirstRunBat (-not ($bytes | Where-Object { $_ -gt 127 })) 'FIRST_RUN.bat must remain ASCII.'
$source = [System.IO.File]::ReadAllText($batPath, [System.Text.Encoding]::ASCII)

foreach ($required in @(
    'set "PROJECT_DIR=%~dp0"',
    'scripts\bootstrap-first-run.ps1',
    '-Runtime "%RUNTIME%"',
    'if errorlevel 1',
    'pause',
    '/self-test',
    'FIRST_RUN_BAT_SELF_TEST=passed'
)) {
    Assert-FirstRunBat ($source.Contains($required)) "Missing launcher behavior: $required"
}

$output = & cmd.exe /d /c "`"$batPath`" /self-test" 2>&1 | Out-String
$exitCode = $LASTEXITCODE
Assert-FirstRunBat ($exitCode -eq 0) "Self-test exited with code $exitCode. Output: $output"
Assert-FirstRunBat ($output -match 'FIRST_RUN_BAT_SELF_TEST=passed') 'Self-test did not report success.'

Write-Output 'FIRST_RUN_BAT_SOURCE=passed'
Write-Output 'FIRST_RUN_BAT_EXECUTION=passed'
exit 0
