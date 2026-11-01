@echo off
title Haas-ASR Speaker Diarization
chcp 65001 > nul

pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_speakers.ps1" "%~1"

echo.
pause
