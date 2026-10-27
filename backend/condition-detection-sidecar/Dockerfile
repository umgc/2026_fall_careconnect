FROM python:3.11-slim

# Pinned KintsugiHealth/dam commit (weights dam3.1.ckpt, Apache-2.0)
ARG DAM_REVISION=df83a1e00101d9c06a5042b96b921eb94d5a2528

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    HF_HOME=/opt/hf \
    DAM_DIR=/opt/dam \
    DAM_REVISION=${DAM_REVISION}

WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt

# Fetch DAM code + real LFS checkpoint, and the whisper backbone it loads at init.
# Downloads happen online; the runtime image is then fully offline.
RUN python - <<'EOF'
import os
from huggingface_hub import snapshot_download
snapshot_download("KintsugiHealth/dam", revision=os.environ["DAM_REVISION"], local_dir="/opt/dam")
snapshot_download("openai/whisper-small.en",
                  allow_patterns=["*.json", "*.txt", "model.safetensors"])
EOF
RUN test "$(stat -c %s /opt/dam/dam3.1.ckpt)" -gt 700000000 \
    && ls /opt/dam/pipeline.py /opt/dam/config.py /opt/dam/model.py /opt/dam/featex.py

ENV HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1

# Fail the build if the offline whisper cache is incomplete
RUN python -c "from transformers import AutoFeatureExtractor, WhisperModel; AutoFeatureExtractor.from_pretrained('openai/whisper-small.en'); WhisperModel.from_pretrained('openai/whisper-small.en')"

COPY app.py dam_adapter.py scoring.py vad.py ./

RUN useradd --system --uid 10001 --no-create-home sidecar
USER sidecar

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=180s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=4).status == 200 else 1)"

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
