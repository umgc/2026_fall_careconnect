"""DAM model adapter (named dam_adapter to avoid clashing with DAM's own model.py). torch/transformers are imported lazily so the rest of the
service (and its tests) work without them."""

import os
import sys
from typing import Dict, Protocol

import numpy as np

from scoring import THRESHOLDS


class ConditionModel(Protocol):
    revision: str

    def score(self, samples: np.ndarray) -> Dict[str, float]:
        """samples: float32 mono 16 kHz. Returns {"depression": raw, "anxiety": raw}."""


class DamModel:
    def __init__(self, dam_dir: str, revision: str) -> None:
        self.revision = revision
        sys.path.insert(0, dam_dir)
        import torch

        torch.set_num_threads(int(os.environ.get("TORCH_NUM_THREADS", "1")))
        from config import default_config  # DAM's own config.py
        from pipeline import Pipeline

        published = {k: tuple(v) for k, v in default_config["inference_thresholds"].items()}
        expected = {k: tuple(v) for k, v in THRESHOLDS.items()}
        if published != expected:
            raise RuntimeError("DAM thresholds differ from scoring.THRESHOLDS; refusing to start")
        self._torch = torch
        self._pipeline = Pipeline(checkpoint=os.path.join(dam_dir, "dam3.1.ckpt"))

    def score(self, samples: np.ndarray) -> Dict[str, float]:
        torch = self._torch
        audio = torch.from_numpy(np.ascontiguousarray(samples, dtype=np.float32)).unsqueeze(0)
        with torch.inference_mode():
            out = self._pipeline.run_on_audio(audio, quantize=False)
        return {k: float(v.mean().item()) for k, v in out.items()}
