# Folder batch transcription helper for Haas-ASR.
# Uses the haas_asr public API from https://github.com/third-intelligence/Haas-ASR
# (Copyright Third Intelligence, Inc., Apache License 2.0). See LICENSE and NOTICE.

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

import haas_asr


SAMPLE_RATE = 16000
SUPPORTED_EXTENSIONS = {
    ".wav",
    ".flac",
    ".mp3",
    ".ogg",
    ".m4a",
    ".mp4",
    ".webm",
}


def read_words_file(path: str | None) -> list[str]:
    """words.txt の各行（"表記=読み,読み"）。空行と # で始まる行は飛ばす。"""
    if path is None:
        return []

    lines = Path(path).read_text(encoding="utf-8-sig").splitlines()
    return [
        line.strip()
        for line in lines
        if line.strip() and not line.strip().startswith("#")
    ]


def transcribe_chunks(model, chunks, batch_size: int, vocabulary) -> list:
    if vocabulary:
        # 語彙の強調は upstream の haas_asr.transcribe が行う
        return haas_asr.transcribe(
            model,
            chunks,
            batch_size=batch_size,
            vocabulary=vocabulary,
        )

    # 語彙なしなら haas_asr.transcribe と同じ結果で、進み具合も表示される
    return model.transcribe(chunks, batch_size=batch_size)


def format_timestamp(seconds: float, tenths: bool = False) -> str:
    if tenths:
        # 話者分離の出力と同じ hh:mm:ss.s 形式
        minutes, seconds = divmod(seconds, 60)
        return f"{int(minutes // 60):02d}:{int(minutes % 60):02d}:{seconds:04.1f}"

    total_seconds = int(seconds)
    hours, remainder = divmod(total_seconds, 3600)
    minutes, seconds = divmod(remainder, 60)
    return f"{hours:02d}:{minutes:02d}:{seconds:02d}"


def split_audio(audio, chunk_seconds: float, split: str) -> list[tuple[int, int]]:
    """(開始, 終了) のサンプル範囲のリスト。

    quiet: upstream の split_at_quiet_points で、目標位置の前後2秒以内の
           一番静かな所で切る（語の途中で切れにくい）。
    fixed: chunk_seconds ごとに機械的に切る（従来の動作）。
    """
    if split == "quiet":
        return haas_asr.split_at_quiet_points(
            audio,
            sample_rate=SAMPLE_RATE,
            chunk_seconds=chunk_seconds,
        )

    chunk_samples = int(chunk_seconds * SAMPLE_RATE)
    return [
        (start, min(start + chunk_samples, len(audio)))
        for start in range(0, len(audio), chunk_samples)
    ]


def convert_with_ffmpeg(input_path: Path, output_path: Path) -> None:
    command = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "error",
        "-y",
        "-i",
        str(input_path),
        "-map",
        "0:a:0",
        "-vn",
        "-ac",
        "1",
        "-ar",
        str(SAMPLE_RATE),
        "-c:a",
        "pcm_s16le",
        str(output_path),
    ]

    subprocess.run(command, check=True)


def get_output_text(output) -> str:
    if hasattr(output, "text"):
        return str(output.text).strip()

    return str(output).strip()


def transcribe_file(
    model,
    audio_path: Path,
    output_path: Path,
    chunk_seconds: float,
    batch_size: int,
    split: str,
    vocabulary,
) -> None:
    temporary_path = None

    try:
        input_for_asr = audio_path

        if audio_path.suffix.lower() in {".mp4", ".m4a", ".webm"}:
            temporary_file = tempfile.NamedTemporaryFile(
                suffix=".wav",
                delete=False,
            )
            temporary_file.close()

            temporary_path = Path(temporary_file.name)

            print(
                f"FFmpeg変換: {audio_path.name}",
                file=sys.stderr,
                flush=True,
            )

            convert_with_ffmpeg(audio_path, temporary_path)
            input_for_asr = temporary_path

        audio = haas_asr.load_audio(str(input_for_asr))
        bounds = split_audio(audio, chunk_seconds, split)
        chunks = [audio[start:end] for start, end in bounds]

        if not chunks:
            raise RuntimeError("音声データがありません")

        print(
            f"認識開始: {audio_path.name} "
            f"({len(chunks)}チャンク)",
            file=sys.stderr,
            flush=True,
        )

        outputs = transcribe_chunks(model, chunks, batch_size, vocabulary)

        with output_path.open(
            "w",
            encoding="utf-8",
            newline="\n",
        ) as output_file:
            for (start, _), output in zip(bounds, outputs, strict=True):
                text = get_output_text(output)

                if not text:
                    continue

                timestamp = format_timestamp(
                    start / SAMPLE_RATE,
                    tenths=split == "quiet",
                )
                output_file.write(
                    f"[{timestamp}] {text}\n"
                )

    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Haas-ASR folder batch transcription"
    )
    parser.add_argument(
        "input_dir",
        help="入力フォルダ",
    )
    parser.add_argument(
        "output_dir",
        help="TXT出力フォルダ",
    )
    parser.add_argument(
        "--model",
        default="third-intelligence/Haas-ja-v1.0",
    )
    parser.add_argument(
        "--chunk-seconds",
        type=float,
        default=30.0,
    )
    parser.add_argument(
        "--split",
        choices=["quiet", "fixed"],
        default="quiet",
        help="quiet: 目標位置付近の一番静かな所で切る（既定） / "
        "fixed: --chunk-seconds ごとに機械的に切る",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=8,
    )
    parser.add_argument(
        "--words-file",
        help='カスタム語彙のファイル（1行に1語、"表記=読み,読み"）',
    )
    parser.add_argument(
        "--recursive",
        action="store_true",
        help="サブフォルダも処理する",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="既存TXTを上書きする",
    )
    args = parser.parse_args()

    input_dir = Path(args.input_dir)
    output_dir = Path(args.output_dir)

    if not input_dir.is_dir():
        parser.error(
            f"入力フォルダがありません: {input_dir}"
        )

    if args.chunk_seconds <= 0:
        parser.error(
            "--chunk-secondsは0より大きくしてください"
        )

    if args.batch_size <= 0:
        parser.error(
            "--batch-sizeは0より大きくしてください"
        )

    output_dir.mkdir(
        parents=True,
        exist_ok=True,
    )

    iterator = (
        input_dir.rglob("*")
        if args.recursive
        else input_dir.glob("*")
    )

    files = sorted(
        path
        for path in iterator
        if path.is_file()
        and path.suffix.lower() in SUPPORTED_EXTENSIONS
    )

    if not files:
        print(
            "対応する音声・動画ファイルがありません。",
            file=sys.stderr,
        )
        raise SystemExit(1)

    print(
        f"対象ファイル数: {len(files)}",
        file=sys.stderr,
    )
    print(
        f"モデル読込: {args.model}",
        file=sys.stderr,
        flush=True,
    )

    vocabulary = haas_asr.Vocabulary.parse(read_words_file(args.words_file))
    if vocabulary:
        print(
            f"カスタム語彙: {len(vocabulary.words)}語",
            file=sys.stderr,
        )

    # モデルの読み込みはここで1回だけ
    model = haas_asr.load_model(args.model)

    succeeded = 0
    failed = 0
    skipped = 0

    for number, audio_path in enumerate(files, start=1):
        relative_path = audio_path.relative_to(input_dir)

        if args.recursive:
            destination_dir = (
                output_dir / relative_path.parent
            )
        else:
            destination_dir = output_dir

        destination_dir.mkdir(
            parents=True,
            exist_ok=True,
        )

        # 元の拡張子も残す
        # example.mp4 → example.mp4.txt
        output_path = (
            destination_dir / f"{audio_path.name}.txt"
        )

        print(
            f"\n[{number}/{len(files)}] "
            f"{relative_path}",
            file=sys.stderr,
            flush=True,
        )

        if output_path.exists() and not args.overwrite:
            print(
                f"スキップ: {output_path.name}",
                file=sys.stderr,
            )
            skipped += 1
            continue

        try:
            transcribe_file(
                model=model,
                audio_path=audio_path,
                output_path=output_path,
                chunk_seconds=args.chunk_seconds,
                batch_size=args.batch_size,
                split=args.split,
                vocabulary=vocabulary,
            )

            print(
                f"完了: {output_path}",
                file=sys.stderr,
            )
            succeeded += 1

        except Exception as error:
            print(
                f"失敗: {audio_path.name}: {error}",
                file=sys.stderr,
            )
            failed += 1

            # 途中まで作られた空ファイルを削除
            if (
                output_path.exists()
                and output_path.stat().st_size == 0
            ):
                output_path.unlink()

    print(
        "\n処理結果: "
        f"成功={succeeded}, "
        f"失敗={failed}, "
        f"スキップ={skipped}",
        file=sys.stderr,
    )

    if failed:
        raise SystemExit(2)


if __name__ == "__main__":
    main()