@echo off
title Haas-ASR Browser

start "" powershell.exe -NoProfile -WindowStyle Hidden -Command "Start-Sleep -Seconds 10; Start-Process 'http://localhost:7860/longform'"

docker run --rm --gpus all --ipc=host ^
  --env PYTHONUNBUFFERED=1 ^
  -p 7860:7860 ^
  --entrypoint bash ^
  --mount "type=volume,src=haas-hf-cache,dst=/tmp/huggingface" ^
  haas-asr:local ^
  -lc "uv run python -m demos.app --host 0.0.0.0"

echo.
echo Haas-ASR has stopped.
pause