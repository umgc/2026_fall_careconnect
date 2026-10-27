import pytest

from scoring import THRESHOLDS, level_for

EPS = 1e-6


@pytest.mark.parametrize("condition", list(THRESHOLDS))
def test_bucket_edges(condition):
    ts = THRESHOLDS[condition]
    assert level_for(condition, ts[0] - EPS) == 0
    for i, t in enumerate(ts):
        assert level_for(condition, t) == i, "upper bound is inclusive"
        assert level_for(condition, t + EPS) == i + 1
    assert level_for(condition, 100.0) == len(ts)
    assert level_for(condition, -100.0) == 0


def test_published_thresholds():
    assert tuple(THRESHOLDS["depression"]) == (-0.6699, -0.2908)
    assert tuple(THRESHOLDS["anxiety"]) == (-0.7939, -0.2173, 0.1521)
