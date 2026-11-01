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

$script = Join-Path $PSScriptRoot '..\scripts\transcribe_timestamped.py'

if (-not (Test-Path -LiteralPath $script -PathType Leaf)) {
    Write-Host "Pythonスクリプトがありません: $script" -ForegroundColor Red
    exit 1
}

$script = (Resolve-Path -LiteralPath $script).Path

$outDir = Split-Path -Parent $audio
$outName = [System.IO.Path]::GetFileName($audio) + '.txt'
$outputPath = Join-Path $outDir $outName

# bashで特殊文字を扱わないための一時ファイル名
$tempName = 'haas_' + [Guid]::NewGuid().ToString('N') + '.txt'
$tempPath = Join-Path $outDir $tempName

Write-Host ''
Write-Host "入力: $audio"
Write-Host "出力: $outputPath"
Write-Host ''

try {
    if ($extension -in @('.mp4', '.m4a', '.webm')) {
        docker run --rm --gpus all --ipc=host `
          --entrypoint bash `
          --env "INPUT_EXT=$extension" `
          --env "TEMP_NAME=$tempName" `
          --env "PYTHONIOENCODING=utf-8" `
          --mount "type=bind,src=$audio,dst=/data/input$extension,readonly" `
          --mount "type=bind,src=$script,dst=/opt/Haas-ASR/transcribe_timestamped.py,readonly" `
          --mount "type=bind,src=$outDir,dst=/output" `
          --mount "type=volume,src=haas-hf-cache,dst=/tmp/huggingface" `
          haas-asr:local `
          -lc 'ffmpeg -hide_banner -loglevel error -i "/data/input${INPUT_EXT}" -map 0:a:0 -vn -ac 1 -ar 16000 -c:a pcm_s16le /tmp/input.wav && uv run python /opt/Haas-ASR/transcribe_timestamped.py --model third-intelligence/Haas-ja-v1.0 --chunk-seconds 30 --batch-size 64 /tmp/input.wav > "/output/${TEMP_NAME}"'
    }
    else {
        docker run --rm --gpus all --ipc=host `
          --entrypoint bash `
          --env "INPUT_EXT=$extension" `
          --env "TEMP_NAME=$tempName" `
          --env "PYTHONIOENCODING=utf-8" `
          --mount "type=bind,src=$audio,dst=/data/input$extension,readonly" `
          --mount "type=bind,src=$script,dst=/opt/Haas-ASR/transcribe_timestamped.py,readonly" `
          --mount "type=bind,src=$outDir,dst=/output" `
          --mount "type=volume,src=haas-hf-cache,dst=/tmp/huggingface" `
          haas-asr:local `
          -lc 'uv run python /opt/Haas-ASR/transcribe_timestamped.py --model third-intelligence/Haas-ja-v1.0 --chunk-seconds 30 --batch-size 64 "/data/input${INPUT_EXT}" > "/output/${TEMP_NAME}"'
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Dockerの処理に失敗しました。終了コード: $LASTEXITCODE"
    }

    if (-not (Test-Path -LiteralPath $tempPath -PathType Leaf)) {
        throw "文字起こしの一時ファイルが生成されませんでした: $tempPath"
    }

    # 既存の出力があれば上書き
    Move-Item `
        -LiteralPath $tempPath `
        -Destination $outputPath `
        -Force

    Write-Host ''
    Write-Host '文字起こしが完了しました。' -ForegroundColor Green
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