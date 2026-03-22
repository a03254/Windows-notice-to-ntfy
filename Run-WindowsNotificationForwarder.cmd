@echo off
setlocal

title windows notification forwarder
cd /d "%~dp0"

echo Starting Windows notification forwarder...
echo.
echo This window watches Windows notifications and forwards them to:
echo   http://127.0.0.1:8787/notify/
echo.
echo Keep Run-NtfyRelay.cmd open at the same time.
echo.
echo Press Ctrl+C to stop.
echo Or close this window directly.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-WindowsNotificationForwarder.ps1"

echo.
echo Windows notification forwarder stopped.
pause
