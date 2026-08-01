@echo off
setlocal EnableExtensions
title Palworld Server Toolkit - Install Windows Native Server

set "PROJECT_DIR=%~dp0"

if /i "%~1"=="/self-test" goto self_test

cd /d "%PROJECT_DIR%" >nul 2>&1
if errorlevel 1 (
    echo [FAIL] Could not enter the project directory: %PROJECT_DIR%
    pause
    exit /b 1
)

echo ============================================================
echo   Palworld Server Toolkit - Windows Native Server Installer
echo ============================================================
echo.
echo This will download SteamCMD and about 5 GB of Palworld server files.
echo The first download may take a while. Keep this window open.
echo Existing files are validated and reused when possible.
echo.

where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo [FAIL] Windows PowerShell was not found.
    echo        Windows PowerShell 5.1 or newer is required.
    pause
    exit /b 1
)

if not exist "%PROJECT_DIR%scripts\install-win-server.ps1" (
    echo [FAIL] Installer script is missing:
    echo        %PROJECT_DIR%scripts\install-win-server.ps1
    pause
    exit /b 1
)

echo [INFO] Starting the download and installation. Progress is shown below.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PROJECT_DIR%scripts\install-win-server.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if "%EXIT_CODE%"=="0" (
    echo [OK] Windows native server installation or validation completed.
    echo      Next step: double-click start-windows.bat.
) else (
    echo [FAIL] Installation failed with exit code %EXIT_CODE%.
    echo        Read the error above, fix the reported prerequisite, and run this BAT again.
)
echo.
pause
exit /b %EXIT_CODE%

:self_test
if not exist "%PROJECT_DIR%scripts\install-win-server.ps1" exit /b 1
if not exist "%PROJECT_DIR%.env.example" exit /b 1
where powershell.exe >nul 2>&1
if errorlevel 1 exit /b 1
echo BAT_SELF_TEST=passed
exit /b 0
