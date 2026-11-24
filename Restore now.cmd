@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0DesktopRestore.ps1" -Action Restore
pause
