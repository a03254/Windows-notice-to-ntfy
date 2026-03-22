@echo off
setlocal

cd /d "%~dp0"
python -m windows_notice_to_ntfy test-toast --title "ntfy forwarder test" --message "If this toast is forwarded to your phone, the Windows notification listener is working."
