# Folder batch transcription with speaker labels for Haas-ASR.
# Imports the upstream example examples/speakers/transcribe_with_speakers.py from
# https://github.com/third-intelligence/Haas-ASR (Copyright Third Intelligence, Inc.,
# Apache License 2.0) and repeats its steps per file, loading the models only once.
# See LICENSE and NOTICE.
#
# Run it in the speakers environment:
#   uv run --project examples/speakers python transcribe_folder_with_speakers.py IN OUT

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import haas_asr

SAMPLE_RATE = 16000
SUPPORTED_EXTENSIONS = {
    ".wav", ".flac", ".mp3", ".ogg", ".m4a", ".mp4", ".webm"
}


def read_words_file(path: Path | None) -> list[str]:
    """words.txt の各行（"表記=読み,読み"）。空行と # で始まる行は飛ばす。"""
    if path is None:
        return []

    lines = path.read_text(encoding="utf-8-sig").splitlines()
    return [
        line.strip()
        for line in lines
        if line.strip() and not line.strip().startswith("#")
    ]


def convert_with_ffmpeg(input_path: Path, output_path: Path) -> None:
    # 1ファイル版と同じく、16 kHz 単一チャンネル WAV にそろえる
    command = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel", "error",
        "-y",
        "-i", str(input_path),
        "-map", "0:a:0",
        "-vn",
        "-ac", "1",
        "-ar", str(SAMPLE_RATE),
        "-c:a", "pcm_s16le",
        str(output_path),
    ]
    subprocess.run(command, check=True)


def transcribe_one(upstream, diarizer, model, vocabulary, audio_path: Path, batch_size: int) -> list[str]:
    """upstream の main() と同じ手順で、1本分の "[時刻] Speaker N: 文" の行を返す。"""
    import torch

    with tempfile.TemporaryDirectory() as work_dir:
        wav_path = Path(work_dir) / "input.wav"
        convert_with_ffmpeg(audio_path, wav_path)
        audio = haas_asr.load_audio(str(wav_path))

    with torch.no_grad():
        (segments,) = diarizer.diarize(
            audio=[audio], sample_rate=haas_asr.SAMPLE_RATE, batch_size=1, verbose=False
        )
    turns = upstream.speaker_turns(segments)

    pieces = [upstream.turn_pieces(audio, turn) for turn in turns]
    texts = iter(
        haas_asr.transcribe(
            model,
            [piece for turn in pieces for piece in turn],
            batch_size=batch_size,
            vocabulary=vocabulary,
        )
    )

    lines = []
    for (start, _, speaker), turn in zip(turns, pieces, strict=True):
        text = "".join(next(texts) for _ in turn)
        if text:
            lines.append(f"[{upstream.timestamp(start)}] Speaker {speaker + 1}: {text}")
    return lines


def write_atomically(output_path: Path, lines: list[str]) -> None:
    # 同じフォルダで一時ファイルを作り、書き終えてから最終TXTへ置き換える。
    output_path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(
        prefix=output_path.name + ".",
        suffix=".tmp",
        dir=output_path.parent,
        text=True,
    )
    os.close(fd)
    temporary_path = Path(temporary_name)

    try:
        with temporary_path.open("w", encoding="utf-8", newline="\n") as stream:
            for line in lines:
                stream.write(line + "\n")
        temporary_path.replace(output_path)
    except Exception:
        temporary_path.unlink(missing_ok=True)
        raise


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Haas-ASR + Nemotron-3-Diarizationで、"
            "フォルダ内音声を話者付きTXTへ変換する"
        )
    )
    parser.add_argument("input_dir", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument(
        "--model",
        default="third-intelligence/Haas-ja-v1.0",
    )
    parser.add_argument(
        "--speakers-dir",
        type=Path,
        default=Path("/opt/Haas-ASR/examples/speakers"),
        help="upstream の transcribe_with_speakers.py があるフォルダ",
    )
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument(
        "--words-file",
        type=Path,
        help='カスタム語彙のファイル（1行に1語、"表記=読み,読み"）',
    )
    parser.add_argument("--recursive", action="store_true")
    parser.add_argument("--overwrite", action="store_true")
    args = parser.parse_args()

    if not args.input_dir.is_dir():
        parser.error(f"入力フォルダがありません: {args.input_dir}")
    if not (args.speakers_dir / "transcribe_with_speakers.py").is_file():
        parser.error(f"公式話者分離スクリプトがありません: {args.speakers_dir}")
    if args.batch_size <= 0:
        parser.error("--batch-sizeは0より大きくしてください")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    iterator = (
        args.input_dir.rglob("*")
        if args.recursive
        else args.input_dir.glob("*")
    )
    files = sorted(
        path for path in iterator
        if path.is_file() and path.suffix.lower() in SUPPORTED_EXTENSIONS
    )

    if not files:
        print("対応する音声・動画ファイルがありません。", file=sys.stderr)
        raise SystemExit(1)

    # upstream の使用例のファイルを、そのままモジュールとして読み込む
    sys.path.insert(0, str(args.speakers_dir))
    import transcribe_with_speakers as upstream

    vocabulary = haas_asr.Vocabulary.parse(read_words_file(args.words_file))
    if vocabulary:
        print(f"カスタム語彙: {len(vocabulary.words)}語", file=sys.stderr)

    # モデルの読み込みはここで1回だけ
    print("話者分離モデル読込", file=sys.stderr, flush=True)
    diarizer = upstream.load_diarizer(upstream.DIARIZER)
    print(f"モデル読込: {args.model}", file=sys.stderr, flush=True)
    model = haas_asr.load_model(args.model)

    succeeded = 0
    skipped = 0
    failed = 0

    for number, input_path in enumerate(files, start=1):
        relative = input_path.relative_to(args.input_dir)
        destination_dir = (
            args.output_dir / relative.parent
            if args.recursive
            else args.output_dir
        )
        # 通常の文字起こし (example.mp4.txt) と同じフォルダに並んでも衝突しない名前
        output_path = destination_dir / f"{input_path.name}.speakers.txt"

        print(f"\n[{number}/{len(files)}] {relative}", file=sys.stderr, flush=True)

        if output_path.exists() and not args.overwrite:
            print(f"スキップ: {output_path}", file=sys.stderr)
            skipped += 1
            continue

        try:
            lines = transcribe_one(
                upstream, diarizer, model, vocabulary, input_path, args.batch_size
            )
            if not lines:
                raise RuntimeError("文字起こし結果が空でした")

            write_atomically(output_path, lines)
            print(f"完了: {output_path}", file=sys.stderr)
            succeeded += 1
        except Exception as error:
            print(f"失敗: {input_path.name}: {error}", file=sys.stderr)
            failed += 1

    print(
        f"\n処理結果: 成功={succeeded}, 失敗={failed}, スキップ={skipped}",
        file=sys.stderr,
    )
    if failed:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
