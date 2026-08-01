@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Palworld Server (Windows Native)

set "PROJECT_DIR=%~dp0"
set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"
set "SAKURA=C:\Program Files\SakuraFrpLauncher\SakuraLauncher.exe"
set "WIN_SERVER=%PROJECT_DIR%\win-server"
set "PAL_SERVER=%WIN_SERVER%\PalServer.exe"

if /i "%~1"=="stop" goto stop

echo ============================================
echo   Palworld Server (Windows Native) - Starting...
echo ============================================
echo.

echo [1/5] Pre-check: PalServer.exe
if not exist "%PAL_SERVER%" (
    echo [FAIL] PalServer.exe not found: %PAL_SERVER%
    echo        Run: powershell -File scripts\install-win-server.ps1
    pause
    exit /b 1
)
echo [OK] PalServer.exe found.

echo.
echo [2/5] Protected runtime switch: Windows native server...
powershell -NoProfile -ExecutionPolicy Bypass -File "%PROJECT_DIR%\scripts\switch-runtime.ps1" -To windows -FullSnapshot
set "SWITCH_EXIT=!ERRORLEVEL!"
if "!SWITCH_EXIT!"=="2" (
    echo [INFO] Windows runtime is already active.
) else if not "!SWITCH_EXIT!"=="0" (
    echo [FAIL] Protected Windows switch failed; exit code !SWITCH_EXIT!.
    echo        No tunnel or Web Console was started. Inspect the switch log and runtime state.
    pause
    exit /b 1
)

echo.
echo [3/5] Starting SakuraFrp Launcher...
if exist "%SAKURA%" (
    start "" "%SAKURA%"
    echo [OK] SakuraFrp started.
) else (
    echo [WARN] SakuraFrp not found at: %SAKURA%
    echo        Edit SAKURA path in this script if installed elsewhere.
)

echo.
echo [4/5] Starting Web Console...
set "PANEL_PORT="
for /f "usebackq delims=" %%P in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%PROJECT_DIR%\scripts\start-web-console.ps1"`) do set "PANEL_PORT=%%P"
if not defined PANEL_PORT (
    echo [WARN] Web Console did not become ready. See data\log-sources\panel\YYYY-MM-DD.log.
) else (
    echo [OK] Web Console ready: http://localhost:%PANEL_PORT%/
)

echo.
echo [5/5] Starting Daily Log Archive...
powershell -NoProfile -Command "$pidPath = '%PROJECT_DIR%\.daily-log-collector.pid'; if (Test-Path -LiteralPath $pidPath) { $id = 0; [void][int]::TryParse((Get-Content -LiteralPath $pidPath -Raw).Trim(), [ref]$id); $p = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $id) -ErrorAction SilentlyContinue; if ($p -and $p.CommandLine -like '*daily-log-collector.ps1*') { exit 0 } }; exit 1" 2>nul
if errorlevel 1 (
    start "" powershell -WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -File "%PROJECT_DIR%\scripts\daily-log-collector.ps1"
    echo [OK] Daily log archive collector started.
) else (
    echo [INFO] Daily log archive collector is already running.
)

if defined PANEL_PORT start "" "http://localhost:%PANEL_PORT%/"

echo.
echo ============================================
echo   All started (Windows Native mode).
echo   - Game: 127.0.0.1:8211
echo   - Web Console: http://localhost:%PANEL_PORT%/
echo   - SakuraFrp: check launcher for tunnel address
echo   - Daily logs: data\log-archive\YYYY-MM-DD.txt
echo ============================================
echo.
echo To stop everything: start-windows.bat stop
echo.
exit /b 0

:stop
echo ============================================
echo   Palworld Server (Windows Native) - Stopping...
echo ============================================
echo.

echo [1/4] Stopping Web Console...
if exist "%PROJECT_DIR%\.settings-panel.pid" (
    powershell -NoProfile -Command "$id = [int](Get-Content -LiteralPath '%PROJECT_DIR%\.settings-panel.pid'); $p = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $id) -ErrorAction SilentlyContinue; if ($p -and $p.CommandLine -like '*settings-panel.ps1*') { Stop-Process -Id $id -Force }" 2>nul
    del /q "%PROJECT_DIR%\.settings-panel.pid" 2>nul
)
if exist "%PROJECT_DIR%\.settings-panel.port" del /q "%PROJECT_DIR%\.settings-panel.port" 2>nul
taskkill /FI "WINDOWTITLE eq Palworld Web Console*" /F 2>nul
echo [OK] Web Console closed.

echo.
echo [2/4] Closing SakuraFrp...
taskkill /IM SakuraLauncher.exe /F 2>nul
echo [OK] SakuraFrp closed.

echo.
echo [3/4] Stopping Windows native server (REST /stop + graceful)...
powershell -NoProfile -ExecutionPolicy Bypass -Command ". '%PROJECT_DIR%\scripts\win-runtime.ps1'; $r = Stop-WindowsRuntime -Grace 120; if ($r.ok) { Write-Host '[OK] Windows server stopped.' } else { Write-Host '[WARN] Stop returned:' $r.detail; if ($r.error) { Write-Host $r.error } }"
if errorlevel 1 (
    echo [WARN] Stop script reported an issue. Check if PalServer.exe is still running.
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%PROJECT_DIR%\scripts\recover-runtime-state.ps1" -Quiet
if errorlevel 1 (
    echo [WARN] Runtime state could not be reconciled after Windows stop. Do not start another runtime until it is repaired.
) else (
    echo [OK] Runtime state reconciled.
)

echo.
echo [4/4] Finalizing Daily Log Archive...
if exist "%PROJECT_DIR%\.daily-log-collector.pid" (
    powershell -NoProfile -Command "$id = [int](Get-Content -LiteralPath '%PROJECT_DIR%\.daily-log-collector.pid'); $p = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $id) -ErrorAction SilentlyContinue; if ($p -and $p.CommandLine -like '*daily-log-collector.ps1*') { Stop-Process -Id $id -Force }" 2>nul
    del /q "%PROJECT_DIR%\.daily-log-collector.pid" 2>nul
)
powershell -ExecutionPolicy Bypass -NoProfile -File "%PROJECT_DIR%\scripts\daily-log-collector.ps1" -Once
if errorlevel 1 (
    echo [WARN] Final daily log refresh failed; existing archives were preserved.
) else (
    echo [OK] Daily log archive finalized.
)

echo.
echo ============================================
echo   All stopped.
echo ============================================
echo.
pause
exit /b 0
