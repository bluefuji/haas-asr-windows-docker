@echo off
chcp 65001 > nul
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_folder_with_speakers.ps1"
echo.
pause
