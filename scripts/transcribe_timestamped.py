# Timestamped long-form transcription helper for Haas-ASR.
# Uses the haas_asr public API from https://github.com/third-intelligence/Haas-ASR
# (Copyright Third Intelligence, Inc., Apache License 2.0). See LICENSE and NOTICE.

import argparse
import sys
from pathlib import Path

import haas_asr


SAMPLE_RATE = 16000


def get_output_text(output) -> str:
    if hasattr(output, "text"):
        return str(output.text).strip()

    return str(output).strip()


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


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Haas-ASR timestamped long-form transcription"
    )
    parser.add_argument("audio", help="Input WAV, FLAC, MP3, or OGG")
    parser.add_argument(
        "--model",
        default="third-intelligence/Haas-ja-v1.0",
        help="Hugging Face model ID or local .nemo path",
    )
    parser.add_argument(
        "--chunk-seconds",
        type=float,
        default=30.0,
        help="Target length of each timestamped chunk in seconds",
    )
    parser.add_argument(
        "--split",
        choices=["quiet", "fixed"],
        default="quiet",
        help="quiet: cut at the quietest point near each target (default); "
        "fixed: cut every --chunk-seconds exactly",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=8,
        help="Inference batch size",
    )
    parser.add_argument(
        "--words-file",
        help='Custom vocabulary, one "written form=reading,reading" per line',
    )
    args = parser.parse_args()

    if args.chunk_seconds <= 0:
        parser.error("--chunk-seconds must be greater than zero")

    if args.batch_size <= 0:
        parser.error("--batch-size must be greater than zero")

    audio_path = Path(args.audio)
    if not audio_path.exists():
        print(f"Input file not found: {audio_path}", file=sys.stderr)
        raise SystemExit(1)

    print("Loading audio...", file=sys.stderr, flush=True)
    audio = haas_asr.load_audio(str(audio_path))

    bounds = split_audio(audio, args.chunk_seconds, args.split)
    chunks = [audio[start:end] for start, end in bounds]

    if not chunks:
        print("No audio samples found.", file=sys.stderr)
        raise SystemExit(1)

    print(
        f"Loading model: {args.model}",
        file=sys.stderr,
        flush=True,
    )
    model = haas_asr.load_model(args.model)

    print(
        f"Transcribing {len(chunks)} chunks "
        f"with batch size {args.batch_size}...",
        file=sys.stderr,
        flush=True,
    )

    vocabulary = haas_asr.Vocabulary.parse(read_words_file(args.words_file))
    if vocabulary:
        print(
            f"Custom vocabulary: {len(vocabulary.words)} words",
            file=sys.stderr,
            flush=True,
        )

    outputs = transcribe_chunks(model, chunks, args.batch_size, vocabulary)

    for (start, _), output in zip(bounds, outputs, strict=True):
        timestamp = format_timestamp(
            start / SAMPLE_RATE,
            tenths=args.split == "quiet",
        )
        text = get_output_text(output)

        if text:
            print(f"[{timestamp}] {text}")

    print("Transcription completed.", file=sys.stderr, flush=True)


if __name__ == "__main__":
    main()