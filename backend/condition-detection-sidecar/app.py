"""CareConnect condition-detection sidecar (DAM depression/anxiety from voice)."""

import io
import logging
import os
import threading
import time
from typing import Callable, Optional

import numpy as np
from fastapi import FastAPI, File, UploadFile
from fastapi.responses import JSONResponse

from dam_adapter import ConditionModel
from scoring import level_for
from vad import SAMPLE_RATE, SpeechExtractor

log = logging.getLogger("sidecar")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")

MAX_UPLOAD_BYTES = 256 * 1024 * 1024


def _torchaudio_resample(samples: np.ndarray, orig_sr: int, target_sr: int) -> np.ndarray:
    import torch
    import torchaudio

    t = torch.from_numpy(np.ascontiguousarray(samples, dtype=np.float32)).unsqueeze(0)
    return torchaudio.functional.resample(t, orig_sr, target_sr).squeeze(0).numpy()


def _default_model_loader() -> ConditionModel:
    from dam_adapter import DamModel

    return DamModel(os.environ.get("DAM_DIR", "/opt/dam"), os.environ.get("DAM_REVISION", "unknown"))


def _default_vad() -> SpeechExtractor:
    from vad import SileroVad

    return SileroVad()


class _InvalidAudio(Exception):
    pass


def _decode_wav(data: bytes) -> tuple:
    import soundfile as sf

    if not data:
        raise _InvalidAudio("empty audio")
    try:
        samples, sr = sf.read(io.BytesIO(data), dtype="float32", always_2d=True)
    except Exception:
        raise _InvalidAudio("unreadable audio") from None
    if samples.shape[1] != 1:
        raise _InvalidAudio("audio must be mono")
    if samples.shape[0] == 0:
        raise _InvalidAudio("empty audio")
    return samples[:, 0], int(sr)


def create_app(
    model_loader: Optional[Callable[[], ConditionModel]] = None,
    vad: Optional[SpeechExtractor] = None,
    resampler: Callable[[np.ndarray, int, int], np.ndarray] = _torchaudio_resample,
    min_speech_seconds: Optional[float] = None,
    max_speech_seconds: Optional[float] = None,
    start_loading: bool = True,
    load_attempts: Optional[int] = None,
    load_retry_seconds: Optional[float] = None,
    sleep: Callable[[float], None] = time.sleep,
    exit_fn: Callable[[int], None] = os._exit,
) -> FastAPI:
    min_s = float(os.environ.get("MIN_SPEECH_SECONDS", "30")) if min_speech_seconds is None else min_speech_seconds
    max_s = float(os.environ.get("MAX_SPEECH_SECONDS", "600")) if max_speech_seconds is None else max_speech_seconds
    attempts = int(os.environ.get("MODEL_LOAD_ATTEMPTS", "5")) if load_attempts is None else load_attempts
    retry_s = float(os.environ.get("MODEL_LOAD_RETRY_SECONDS", "60")) if load_retry_seconds is None else load_retry_seconds
    loader = model_loader or _default_model_loader

    app = FastAPI(title="condition-detection-sidecar")
    state = {"model": None, "vad": vad}
    infer_lock = threading.Lock()

    def _load() -> None:
        # Retry with doubling backoff, then exit: a process that stays up without a model looks
        # alive but can never serve, and ECS only restarts the (non-essential) sidecar on exit.
        delay = retry_s
        for attempt in range(1, attempts + 1):
            try:
                if state["vad"] is None:
                    state["vad"] = _default_vad()
                state["model"] = loader()
                log.info("model loaded")
                return
            except Exception:
                log.exception("model load failed (attempt %d/%d)", attempt, attempts)
            if attempt < attempts:
                sleep(delay)
                delay = min(delay * 2, 600.0)
        log.error("model load failed permanently; exiting")
        # os._exit, not sys.exit: this runs on the loader thread, where sys.exit ends only the thread.
        exit_fn(1)

    app.state.load = _load  # tests may call this synchronously (start_loading=False)
    if start_loading:
        threading.Thread(target=_load, name="model-loader", daemon=True).start()

    @app.get("/health")
    def health():
        model = state["model"]
        if model is None:
            return JSONResponse({"status": "loading"}, status_code=503)
        return {"status": "ok", "model_revision": model.revision}

    @app.post("/v1/analyze")
    def analyze(audio: UploadFile = File(...)):
        model = state["model"]
        if model is None:
            return JSONResponse({"status": "loading"}, status_code=503)
        started = time.monotonic()
        try:
            data = audio.file.read(MAX_UPLOAD_BYTES + 1)
            if len(data) > MAX_UPLOAD_BYTES:
                raise _InvalidAudio("audio too large")
            samples, sr = _decode_wav(data)
            del data
            if sr != SAMPLE_RATE:
                samples = resampler(samples, sr, SAMPLE_RATE)
            speech = state["vad"].extract_speech(samples.astype(np.float32, copy=False))
            speech_seconds = len(speech) / SAMPLE_RATE
            if speech_seconds < min_s:
                log.info("insufficient speech: %.1fs", speech_seconds)
                return {"status": "INSUFFICIENT_SPEECH", "speech_seconds": speech_seconds,
                        "min_speech_seconds": min_s}
            speech = speech[: int(max_s * SAMPLE_RATE)]
            with infer_lock:
                raw = model.score(speech)
            result = {
                "status": "OK",
                "speech_seconds": speech_seconds,
                "analyzed_seconds": len(speech) / SAMPLE_RATE,
                "model_revision": model.revision,
                "depression": {"raw": float(raw["depression"]), "level": level_for("depression", raw["depression"])},
                "anxiety": {"raw": float(raw["anxiety"]), "level": level_for("anxiety", raw["anxiety"])},
            }
            log.info("analyzed %.1fs speech in %.1fs", result["analyzed_seconds"], time.monotonic() - started)
            return result
        except _InvalidAudio as e:
            return JSONResponse({"status": "INVALID_AUDIO", "detail": str(e)}, status_code=400)
        except Exception:
            log.error("inference failed")  # deliberately no exception text or traceback
            return JSONResponse({"status": "ERROR", "detail": "inference failed"}, status_code=500)

    return app


# Tests set SIDECAR_SKIP_DEFAULT_APP=1 so importing this module does not start loading real weights.
app = None if os.environ.get("SIDECAR_SKIP_DEFAULT_APP") == "1" else create_app()

if __name__ == "__main__":
    import uvicorn

    uvicorn.run("app:app", host="0.0.0.0", port=int(os.environ.get("PORT", "8000")), workers=1)
