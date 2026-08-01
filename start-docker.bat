@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Palworld Server (Docker)

set "PROJECT_DIR=%~dp0"
set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"

if /i "%~1"=="stop" goto stop

echo ============================================
echo   Palworld Server (Docker) - Starting...
echo ============================================
echo.

echo [1/5] Protected runtime switch: Docker
cd /d "%PROJECT_DIR%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%PROJECT_DIR%\scripts\switch-runtime.ps1" -To docker -FullSnapshot
set "SWITCH_EXIT=!ERRORLEVEL!"
if "!SWITCH_EXIT!"=="2" (
    echo [INFO] Docker runtime is already active.
) else if not "!SWITCH_EXIT!"=="0" (
    echo [FAIL] Protected Docker switch failed; exit code !SWITCH_EXIT!.
    echo        No tunnel or Web Console was started. Inspect the switch log and runtime state.
    pause
    exit /b 1
)

echo.
echo [2/5] Waiting for container to be running...
set /a WAIT_COUNT=0
:wait_container
set "STATE="
for /f "delims=" %%i in ('docker inspect -f "{{.State.Running}}" palworld-server 2^>nul') do set STATE=%%i
if /i not "!STATE!"=="true" (
    set /a WAIT_COUNT+=1
    if !WAIT_COUNT! GEQ 60 (
        echo [FAIL] Container did not enter running state within 120 seconds.
        docker compose logs --tail 80 --no-color palworld-server
        pause
        exit /b 1
    )
    timeout /t 2 /nobreak >nul
    goto wait_container
)
echo [OK] Container is running.

echo.
echo [3/5] Starting configured tunnel provider...
powershell -NoProfile -ExecutionPolicy Bypass -File "%PROJECT_DIR%\scripts\tunnel-provider.ps1" -Action Start
if errorlevel 1 (
    echo [FAIL] Configured tunnel provider could not be started.
    echo        Set NETWORK_MODE=direct to run without a tunnel.
    pause
    exit /b 1
)
echo [OK] Tunnel provider step completed. Provider none is a safe no-op.

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
echo   All started (Docker mode).
echo   - Game: 127.0.0.1:8211
echo   - Web Console: http://localhost:%PANEL_PORT%/
echo   - Tunnel: check the configured provider; external access is not verified here
echo   - Daily logs: data\log-archive\YYYY-MM-DD.txt
echo ============================================
echo.
echo To stop everything: start-docker.bat stop
echo.
exit /b 0

:stop
echo ============================================
echo   Palworld Server (Docker) - Stopping...
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
echo [2/4] Stopping the project-owned tunnel provider...
powershell -NoProfile -ExecutionPolicy Bypass -File "%PROJECT_DIR%\scripts\tunnel-provider.ps1" -Action Stop
if errorlevel 1 echo [WARN] Tunnel provider stop was refused or failed; unrelated processes were not touched.

echo.
echo [3/4] Stopping Docker container (graceful save + SIGTERM)...
cd /d "%PROJECT_DIR%"
docker compose stop -t 120 palworld-server
if errorlevel 1 (
    echo [FAIL] Container stop failed. Check Docker Desktop and run "docker compose ps".
    pause
    exit /b 1
)
echo [OK] Container stopped.
powershell -NoProfile -ExecutionPolicy Bypass -File "%PROJECT_DIR%\scripts\recover-runtime-state.ps1" -Quiet
if errorlevel 1 (
    echo [WARN] Runtime state could not be reconciled after Docker stop. Do not start another runtime until it is repaired.
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
