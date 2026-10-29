"""Severity bucketing for DAM raw scores. Pure functions, no torch dependency."""

from bisect import bisect_left
from typing import Mapping, Sequence

# Published DAM v3.1 thresholds (KintsugiHealth/dam config.py, inference_thresholds).
# Upper bound of each bucket is INCLUSIVE: this matches torch.searchsorted(right=False),
# which DAM's Classifier.quantize_scores uses, and bisect_left below.
#   depression: <= -0.6699 -> 0 (PHQ-9 <= 9); <= -0.2908 -> 1 (10-14); else 2 (>= 15)
#   anxiety:    <= -0.7939 -> 0 (GAD-7 <= 4); <= -0.2173 -> 1 (5-9); <= 0.1521 -> 2 (10-14); else 3
THRESHOLDS: Mapping[str, Sequence[float]] = {
    "depression": (-0.6699, -0.2908),
    "anxiety": (-0.7939, -0.2173, 0.1521),
}


def level_for(condition: str, raw: float, thresholds: Mapping[str, Sequence[float]] = THRESHOLDS) -> int:
    """Return the severity level (0..len(thresholds)) for a raw score."""
    return bisect_left(list(thresholds[condition]), raw)
