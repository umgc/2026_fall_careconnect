"""Voice activity detection wrapper. Injectable so tests need no torch/silero."""

from typing import Protocol

import numpy as np

SAMPLE_RATE = 16000


class SpeechExtractor(Protocol):
    def extract_speech(self, samples: np.ndarray) -> np.ndarray:
        """Return the concatenated speech-only samples (float32 mono, 16 kHz)."""


class SileroVad:
    """Silero VAD (CPU). The model ships inside the silero-vad pip package."""

    def __init__(self) -> None:
        from silero_vad import load_silero_vad

        self._model = load_silero_vad()

    def extract_speech(self, samples: np.ndarray) -> np.ndarray:
        import torch
        from silero_vad import get_speech_timestamps

        if samples.size == 0:
            return samples
        stamps = get_speech_timestamps(
            torch.from_numpy(np.ascontiguousarray(samples, dtype=np.float32)),
            self._model,
            sampling_rate=SAMPLE_RATE,
        )
        if not stamps:
            return np.zeros(0, dtype=np.float32)
        return np.concatenate([samples[s["start"]:s["end"]] for s in stamps]).astype(np.float32)
