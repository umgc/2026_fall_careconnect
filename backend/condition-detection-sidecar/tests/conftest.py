import io
import os
import sys

os.environ["SIDECAR_SKIP_DEFAULT_APP"] = "1"
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import numpy as np
import pytest
import soundfile as sf
from fastapi.testclient import TestClient

from app import create_app


class FakeModel:
    revision = "testrev"

    def __init__(self, raw=None, error=None):
        self.raw = raw or {"depression": -0.5, "anxiety": 0.2}
        self.error = error
        self.calls = []

    def score(self, samples):
        self.calls.append(len(samples))
        if self.error:
            raise self.error
        return self.raw


class PassThroughVad:
    """Treats all audio as speech."""

    def extract_speech(self, samples):
        return samples


def wav_bytes(seconds=40, sr=16000, channels=1):
    n = int(seconds * sr)
    data = (0.1 * np.sin(np.linspace(0, 1000, n))).astype("float32")
    if channels > 1:
        data = np.stack([data] * channels, axis=1)
    buf = io.BytesIO()
    sf.write(buf, data, sr, format="WAV", subtype="PCM_16")
    return buf.getvalue()


@pytest.fixture
def make_client():
    def _make(model=None, vad=None, ready=True, **kwargs):
        model = model or FakeModel()
        app = create_app(
            model_loader=lambda: model,
            vad=vad or PassThroughVad(),
            start_loading=False,
            **kwargs,
        )
        if ready:
            app.state.load()
        return TestClient(app), model

    return _make
