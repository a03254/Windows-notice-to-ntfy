@echo off
setlocal

cd /d "%~dp0"
python -m windows_notice_to_ntfy run --config "%~dp0config.json"
