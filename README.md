# Haas-ASR Docker + Windows wrappers / Windows 用の Docker ラッパー

[日本語](#日本語) | [English](#english)

Haas-ASR（日本語音声認識モデル [Haas-ja-v1.0](https://huggingface.co/third-intelligence/Haas-ja-v1.0)）を、
**Windows で Docker だけ**使って動かすための、薄いラッパー集です。
Python も ffmpeg もインストールせず、`.bat` にファイルをドラッグして文字起こしします。

本リポジトリが足しているのは次のものだけで、認識本体は upstream をそのまま使います。

- `Dockerfile` — upstream を clone して必要な環境を作るイメージ（upstream には Docker 定義がありません）
- `haas.bat` — ファイルでもフォルダでもドラッグできる統合ランチャー
- `wrappers/` — 目的ごとの個別ランチャー（ドラッグするだけで実行）
- `scripts/` — コンテナ内で動く文字起こしスクリプトと、統合ランチャーの本体

元のリポジトリ: [third-intelligence/Haas-ASR](https://github.com/third-intelligence/Haas-ASR)（Apache-2.0）。
本リポジトリは非公式です（[NOTICE](NOTICE) 参照）。

---

## 日本語

### 動作条件

| 項目 | 内容 |
|---|---|
| GPU | **NVIDIA GPU** が必要です（Docker Desktop + WSL2 経由で使います）。CPU だけの PC や macOS では動きません。upstream の認識処理が Triton/CUDA を前提にしているためです |
| ディスク | **数十 GB** の空きが必要です（CUDA 12.8 イメージ、PyTorch/NeMo などの依存、話者ラベル用の別環境、モデルの重み） |
| PowerShell | **PowerShell 7（`pwsh`）が必要です。** `run_browser.bat` 以外の `.bat` は `pwsh` で動きます（`winget install Microsoft.PowerShell` でインストールできます） |
| 不要なもの | Python / uv / ffmpeg / NeMo のインストール、Hugging Face へのログイン |

### 1. イメージを作る（1回だけ）

```bat
docker build -t haas-asr:local .
```

ビルドには時間がかかります。本体の環境に加えて、話者ラベル用とブラウザデモ用の環境もここで作るためです。

upstream は tag を付けていないので、[Dockerfile](Dockerfile) では動作を確認した commit `acc614f` に固定しています
（uv のバージョンも固定しています）。upstream の最新版を使いたいときは、次のようにビルドします。

```bat
docker build -t haas-asr:local --build-arg HAAS_REF=main .
```

その場合は、話者ラベル付きのフォルダ一括も一度試してください。このモードは upstream の使用例
（`examples/speakers/transcribe_with_speakers.py`）の関数を読み込んで使っているので、
upstream がそのファイルを書き換えると動かなくなることがあります。

### 2. 使う（統合版 `haas.bat`）

`haas.bat` に**音声・動画ファイル**か**フォルダ**をドラッグします（ダブルクリックで起動して、あとからパスを入力することもできます）。
メニューが出るので、番号を選んでください。

```
  1) 文字起こし（時刻付き）
  2) 話者ラベル付き文字起こし
  3) ブラウザデモ
```

| 選択 | ファイルを渡したとき | フォルダを渡したとき |
|---|---|---|
| 1) 時刻付き | 同じ場所に `元のファイル名.txt`（既存なら上書き） | 各音声の隣に `元のファイル名.txt`（既存ならスキップ） |
| 2) 話者ラベル付き | 同じ場所に `元のファイル名.speakers.txt`（既存なら上書き） | 各音声の隣に `元のファイル名.speakers.txt`（既存ならスキップ） |

**3) ブラウザデモ**を選ぶと、ファイルを渡す必要はなく、少し待つと `http://localhost:7860/longform` がブラウザで開きます。
音声をアップロードして文字起こししたり、マイクの音声にリアルタイムで字幕を付けたりできます。
終了するときは、黒い画面で `Ctrl+C` を押してください。

### 2'. 使う（個別版 `wrappers/`）

毎回メニューを選ぶのが面倒なときは、目的ごとの `.bat` を使います。

| 目的 | 起動 | 出力 |
|---|---|---|
| 1本の音声・動画 | `wrappers/run_file_batch64.bat` にファイルをドラッグ | 同じ場所に `元のファイル名.txt`（既存なら上書き） |
| フォルダ一括 | `wrappers/run_folder_batch64.bat` を起動し、フォルダパスを入力 | 各音声の隣に `元のファイル名.txt`（既存ならスキップ） |
| 話者ラベル付き（1本） | `wrappers/run_speakers.bat` にファイルをドラッグ | 同じ場所に `元のファイル名.txt`（`Speaker 1: …` 形式、既存なら上書き） |
| 話者ラベル付き（フォルダ一括） | `wrappers/run_folder_with_speakers.bat` を起動し、フォルダパスを入力 | 各音声の隣に `元のファイル名.speakers.txt`（既存ならスキップ） |
| ブラウザデモ | `wrappers/run_browser.bat` | `http://localhost:7860/longform` が自動で開きます |

`.bat` をデスクトップに置きたいときは、コピーではなく**ショートカット**を作ってください。
`.bat` は自分と同じフォルダにある `.ps1` を探すので、コピーすると動きません。

対応形式: `.wav` `.flac` `.mp3` `.ogg` `.m4a` `.mp4` `.webm`
（動画は最初の音声トラックだけを取り出し、16 kHz モノラルに変換して認識します。映像は使いません）

### 出力の形

**時刻付き**

```
[00:00:00.0] 最初の区間の認識結果
[00:00:28.6] 次の区間の認識結果
[00:00:59.5] …
```

モデルは 30 秒までの発話で学習されているので、長い音声は区切って処理します。
区切り方は upstream の `transcribe_longform` と同じで、**約 30 秒ごとに、その前後 2 秒の中で一番静かな位置**で
区切ります（`haas_asr.split_at_quiet_points`）。各行の `[hh:mm:ss.s]` は、その区間が始まった時刻です。

静かな位置で区切るので、語の途中で切れることはほとんどありません。ただし 1 行は発言ごとではなく約 30 秒分なので、
字幕のように細かくタイミングを合わせる用途には向きません。

30 秒ちょうどで区切る以前の方式に戻したいときは、リポジトリのフォルダで次のように実行します
（時刻は `[00:00:30]` の形式になります。スクリプトを直接使う場合は `--split fixed` です）。

```bat
pwsh -NoProfile -File scripts\haas.ps1 -Mode timestamp -Split fixed "C:\path\to\audio.mp4"
```

**話者ラベル付き**

```
[00:00:00.9] Speaker 1: こんにちは、本日はよろしくお願いします
[00:00:04.2] Speaker 2: よろしくお願いします
[00:00:06.9] Speaker 1: では始めましょうか
```

upstream の話者分離モデル（Nemotron-3-Diarization）で「誰がいつ話したか」を調べ、発言ごとに文字起こしします。
時刻はその発言が始まった時刻です。30 秒を超える発言だけは、静かな位置で分けて認識します。
話者には登場した順に `Speaker 1, 2, …` と番号が付きます（誰なのかまでは分かりません）。
声の違いで聞き分けているため、声が似ている人や、同時に話している部分は、同じ話者にまとめられることがあります。

### VRAM が足りないとき

一度に処理する区間の数（batch size）は 64 にしています。作者の環境では 8 より 64 のほうが良い結果でしたが、
VRAM の少ない GPU ではメモリ不足（out of memory）で止まることがあります。その場合は `16` や `8` に下げてください。

- 統合版: [scripts/haas.ps1](scripts/haas.ps1) の先頭にある `[int]$BatchSize = 64` を書き換える（時刻付き・話者ラベル付きの両方に効きます）
- 個別版: `wrappers/run_file_batch64.ps1` / `wrappers/run_folder_batch64.ps1` の中の `--batch-size 64` を書き換える

区間の長さ（統合版の `$ChunkSeconds`、個別版の `--chunk-seconds`）も同じ場所で変えられます。

なお upstream の説明によると、batch size を変えると、判定が僅差の箇所で数文字変わることがあります。

### カスタム語彙（人名・作品名などを正しく書かせる）

人名・作品名・専門用語などがうまく認識されないときは、語彙として登録できます。

1. [words.example.txt](words.example.txt) をコピーし、`haas.bat` と同じフォルダに **`words.txt`** という名前で置く
2. 1行に1語ずつ、`表記=読み,読み` の形で書く（読みはひらがなでもカタカナでもよく、省略もできます）

```
# この行のように # で始まる行と、空行は無視されます
Haas=ハース
田中ミク=たなかみく
サードインテリジェンス
```

`words.txt` を置くと、`haas.bat` は時刻付き・話者ラベル付きのどちらでも自動で読み込みます
（起動時に「カスタム語彙: …」と表示されます）。登録した語は認識されやすくなり、読みで認識された箇所は左側の表記で書かれます。

- 登録した語は、実際には言っていない箇所にも出てきやすくなります。本当に必要な語だけに絞ってください
- `wrappers/` の個別版は `words.txt` を読みません。語彙を使うときは `haas.bat` を使ってください
- `words.txt` は `.gitignore` に入っているので、fork して使っても誤ってコミットされることはありません

仕組みは upstream の `haas_asr.Vocabulary` です。詳しくは upstream の
[examples/transcribe_with_vocabulary.py](https://github.com/third-intelligence/Haas-ASR/blob/main/examples/transcribe_with_vocabulary.py) を参照してください。

### キャッシュ

Hugging Face から取得したモデルの重み（Haas と話者分離モデル、合わせて数 GB）は、毎回ダウンロードし直さなくて済むよう
Docker volume `haas-hf-cache` に保存しています。プログラムやライブラリはすべてイメージの中にあるので、
実行時にダウンロードするのはこの重みだけです。

ディスクを空けたいときは、次のコマンドで消せます（次回の実行時にまたダウンロードされます）。

```bat
docker volume rm haas-hf-cache
```

### トラブルシューティング

- **`could not find a CUDA device` や `--gpus` に関するエラーが出る** — Docker Desktop の Settings → Resources → Advanced で GPU が有効になっているか、WSL の中で `nvidia-smi` が動くかを確認してください。`nvidia-smi` が動かない環境では使えません
- **`Unable to find image 'haas-asr:local'` と出る** — イメージがまだありません。「1. イメージを作る」を実行してください
- **`pwsh` が見つからないと出る** — PowerShell 7 をインストールしてください
- **1回目の実行がとても遅い** — モデルの重み（Haas と話者分離モデル）をダウンロードしているためです。2回目からは保存済みのものを使います
- **フォルダ一括で一部のファイルだけ失敗した** — 失敗したファイルの `.txt` は作られず、最後に理由と成功・失敗・スキップの件数が表示されます。成功したファイルの結果は残ります
- **フォルダ一括が書き込みエラーで止まる** — 結果の `.txt` は音声と同じフォルダに書き込みます。読み取り専用のフォルダ（共有フォルダなど）では使えないので、書き込めるフォルダにコピーしてから実行してください
- **作り直したい** — フォルダ一括は、`.txt` がすでにあるファイルを飛ばします。作り直したいファイルの `.txt` を削除してから実行してください

### ファイル構成

```
haas.bat                     統合ランチャー（ここから使う）
words.example.txt            カスタム語彙の見本（words.txt にコピーして使う）
Dockerfile                   イメージの定義（upstream を commit 固定で取得し、本体・話者ラベル用・デモ用の環境を作る）
scripts/
  haas.ps1                   統合ランチャーの本体
  transcribe_timestamped.py  1本の音声を静かな位置で区切り、時刻付きテキストを出力
  transcribe_folder.py       上のフォルダ一括版（動画の変換・サブフォルダ・スキップ・成功/失敗の集計）
  transcribe_folder_with_speakers.py
                             フォルダ内一括の話者ラベル付き版（upstream の speakers 例の関数を使い、
                             モデルは最初に1回だけ読み込む）
wrappers/
  run_file_batch64.bat/.ps1         1本用
  run_folder_batch64.bat/.ps1       フォルダ一括
  run_speakers.bat/.ps1             話者ラベル付き（1本）
  run_folder_with_speakers.bat/.ps1 話者ラベル付き（フォルダ一括）
  run_browser.bat                   upstream のブラウザデモを 7860 番ポートで起動
LICENSE / NOTICE             Apache-2.0 と出所の表記
```

`scripts/` の `.py` は Windows で直接実行するものではありません。`docker run` のときにコンテナへ渡して使います。

### 作者メモ

もともと自分用に作ったものを公開しています。動作確認は作者の環境（Windows 11 + NVIDIA GPU）でしかしていません。

- 体感では、Whisper よりかなり精度が良いです
- 一人だけが話しているバイノーラル音声なら、これに読み込ませてモノラルに変換する処理で問題なく認識できます
- 二人が同時に耳元で話している音声は、話者ラベル付きでもうまく分けられません。
  バイノーラル録音では左右どちらのチャンネルにも両方の声が入っているので、ステレオの左右で分けても解決しないことなどに起因しているのかと。
  話者の声が大きく違えば、認識するかもしれませんが、確認不足です。

---

## English

A thin wrapper set for running [Haas-ASR](https://github.com/third-intelligence/Haas-ASR) /
[Haas-ja-v1.0](https://huggingface.co/third-intelligence/Haas-ja-v1.0) (Japanese ASR) on **Windows with Docker only** —
no local Python or ffmpeg; drag a file or a folder onto `haas.bat` to get a transcript.

Added here: a `Dockerfile` (the upstream repo ships none), Windows launchers (`haas.bat` and the per-task
`wrappers/`), and transcription scripts that cut long audio at quiet points and emit timestamps.

### Requirements

- **NVIDIA GPU** on Windows via Docker Desktop (WSL2 GPU passthrough). **CPU-only and macOS are not supported** —
  the decoder's attention kernels need Triton and CUDA, which is an upstream requirement.
- **Tens of GB** of free disk (CUDA 12.8 image, PyTorch/NeMo dependencies, model weights, the speaker-label environment).
- **PowerShell 7 (`pwsh`)** for `haas.bat` and every wrapper except `run_browser.bat`.
- Nothing else to install locally.

### Build once

```bash
docker build -t haas-asr:local .
```

The build also creates the speaker-label and browser-demo environments. The default pins a verified upstream
commit (the upstream repo has no tags) and a fixed uv version. Follow upstream with `--build-arg HAAS_REF=main`,
then try the speaker-label mode once: the folder version imports functions from the upstream example
`examples/speakers/transcribe_with_speakers.py`, which upstream may change.

### Run

**All-in-one:** drag an audio/video file **or a folder** onto `haas.bat` (or double-click it and type a path),
then pick `1` timestamped transcript, `2` speaker labels, or `3` browser demos.

| Choice | Given a file | Given a folder |
|---|---|---|
| 1) Timestamped | `<original name>.txt` next to it (overwritten) | `<original name>.txt` beside each file (existing ones skipped) |
| 2) Speaker labels | `<original name>.speakers.txt` next to it (overwritten) | `<original name>.speakers.txt` beside each file (existing ones skipped) |
| 3) Browser demos | opens `http://localhost:7860/longform` | — |

**One `.bat` per task** (no menu) lives in `wrappers/`:

| Task | Start | Output |
|---|---|---|
| One file | drag it onto `wrappers/run_file_batch64.bat` | `<original name>.txt` next to the input (overwritten) |
| Whole folder | `wrappers/run_folder_batch64.bat`, then type a folder path | `<original name>.txt` beside each file (existing ones are skipped) |
| Speaker labels, one file | drag onto `wrappers/run_speakers.bat` | `<original name>.txt` with `Speaker 1: …` lines (overwritten) |
| Speaker labels, whole folder | `wrappers/run_folder_with_speakers.bat`, then type a folder path | `<original name>.speakers.txt` beside each file (existing ones are skipped) |
| Browser demos | `wrappers/run_browser.bat` | opens `http://localhost:7860/longform` |

To put a launcher on the desktop, create a shortcut rather than copying the `.bat`: each one looks for its
`.ps1` next to itself.

Supported inputs: `.wav` `.flac` `.mp3` `.ogg` `.m4a` `.mp4` `.webm`. Video containers are reduced to their
first audio track (`-map 0:a:0`), resampled to 16 kHz mono.

Timestamped transcripts:

```
[00:00:00.0] ...
[00:00:28.6] ...
```

Haas is trained on utterances up to 30 s, so long audio is cut the way the upstream `transcribe_longform`
does it — roughly every 30 s, at the quietest point within 2 s of each target (`haas_asr.split_at_quiet_points`) —
and each line carries the start time of its chunk. Pass `-Split fixed` (or `--split fixed` to the scripts) for
the older exact 30-second windows.

Speaker-labelled transcripts come from the upstream diarization example: one line per speaker turn, stamped
with the turn's start, speakers numbered in order of appearance:

```
[00:00:00.9] Speaker 1: ...
[00:00:04.2] Speaker 2: ...
```

Out of memory? Lower the batch size to `16` or `8`: `[int]$BatchSize = 64` at the top of `scripts/haas.ps1`
(both modes), or `--batch-size 64` in `wrappers/run_*_batch64.ps1`. 64 gave the author better results
than 8, but it needs more VRAM. `--chunk-seconds` is in the same place.

**Custom vocabulary:** copy [words.example.txt](words.example.txt) to `words.txt` next to `haas.bat` and list one
word per line as `written form=reading,reading` (readings optional, hiragana or katakana). `haas.bat` then boosts
those words in both modes and writes them in their written form. Keep the list short: listed words also turn up
where they were not said more often. The `wrappers/` do not read `words.txt`.

The model weights are kept in the named volume `haas-hf-cache` (everything else is inside the image, so these
weights are the only runtime download); removing it forces a re-download.

CPU-only hosts, missing GPU passthrough, and the first run's download time are the most common problems —
see the 日本語 troubleshooting section for the checks.

### Not affiliated with Third Intelligence

The recogniser, the model weights and the speaker-diarization and demo code come from
[third-intelligence/Haas-ASR](https://github.com/third-intelligence/Haas-ASR). The files in this repository are
Apache-2.0 (see [LICENSE](LICENSE) and [NOTICE](NOTICE)); third-party components keep their own licenses.
