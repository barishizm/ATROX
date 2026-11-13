"""P057: tam skor hattının Python referans uygulaması (docs/03-ML-MODEL.md §2–§8).

Swift `StrengthKit` bunun birebir kopyası olacak (P061–P062). Sabitlerin hepsi `Params`'tan gelir
(`params_draft/*.json`; P060 tek `params.json`'a birleştirir); bu dosyada sihirli sayı yoktur.

Akış:
    score_set            set → e1RM + güven (P054 eğrileri)
    current_strength     oturumlar → güncel güç, aykırı değer işareti, bayatlama, güven düzeyi (§3)
    exercise_score       güncel güç → çapa eşdeğeri → yarışmacı z (P053) → nüfus z (P055) →
                         oran büzülmesi (§6) → yüzdelik + bant (+ cinsiyetsiz karışım §4.5)
    aggregate            kas grubu ve genel skor, z uzayında korelasyon düzeltmeli birleştirme (§8)
"""

from __future__ import annotations

import json
import math
import pickle
from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path
from typing import Any

import numpy as np
import polars as pl
from scipy.stats import norm

from gymml.calibration.reference import age_band_of
from gymml.models.e1rm import Curve, category_for_pattern
from gymml.models.e1rm import confidence as set_confidence

ML_ROOT = Path(__file__).resolve().parents[2]
PARAMS_DIR = ML_ROOT / "params_draft"
LIFTS = ("squat", "bench", "deadlift")
CONFIDENCE_ORDER = ("low", "medium", "high")


# ----------------------------------------------------------------------------------------------
# Parametreler
# ----------------------------------------------------------------------------------------------


@dataclass
class Params:
    e1rm: dict
    calibration: dict
    scoring: dict
    correlation: np.ndarray  # squat, bench, deadlift

    @classmethod
    def load(cls, directory: Path = PARAMS_DIR) -> Params:
        def read(name: str) -> dict:
            return json.loads((directory / f"{name}.json").read_text(encoding="utf-8"))

        scoring = read("scoring")
        corr = scoring.get("anchor_correlation") or read("correlation")
        m = np.asarray(corr["matrix"], dtype=float)
        if list(corr["variables"]) != list(LIFTS):
            raise ValueError(f"korelasyon değişkenleri {corr['variables']} != {LIFTS}")
        return cls(read("e1rm"), read("calibration")["calibration"], scoring, m)

    def curve(self, movement_pattern: str | None) -> Curve:
        cat = category_for_pattern(movement_pattern)
        cats = self.e1rm["categories"]
        c = cats.get(cat) or cats[self.e1rm["default_category"]]
        return Curve(self.e1rm["family"], {"k": c["k"], "p": c["p"]})


# ----------------------------------------------------------------------------------------------
# Girdiler
# ----------------------------------------------------------------------------------------------


@dataclass(frozen=True)
class Exercise:
    """`tools/catalog/scoring_taxonomy.yaml` satırı + katalogdaki kaslar ve ekipman."""

    id: str
    movement_pattern: str | None
    scoring_type: str  # weighted | bodyweight_loaded | reps_only | time | none
    load_convention: str | None = None
    anchor: str | None = None
    ratio: float | None = None
    tau: float | None = None
    ratio_confidence: str | None = None  # A | B | C
    bw_fraction: float | None = None
    ratio_source: str | None = None  # "anchor" = çapa hareketin kendisi
    primary_muscles: tuple[str, ...] = ()
    secondary_muscles: tuple[str, ...] = ()
    equipment: str | None = None

    @property
    def is_anchor(self) -> bool:
        return self.ratio_source == "anchor"

    @property
    def scorable(self) -> bool:
        if self.scoring_type == "reps_only":
            return True
        return self.scoring_type in ("weighted", "bodyweight_loaded") and self.anchor is not None


@dataclass(frozen=True)
class User:
    sex: str | None  # "M" | "F" | None (belirtilmemiş → §4.5 karışım)
    age: float
    bodyweight_kg: float


@dataclass(frozen=True)
class LoggedSet:
    day: date
    weight_kg: float  # kullanıcının yazdığı sayı (load_convention birimiyle)
    reps: int
    rir: float | None = None
    is_warmup: bool = False
    confirmed: bool = False  # kullanıcı "Bu seti doğru mu girdin?" sorusuna Evet dedi


# ----------------------------------------------------------------------------------------------
# 1) Set → e1RM
# ----------------------------------------------------------------------------------------------


@dataclass(frozen=True)
class SetScore:
    e1rm_kg: float  # efektif yük biriminde (bodyweight_loaded için vücut ağırlığı dahil)
    confidence: float


def effective_load(ex: Exercise, weight_kg: float, user: User) -> float:
    if ex.scoring_type == "bodyweight_loaded":
        if ex.bw_fraction is None:
            raise ValueError(f"{ex.id}: bodyweight_loaded ama bw_fraction yok")
        return ex.bw_fraction * user.bodyweight_kg + weight_kg
    return weight_kg


def score_set(ex: Exercise, s: LoggedSet, user: User, p: Params) -> SetScore:
    load = effective_load(ex, s.weight_kg, user)
    if load <= 0 or s.reps < 1:
        return SetScore(0.0, 0.0)
    r_eff = float(s.reps) + (0.0 if s.rir is None else float(s.rir))
    e = float(p.curve(ex.movement_pattern).e1rm(load, r_eff))
    c = float(set_confidence(r_eff, s.rir is not None, s.is_warmup, p.e1rm["confidence"]))
    return SetScore(e, c)


# ----------------------------------------------------------------------------------------------
# 2) Güncel güç (§3)
# ----------------------------------------------------------------------------------------------


@dataclass(frozen=True)
class SessionValue:
    day: date
    e1rm_kg: float
    confidence: float
    flagged: bool = False  # %12 sıçrama, onay bekliyor


@dataclass(frozen=True)
class CurrentStrength:
    e1rm_kg: float | None
    confidence: str  # low | medium | high
    stale: bool
    sessions_in_window: int
    flagged: tuple[SessionValue, ...] = ()


def session_values(
    ex: Exercise, sets: Sequence[LoggedSet], user: User, p: Params
) -> list[tuple[SessionValue, bool]]:
    """Gün başına güven ağırlıklı en iyi set: e1RM × güven en büyük olan. (değer, onaylı mı)."""
    cfg = p.scoring["current_strength"]
    by_day: dict[date, list[tuple[SetScore, bool]]] = {}
    for s in sets:
        sc = score_set(ex, s, user, p)
        if sc.confidence >= cfg["min_set_confidence"]:
            by_day.setdefault(s.day, []).append((sc, s.confirmed))
    out = []
    for d in sorted(by_day):
        best, conf_ok = max(by_day[d], key=lambda t: (t[0].e1rm_kg * t[0].confidence, t[0].e1rm_kg))
        out.append((SessionValue(d, best.e1rm_kg, best.confidence), conf_ok))
    return out


def current_strength(
    ex: Exercise, sets: Sequence[LoggedSet], user: User, as_of: date, p: Params
) -> CurrentStrength:
    cfg = p.scoring["current_strength"]
    sessions = [(v, ok) for v, ok in session_values(ex, sets, user, p) if v.day <= as_of]
    accepted: list[SessionValue] = []
    flagged: list[SessionValue] = []
    for v, ok in sessions:
        prev = max((a.e1rm_kg for a in accepted), default=None)
        if prev is not None and v.e1rm_kg > prev * (1 + cfg["outlier_jump"]) and not ok:
            flagged.append(SessionValue(v.day, v.e1rm_kg, v.confidence, flagged=True))
            continue
        accepted.append(v)
    if not accepted:
        return CurrentStrength(None, "low", False, 0, tuple(flagged))

    window = [a for a in accepted if (as_of - a.day).days <= cfg["window_days"]]
    if window:
        best = max(window, key=lambda a: a.e1rm_kg)
        value, stale = best.e1rm_kg, False
    else:
        # Pencere dışı: her oturum, pencereyi aştığı hafta kadar indirimli; en iyisi alınır.
        def decayed(a: SessionValue) -> float:
            weeks = max(0.0, ((as_of - a.day).days - cfg["window_days"]) / 7.0)
            return a.e1rm_kg * (1 - cfg["stale_decay_per_week"]) ** weeks

        value, stale = max(decayed(a) for a in accepted), True

    last = max(a.day for a in accepted)
    used = window or accepted
    level = _confidence_level(
        len(window), (as_of - last).days, float(np.mean([a.confidence for a in used])), cfg
    )
    if stale:
        level = "low"
    return CurrentStrength(value, level, stale, len(window), tuple(flagged))


def _confidence_level(n: int, days_since: int, mean_conf: float, cfg: Mapping) -> str:
    for lvl in ("high", "medium"):
        t = cfg["confidence_levels"][lvl]
        if (n >= t["min_sessions"] and days_since <= t["max_days_since_last"]
                and mean_conf >= t["min_mean_set_confidence"]):  # fmt: skip
            return lvl
    return "low"


# ----------------------------------------------------------------------------------------------
# 3) Hareket skoru (§4–§6)
# ----------------------------------------------------------------------------------------------


@dataclass(frozen=True)
class ExerciseScore:
    exercise_id: str
    score: float  # [1, 99]
    z: float
    band: tuple[float, float]  # yüzdelik
    confidence: str
    level: str
    population: str
    is_machine: bool
    anchor: str | None
    stale: bool = False


class AnchorModel:
    """P053 kazananı: kaldırış başına `DistributionModel` (quantile/cdf)."""

    def __init__(self, models: Mapping[str, Any], p: Params):
        self.models = models
        cfg = p.scoring["anchor_model"]
        self.clip = tuple(cfg["cdf_clip"])
        self.scale_q = np.asarray(cfg["scale_quantiles"], dtype=float)

    @classmethod
    def load(cls, p: Params, root: Path = ML_ROOT) -> AnchorModel:
        cfg = p.scoring["anchor_model"]
        models = {}
        for lift in LIFTS:
            path = root / cfg["pickle_pattern"].format(key=cfg["key"], lift=lift)
            with path.open("rb") as f:
                models[lift] = pickle.load(f)
        return cls(models, p)

    def z_and_scale(
        self, lift: str, sex: str, age: float, bw: float, value_kg: float
    ) -> tuple[float, float]:
        """Yarışmacı z = Φ⁻¹(F(y|x)) ve log ölçekte yayılım s_c = (log Q84 − log Q16)/2."""
        x = pl.DataFrame({"sex": [sex], "age": [float(age)], "bodyweight_kg": [float(bw)]})
        m = self.models[lift]
        f = float(np.clip(m.cdf(x, np.array([value_kg]))[0], *self.clip))
        lo, hi = np.log(m.quantile(x, self.scale_q)[0])
        return float(norm.ppf(f)), float((hi - lo) / 2)


def calibrate_z(
    z_c: float, s_c: float, pop: str, sex: str, lift: str, age: float, p: Params
) -> tuple[float, float]:
    """§5.1: z_g = (z_c + δ/s_c)/κ; yayılım s_g = κ·s_c. Yarışmacı için δ = 0, κ = 1."""
    if pop == "competitor":
        return z_c, s_c
    cal = p.calibration
    # Under 20 uses the 20-39 band (P057); 86+ uses 70+ (the anchor model also clips age at 85).
    band = age_band_of(min(max(age, _band_min_age(p)), 85.0))
    delta = cal["delta"][pop][sex][lift][band]
    kappa = cal["kappa"][pop][sex]
    return (z_c + delta / s_c) / kappa, kappa * s_c


def _band_min_age(p: Params) -> float:
    return float(p.scoring["exercise_score"]["calibration_min_age_band"].split("-")[0])


def is_machine(ex: Exercise, p: Params) -> bool:
    cfg = p.scoring["exercise_score"]
    return (ex.load_convention in cfg["machine_conventions"]
            or (ex.equipment or "") in cfg["machine_equipment"])  # fmt: skip


def _tau(ex: Exercise, p: Params) -> float:
    if ex.tau is None:
        raise ValueError(f"{ex.id}: tau yok")
    return float(ex.tau)


def _cap(ex: Exercise, p: Params) -> str:
    caps = p.scoring["exercise_score"]["grade_confidence_cap"]
    if is_machine(ex, p):
        return "low"
    return caps["anchor"] if ex.is_anchor else caps.get(ex.ratio_confidence or "C", "low")


def _min_conf(*levels: str) -> str:
    return min(levels, key=CONFIDENCE_ORDER.index)


def level_key(score: float, p: Params) -> str:
    key = p.scoring["levels"][0]["key"]
    for lvl in p.scoring["levels"]:
        if score >= lvl["min"]:
            key = lvl["key"]
    return key


def _calibration_band_z(pop: str, p: Params) -> float:
    """P055 belirsizlik bandı (medyan yarı genişlik, yüzdelik puan) → medyanda z yarı genişliği."""
    if pop == "competitor":
        return 0.0
    hw = p.calibration["uncertainty_band_pct_points"][pop]["median_half_width"]
    return float(norm.ppf(0.5 + hw / 100.0))


def _anchor_z_for_sex(
    ex: Exercise, sex: str, user: User, e1rm_logged: float, pop: str, model: AnchorModel, p: Params
) -> tuple[float, float]:
    """Tek cinsiyet: büzülmüş nüfus z'si ve büzülme sonrası oran belirsizliği (z birimi)."""
    if ex.anchor is None or ex.ratio is None:
        raise ValueError(f"{ex.id}: çapa/oran yok")
    anchor_equiv = e1rm_logged / ex.ratio
    z_c, s_c = model.z_and_scale(ex.anchor, sex, user.age, user.bodyweight_kg, anchor_equiv)
    z_g, s_g = calibrate_z(z_c, s_c, pop, sex, ex.anchor, user.age, p)
    tau = _tau(ex, p)
    shrink = s_g / math.sqrt(s_g**2 + tau**2)
    return z_g * shrink, tau / math.sqrt(s_g**2 + tau**2)


def exercise_score(
    ex: Exercise,
    strength: CurrentStrength,
    user: User,
    model: AnchorModel,
    p: Params,
    population: str | None = None,
    reps: float | None = None,
) -> ExerciseScore | None:
    """Güncel güçten 1–99 skor. `reps_only` için `reps` (en iyi set tekrarı) verilir."""
    cfg = p.scoring["exercise_score"]
    pop = population or cfg["default_population"]
    lo_clip, hi_clip = cfg["score_clip"]
    if ex.scoring_type in ("none", "time"):
        return None

    if ex.scoring_type == "reps_only":
        return _reps_only_score(ex, user, reps, pop, p)

    if not ex.scorable or strength.e1rm_kg is None:
        return None
    sexes = [user.sex] if user.sex else list(cfg["unspecified_sex_mix"])
    mix = {user.sex: 1.0} if user.sex else cfg["unspecified_sex_mix"]
    cal_b = _calibration_band_z(pop, p)

    # e1RM yazılan birimde (bodyweight_loaded: efektif yük); oran o birimle tanımlı (ratios.yaml).
    def pct_at(shift: float) -> float:
        total = 0.0
        for sex in sexes:
            z, ratio_b = _anchor_z_for_sex(ex, sex, user, strength.e1rm_kg, pop, model, p)
            b = math.sqrt(cal_b**2 + ratio_b**2)
            total += mix[sex] * float(norm.cdf(z + shift * b))
        return total

    pct = pct_at(0.0)
    z = float(norm.ppf(np.clip(pct, 1e-9, 1 - 1e-9)))
    score = float(np.clip(100 * pct, lo_clip, hi_clip))
    band = (float(np.clip(100 * pct_at(-1.0), lo_clip, hi_clip)),
            float(np.clip(100 * pct_at(1.0), lo_clip, hi_clip)))  # fmt: skip
    conf = _min_conf(strength.confidence, _cap(ex, p))
    return ExerciseScore(ex.id, score, z, band, conf, level_key(score, p), pop, is_machine(ex, p),
                         ex.anchor, strength.stale)  # fmt: skip


def _reps_only_score(
    ex: Exercise, user: User, reps: float | None, pop: str, p: Params
) -> ExerciseScore | None:
    from gymml.data import rep_norms

    if reps is None:
        return None
    cfg = p.scoring["exercise_score"]
    lo_clip, hi_clip = cfg["score_clip"]
    points = rep_norms.load()
    sexes = [user.sex] if user.sex else list(cfg["unspecified_sex_mix"])
    mix = {user.sex: 1.0} if user.sex else cfg["unspecified_sex_mix"]
    vals = []
    for sex in sexes:
        v = rep_norms.percentile(points, ex.id, sex, int(user.age), reps)
        if v is None:
            return None
        vals.append(mix[sex] * v)
    score = float(np.clip(sum(vals), lo_clip, hi_clip))
    z = float(norm.ppf(score / 100))
    return ExerciseScore(ex.id, score, z, (lo_clip, hi_clip), "low", level_key(score, p), pop,
                         False, None)  # fmt: skip


# ----------------------------------------------------------------------------------------------
# 4) Birleştirme (§8)
# ----------------------------------------------------------------------------------------------


@dataclass(frozen=True)
class GroupScore:
    key: str
    score: float
    z: float
    n: int
    confidence: str
    provisional: bool = False
    level: str = ""
    patterns: tuple[str, ...] = field(default=())


def _pair_r(a: ExerciseScore, b: ExerciseScore, p: Params) -> float:
    cfg = p.scoring["aggregate"]
    if a.anchor is None or b.anchor is None:
        return cfg["unknown_pair_correlation"]
    if a.anchor == b.anchor:
        return cfg["same_anchor_correlation"]
    return float(p.correlation[LIFTS.index(a.anchor), LIFTS.index(b.anchor)])


def combine(zs: Sequence[float], ws: Sequence[float], r: np.ndarray) -> float:
    """§8: z = Σ w z / sqrt(Σ w² + 2 Σ_{i<j} w_i w_j r_ij); `r` simetrik, köşegen kullanılmaz."""
    w = np.asarray(ws, dtype=float)
    z = np.asarray(zs, dtype=float)
    R = np.array(r, dtype=float, copy=True)
    np.fill_diagonal(R, 1.0)
    den = float(w @ R @ w)
    return float(w @ z / math.sqrt(den))


def _item_weight(s: ExerciseScore, p: Params) -> float:
    cfg = p.scoring["aggregate"]
    w = cfg["confidence_weights"][s.confidence]
    if s.stale:
        w *= cfg["stale_weight"]
    if s.is_machine:
        w *= cfg["machine_weight"]
    return w


def _to_score(z: float, p: Params) -> float:
    lo, hi = p.scoring["exercise_score"]["score_clip"]
    return float(np.clip(100 * norm.cdf(z), lo, hi))


def _combine_scores(items: Sequence[ExerciseScore], extra_w: Sequence[float], p: Params) -> float:
    ws = [e * _item_weight(s, p) for s, e in zip(items, extra_w, strict=True)]
    n = len(items)
    R = np.eye(n)
    for i in range(n):
        for j in range(i + 1, n):
            R[i, j] = R[j, i] = _pair_r(items[i], items[j], p)
    return combine([s.z for s in items], ws, R)


def muscle_group_scores(
    scores: Sequence[ExerciseScore], exercises: Mapping[str, Exercise], p: Params
) -> dict[str, GroupScore]:
    cfg = p.scoring["aggregate"]["muscle_weights"]
    groups: dict[str, list[tuple[ExerciseScore, float]]] = {}
    for s in scores:
        ex = exercises[s.exercise_id]
        for m in ex.primary_muscles:
            groups.setdefault(m, []).append((s, cfg["primary"]))
        for m in ex.secondary_muscles:
            if m not in ex.primary_muscles:
                groups.setdefault(m, []).append((s, cfg["secondary"]))
    out = {}
    for m, items in sorted(groups.items()):
        sc, ew = [i for i, _ in items], [w for _, w in items]
        z = _combine_scores(sc, ew, p)
        score = _to_score(z, p)
        conf = max((s.confidence for s in sc), key=CONFIDENCE_ORDER.index)
        out[m] = GroupScore(m, score, z, len(sc), conf, level=level_key(score, p))
    return out


def overall_score(
    scores: Sequence[ExerciseScore], exercises: Mapping[str, Exercise], p: Params
) -> GroupScore | None:
    cfg = p.scoring["aggregate"]
    by_pattern: dict[str, list[ExerciseScore]] = {}
    for s in scores:
        pat = exercises[s.exercise_id].movement_pattern
        if pat in cfg["patterns"]:
            by_pattern.setdefault(pat, []).append(s)
    if not by_pattern:
        return None
    pats = sorted(by_pattern, key=cfg["patterns"].index)
    pz = [_combine_scores(by_pattern[k], [1.0] * len(by_pattern[k]), p) for k in pats]
    pw = [max(_item_weight(s, p) for s in by_pattern[k]) for k in pats]
    R = np.full((len(pats), len(pats)), cfg["pattern_correlation"])
    z = combine(pz, pw, R)
    score = _to_score(z, p)
    has_upper = any(k in cfg["upper_patterns"] for k in pats)
    has_lower = any(k in cfg["lower_patterns"] for k in pats)
    provisional = len(pats) < cfg["min_patterns_for_full_score"] or not (has_upper and has_lower)
    conf = max((s.confidence for s in scores), key=CONFIDENCE_ORDER.index)
    return GroupScore("overall", score, z, len(scores), conf, provisional, level_key(score, p),
                      tuple(pats))  # fmt: skip
