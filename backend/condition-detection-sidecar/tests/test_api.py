import numpy as np
import pytest

from fastapi.testclient import TestClient

from app import create_app
from conftest import FakeModel, PassThroughVad, wav_bytes


def post(client, data, name="x.wav"):
    return client.post("/v1/analyze", files={"audio": (name, data, "audio/wav")})


def test_health_loading_then_ready(make_client):
    client, _ = make_client(ready=False)
    r = client.get("/health")
    assert r.status_code == 503 and r.json() == {"status": "loading"}
    assert post(client, wav_bytes()).status_code == 503
    client.app.state.load()
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok", "model_revision": "testrev"}


class FlakyLoader:
    """Fails the first `failures` loads, then returns a model."""

    def __init__(self, failures):
        self.failures = failures
        self.calls = 0

    def __call__(self):
        self.calls += 1
        if self.calls <= self.failures:
            raise RuntimeError("weights not readable")
        return FakeModel()


def _retrying_app(loader, attempts=3):
    sleeps, exits = [], []
    app = create_app(
        model_loader=loader, vad=PassThroughVad(), start_loading=False,
        load_attempts=attempts, load_retry_seconds=60, sleep=sleeps.append, exit_fn=exits.append,
    )
    return app, sleeps, exits


def test_model_load_retries_then_becomes_healthy():
    # Two failures, third attempt loads: no exit, and the backoff doubled between attempts.
    loader = FlakyLoader(failures=2)
    app, sleeps, exits = _retrying_app(loader)

    app.state.load()

    assert loader.calls == 3
    assert sleeps == [60, 120]
    assert exits == []
    assert TestClient(app).get("/health").status_code == 200


def test_model_load_exhausted_exits_nonzero():
    # Every attempt fails: the process must exit so ECS restarts the container.
    loader = FlakyLoader(failures=99)
    app, sleeps, exits = _retrying_app(loader)

    app.state.load()

    assert loader.calls == 3
    assert sleeps == [60, 120]  # no sleep after the last attempt
    assert exits == [1]
    assert TestClient(app).get("/health").status_code == 503


def test_analyze_ok(make_client):
    client, model = make_client(min_speech_seconds=30)
    r = post(client, wav_bytes(40))
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "OK"
    assert body["speech_seconds"] == pytest.approx(40)
    assert body["analyzed_seconds"] == pytest.approx(40)
    assert body["model_revision"] == "testrev"
    assert body["depression"] == {"raw": -0.5, "level": 1}
    assert body["anxiety"] == {"raw": 0.2, "level": 3}
    assert model.calls == [40 * 16000]


def test_insufficient_speech(make_client):
    client, model = make_client(min_speech_seconds=30)
    r = post(client, wav_bytes(10))
    assert r.status_code == 200
    assert r.json() == {"status": "INSUFFICIENT_SPEECH", "speech_seconds": pytest.approx(10),
                        "min_speech_seconds": 30}
    assert model.calls == []


def test_vad_removes_silence(make_client):
    class HalfVad:
        def extract_speech(self, samples):
            return samples[: len(samples) // 2]

    client, model = make_client(vad=HalfVad(), min_speech_seconds=30)
    r = post(client, wav_bytes(40))  # 20 s of speech < 30
    assert r.json()["status"] == "INSUFFICIENT_SPEECH"
    assert r.json()["speech_seconds"] == pytest.approx(20)


def test_stereo_rejected(make_client):
    client, model = make_client()
    r = post(client, wav_bytes(40, channels=2))
    assert r.status_code == 400
    assert r.json()["status"] == "INVALID_AUDIO"
    assert model.calls == []


def test_garbage_rejected(make_client):
    client, _ = make_client()
    r = post(client, b"not a wav file at all")
    assert r.status_code == 400 and r.json()["status"] == "INVALID_AUDIO"


def test_empty_rejected(make_client):
    client, _ = make_client()
    r = post(client, b"")
    assert r.status_code == 400 and r.json()["status"] == "INVALID_AUDIO"


def test_model_exception_not_leaked(make_client):
    client, _ = make_client(model=FakeModel(error=RuntimeError("secret patient detail")))
    r = post(client, wav_bytes(40))
    assert r.status_code == 500
    assert r.json() == {"status": "ERROR", "detail": "inference failed"}
    assert "secret" not in r.text


def test_max_speech_truncation(make_client):
    client, model = make_client(min_speech_seconds=5, max_speech_seconds=20)
    body = post(client, wav_bytes(40)).json()
    assert model.calls == [20 * 16000]
    assert body["speech_seconds"] == pytest.approx(40)
    assert body["analyzed_seconds"] == pytest.approx(20)


def test_resample_injected(make_client):
    seen = {}

    def fake_resample(samples, orig, target):
        seen["args"] = (orig, target)
        return samples[:: orig // target]

    client, model = make_client(resampler=fake_resample)
    r = post(client, wav_bytes(40, sr=48000))
    assert r.json()["status"] == "OK"
    assert seen["args"] == (48000, 16000)
    assert model.calls == [40 * 16000]


def test_resample_torchaudio_48k(make_client):
    # Fails rather than skips without torchaudio: this is the only test of the resampler the
    # sidecar actually runs, and a skip would let a partial install report the suite as passing.
    try:
        import torchaudio  # noqa: F401
    except ImportError:
        pytest.fail("torchaudio is not installed; run `pip install -r requirements-dev.txt` on Python 3.11 or 3.12")
    client, model = make_client(min_speech_seconds=5)
    r = post(client, wav_bytes(10, sr=48000))
    assert r.json()["status"] == "OK"
    assert model.calls == [10 * 16000]
    assert r.json()["analyzed_seconds"] == pytest.approx(10)
