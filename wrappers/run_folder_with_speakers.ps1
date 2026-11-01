[Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
$ErrorActionPreference = 'Stop'

$audioDir = Read-Host '話者分離する音声フォルダを入力してください'
$audioDir = $audioDir.Trim('"')

if (-not (Test-Path -LiteralPath $audioDir -PathType Container)) {
    Write-Host "フォルダを指定してください: $audioDir" -ForegroundColor Red
    exit 1
}

$audioDir = (Resolve-Path -LiteralPath $audioDir).Path
$script = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\scripts\transcribe_folder_with_speakers.py')).Path

& docker run --rm --gpus all --ipc=host `
  --entrypoint uv `
  --env "PYTHONIOENCODING=utf-8" `
  --mount "type=bind,src=$audioDir,dst=/data" `
  --mount "type=bind,src=$script,dst=/opt/Haas-ASR/transcribe_folder_with_speakers.py,readonly" `
  --mount "type=volume,src=haas-hf-cache,dst=/tmp/huggingface" `
  haas-asr:local `
  run --project examples/speakers python /opt/Haas-ASR/transcribe_folder_with_speakers.py `
  /data /data `
  --model third-intelligence/Haas-ja-v1.0

$exitCode = $LASTEXITCODE
if ($exitCode -eq 0) {
    Write-Host "`n完了しました: $audioDir" -ForegroundColor Green
} else {
    Write-Host "`n失敗しました。終了コード: $exitCode" -ForegroundColor Red
    exit $exitCode
}
