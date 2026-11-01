@echo off
title Haas-ASR
chcp 65001 > nul

where pwsh.exe > nul 2>&1
if errorlevel 1 goto no_pwsh

pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\haas.ps1" "%~1"

echo.
pause
exit /b

:no_pwsh
echo PowerShell 7 (pwsh) が見つかりません。
echo winget install Microsoft.PowerShell でインストールしてください。
echo.
pause
exit /b 1
