@echo off
chcp 65001 > nul
pwsh.exe -NoProfile -ExecutionPolicy Bypass -Command "[Console]::InputEncoding=[System.Text.UTF8Encoding]::new(); [Console]::OutputEncoding=[System.Text.UTF8Encoding]::new(); & '%~dp0run_folder_batch64.ps1'"
echo.
pause