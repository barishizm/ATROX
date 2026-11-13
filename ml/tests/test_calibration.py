"""P055 nüfus kalibrasyonu testleri."""

from __future__ import annotations

import csv
import json
from datetime import date
from pathlib import Path

import numpy as np
import polars as pl
import pytest
from scipy.stats import norm

from gymml.calibration import fit as F
from gymml.calibration.anchors import (
    COLUMNS,
    Anchor,
    AnchorError,
    load_anchors,
    parse_row,
    scale_source_bodyweight,
    validate_relative_groups,
)
from gymml.calibration.bmi import BMICorrection
from gymml.calibration.reference import (
    AGE_BANDS,
    LIFTS,
    REF_BAND,
    EmpiricalOPLReference,
    ParametricReference,
    age_band_of,
)

ML = Path(__file__).resolve().parents[1]
ANCHORS = ML / "data/anchors.csv"
PARAMS = ML / "params_draft/calibration.json"

REF = ParametricReference({("M", "squat"): 1.9, ("M", "bench"): 1.6, ("M", "deadlift"): 2.1,
                           ("F", "squat"): 1.6, ("F", "bench"): 1.1, ("F", "deadlift"): 1.9})


def _row(**kw) -> dict[str, str]:
    base = dict(population="gym", sex="M", lift="bench", age_band="all", bodyweight_kg="80",
                percentile="50", value_kg="100", source_url="https://example.org/a",
                accessed="2026-11-13", reliability="2", note="")
    base.update(kw)
    return base


# --- çapa dosyası -----------------------------------------------------------------------------

def test_anchor_file_is_fully_sourced():
    with open(ANCHORS, newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == COLUMNS
        rows = list(reader)
    assert rows
    for r in rows:
        assert r["source_url"].startswith("https://"), r
        date.fromisoformat(r["accessed"])
        assert r["reliability"] in {"1", "2", "3"}
    anchors = load_anchors(ANCHORS)
    assert len(anchors) == len(rows)


def test_anchor_file_takes_few_points_per_source():
    anchors = load_anchors(ANCHORS)
    per: dict[str, int] = {}
    for a in anchors:
        per[a.source_url] = per.get(a.source_url, 0) + 1
    assert len(per) >= 5
    assert max(per.values()) <= 25  # tablolar toplu kopyalanmaz


def test_anchor_file_covers_both_populations_and_sexes():
    anchors = load_anchors(ANCHORS)
    seen = {(a.population, a.sex) for a in anchors if not a.relative}
    assert seen == {("gym", "M"), ("gym", "F"), ("general", "M"), ("general", "F")}


@pytest.mark.parametrize("bad", [
    {"source_url": ""},
    {"source_url": "http://insecure.example"},
    {"accessed": "13.11.2026"},
    {"reliability": "4"},
    {"percentile": "100"},
    {"value_kg": "0"},
    {"population": "elite"},
    {"lift": "curl"},
    {"age_band": "30-35"},
    {"lift": "grip", "bodyweight_kg": "80"},
])
def test_parse_row_rejects_invalid(bad):
    with pytest.raises(AnchorError):
        parse_row(_row(**bad), 2)


def test_all_age_band_maps_to_reference_band():
    assert parse_row(_row(age_band="all"), 2).age_band == REF_BAND


def test_relative_group_needs_reference_row():
    a = parse_row(_row(bodyweight_kg="", age_band="50-59"), 2)
    with pytest.raises(AnchorError):
        validate_relative_groups([a])


def test_scale_source_bodyweight_keeps_ratio():
    a = parse_row(_row(bodyweight_kg="85", value_kg="85"), 2)
    (b,) = scale_source_bodyweight([a], a.source_url, 10)
    assert b.bodyweight_kg == 95 and b.value_kg == pytest.approx(95)


# --- referans ---------------------------------------------------------------------------------

def test_age_band_of():
    assert age_band_of(30) == "20-39"
    assert age_band_of(45) == "40-49"
    assert age_band_of(70) == "70+"
    with pytest.raises(ValueError):
        age_band_of(15)


def _synthetic_opl(n: int = 6000, seed: int = 1) -> pl.DataFrame:
    rng = np.random.default_rng(seed)
    sex = rng.choice(["M", "F"], n)
    age = rng.uniform(20, 80, n)
    bw = rng.uniform(55, 110, n)
    lifts = {}
    for lift, k in (("squat", 2.0), ("bench", 1.3), ("deadlift", 2.4)):
        base = k * bw * np.where(sex == "M", 1.0, 0.65) * np.exp(rng.normal(0, 0.15, n))
        lifts[f"{lift}_kg"] = base * np.where(age > 50, 0.85, 1.0)
    return pl.DataFrame({
        "athlete_id": [f"a{i}" for i in range(n)], "sex": sex, "equipment": "Raw", "age": age,
        "bodyweight_kg": bw, **lifts, "tested": True,
        "date": [date(2020, 1, 1)] * n,
    })


def test_empirical_reference_from_frame():
    ref = EmpiricalOPLReference.from_frame(_synthetic_opl(), bin_kg=10, min_n=20)
    for sex in ("M", "F"):
        for lift in LIFTS:
            for band in AGE_BANDS:
                m, s = ref.location_scale(sex, lift, band, 80)
                assert np.isfinite(m) and 0.05 < s < 0.4
    m_light, _ = ref.location_scale("M", "bench", REF_BAND, 60)
    m_heavy, _ = ref.location_scale("M", "bench", REF_BAND, 100)
    assert m_heavy > m_light
    m_young, _ = ref.location_scale("M", "bench", REF_BAND, 80)
    m_old, _ = ref.location_scale("M", "bench", "60-69", 80)
    assert m_old < m_young
    # Bilinen: 1.3 × 80 kg medyanı
    assert np.exp(m_young) == pytest.approx(1.3 * 80, rel=0.06)


# --- kestirim ---------------------------------------------------------------------------------

TRUE = {"D|gym|M": 0.25, "D|gym|F": 0.30, "D|general|M": 0.55, "D|general|F": 0.60,
        "L|M|squat": 0.10, "L|M|deadlift": 0.05, "L|F|squat": 0.20, "L|F|deadlift": 0.15,
        "A|gym|M|60-69": 0.10, "A|general|F|60-69": -0.05, "K|gym": 1.8, "K|general": 1.3}


def _true_cal() -> F.Calibration:
    theta = {n: TRUE.get(n, 0.0) for n in F.param_names()}
    return F.Calibration(theta, REF.name)


def _synthetic_anchors() -> list[Anchor]:
    cal = _true_cal()
    out = []
    i = 0
    for pop in ("gym", "general"):
        for sex in ("M", "F"):
            for lift in LIFTS:
                for bw in (60.0, 80.0, 100.0):
                    for p in (5.0, 50.0, 95.0):
                        v = cal.quantile_kg(REF, pop, sex, lift, REF_BAND, bw, p)
                        out.append(Anchor(pop, sex, lift, REF_BAND, bw, p, v,
                                          f"https://src{i % 4}.example", date(2026, 11, 13), 2, ""))
                        i += 1
            # yaşa göreli satırlar (VA bilinmiyor)
            for band in AGE_BANDS:
                v = cal.quantile_kg(REF, pop, sex, "bench", band, F.REL_BODYWEIGHT[sex], 50)
                out.append(Anchor(pop, sex, "bench", band, None, 50.0, v, "https://age.example",
                                  date(2026, 11, 13), 2, ""))
    return out


def test_fit_recovers_known_parameters():
    cal = F.fit(_synthetic_anchors(), REF)
    for name, value in TRUE.items():
        assert cal.theta[name] == pytest.approx(value, abs=0.01), name
    assert cal.meta["weighted_rss"] < 1e-5


def test_quantile_and_percentile_are_inverse():
    cal = _true_cal()
    for p in (5, 30, 50, 80, 97):
        kg = cal.quantile_kg(REF, "gym", "F", "squat", "50-59", 70, p)
        assert cal.percentile(REF, "gym", "F", "squat", "50-59", 70, kg) == pytest.approx(p)


def test_score_monotone_in_load_and_population_order():
    cal = _true_cal()
    loads = np.linspace(30, 200, 30)
    for pop in ("competitor", "gym", "general"):
        ps = [cal.percentile(REF, pop, "M", "bench", REF_BAND, 80, kg) for kg in loads]
        assert all(b > a for a, b in zip(ps, ps[1:], strict=False))
    # Aynı yük: genel nüfusa göre > salona göre > yarışmacıya göre (δ_general > δ_gym > 0).
    pc = cal.percentile(REF, "competitor", "M", "bench", REF_BAND, 80, 90)
    pg = cal.percentile(REF, "gym", "M", "bench", REF_BAND, 80, 90)
    pn = cal.percentile(REF, "general", "M", "bench", REF_BAND, 80, 90)
    assert pc < pg < pn


def test_relative_anchor_identifies_age_offset_only():
    anchors = [a for a in _synthetic_anchors() if a.relative or a.age_band == REF_BAND]
    eqs = F.build_equations(anchors, REF)
    rel = [e for e in eqs if e.anchor.relative]
    assert rel and all(e.anchor.age_band != REF_BAND for e in rel)
    names = F.param_names()
    for e in rel:
        used = {names[i].split("|")[0] for i in np.flatnonzero(e.row)}
        assert used <= {"A", "K"}


def test_bootstrap_is_seeded_and_covers_truth():
    anchors = _synthetic_anchors()
    b1 = F.bootstrap(anchors, REF, n_boot=20, seed=3)
    b2 = F.bootstrap(anchors, REF, n_boot=20, seed=3)
    assert [b.theta for b in b1] == [b.theta for b in b2]
    ks = [b.kappa("gym", "M") for b in b1]
    assert min(ks) - 0.01 <= TRUE["K|gym"] <= max(ks) + 0.01  # önsel hafifçe büzer


def test_leave_one_source_out_predicts_held_out_source():
    anchors = _synthetic_anchors()
    loso = F.leave_one_source_out(anchors, REF)
    assert set(loso) == {a.source_url for a in anchors}
    for _, held in loso.values():
        for h in held:
            if h.percentile_error is not None:
                assert abs(h.percentile_error) < 1.0  # gürültüsüz veride neredeyse tam


def test_weighting_modes():
    anchors = _synthetic_anchors()
    for mode in ("equal", "reliability", "reliability/sqrt(n_source)"):
        cal = F.fit(anchors, REF, weights_mode=mode)
        assert cal.theta["K|gym"] == pytest.approx(TRUE["K|gym"], abs=0.01)


# --- BMI --------------------------------------------------------------------------------------

def test_bmi_correction():
    c = BMICorrection(threshold=25, beta=0.5)
    assert c.effective_bodyweight(70, 180) == 70            # BMI 21.6
    cap = 25 * 1.8**2
    assert c.effective_bodyweight(110, 180) == pytest.approx(cap + 0.5 * (110 - cap))
    ws = [c.effective_bodyweight(w, 175) for w in range(50, 150, 5)]
    assert all(b >= a for a, b in zip(ws, ws[1:], strict=False))
    fn = c.with_assumed_height({"M": 180.0, "F": 165.0})
    assert fn("M", 110) < 110


# --- üretilen taslak ----------------------------------------------------------------------------

def test_params_draft_calibration_section():
    data = json.loads(PARAMS.read_text())["calibration"]
    assert data["bmi_correction"]["enabled"] is False
    assert data["reference_age_band"] == REF_BAND
    for pop in ("gym", "general"):
        for sex in ("M", "F"):
            assert data["kappa"][pop][sex] > 0
            for lift in LIFTS:
                for band in AGE_BANDS:
                    d = data["delta"][pop][sex][lift][band]
                    assert 0.0 < d < 1.5  # salon/genel nüfus yarışmacıdan zayıf
    band = data["uncertainty_band_pct_points"]
    assert 0 < band["gym"]["median_half_width"] <= band["general"]["median_half_width"]


def test_normal_constants():
    # 15.87/84.13 yüzdelikleri ±1σ
    assert norm.ppf(0.841345) == pytest.approx(1.0, abs=1e-4)
