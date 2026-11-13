"""P056: rep_norms.csv is well-formed, sourced and monotone; interpolation behaves."""
from collections import defaultdict

from gymml.data import rep_norms as rn

POINTS = rn.load()


def test_every_row_is_sourced_and_valid():
    assert POINTS
    for p in POINTS:
        assert p.source in rn.SOURCES
        assert p.sex in ("M", "F")
        assert 0 < p.percentile < 100 and p.reps >= 0
        assert p.age_min <= p.age_max
        assert p.protocol


def test_sources_are_documented():
    doc = (rn.ML_ROOT / "data" / "REP_NORMS.md").read_text(encoding="utf-8")
    for s in rn.SOURCES:
        assert f"`{s}`" in doc


def test_reps_rise_with_percentile_in_every_cell():
    cells = defaultdict(list)
    for p in POINTS:
        cells[(p.test, p.sex, p.age_min, p.age_max)].append((p.percentile, p.reps))
    for key, pts in cells.items():
        pts.sort()
        reps = [r for _, r in pts]
        assert reps == sorted(reps) and len(set(reps)) == len(reps), key


def test_age_bands_do_not_overlap():
    bands = defaultdict(set)
    for p in POINTS:
        bands[(p.test, p.sex)].add((p.age_min, p.age_max))
    for key, bs in bands.items():
        bs = sorted(bs)
        for (_a0, b0), (a1, _b1) in zip(bs, bs[1:], strict=False):
            assert b0 < a1, key


def test_interpolation():
    # CSEP men 20-29: 22 push-ups = p40, 29 = p60 -> 25.5 is halfway.
    assert rn.percentile(POINTS, "pushups", "M", 25, 22) == 40
    assert abs(rn.percentile(POINTS, "pushups", "M", 25, 25.5) - 50) < 1e-9
    assert rn.percentile(POINTS, "pushups", "M", 25, 0) == 20      # clamped below
    assert rn.percentile(POINTS, "pushups", "M", 25, 200) == 80    # clamped above
    assert rn.percentile(POINTS, "crunches", "F", 30, 34) == 50
    assert rn.percentile(POINTS, "sit-up", "M", 30, 20) is None    # no norm
    assert rn.percentile(POINTS, "pushups", "M", 75, 20) is None   # outside the CSEP age range
