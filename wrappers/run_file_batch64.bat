@echo off
chcp 65001 > nul

pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_file_batch64.ps1" "%~1"

echo.
pause