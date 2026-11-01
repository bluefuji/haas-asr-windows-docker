#Requires -Version 7.0

param(
    [string]$InputPath
)

[Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($InputPath)) {
    $InputPath = Read-Host '処理する音声・動画ファイルを入力してください'
}

$InputPath = $InputPath.Trim('"')

try {
    $audio = (Resolve-Path -LiteralPath $InputPath).Path
}
catch {
    Write-Host "ファイルが見つかりません: $InputPath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $audio -PathType Leaf)) {
    Write-Host "ファイルを指定してください: $audio" -ForegroundColor Red
    exit 1
}

$extension = [System.IO.Path]::GetExtension($audio).ToLowerInvariant()

$supportedExtensions = @(
    '.wav',
    '.flac',
    '.mp3',
    '.ogg',
    '.m4a',
    '.mp4',
    '.webm'
)

if ($extension -notin $supportedExtensions) {
    Write-Host "対応していない形式です: $extension" -ForegroundColor Red
    Write-Host "対応形式: $($supportedExtensions -join ', ')"
    exit 1
}

# 元ファイルと同じフォルダへ出力
$outDir = Split-Path -Parent $audio
$outName = [System.IO.Path]::GetFileName($audio) + '.txt'
$outputPath = Join-Path $outDir $outName

# bashで特殊文字を扱わせないため、コンテナ内では安全な一時名を使用
$tempName = 'haas_speakers_' + [Guid]::NewGuid().ToString('N') + '.txt'
$tempPath = Join-Path $outDir $tempName

Write-Host ''
Write-Host 'Haas-ASR 話者分離を開始します。' -ForegroundColor Cyan
Write-Host "入力: $audio"
Write-Host "出力: $outputPath"
Write-Host ''

try {
    docker run --rm --gpus all --ipc=host `
      --entrypoint bash `
      --env "TEMP_NAME=$tempName" `
      --env "PYTHONIOENCODING=utf-8" `
      --mount "type=bind,src=$audio,dst=/data/input$extension,readonly" `
      --mount "type=bind,src=$outDir,dst=/output" `
      --mount "type=volume,src=haas-hf-cache,dst=/tmp/huggingface" `
      haas-asr:local `
      -lc 'ffmpeg -hide_banner -loglevel error -y -i /data/input* -map 0:a:0 -vn -ac 1 -ar 16000 -c:a pcm_s16le /tmp/input.wav && uv run --project examples/speakers python examples/speakers/transcribe_with_speakers.py /tmp/input.wav > "/output/${TEMP_NAME}"'

    if ($LASTEXITCODE -ne 0) {
        throw "Dockerの処理に失敗しました。終了コード: $LASTEXITCODE"
    }

    if (-not (Test-Path -LiteralPath $tempPath -PathType Leaf)) {
        throw "文字起こし結果が生成されませんでした: $tempPath"
    }

    if ((Get-Item -LiteralPath $tempPath).Length -eq 0) {
        throw '生成された文字起こし結果が空です。'
    }

    Move-Item `
        -LiteralPath $tempPath `
        -Destination $outputPath `
        -Force

    Write-Host ''
    Write-Host '話者分離付き文字起こしが完了しました。' -ForegroundColor Green
    Write-Host "保存先: $outputPath"
}
catch {
    if (Test-Path -LiteralPath $tempPath) {
        Remove-Item -LiteralPath $tempPath -Force
    }

    Write-Host ''
    Write-Host "処理に失敗しました: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}