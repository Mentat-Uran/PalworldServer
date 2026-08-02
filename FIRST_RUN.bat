@echo off
setlocal EnableExtensions
title Palworld Server - First Run

set "PROJECT_DIR=%~dp0"

if /i "%~1"=="/self-test" goto self_test
if "%~1"=="" set "RUNTIME=windows"
if /i "%~1"=="windows" set "RUNTIME=windows"
if /i "%~1"=="docker" set "RUNTIME=docker"
if not defined RUNTIME goto usage

if not exist "%PROJECT_DIR%scripts\bootstrap-first-run.ps1" (
    echo [FAIL] bootstrap-first-run.ps1 was not found.
    echo        Run this file from the extracted project root.
    pause
    exit /b 1
)

where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo [FAIL] powershell.exe was not found.
    pause
    exit /b 1
)

cd /d "%PROJECT_DIR%"
echo ============================================
echo   Palworld Server - First Run
echo ============================================
echo Runtime: %RUNTIME%
echo.
echo This creates .env and project.json.
echo The generated administrator password is not printed.
echo Store it in a password manager after setup.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PROJECT_DIR%scripts\bootstrap-first-run.ps1" -Runtime "%RUNTIME%"
set "EXIT_CODE=%ERRORLEVEL%"
if not "%EXIT_CODE%"=="0" (
    echo.
    echo [FAIL] First-run setup failed with exit code %EXIT_CODE%.
    echo        Review the error above and run this file again after fixing it.
) else (
    echo.
    echo [OK] First-run setup completed.
    echo      Next: run scripts\test-host-prerequisites.ps1.
)
pause
exit /b %EXIT_CODE%

:usage
echo Usage: FIRST_RUN.bat [windows^|docker]
echo Default runtime: windows
pause
exit /b 2

:self_test
if not exist "%PROJECT_DIR%scripts\bootstrap-first-run.ps1" exit /b 1
where powershell.exe >nul 2>&1
if errorlevel 1 exit /b 1
echo FIRST_RUN_BAT_SELF_TEST=passed
exit /b 0
