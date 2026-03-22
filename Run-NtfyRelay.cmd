@echo off
setlocal

title ntfy relay
cd /d "%~dp0"

echo Starting ntfy relay...
echo.
echo Mobile topic:
echo   Check your local config.json
echo.
echo EZ Notification Forwarder target:
echo   http://127.0.0.1:8787/notify/
echo.
echo Press Ctrl+C to stop the relay.
echo Or close this window directly.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-NtfyRelay.ps1" -ConfigPath "%~dp0config.json"

echo.
echo Relay stopped.
pause
