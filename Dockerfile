FROM nvidia/cuda:12.8.1-cudnn-runtime-ubuntu24.04

# UV_NO_DEV / UV_FROZEN: 実行時の uv run が dev グループ (ruff など) を入れ直したり、
# uv.lock を解き直したりしないようにする（イメージは下で --frozen --no-dev で作る）。
ENV DEBIAN_FRONTEND=noninteractive \
    UV_LINK_MODE=copy \
    UV_NO_PROGRESS=1 \
    UV_NO_DEV=1 \
    UV_FROZEN=1 \
    UV_CACHE_DIR=/tmp/uv-cache \
    HF_HOME=/tmp/huggingface \
    XDG_CACHE_HOME=/tmp/cache \
    CC=gcc \
    CXX=g++

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        ffmpeg \
        git \
        libsndfile1 \
        python3 \
        python3-dev \
    && rm -rf /var/lib/apt/lists/*

# uv はバージョンを固定する（上げるときはこの数字を書き換える）
COPY --from=ghcr.io/astral-sh/uv:0.13.6 /uv /uvx /usr/local/bin/

WORKDIR /opt

# upstream は tag を出していないため、既定では確認済みの commit で固定する。
# 追従したいときは --build-arg HAAS_REF=main で最新を追える。
ARG HAAS_REPO=https://github.com/third-intelligence/Haas-ASR.git
ARG HAAS_REF=acc614f68769dcbfae9dba96b48439c4a66295af

RUN git init /opt/Haas-ASR \
    && git -C /opt/Haas-ASR remote add origin "${HAAS_REPO}" \
    && git -C /opt/Haas-ASR fetch --depth=1 origin "${HAAS_REF}" \
    && git -C /opt/Haas-ASR checkout --detach FETCH_HEAD \
    && git -C /opt/Haas-ASR rev-parse HEAD > /opt/Haas-ASR/.haas-asr-ref \
    && rm -rf /opt/Haas-ASR/.git

WORKDIR /opt/Haas-ASR

# 本体の環境（ブラウザデモ用の demo グループも含める）と、
# 話者ラベル用の別環境 (examples/speakers) をビルド時に作っておく。
RUN uv sync --no-dev --group demo \
    && uv sync --project examples/speakers \
    && rm -rf \
        /tmp/uv-cache \
        /tmp/cache \
        /tmp/huggingface \
        /root/.cache

# 環境は上ですべて作り終えているので、実行時の uv run は同期せずにそのまま使う。
# （同期させると、キャッシュを消してあるため NeMo を GitHub から取り直してビルドしてしまう）
ENV UV_NO_SYNC=1

ENTRYPOINT ["uv", "run", "python", "examples/quickstart.py"]
CMD ["--help"]
