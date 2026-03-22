@echo off
setlocal

cd /d "%~dp0"
title ntfy notification stack launcher

echo Starting ntfy relay and Windows notification forwarder...
echo.

start "ntfy relay" cmd /k ""%~dp0Run-NtfyRelay.cmd""
timeout /t 2 /nobreak >nul
start "windows notification forwarder" cmd /k ""%~dp0Run-WindowsNotificationForwarder.cmd""

echo Both windows have been launched.
echo.
echo Mobile topic:
echo   Check your local config.json
echo.
echo Close the two opened windows, or run Stop-All.cmd to stop them.
echo.
pause
