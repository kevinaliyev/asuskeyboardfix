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
echo  Installing ASUS N-KEY Keyboard Wake Fix Scheduled Task
echo ============================================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0schedule-task.ps1"

echo.
pause
