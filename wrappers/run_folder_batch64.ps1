[Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

$ErrorActionPreference = 'Stop'

$audioDir = Read-Host '処理する音声フォルダを入力してください'
$audioDir = $audioDir.Trim('"')

if (-not (Test-Path -LiteralPath $audioDir -PathType Container)) {
    Write-Host "フォルダを指定してください: $audioDir" -ForegroundColor Red
    exit 1
}

$audioDir = (Resolve-Path -LiteralPath $audioDir).Path

$script = Join-Path $PSScriptRoot '..\scripts\transcribe_folder.py'
$script = (Resolve-Path -LiteralPath $script).Path

docker run --rm --gpus all --ipc=host `
  --entrypoint uv `
  --env "PYTHONIOENCODING=utf-8" `
  --mount "type=bind,src=$audioDir,dst=/data" `
  --mount "type=bind,src=$script,dst=/opt/Haas-ASR/transcribe_folder.py,readonly" `
  --mount "type=volume,src=haas-hf-cache,dst=/tmp/huggingface" `
  haas-asr:local `
  run python /opt/Haas-ASR/transcribe_folder.py `
  /data /data `
  --model third-intelligence/Haas-ja-v1.0 `
  --chunk-seconds 30 `
  --batch-size 64

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n完了しました: $audioDir" -ForegroundColor Green
}
else {
    Write-Host "`n失敗しました。終了コード: $LASTEXITCODE" -ForegroundColor Red
    exit $LASTEXITCODE
}