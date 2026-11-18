"""P094 · retraining pipeline: export filter, calibration and ratio updates, gates, end to end on synthetic data."""

from __future__ import annotations

import copy
import json
import math
import shutil

import numpy as np
import polars as pl
import pytest

from gymml.export import keys
from gymml.retrain import (
    calibration,
    contributions,
    curve,
    gates,
    integrity,
    ratios,
    run,
    synthetic,
)
from gymml.retrain.contributions import InsufficientData


@pytest.fixture(scope="module")
def base():
    p, cat, model, manifest, shipped = run._base(run.EMBEDDED)
    return p, cat, model


@pytest.fixture(scope="module")
def cfg():
    c = run.load_config()
    c["gates"]["max_rows"] = 600
    c["gates"]["monotonic_grid"] = 8
    return c


@pytest.fixture(scope="module")
def good(base):
    p, cat, model = base
    truth = synthetic.Truth(delta_shift=0.08, kappa_factor=0.9, ratio_factor={"barbell-curl": 1.2})
    return synthetic.generate(3000, cat, model, p, truth, seed=11)


def _row(key: str, **kw) -> dict:
    r = {"contribution_key": key, "sex": "male", "age_band": 30, "bodyweight_kg": 80, "height_band": 180,
         "experience_band": "two_to_5_years", "frequency_band": "3-4", "month": "2026-09",
         "exercise_id": "barbell-full-squat", "best_e1rm_kg": 120.0, "best_set_reps": 5,
         "sessions_in_month": 8, "model_version": "1.0.0"}
    return {**r, **kw}


def test_k_anonymity_drops_small_cells_and_reports_them():
    rows = [_row(f"k{i}") for i in range(25)]
    rows += [_row(f"s{i}", bodyweight_kg=131) for i in range(5)]  # 130-139 kg band: 5 people
    rows += [_row("k0", month="2026-10")] * 1  # same key twice: still one contributor
    out, rep = contributions.k_anonymize(contributions.frame(rows), k=20, weight_band_kg=10)
    assert rep.cells_in == 2 and rep.cells_dropped == 1
    assert rep.rows_out == 26 and rep.contributors_out == 25
    assert set(out["bodyweight_kg"].to_list()) == {80}
    assert "weight_band" not in out.columns


def test_insufficient_data_stops_with_message():
    df = contributions.frame([_row(f"k{i}") for i in range(30)])
    with pytest.raises(InsufficientData, match="min_contributors"):
        contributions.check_sufficient(df, {"barbell-full-squat"},
                                       {"min_contributors": 300, "min_anchor_contributors_per_sex": 1})
    with pytest.raises(InsufficientData, match="female"):
        contributions.check_sufficient(df, {"barbell-full-squat"},
                                       {"min_contributors": 10, "min_anchor_contributors_per_sex": 5})


def test_holdout_is_by_key_and_stable(good):
    a = contributions.holdout_mask(good, 0.2, 1)
    b = contributions.holdout_mask(good, 0.2, 1)
    assert a.to_list() == b.to_list()
    held = good.filter(a)["contribution_key"].unique()
    kept = good.filter(~a)["contribution_key"].unique()
    assert not set(held.to_list()) & set(kept.to_list())
    assert 0.15 < held.len() / good["contribution_key"].n_unique() < 0.25


def test_prior_weight_shrinks_but_never_vanishes():
    cfg = {"prior_pseudo_n": 200, "prior_weight_floor": 0.25}
    assert calibration.prior_weight(0, cfg) == 1.0
    assert calibration.prior_weight(200, cfg) == 0.5
    assert calibration.prior_weight(10**9, cfg) == 0.25


def test_calibration_moves_toward_the_truth(base, good, cfg):
    p, cat, model = base
    obs = calibration.anchor_observations(contributions.latest_per_lift(good), cat, model, p)
    loose = dict(cfg["calibration"], prior_weight_floor=0.0, prior_pseudo_n=1e-6)
    cal, rep = calibration.update(obs, p, loose)
    for sex in ("M", "F"):
        true_k = p.calibration["kappa"]["gym"][sex] * 0.9
        assert rep["kappa"][sex]["estimate"] == pytest.approx(true_k, rel=0.04)
    big = [c for c in rep["cells"] if c["n"] >= 150]
    assert big
    shifts = [c["estimate"] - c["prior"] for c in big]
    assert np.median(shifts) == pytest.approx(0.08, abs=0.03)
    # General population and empty cells keep the prior.
    assert cal["delta"]["general"] == p.calibration["delta"]["general"]
    empty = [c for c in rep["cells"] if c["n"] < cfg["calibration"]["min_cell_contributors"]]
    assert all(c["posterior"] == c["prior"] for c in empty)
    # With the floor the posterior keeps a quarter of the prior.
    cal2, rep2 = calibration.update(obs, p, cfg["calibration"])
    c = max(rep2["cells"], key=lambda c: c["n"])
    assert c["w_prior"] >= 0.25
    assert c["posterior"] == pytest.approx(c["w_prior"] * c["prior"] + (1 - c["w_prior"]) * c["estimate"], abs=1e-4)


def test_ratio_update_recovers_shift_and_respects_floors(base, good, cfg):
    p, cat, model = base
    pairs = ratios.paired_log_ratios(good, cat)
    new_cat, rows = ratios.update(pairs, cat, p, cfg["ratios"])
    by = {r["exercise_id"]: r for r in rows}
    curl = by["barbell-curl"]
    assert curl["ratio"] / curl["prior_ratio"] == pytest.approx(1.2, rel=0.03)
    assert curl["between_sd"] == pytest.approx(0.12, abs=0.02)
    assert new_cat["barbell-curl"].ratio == curl["ratio"]
    for r in rows:
        if not r["changed"]:
            continue
        ex = cat[r["exercise_id"]]
        floor = cfg["ratios"]["tau_floor"]["machine" if ratios.is_machine(ex, p) else r["grade"]]
        assert r["tau"] >= floor - 1e-9
        assert ratios.GRADES.index(r["grade"]) >= ratios.GRADES.index(r["prior_grade"])
        if ratios.is_machine(ex, p):
            assert r["grade"] == "C"
    assert ratios.implausible(rows, 2.0) == []
    assert ratios.implausible([{**curl, "ratio": curl["prior_ratio"] * 3}], 2.0)


def test_machine_rows_stay_grade_c(base, cfg):
    p, cat, model = base
    machine = next(e for e in cat.values() if e.scorable and e.anchor == "bench" and ratios.is_machine(e, p)
                   and not e.is_anchor and e.scoring_type == "weighted")
    rng = np.random.default_rng(0)
    d = np.log(machine.ratio) + rng.normal(0, 0.05, 2000)
    pairs = pl.DataFrame({"exercise_id": [machine.id] * 2000, "contribution_key": [str(i) for i in range(2000)],
                          "d": d})
    _, rows = ratios.update(pairs, cat, p, cfg["ratios"])
    assert rows[0]["grade"] == "C" and rows[0]["tau"] >= 0.5


def test_curve_is_not_identifiable_from_monthly_rows(good):
    rep = curve.identifiability(good)
    assert rep["within_month_contrasts"] == 0 and rep["refit"] is False
    assert rep["with_two_or_more_months"] > 0


def test_golden_gate_catches_a_changed_vector(base, tmp_path):
    p, cat, model = base
    ref = tmp_path / "golden"
    shutil.copytree(gates.golden.GOLDEN_DIR, ref)
    pp, ip = run._progress_imbalance()

    def write(out):
        return gates.golden.write_all(cat, model, p, pp, ip, out=out)

    assert gates.golden_gate(write, 1e-4, ref).passed
    doc = json.loads((ref / "calibration.json").read_text())

    def bump(node) -> bool:
        items = node.items() if isinstance(node, dict) else enumerate(node)
        for k, v in items:
            if isinstance(v, float):
                node[k] = v + 1e-3
                return True
            if isinstance(v, dict | list) and bump(v):
                return True
        return False

    assert bump(doc["cases"][0])
    (ref / "calibration.json").write_text(json.dumps(doc))
    g = gates.golden_gate(write, 1e-4, ref)
    assert not g.passed and "calibration.json" in g.detail["mismatches"]


def test_sanity_gate_flags_bad_kappa(base, cfg):
    p, cat, model = base
    bad = copy.deepcopy(p)
    bad.calibration = copy.deepcopy(p.calibration)
    bad.calibration["kappa"]["gym"]["M"] = 9.0
    g = gates.sanity_gate(np.array([50.0]), gates.Candidate(bad, cat, model), [1.0, 3.5], [], 4)
    assert not g.passed and any("kappa" in x for x in g.detail["problems"])


def _small_cfg(cfg):
    c = copy.deepcopy(cfg)
    c["export"]["min_contributors"] = 200
    c["export"]["min_anchor_contributors_per_sex"] = 50
    return c


def test_end_to_end_synthetic_writes_signed_bundle(base, good, cfg, tmp_path, monkeypatch):
    key = tmp_path / "key.pem"
    pub = keys.generate(key)
    monkeypatch.setenv(keys.KEY_ENV, str(key))
    res = run.retrain(good, _small_cfg(cfg), version="1.1.0", out_root=tmp_path / "dist",
                      report_dir=tmp_path / "reports", processed_dir=tmp_path / "processed", sign=True,
                      source="synthetic", public_key_b64=pub)
    assert res.passed, {g.name: g.detail for g in res.gates}
    manifest = keys.verify_bundle(res.bundle, pub)
    assert manifest["version"] == "1.1.0"
    assert manifest["metrics"]["retrain"]["gates"]["drift"]["passed"]
    params_new = json.loads((res.bundle / "params.json").read_text())
    params_old = json.loads((run.EMBEDDED / "params.json").read_text())
    assert params_new["calibration"]["kappa"]["gym"] != params_old["calibration"]["kappa"]["gym"]
    assert params_new["calibration"]["delta"]["general"] == params_old["calibration"]["delta"]["general"]
    tax = {r["id"]: r for r in json.loads((res.bundle / "taxonomy.json").read_text())["exercises"]}
    assert tax["barbell-curl"]["ratio"] == pytest.approx(0.5 * 1.2, rel=0.03)
    assert (res.bundle / "anchor_tables.json").read_bytes() == (run.EMBEDDED / "anchor_tables.json").read_bytes()
    text = res.report.read_text()
    assert "GEÇTİ" in text and "--rollout 10" in text and "rep_profile" in text
    assert list((tmp_path / "processed").glob("contributions-*.parquet"))
    # The exported Parquet is the filtered table: no cell under k.
    exported = pl.read_parquet(next((tmp_path / "processed").glob("*.parquet")))
    _, rep = contributions.k_anonymize(exported, 20, 10)
    assert rep.cells_dropped == 0


def test_broken_data_fails_the_gates_and_writes_no_bundle(base, cfg, tmp_path):
    p, cat, model = base
    broken = synthetic.generate(3000, cat, model, p, synthetic.Truth(e1rm_factor=2.5), seed=12)
    res = run.retrain(broken, _small_cfg(cfg), version="1.1.0", out_root=tmp_path / "dist",
                      report_dir=tmp_path / "reports", processed_dir=None, source="synthetic")
    assert not res.passed and res.bundle is None
    failed = {g.name for g in res.gates if not g.passed}
    assert "drift" in failed
    assert not (tmp_path / "dist").exists()
    assert "KALDI" in res.report.read_text()


def test_too_few_contributors_stops_before_any_output(base, cfg, tmp_path):
    p, cat, model = base
    few = synthetic.generate(50, cat, model, p, synthetic.Truth(), seed=13)
    with pytest.raises(InsufficientData):
        run.retrain(few, cfg, out_root=tmp_path / "dist", report_dir=tmp_path / "r", processed_dir=tmp_path / "x")
    assert not (tmp_path / "dist").exists() and not (tmp_path / "x").exists()


def test_fetch_pages_through_postgrest():
    pages = [[_row(f"k{i}") for i in range(3)], [_row("k9")]]
    seen = []

    def get(url, headers):
        seen.append(url)
        assert headers["apikey"] == "svc"
        return json.dumps(pages[len(seen) - 1]).encode()

    df = contributions.fetch("https://x.supabase.co/", "svc", page=3, get=get)
    assert df.height == 4 and "offset=3" in seen[1] and math.isfinite(df["best_e1rm_kg"].sum())


# --- poisoning defences (integrity filters + shift gate) -------------------------------------------------------

INTEGRITY = run.load_config()["integrity"]


def _sanitize(df, base):
    p, cat, model = base
    return integrity.sanitize(df, cat, model, p, INTEGRITY, 10, 1)


def _evasive(i: int) -> dict:
    """Bot payloads that differ from each other (no exact duplicates) but all pile onto one ~215 kg e1RM bin."""
    return {"best_e1rm_kg": round(215.0 + 0.1 * (i % 11), 1), "best_set_reps": 1 + (i // 11) % 30,
            "sessions_in_month": 1 + (i // 330) % 62}


def _bots(n: int, start: int = 0, **kw) -> list[dict]:
    return [_row(f"bot{start + i:04d}", **kw) for i in range(n)]


def test_identical_profiles_collapse_to_one_key(base):
    honest = [_row(f"h{i}", best_e1rm_kg=90.0 + i) for i in range(40)]
    out, rep = _sanitize(contributions.frame(honest + _bots(30, best_e1rm_kg=121.5)), base)
    assert rep.duplicate_keys == 29
    assert out["contribution_key"].n_unique() == 41


def test_absurd_anchor_values_are_dropped_as_outliers(base):
    honest = [_row(f"h{i}", best_e1rm_kg=100.0 + i) for i in range(60)]
    fake = [_row(f"f{i}", best_e1rm_kg=690.0 - i * 3) for i in range(10)]
    out, rep = _sanitize(contributions.frame(honest + fake), base)
    assert rep.outlier_rows == 10 and out["best_e1rm_kg"].max() < 200


def test_piled_up_values_are_thinned_but_honest_spread_is_kept(base):
    rng = np.random.default_rng(3)
    honest = [_row(f"h{i}", best_e1rm_kg=round(float(rng.normal(130, 18)), 1)) for i in range(150)]
    # 100 distinct-looking bots all sitting at ~160 kg (differ by 0.1 kg so they are not exact duplicates).
    farm = [_row(f"b{i}", **_evasive(i)) for i in range(100)]
    out, rep = _sanitize(contributions.frame(honest + farm), base)
    kept_farm = out.filter(pl.col("contribution_key").str.starts_with("b"))["contribution_key"].n_unique()
    kept_honest = out.filter(pl.col("contribution_key").str.starts_with("h"))["contribution_key"].n_unique()
    assert rep.density_keys >= 60 and kept_farm <= 0.2 * 250
    assert kept_honest >= 120  # a few honest keys sharing the farm's bin are thinned with it


def test_sanitize_is_deterministic(base):
    df = contributions.frame([_row(f"h{i}", best_e1rm_kg=100.0 + i % 40) for i in range(120)] + _bots(40))
    a, _ = _sanitize(df, base)
    b, _ = _sanitize(df, base)
    assert a.sort(["contribution_key", "exercise_id"]).equals(b.sort(["contribution_key", "exercise_id"]))


def test_honest_synthetic_data_loses_little(base, good):
    out, rep = _sanitize(good, base)
    assert rep.dropped_row_fraction < INTEGRITY["max_dropped_fraction"], rep.as_dict()


def test_bot_farm_is_neutralised_end_to_end(base, good, cfg, tmp_path):
    """Thousands of fake keys piled on one lift/value must not get a bundle that moves the population."""
    p, cat, model = base
    farm = [_row(f"x{i:05d}", sex="male", age_band=30, bodyweight_kg=80 + i % 10, **_evasive(i))
            for i in range(1500)]
    poisoned = pl.concat([good, contributions.frame(farm)])
    res = run.retrain(poisoned, _small_cfg(cfg), version="1.1.0", out_root=tmp_path / "dist",
                      report_dir=tmp_path / "reports", processed_dir=None, source="synthetic")
    rep = res.summary["integrity"]
    assert rep["density_keys"] + rep["duplicate_keys"] > 1000
    # What survives is the honest data: the calibration lands where it does without the farm.
    clean = run.retrain(good, _small_cfg(cfg), version="1.1.0", out_root=tmp_path / "dist2",
                        report_dir=tmp_path / "reports2", processed_dir=None, source="synthetic")
    a = res.summary["calibration"]["kappa"]["M"]["posterior"]
    b = clean.summary["calibration"]["kappa"]["M"]["posterior"]
    assert a == pytest.approx(b, rel=0.03)


def test_shift_gate_flags_systematic_movement_and_big_cells(base):
    p, _, _ = base
    cal = p.calibration
    moved = copy.deepcopy(cal)
    sex, lift = "M", next(iter(cal["delta"]["gym"]["M"]))
    band = next(iter(cal["delta"]["gym"][sex][lift]))
    moved["delta"]["gym"][sex][lift][band] += 0.5
    moved["kappa"]["gym"]["F"] *= 1.5
    gcfg = run.load_config()["gates"]
    old = np.full(100, 50.0)
    g = gates.shift_gate(old, old + 7.0, cal, moved, "gym", gcfg)
    assert not g.passed
    text = " ".join(g.detail["problems"])
    assert "mean signed" in text and "delta" in text and "kappa F" in text
    assert gates.shift_gate(old, old + np.array([1.0, -1.0] * 50), cal, cal, "gym", gcfg).passed


def test_integrity_gate_fails_when_too_much_is_dropped():
    cfg = {"max_dropped_fraction": 0.1}
    rep = {"dropped_row_fraction": 0.3, "duplicate_keys": 5, "outlier_rows": 1, "density_keys": 2}
    assert not gates.integrity_gate(rep, cfg).passed
    assert gates.integrity_gate({**rep, "dropped_row_fraction": 0.02}, cfg).passed
