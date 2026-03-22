@echo off
setlocal

title ntfy notification stack stopper

echo Stopping ntfy relay and Windows notification forwarder windows...
echo.

taskkill /FI "WINDOWTITLE eq ntfy relay" /FI "IMAGENAME eq cmd.exe" /T /F
taskkill /FI "WINDOWTITLE eq windows notification forwarder" /FI "IMAGENAME eq cmd.exe" /T /F

echo.
echo Stop request sent.
pause
