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
| ディスク | **数十 GB** の空きが必要です（CUDA のベースイメージ、PyTorch/NeMo などの依存、話者ラベル用の別環境、モデルの重み） |
| PowerShell | **PowerShell 7（`pwsh`）が必要です。** Windows に最初から入っている PowerShell 5.1 とは別物です（入れ方は「0. 準備」の手順 4） |
| 不要なもの | Python / uv / ffmpeg / NeMo のインストール、Hugging Face へのログイン |

### 0. 準備（1回だけ）

すでに Docker Desktop で GPU を使えている場合は、手順 4（PowerShell 7）と手順 5（GPU の確認）だけ済ませて、手順 6 へ進んでください。

**1) NVIDIA のドライバを Windows に入れる**

[NVIDIA のドライバのページ](https://www.nvidia.com/drivers/) から、お使いの GPU 向けの最新ドライバを Windows にインストールします。
このイメージに入る PyTorch は CUDA 13.0 を使うので、**それに対応した新しいドライバ（580 番台以降が目安）**が必要です
（ベースイメージは CUDA 12.8 ですが、PyTorch が CUDA 13.0 の部品を同梱しています）。
作者の環境は GeForce RTX 5070 Ti + ドライバ 610.88 です。

Windows 用のドライバを入れれば、WSL2 からも GPU が使えるようになります。
**WSL（Linux）の中に NVIDIA のドライバや CUDA を別に入れる必要はありません**（入れるとかえって動かなくなることがあります）。

**2) WSL2 を入れる**

スタートメニューで「PowerShell」を右クリック →**管理者として実行**で開き、次のコマンドを実行してから、Windows を再起動します
（ここは Windows に最初から入っている PowerShell で構いません）。

```bat
wsl --install
```

すでに WSL を入れている場合は、`wsl --update` で最新にしておいてください。

**3) Docker Desktop を入れる**

[Docker Desktop](https://www.docker.com/products/docker-desktop/) をインストールして起動します。
インストール時の「Use WSL 2 instead of Hyper-V」（設定画面では「Use the WSL 2 based engine」）はオンのままにしてください。
Docker Desktop は、個人や小規模な組織なら無料で使えますが、大きな企業で使う場合は有料のプランが必要です（詳しくは Docker の利用条件を確認してください）。

Docker のデータは、既定では C ドライブに保存されます。このイメージだけで数十 GB を使うので、C ドライブに余裕がない場合は
Docker Desktop の Settings → Resources → Advanced → **Disk image location** で、保存先を別のドライブに変えておくと安心です。

**4) PowerShell 7 を入れる**

`haas.bat` と `wrappers/` の `.bat`（`run_browser.bat` 以外）は、**PowerShell 7（`pwsh`）**で動きます。
Windows に最初から入っている「Windows PowerShell」（バージョン 5.1）とは別のソフトなので、入っていなければ追加でインストールします。

```bat
winget install --id Microsoft.PowerShell --source winget
```

`winget` が使えない場合は、Microsoft Store で「PowerShell」を検索してインストールしても構いません。
インストールしたら、新しく開いたコマンドプロンプトで次を実行し、`7.` で始まるバージョンが表示されれば大丈夫です（作者の環境は 7.6.9）。

```bat
pwsh --version
```

**5) Docker から GPU が見えるか確かめる**

Docker Desktop を起動した状態で、PowerShell かコマンドプロンプトで次を実行します。

```bat
docker run --rm --gpus all nvidia/cuda:12.8.1-base-ubuntu24.04 nvidia-smi
```

GPU の名前やドライバのバージョンが入った表が出て、表の右上の **`CUDA Version` が 13.0 以上**なら準備完了です。
この確認用のイメージは CUDA 12.8 なので、ドライバが 570 番台でも表は出ますが、その場合は実際に使うときにエラーになります。
`CUDA Version` が 13.0 より小さいときは、手順 1 に戻ってドライバを更新してください。
エラーになる場合は、下の「トラブルシューティング」を見てください。

**6) このリポジトリを取ってくる**

`git` を使っているなら clone します。使っていなければ、このページの緑色の **Code** ボタン → **Download ZIP** でダウンロードして展開してください。
ZIP で取ってきた場合、`.bat` を開くたびに「セキュリティの警告」が出ることがあります。気になるときは、展開する**前に**
ZIP ファイルを右クリック →「プロパティ」→ 下の方の「許可する」にチェックを入れて OK を押してから展開してください。

```bat
git clone https://github.com/bluefuji/haas-asr-windows-docker.git
```

以降のコマンドは、このフォルダ（`Dockerfile` がある場所）で実行します。エクスプローラーでフォルダを開き、
アドレスバーに `cmd` と入力して Enter を押すと、そのフォルダでコマンドプロンプトが開きます。

### 1. イメージを作る（1回だけ）

リポジトリのフォルダで次を実行します。

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

ドラッグできるのは 1 つだけです。複数のファイルをまとめてドラッグしても、処理されるのは最初の 1 つだけなので、
複数あるときは 1 つのフォルダに入れて、そのフォルダを渡してください。

結果は、**元のファイル名（拡張子も含む）の後ろに `.txt` か `.speakers.txt` を付けた名前**で保存されます。

| 選択 | ファイルを渡したとき | フォルダを渡したとき |
|---|---|---|
| 1) 時刻付き | 同じ場所に `会議.mp4.txt`（既存なら上書き） | 各音声の隣に `会議.mp4.txt` の形で（既存ならスキップ） |
| 2) 話者ラベル付き | 同じ場所に `会議.mp4.speakers.txt`（既存なら上書き） | 各音声の隣に `会議.mp4.speakers.txt` の形で（既存ならスキップ） |

フォルダを渡したときに処理するのは、**そのフォルダの直下にあるファイルだけ**です。サブフォルダの中は処理しません。

**3) ブラウザデモ**を選ぶと、ファイルを渡す必要はなく、少し待つと `http://localhost:7860/longform` がブラウザで開きます。
音声をアップロードして文字起こししたり、マイクの音声にリアルタイムで字幕を付けたりできます。
終了するときは、黒い画面で `Ctrl+C` を押してください。

ブラウザは起動から 10 秒後に開きますが、サーバーはモデルを読み込み終わるまで応答しません（初回は重みのダウンロードもあります）。
「このサイトにアクセスできません」のような画面が出たら、黒い画面に `Ready on …: http://0.0.0.0:7860` と表示されるのを待ってから、
ページを再読み込みしてください。

### 2'. 使う（個別版 `wrappers/`）

毎回メニューを選ぶのが面倒なときは、目的ごとの `.bat` を使います。

| 目的 | 起動 | 出力 |
|---|---|---|
| 1本の音声・動画 | `wrappers/run_file_batch64.bat` にファイルをドラッグ | 同じ場所に `会議.mp4.txt`（既存なら上書き） |
| フォルダ一括 | `wrappers/run_folder_batch64.bat` を起動し、フォルダパスを入力 | 各音声の隣に `会議.mp4.txt` の形で（既存ならスキップ） |
| 話者ラベル付き（1本） | `wrappers/run_speakers.bat` にファイルをドラッグ | 同じ場所に `会議.mp4.speakers.txt`（既存なら上書き） |
| 話者ラベル付き（フォルダ一括） | `wrappers/run_folder_with_speakers.bat` を起動し、フォルダパスを入力 | 各音声の隣に `会議.mp4.speakers.txt` の形で（既存ならスキップ） |
| ブラウザデモ | `wrappers/run_browser.bat` | `http://localhost:7860/longform` が自動で開きます |

ドラッグできるのが 1 つだけなこと、フォルダ一括がサブフォルダの中を処理しないこと、ブラウザデモで再読み込みが必要になることがあるのは、
統合版と同じです。

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
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\haas.ps1 -Mode timestamp -Split fixed "C:\path\to\audio.mp4"
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
- 個別版: 使っている `.ps1`（`wrappers/run_file_batch64.ps1` / `run_folder_batch64.ps1` / `run_speakers.ps1` / `run_folder_with_speakers.ps1`）の中の `--batch-size 64` を書き換える

時刻付きの区間の長さ（統合版の `$ChunkSeconds`、個別版 `run_file_batch64.ps1` / `run_folder_batch64.ps1` の `--chunk-seconds`）も同じ場所で変えられます。

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

### 更新するとき

`git pull`（ZIP の場合は新しい ZIP を展開し直す）でこのリポジトリを更新したとき、`haas.bat`・`wrappers/`・`scripts/` の変更は、
次の実行からそのまま使われます（スクリプトは実行のたびにコンテナへ渡しているためです）。
**`Dockerfile` が変わったときだけ**、「1. イメージを作る」の `docker build` をもう一度実行してください。

ZIP で更新する場合、自分で作った `words.txt` は新しいフォルダにコピーし直してください。

### すべて削除するとき

イメージ本体（数十 GB）、モデルの重み、「0. 準備」の手順 5 で使った確認用のイメージは、次のコマンドで消せます。

```bat
docker image rm haas-asr:local
docker volume rm haas-hf-cache
docker image rm nvidia/cuda:12.8.1-base-ubuntu24.04
```

ビルドの途中経過（ビルドキャッシュ）も残っているので、続けて次を実行します（確認が出たら `y`）。
**使われていないビルドキャッシュをすべて消すので、他のプロジェクトのビルドキャッシュも一緒に消えます。**

```bat
docker builder prune -a
```

最後にリポジトリのフォルダを削除すれば終わりです。

### トラブルシューティング

- **`could not find a CUDA device` や `--gpus` に関するエラーが出る** — Docker から GPU が見えていません。「0. 準備」の手順 5 のコマンドが動くか確かめてください。動かない場合は、次を順に確認します
  - Windows の NVIDIA ドライバが新しいか（古いと CUDA 13.0 に対応していません）
  - `wsl --update` で WSL が最新か
  - Docker Desktop が「WSL 2 based engine」で動いているか（Settings → General）
  - 上を直したら、Docker Desktop を再起動するか、`wsl --shutdown` を実行してから Docker Desktop を起動し直す
- **`requirement error: unsatisfied condition: cuda>=12.8` のようなエラーが出る** — ドライバが古すぎます。NVIDIA のドライバを更新してください
- **`The NVIDIA driver on your system is too old` と出る** — ドライバが CUDA 13.0 に対応していません（580 番台より前）。「0. 準備」の手順 5 の確認が通っていても起こります。NVIDIA のドライバを更新してください
- **`docker` が見つからない / `Cannot connect to the Docker daemon` と出る** — Docker Desktop が起動していません。起動してから実行してください
- **`Unable to find image 'haas-asr:local'` と出る** — イメージがまだありません。「1. イメージを作る」を実行してください
- **「PowerShell 7 (pwsh) が見つかりません」や「'pwsh.exe' は、内部コマンドまたは外部コマンド…として認識されていません」と出る** — PowerShell 7 が入っていません。「0. 準備」の手順 4 でインストールしてください。インストール直後は、開いていたウィンドウを閉じてから `.bat` を起動し直してください
- **1回目の実行がとても遅い** — モデルの重み（Haas と話者分離モデル）をダウンロードしているためです。2回目からは保存済みのものを使います
- **`invalid field '…' must be a key=value pair` と出てすぐ止まる** — ファイル名かフォルダのパスにカンマ（`,`）が入っています。このラッパーはカンマを含むパスを Docker に渡せないので、名前からカンマを消すか、カンマのない場所にコピーしてから実行してください
- **ブラウザデモで「このサイトにアクセスできません」と出る** — サーバーの準備がまだ終わっていません。黒い画面に `Ready on …` と表示されてから、ページを再読み込みしてください
- **フォルダ一括で「対応する音声・動画ファイルがありません」と出る** — 処理するのはフォルダ直下のファイルだけです。サブフォルダの中にあるときは、そのサブフォルダを渡してください
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
  transcribe_folder.py       上のフォルダ一括版（動画の変換・スキップ・成功/失敗の集計）
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
- **Tens of GB** of free disk (CUDA base image, PyTorch/NeMo dependencies, model weights, the speaker-label environment).
- **PowerShell 7 (`pwsh`)** for `haas.bat` and every wrapper except `run_browser.bat`.
- Nothing else to install locally.

### Setup (once)

1. **NVIDIA driver on Windows.** Install a recent driver from [nvidia.com/drivers](https://www.nvidia.com/drivers/).
   PyTorch in the image ships CUDA 13.0 (the base image is CUDA 12.8), so the driver must support 13.0 (the 580
   series or newer, roughly); the author runs an RTX 5070 Ti on driver 610.88. Do **not** install a driver or
   CUDA inside WSL — the Windows driver covers it.
2. **WSL2.** In an administrator PowerShell, run `wsl --install` and reboot (or `wsl --update` if WSL is already there).
3. **Docker Desktop.** Install [Docker Desktop](https://www.docker.com/products/docker-desktop/) with the WSL 2 based
   engine (the default). It is free for personal use and small organisations; larger companies need a paid plan.
   Its data lives on `C:` by default; this image alone takes tens of GB, so move it with Settings → Resources →
   Advanced → Disk image location if `C:` is tight.
4. **PowerShell 7.** `haas.bat` and the wrappers (except `run_browser.bat`) run on PowerShell 7 (`pwsh`), which is
   separate from the Windows PowerShell 5.1 that ships with Windows. Install it with
   `winget install --id Microsoft.PowerShell --source winget` (or from the Microsoft Store), then check that
   `pwsh --version` prints `7.x` in a new terminal (the author uses 7.6.9).
5. **Check that Docker sees the GPU:**
   ```bash
   docker run --rm --gpus all nvidia/cuda:12.8.1-base-ubuntu24.04 nvidia-smi
   ```
   A table with your GPU and driver version, with **`CUDA Version` 13.0 or higher** in its top-right corner, means
   you are ready. This test image only needs CUDA 12.8, so a 570-series driver still prints the table but fails
   at run time; update the driver if `CUDA Version` is below 13.0. If the command fails, update the driver, run
   `wsl --update`, then `wsl --shutdown` and restart Docker Desktop.
6. **Get this repository** with `git clone https://github.com/bluefuji/haas-asr-windows-docker.git`, or
   **Code → Download ZIP** on this page, and run the commands below in that folder. If you use the ZIP, unblock it
   first (right-click → Properties → Unblock) to avoid a security prompt every time you open a `.bat`.

### Build once

In the repository folder:

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
Drop one item at a time: if you drop several files, only the first is processed, so put them in a folder instead.
Outputs keep the full original name, extension included, plus `.txt` or `.speakers.txt`.

| Choice | Given a file | Given a folder |
|---|---|---|
| 1) Timestamped | `meeting.mp4.txt` next to it (overwritten) | `meeting.mp4.txt` and so on beside each file (existing ones skipped) |
| 2) Speaker labels | `meeting.mp4.speakers.txt` next to it (overwritten) | `meeting.mp4.speakers.txt` and so on beside each file (existing ones skipped) |
| 3) Browser demos | opens `http://localhost:7860/longform` | — |

Folders are not searched recursively: only the files directly inside are processed.

The browser opens 10 s after launch, but the server answers only once the model is loaded (and, on the first
run, downloaded). If the page does not load, wait for `Ready on …: http://0.0.0.0:7860` in the console and reload.

**One `.bat` per task** (no menu) lives in `wrappers/`:

| Task | Start | Output |
|---|---|---|
| One file | drag it onto `wrappers/run_file_batch64.bat` | `meeting.mp4.txt` next to the input (overwritten) |
| Whole folder | `wrappers/run_folder_batch64.bat`, then type a folder path | `meeting.mp4.txt` and so on beside each file (existing ones are skipped) |
| Speaker labels, one file | drag onto `wrappers/run_speakers.bat` | `meeting.mp4.speakers.txt` next to the input (overwritten) |
| Speaker labels, whole folder | `wrappers/run_folder_with_speakers.bat`, then type a folder path | `meeting.mp4.speakers.txt` and so on beside each file (existing ones are skipped) |
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
(both modes), or `--batch-size 64` in the `wrappers/*.ps1` you use. 64 gave the author better results
than 8, but it needs more VRAM. The timestamped chunk length (`$ChunkSeconds`, or `--chunk-seconds` in
`run_file_batch64.ps1` / `run_folder_batch64.ps1`) is set in the same places.

**Custom vocabulary:** copy [words.example.txt](words.example.txt) to `words.txt` next to `haas.bat` and list one
word per line as `written form=reading,reading` (readings optional, hiragana or katakana). `haas.bat` then boosts
those words in both modes and writes them in their written form. Keep the list short: listed words also turn up
where they were not said more often. The `wrappers/` do not read `words.txt`.

The model weights are kept in the named volume `haas-hf-cache` (everything else is inside the image, so these
weights are the only runtime download); removing it forces a re-download.

**Updating:** after `git pull` (or unpacking a newer ZIP — copy your `words.txt` over), changes to `haas.bat`,
`wrappers/` and `scripts/` apply on the next run, since the scripts are mounted into the container each time.
Rebuild the image only when the `Dockerfile` changes.

**Removing everything:** `docker image rm haas-asr:local`, `docker volume rm haas-hf-cache` and
`docker image rm nvidia/cuda:12.8.1-base-ubuntu24.04`, then `docker builder prune -a` for the build cache
(this clears all unused build cache, other projects' included), and delete the repository folder.

CPU-only hosts, missing PowerShell 7, missing GPU passthrough (step 5 of Setup fails), an outdated driver
(`The NVIDIA driver on your system is too old`), paths containing a comma (`invalid field … must be a key=value
pair`; rename or move the file), and the first run's download time are the most common problems — see the 日本語
troubleshooting section for the checks.

### Not affiliated with Third Intelligence

The recogniser, the model weights and the speaker-diarization and demo code come from
[third-intelligence/Haas-ASR](https://github.com/third-intelligence/Haas-ASR). The files in this repository are
Apache-2.0 (see [LICENSE](LICENSE) and [NOTICE](NOTICE)); third-party components keep their own licenses.
