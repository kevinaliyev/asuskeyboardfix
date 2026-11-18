@echo off
setlocal

:: Check for Administrator privileges; re-launch with UAC prompt if needed
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting Administrator privileges...
    set "__WRAPPER_PATH=%~f0"
    powershell -NoProfile -Command "Start-Process -FilePath $env:__WRAPPER_PATH -Verb RunAs"
    exit /b
)

echo.
echo ============================================================================
echo  ASUS Keyboard Wake Fix (One-Time Run)
echo ============================================================================
echo  TIP: For automatic protection on every startup and wake from sleep, it is
echo       highly recommended to register this fix as a scheduled task by
echo       double-clicking "install-task.cmd" (or running schedule-task.ps1 as
echo       Administrator).
echo ============================================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fix.ps1"

echo.
pause
