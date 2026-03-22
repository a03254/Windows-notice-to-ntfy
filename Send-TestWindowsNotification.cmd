@echo off
setlocal

cd /d "%~dp0"
title send test windows notification

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Send-TestWindowsNotification.ps1"

echo.
pause
