# Condition Detection Sidecar

A small Python HTTP service that runs the open-source
[KintsugiHealth/dam](https://huggingface.co/KintsugiHealth/dam) model (Apache-2.0) on CPU to estimate
depression and anxiety severity from a patient's voice. It runs as a second container in the same ECS
Fargate task as the Java backend and is reachable only at `http://localhost:8000`.

**This is a screening signal, not a diagnosis.** Levels map to PHQ-9 / GAD-7 bands but must never be
presented to a patient or clinician as a diagnostic result.

## Contract

`GET /health`

- `200 {"status":"ok","model_revision":"<sha>"}` once the model is loaded
- `503 {"status":"loading"}` before that (the model loads in a background thread)

`POST /v1/analyze` - `multipart/form-data`, field `audio` = a mono WAV of ONE speaker (16 kHz preferred;
other rates are resampled). Stereo is rejected, not downmixed.

| Status | Body |
| --- | --- |
| 200 | `{"status":"OK","speech_seconds":f,"analyzed_seconds":f,"model_revision":s,"depression":{"raw":f,"level":i},"anxiety":{"raw":f,"level":i}}` |
| 200 | `{"status":"INSUFFICIENT_SPEECH","speech_seconds":f,"min_speech_seconds":f}` |
| 400 | `{"status":"INVALID_AUDIO","detail":s}` (unreadable, empty, or non-mono) |
| 503 | `{"status":"loading"}` |
| 500 | `{"status":"ERROR","detail":"inference failed"}` |

Levels (upper bound of each band is inclusive, matching DAM's `torch.searchsorted`):

- depression: 0 none (PHQ-9 <= 9), 1 mild-moderate (10-14), 2 severe (>= 15); thresholds `-0.6699`, `-0.2908`
- anxiety: 0 none (GAD-7 <= 4), 1 mild (5-9), 2 moderate (10-14), 3 severe (>= 15); thresholds `-0.7939`, `-0.2173`, `0.1521`

Processing: decode WAV, require mono, resample to 16 kHz, Silero VAD keeps speech only, reject if under
`MIN_SPEECH_SECONDS`, truncate to `MAX_SPEECH_SECONDS`, run DAM (30 s windows, embeddings averaged).
The DAM authors prefer at least 30 s of speech.

## Environment variables

| Variable | Default | Meaning |
| --- | --- | --- |
| `MIN_SPEECH_SECONDS` | `30` | Minimum VAD speech needed, else `INSUFFICIENT_SPEECH` |
| `MAX_SPEECH_SECONDS` | `600` | Speech beyond this is dropped before inference |
| `TORCH_NUM_THREADS` | `1` | `torch.set_num_threads` |
| `PORT` | `8000` | Only used by `python app.py`; the Docker CMD binds 8000 |
| `DAM_DIR` | `/opt/dam` | Where the DAM repo (code + `dam3.1.ckpt`) lives |

## Privacy

Audio is processed in memory only. Nothing is written to disk. Logs contain durations and statuses only,
never audio, client file names, or scores; error responses never echo exception text.

## Run tests (no weights, no network)

```bash
python3.11 -m venv .venv && . .venv/bin/activate   # Windows: py -3.12 -m venv .venv; .venv\Scripts\activate
pip install -r requirements-dev.txt
pytest
```

Use Python 3.11 (the image's version) or 3.12. The pinned `torch==2.6.0` has no wheels for 3.14, so
a 3.14 venv cannot install the suite. `requirements-dev.txt` pulls in `requirements.txt`, so torch and
torchaudio (CPU builds) are always installed. The 48 kHz resample test runs the real torchaudio
resampler and **fails** if torchaudio is missing, so a partial install can't report the suite as passing.

## Build and run

```bash
docker build -t careconnect-dam-sidecar .
docker run --rm -p 8000:8000 --memory 4g careconnect-dam-sidecar
curl localhost:8000/health
```

Or from `backend/core/pg_docker/`: `docker compose up --build dam-sidecar`.

The image is large (Docker reports about 1.5 GB of image content, which unpacks to several GB on disk): CPU PyTorch, the 736 MB DAM checkpoint, and whisper-small.en (~967 MB)
are baked in so the container runs fully offline (`HF_HUB_OFFLINE=1`). Give the task at least 4 GB of
memory; model load takes tens of seconds, so allow a health-check start period of about 3 minutes.

The DAM commit is pinned in the `Dockerfile` (`DAM_REVISION`) and reported as `model_revision`.
