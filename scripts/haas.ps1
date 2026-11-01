#Requires -Version 7.0
# Haas-ASR の統合ランチャー（haas.bat から呼ばれる）。
# ファイルでもフォルダでも受け付け、モードはメニューか -Mode で選ぶ。
# 動作は wrappers/ の個別ラッパーと同じ docker run を組み立てている。

param(
    [string]$InputPath,
    [ValidateSet('', 'timestamp', 'speakers', 'browser')]
    [string]$Mode = '',
    [int]$BatchSize = 64,
    [double]$ChunkSeconds = 30,
    # quiet: 無音に近い所で区切る / fixed: ChunkSeconds ごとに機械的に区切る（従来の動作）
    [ValidateSet('quiet', 'fixed')]
    [string]$Split = 'quiet'
)

[Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

$ErrorActionPreference = 'Stop'

$image = 'haas-asr:local'
$model = 'third-intelligence/Haas-ja-v1.0'

$supportedExtensions = @('.wav', '.flac', '.mp3', '.ogg', '.m4a', '.mp4', '.webm')
$videoExtensions = @('.mp4', '.m4a', '.webm')

# 全モード共通の docker run 引数
$commonArgs = @(
    'run', '--rm', '--gpus', 'all', '--ipc=host',
    '--env', 'PYTHONIOENCODING=utf-8',
    '--mount', 'type=volume,src=haas-hf-cache,dst=/tmp/huggingface'
)

# haas.bat と同じフォルダの words.txt があれば、カスタム語彙として使う
$wordsPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'words.txt'
$wordsArgs = @()
$hasWords = Test-Path -LiteralPath $wordsPath -PathType Leaf

if ($hasWords) {
    $wordsArgs = @('--mount', "type=bind,src=$wordsPath,dst=/opt/words.txt,readonly")
}

function Get-ScriptPath([string]$name) {
    (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot $name)).Path
}

function Invoke-Docker([string[]]$arguments, [switch]$Batch) {
    & docker @arguments

    # 終了コード 2 はフォルダ一括のスクリプトが「一部失敗」に使う。
    # 1本だけのときは引数エラーなども 2 になるので、そのまま表示する。
    if ($Batch -and $LASTEXITCODE -eq 2) {
        throw '一部のファイルで失敗しました（上のログを確認してください）'
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Dockerの処理に失敗しました。終了コード: $LASTEXITCODE"
    }
}

function Invoke-SingleFile(
    [string]$audio,
    [string]$outputSuffix,
    [string[]]$extraArgs,
    [string]$command
) {
    $outDir = Split-Path -Parent $audio
    $extension = [System.IO.Path]::GetExtension($audio).ToLowerInvariant()
    $outputPath = Join-Path $outDir ([System.IO.Path]::GetFileName($audio) + $outputSuffix)

    # bashで特殊文字を扱わないための一時ファイル名
    $tempName = 'haas_' + [Guid]::NewGuid().ToString('N') + '.txt'
    $tempPath = Join-Path $outDir $tempName

    Write-Host "入力: $audio"
    Write-Host "出力: $outputPath"
    Write-Host ''

    try {
        Invoke-Docker ($commonArgs + $extraArgs + @(
            '--entrypoint', 'bash',
            '--env', "INPUT_EXT=$extension",
            '--env', "TEMP_NAME=$tempName",
            '--mount', "type=bind,src=$audio,dst=/data/input$extension,readonly",
            '--mount', "type=bind,src=$outDir,dst=/output",
            $image,
            '-lc', $command
        ))

        if (-not (Test-Path -LiteralPath $tempPath -PathType Leaf)) {
            throw "文字起こし結果が生成されませんでした: $tempPath"
        }
        if ((Get-Item -LiteralPath $tempPath).Length -eq 0) {
            throw '生成された文字起こし結果が空です。'
        }

        # 既存の出力があれば上書き
        Move-Item -LiteralPath $tempPath -Destination $outputPath -Force
        Write-Host "保存先: $outputPath"
    }
    catch {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force
        }
        throw
    }
}

function Invoke-Folder(
    [string]$dir,
    [string]$scriptName,
    [string[]]$uvRunArgs,
    [string[]]$scriptArgs
) {
    $script = Get-ScriptPath $scriptName

    Write-Host "フォルダ: $dir"
    Write-Host ''

    Invoke-Docker -Batch ($commonArgs + $wordsArgs + @(
        '--entrypoint', 'uv',
        '--mount', "type=bind,src=$dir,dst=/data",
        '--mount', "type=bind,src=$script,dst=/opt/Haas-ASR/$scriptName,readonly",
        $image,
        'run'
    ) + $uvRunArgs + @(
        'python', "/opt/Haas-ASR/$scriptName",
        '/data', '/data',
        '--model', $model
    ) + $scriptArgs)
}

function Start-BrowserDemo {
    # サーバーの起動を待ってからブラウザを開く
    Start-Process pwsh -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-Command',
        "Start-Sleep -Seconds 10; Start-Process 'http://localhost:7860/longform'"
    )

    & docker @($commonArgs + @(
        '-p', '7860:7860',
        '--entrypoint', 'bash',
        $image,
        '-lc', 'uv run python -m demos.app --host 0.0.0.0'
    ))

    Write-Host ''
    Write-Host 'Haas-ASR のブラウザデモを終了しました。'
}

# ---------------------------------------------------------------------------
# モード選択
# ---------------------------------------------------------------------------

if (-not $Mode) {
    Write-Host ''
    Write-Host 'Haas-ASR' -ForegroundColor Cyan
    Write-Host '  1) 文字起こし（時刻付き）'
    Write-Host '  2) 話者ラベル付き文字起こし'
    Write-Host '  3) ブラウザデモ'
    Write-Host ''

    $choice = (Read-Host '番号を選んでください').Trim()
    switch ($choice) {
        '1' { $Mode = 'timestamp' }
        '2' { $Mode = 'speakers' }
        '3' { $Mode = 'browser' }
        default {
            Write-Host "1〜3 の番号を入力してください: $choice" -ForegroundColor Red
            exit 1
        }
    }
}

if ($Mode -eq 'browser') {
    Start-BrowserDemo
    exit 0
}

# ---------------------------------------------------------------------------
# 入力（ファイルかフォルダか）
# ---------------------------------------------------------------------------

if ([string]::IsNullOrWhiteSpace($InputPath)) {
    $InputPath = Read-Host '処理するファイルまたはフォルダのパスを入力してください'
}

$InputPath = $InputPath.Trim().Trim('"')

if (-not (Test-Path -LiteralPath $InputPath)) {
    Write-Host "ファイルまたはフォルダが見つかりません: $InputPath" -ForegroundColor Red
    exit 1
}

$target = (Resolve-Path -LiteralPath $InputPath).Path
$isFolder = Test-Path -LiteralPath $target -PathType Container

if (-not $isFolder) {
    $extension = [System.IO.Path]::GetExtension($target).ToLowerInvariant()

    if ($extension -notin $supportedExtensions) {
        Write-Host "対応していない形式です: $extension" -ForegroundColor Red
        Write-Host "対応形式: $($supportedExtensions -join ', ')"
        exit 1
    }
}

$invariant = [System.Globalization.CultureInfo]::InvariantCulture
$chunkText = $ChunkSeconds.ToString($invariant)
$batchText = $BatchSize.ToString($invariant)

# 自作スクリプトは --words-file でファイルごと読む
$wordsFileArgs = @()
if ($hasWords) {
    $wordsFileArgs = @('--words-file', '/opt/words.txt')
    Write-Host ''
    Write-Host "カスタム語彙: $wordsPath" -ForegroundColor Cyan
}

Write-Host ''

try {
    if ($Mode -eq 'timestamp' -and -not $isFolder) {
        $script = Get-ScriptPath 'transcribe_timestamped.py'
        $asr = 'uv run python /opt/Haas-ASR/transcribe_timestamped.py' +
            " --model $model --chunk-seconds $chunkText --batch-size $batchText --split $Split" +
            $(if ($hasWords) { ' --words-file /opt/words.txt' } else { '' })

        if ($extension -in $videoExtensions) {
            $command = 'ffmpeg -hide_banner -loglevel error -i "/data/input${INPUT_EXT}" -map 0:a:0 -vn -ac 1 -ar 16000 -c:a pcm_s16le /tmp/input.wav && ' +
                $asr + ' /tmp/input.wav > "/output/${TEMP_NAME}"'
        }
        else {
            $command = $asr + ' "/data/input${INPUT_EXT}" > "/output/${TEMP_NAME}"'
        }

        Invoke-SingleFile $target '.txt' (@(
            '--mount', "type=bind,src=$script,dst=/opt/Haas-ASR/transcribe_timestamped.py,readonly"
        ) + $wordsArgs) $command
    }
    elseif ($Mode -eq 'timestamp') {
        Invoke-Folder $target 'transcribe_folder.py' @() (@(
            '--chunk-seconds', $chunkText,
            '--batch-size', $batchText,
            '--split', $Split
        ) + $wordsFileArgs)
    }
    elseif (-not $isFolder) {
        # upstream のスクリプトは --words "表記=読み" ... を受け取るので、
        # words.txt の行（空行と # で始まる行を除く）を bash の配列にして渡す
        $readWords = 'WORDS=(); if [ -f /opt/words.txt ]; then mapfile -t WORDS < <(tr -d "\r" < /opt/words.txt | sed "1s/^\xEF\xBB\xBF//; s/^[[:space:]]*//; s/[[:space:]]*$//; /^#/d; /^$/d"); fi; '
        $command = $readWords +
            'ffmpeg -hide_banner -loglevel error -y -i "/data/input${INPUT_EXT}" -map 0:a:0 -vn -ac 1 -ar 16000 -c:a pcm_s16le /tmp/input.wav && ' +
            'uv run --project examples/speakers python examples/speakers/transcribe_with_speakers.py /tmp/input.wav --batch-size ' + $batchText + ' ${WORDS[@]+--words "${WORDS[@]}"} > "/output/${TEMP_NAME}"'

        # フォルダ一括と同じ名前にして、通常の文字起こしの .txt と衝突させない
        Invoke-SingleFile $target '.speakers.txt' $wordsArgs $command
    }
    else {
        # upstream の話者分離の関数を使うので、話者分離用の環境で動かす
        Invoke-Folder $target 'transcribe_folder_with_speakers.py' @('--project', 'examples/speakers') (@(
            '--batch-size', $batchText
        ) + $wordsFileArgs)
    }

    Write-Host ''
    Write-Host '完了しました。' -ForegroundColor Green
}
catch {
    Write-Host ''
    Write-Host "処理に失敗しました: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
