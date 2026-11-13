"""Dengesizlik analizi — Python referansı (docs/03-ML-MODEL.md §10, P059).

Swift StrengthKit bu modülü birebir taşır; bu yüzden saf ve deterministiktir, sayı sabitleri koda
gömülmez (hepsi `ImbalanceParams` içinden, taslağı `ml/params_draft/imbalance.json`).

Üç bulgu kaynağı:

1. ``conditional_residual`` — korelasyon matrisinden ``E[z_i | diğer z'ler]`` ve artığın
   standart sapması. Standart artık ``(z_i - E) / SD`` eşiği aşarsa bulgu. Tek bir zayıf kaldırış
   diğerlerinin artığını ters yönde şişirdiği için "soyma" uygulanır: en büyük |artık| bulgu olur,
   o değişken çıkarılır, kalanlar ``min_variables`` sağladıkça yeniden hesaplanır.
2. ``ratio_rule`` — itiş/çekiş, üst/alt vücut, squat/deadlift. Skorlar zaten aynı nüfusa göre
   z'ye çevrildiği için "oran" z uzayında fark olarak ölçülür (eşit z = dengeli). Grup skoru §8
   formülüyle birleştirilir.
3. ``left_right`` — tek taraflı hareketlerde aynı hareketin sol/sağ e1RM'i:
   ``(güçlü - zayıf) / güçlü``.

Kapı: yalnızca ``allowed_confidence`` içindeki güvenle gelen ve makine olmayan skorlar kullanılır.
Çıktı metin içermez; uygulama ``recommendation_key`` ile yerelleştirilmiş şablon seçer (P069).
Şema: ``ml/reports/imbalance.md``.
"""

from __future__ import annotations

import json
import math
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

FINDING_SCHEMA_VERSION = 1
SEVERITIES: tuple[str, ...] = ("mild", "moderate", "severe")
CONFIDENCES: tuple[str, ...] = ("low", "medium", "high")
PATTERNS: tuple[str, ...] = (
    "horizontal_push",
    "vertical_push",
    "horizontal_pull",
    "vertical_pull",
    "squat",
    "hinge",
    "core",
)

KIND_RESIDUAL = "conditional_residual"
KIND_RATIO = "ratio_rule"
KIND_LEFT_RIGHT = "left_right"

DEFAULT_PARAMS_PATH = Path(__file__).resolve().parents[2] / "params_draft" / "imbalance.json"


# --------------------------------------------------------------------------------------------
# Girdiler
# --------------------------------------------------------------------------------------------


@dataclass(frozen=True)
class ScoreInput:
    """Bir hareketin z uzayındaki skoru.

    ``corr_key`` hareket korelasyon matrisindeki bir değişkense (ör. ``"bench"``) doludur; yalnızca
    çapa hareketin kendisi için verilir.
    """

    exercise_id: str
    z: float
    confidence: str
    pattern: str
    is_machine: bool = False
    corr_key: str | None = None
    muscles: tuple[str, ...] = ()

    def __post_init__(self) -> None:
        if self.confidence not in CONFIDENCES:
            raise ValueError(f"unknown confidence: {self.confidence!r}")
        if self.pattern not in PATTERNS:
            raise ValueError(f"unknown pattern: {self.pattern!r}")
        if not math.isfinite(self.z):
            raise ValueError(f"non-finite z for {self.exercise_id}")


@dataclass(frozen=True)
class UnilateralInput:
    """Tek taraflı bir hareketin sol ve sağ e1RM'i (kg, aynı hareket)."""

    exercise_id: str
    left_kg: float
    right_kg: float
    confidence: str
    is_machine: bool = False
    muscles: tuple[str, ...] = ()

    def __post_init__(self) -> None:
        if self.confidence not in CONFIDENCES:
            raise ValueError(f"unknown confidence: {self.confidence!r}")
        if not (self.left_kg > 0 and self.right_kg > 0):
            raise ValueError(f"e1RM must be positive for {self.exercise_id}")


# --------------------------------------------------------------------------------------------
# Parametreler
# --------------------------------------------------------------------------------------------


def _ladder(raw: Mapping[str, float], name: str) -> tuple[float, ...]:
    if set(raw) != set(SEVERITIES):
        raise ValueError(f"{name} must define exactly {SEVERITIES}")
    values = tuple(float(raw[s]) for s in SEVERITIES)
    if not all(0 < a < b for a, b in zip(values, values[1:], strict=False)) or values[0] <= 0:
        raise ValueError(f"{name} must be positive and strictly increasing")
    return values


@dataclass(frozen=True)
class RatioRule:
    id: str
    group_a: str
    patterns_a: frozenset[str]
    group_b: str
    patterns_b: frozenset[str]
    min_exercises_per_group: int
    severity_z_gap: tuple[float, ...]


@dataclass(frozen=True)
class ImbalanceParams:
    variables: tuple[str, ...]
    correlation: np.ndarray = field(compare=False)
    min_variables: int
    severity_sd: tuple[float, ...]
    unknown_pair_correlation: float
    confidence_weights: Mapping[str, float]
    allowed_confidence: frozenset[str]
    exclude_machine: bool
    ratio_rules: tuple[RatioRule, ...]
    severity_asymmetry: tuple[float, ...]

    @classmethod
    def from_dict(cls, raw: Mapping) -> ImbalanceParams:
        if raw.get("schema_version") != 1:
            raise ValueError("unsupported imbalance params schema_version")
        corr = raw["correlation"]
        variables = tuple(corr["variables"])
        matrix = np.asarray(corr["matrix"], dtype=np.float64)
        _validate_correlation(variables, matrix)

        residual = raw["residual"]
        agg = raw["aggregation"]
        gate = raw["gate"]
        allowed = frozenset(gate["allowed_confidence"])
        if not allowed <= set(CONFIDENCES):
            raise ValueError("allowed_confidence has unknown levels")
        weights = {k: float(v) for k, v in agg["confidence_weights"].items()}
        if set(weights) != allowed or any(w <= 0 for w in weights.values()):
            raise ValueError("confidence_weights must be positive for every allowed confidence")
        r_unknown = float(agg["unknown_pair_correlation"])
        if not -1 < r_unknown < 1:
            raise ValueError("unknown_pair_correlation must be in (-1, 1)")

        rules = []
        seen: set[str] = set()
        for r in raw["ratio_rules"]:
            if r["id"] in seen:
                raise ValueError(f"duplicate ratio rule {r['id']}")
            seen.add(r["id"])
            pa, pb = frozenset(r["group_a"]["patterns"]), frozenset(r["group_b"]["patterns"])
            if not (pa and pb) or pa & pb or not (pa | pb) <= set(PATTERNS):
                raise ValueError(f"rule {r['id']}: groups must be non-empty, disjoint, known")
            rules.append(
                RatioRule(
                    id=r["id"],
                    group_a=r["group_a"]["name"],
                    patterns_a=pa,
                    group_b=r["group_b"]["name"],
                    patterns_b=pb,
                    min_exercises_per_group=int(r["min_exercises_per_group"]),
                    severity_z_gap=_ladder(r["severity_z_gap"], f"{r['id']}.severity_z_gap"),
                )
            )
        min_vars = int(residual["min_variables"])
        if min_vars < 2:
            raise ValueError("min_variables must be >= 2")
        return cls(
            variables=variables,
            correlation=matrix,
            min_variables=min_vars,
            severity_sd=_ladder(residual["severity_sd"], "residual.severity_sd"),
            unknown_pair_correlation=r_unknown,
            confidence_weights=weights,
            allowed_confidence=allowed,
            exclude_machine=bool(gate["exclude_machine"]),
            ratio_rules=tuple(rules),
            severity_asymmetry=_ladder(
                raw["left_right"]["severity_asymmetry"], "left_right.severity_asymmetry"
            ),
        )

    def with_correlation(self, variables: Sequence[str], matrix: np.ndarray) -> ImbalanceParams:
        """Aynı eşiklerle başka bir (ör. kişinin x'ine koşullu) korelasyon matrisi kullan."""
        variables = tuple(variables)
        matrix = np.asarray(matrix, dtype=np.float64)
        _validate_correlation(variables, matrix)
        return ImbalanceParams(
            variables=variables,
            correlation=matrix,
            min_variables=self.min_variables,
            severity_sd=self.severity_sd,
            unknown_pair_correlation=self.unknown_pair_correlation,
            confidence_weights=self.confidence_weights,
            allowed_confidence=self.allowed_confidence,
            exclude_machine=self.exclude_machine,
            ratio_rules=self.ratio_rules,
            severity_asymmetry=self.severity_asymmetry,
        )


def _validate_correlation(variables: tuple[str, ...], m: np.ndarray) -> None:
    k = len(variables)
    if len(set(variables)) != k:
        raise ValueError("correlation variables must be unique")
    if m.shape != (k, k):
        raise ValueError("correlation matrix shape does not match variables")
    if not np.all(np.isfinite(m)) or not np.allclose(m, m.T, atol=1e-12):
        raise ValueError("correlation matrix must be finite and symmetric")
    if not np.allclose(np.diag(m), 1.0, atol=1e-12):
        raise ValueError("correlation matrix must have a unit diagonal")
    try:
        np.linalg.cholesky(m)
    except np.linalg.LinAlgError as exc:
        raise ValueError("correlation matrix must be positive definite") from exc


def load_params(path: str | Path = DEFAULT_PARAMS_PATH) -> ImbalanceParams:
    with open(path, encoding="utf-8") as fh:
        return ImbalanceParams.from_dict(json.load(fh))


# --------------------------------------------------------------------------------------------
# Bulgu nesnesi
# --------------------------------------------------------------------------------------------


@dataclass(frozen=True)
class Finding:
    """Makine tarafından okunur bulgu. Metin yok; şema ``ml/reports/imbalance.md``."""

    kind: str
    rule_id: str
    severity: str
    magnitude: float
    weak_group: str
    strong_group: str | None
    weak_exercise_ids: tuple[str, ...]
    strong_exercise_ids: tuple[str, ...]
    muscles: tuple[str, ...]
    recommendation_key: str
    metrics: Mapping[str, float]

    def to_dict(self) -> dict:
        return {
            "schema_version": FINDING_SCHEMA_VERSION,
            "kind": self.kind,
            "rule_id": self.rule_id,
            "severity": self.severity,
            "magnitude": self.magnitude,
            "weak_group": self.weak_group,
            "strong_group": self.strong_group,
            "weak_exercise_ids": list(self.weak_exercise_ids),
            "strong_exercise_ids": list(self.strong_exercise_ids),
            "muscles": list(self.muscles),
            "recommendation_key": self.recommendation_key,
            "metrics": {k: self.metrics[k] for k in sorted(self.metrics)},
        }


def _severity(value: float, ladder: tuple[float, ...]) -> str | None:
    level = None
    for name, threshold in zip(SEVERITIES, ladder, strict=True):
        if value >= threshold:
            level = name
    return level


def _muscles(items: Iterable[ScoreInput | UnilateralInput]) -> tuple[str, ...]:
    return tuple(sorted({m for it in items for m in it.muscles}))


# --------------------------------------------------------------------------------------------
# Kapı
# --------------------------------------------------------------------------------------------


def _passes_gate(item: ScoreInput | UnilateralInput, p: ImbalanceParams) -> bool:
    if item.confidence not in p.allowed_confidence:
        return False
    return not (p.exclude_machine and item.is_machine)


# --------------------------------------------------------------------------------------------
# 1) Koşullu beklenti
# --------------------------------------------------------------------------------------------


def conditional_moments(
    corr: np.ndarray, target: int, given: Sequence[int], z_given: Sequence[float]
) -> tuple[float, float]:
    """Standart çok değişkenli normalde ``E[z_t | z_g]`` ve koşullu SD.

    ``E = Σ_tg Σ_gg⁻¹ z_g``, ``Var = 1 - Σ_tg Σ_gg⁻¹ Σ_gt``.
    """
    g = list(given)
    s_gg = corr[np.ix_(g, g)]
    s_tg = corr[target, g]
    beta = np.linalg.solve(s_gg, s_tg)  # Σ_gg simetrik → Σ_gg⁻¹ Σ_gt
    mean = float(beta @ np.asarray(z_given, dtype=np.float64))
    var = float(1.0 - s_tg @ beta)
    return mean, math.sqrt(max(var, 0.0))


def residual_findings(scores: Sequence[ScoreInput], p: ImbalanceParams) -> list[Finding]:
    by_key: dict[str, ScoreInput] = {}
    for s in scores:
        if s.corr_key is None or not _passes_gate(s, p):
            continue
        if s.corr_key not in p.variables:
            continue
        if s.corr_key in by_key:
            raise ValueError(f"duplicate score for correlation variable {s.corr_key!r}")
        by_key[s.corr_key] = s

    active = [i for i, v in enumerate(p.variables) if v in by_key]
    findings: list[Finding] = []
    while len(active) >= p.min_variables:
        best: tuple[float, int, float, float] | None = None  # (|r|, idx, expected, sd)
        for t in active:
            given = [i for i in active if i != t]
            z_g = [by_key[p.variables[i]].z for i in given]
            mean, sd = conditional_moments(p.correlation, t, given, z_g)
            if sd <= 0:
                continue
            r = (by_key[p.variables[t]].z - mean) / sd
            if best is None or abs(r) > best[0]:  # eşitlikte ilk değişken (deterministik)
                best = (abs(r), t, mean, sd)
        if best is None:
            break
        abs_r, t, mean, sd = best
        severity = _severity(abs_r, p.severity_sd)
        if severity is None:
            break
        var = p.variables[t]
        target = by_key[var]
        others = [by_key[p.variables[i]] for i in active if i != t]
        below = target.z < mean
        direction = "below_expected" if below else "above_expected"
        findings.append(
            Finding(
                kind=KIND_RESIDUAL,
                rule_id=var,
                severity=severity,
                magnitude=abs_r,
                weak_group=var if below else "others",
                strong_group="others" if below else var,
                weak_exercise_ids=(target.exercise_id,) if below else _ids(others),
                strong_exercise_ids=_ids(others) if below else (target.exercise_id,),
                muscles=_muscles([target] if below else others),
                recommendation_key=f"{KIND_RESIDUAL}.{var}.{direction}",
                metrics={
                    "observed_z": target.z,
                    "expected_z": mean,
                    "residual_sd": sd,
                    "standardized_residual": (target.z - mean) / sd,
                },
            )
        )
        active.remove(t)
    return findings


def _ids(items: Iterable[ScoreInput | UnilateralInput]) -> tuple[str, ...]:
    return tuple(sorted(it.exercise_id for it in items))


# --------------------------------------------------------------------------------------------
# 2) Kural tabanlı oranlar
# --------------------------------------------------------------------------------------------


def combine_z(items: Sequence[ScoreInput], p: ImbalanceParams) -> float:
    """§8: ``Σ w z / sqrt(Σ w² + 2 Σ_{i<j} w_i w_j r)``; çiftler için ``r`` bilinmeyen çift değeri,
    iki hareket de matristeyse matristeki değer."""
    w = [p.confidence_weights[it.confidence] for it in items]
    num = sum(wi * it.z for wi, it in zip(w, items, strict=True))
    den = sum(wi * wi for wi in w)
    for i in range(len(items)):
        for j in range(i + 1, len(items)):
            den += 2 * w[i] * w[j] * _pair_corr(items[i], items[j], p)
    return num / math.sqrt(den)


def _pair_corr(a: ScoreInput, b: ScoreInput, p: ImbalanceParams) -> float:
    if a.corr_key in p.variables and b.corr_key in p.variables and a.corr_key != b.corr_key:
        return float(p.correlation[p.variables.index(a.corr_key), p.variables.index(b.corr_key)])
    return p.unknown_pair_correlation


def ratio_findings(scores: Sequence[ScoreInput], p: ImbalanceParams) -> list[Finding]:
    eligible = sorted((s for s in scores if _passes_gate(s, p)), key=lambda s: s.exercise_id)
    findings: list[Finding] = []
    for rule in p.ratio_rules:
        a = [s for s in eligible if s.pattern in rule.patterns_a]
        b = [s for s in eligible if s.pattern in rule.patterns_b]
        if min(len(a), len(b)) < rule.min_exercises_per_group:
            continue
        za, zb = combine_z(a, p), combine_z(b, p)
        gap = abs(za - zb)
        severity = _severity(gap, rule.severity_z_gap)
        if severity is None:
            continue
        a_weak = za < zb
        names = (rule.group_a, rule.group_b)
        weak_name, strong_name = names if a_weak else names[::-1]
        weak, strong = (a, b) if a_weak else (b, a)
        findings.append(
            Finding(
                kind=KIND_RATIO,
                rule_id=rule.id,
                severity=severity,
                magnitude=gap,
                weak_group=weak_name,
                strong_group=strong_name,
                weak_exercise_ids=_ids(weak),
                strong_exercise_ids=_ids(strong),
                muscles=_muscles(weak),
                recommendation_key=f"{KIND_RATIO}.{rule.id}.{weak_name}_behind",
                metrics={"weak_z": min(za, zb), "strong_z": max(za, zb), "z_gap": gap},
            )
        )
    return findings


# --------------------------------------------------------------------------------------------
# 3) Sol / sağ
# --------------------------------------------------------------------------------------------


def left_right_findings(pairs: Sequence[UnilateralInput], p: ImbalanceParams) -> list[Finding]:
    findings: list[Finding] = []
    for u in sorted(pairs, key=lambda x: x.exercise_id):
        if not _passes_gate(u, p) or u.left_kg == u.right_kg:
            continue
        strong, weak = max(u.left_kg, u.right_kg), min(u.left_kg, u.right_kg)
        asym = (strong - weak) / strong
        severity = _severity(asym, p.severity_asymmetry)
        if severity is None:
            continue
        weak_side = "left" if u.left_kg < u.right_kg else "right"
        strong_side = "right" if weak_side == "left" else "left"
        findings.append(
            Finding(
                kind=KIND_LEFT_RIGHT,
                rule_id=u.exercise_id,
                severity=severity,
                magnitude=asym,
                weak_group=weak_side,
                strong_group=strong_side,
                weak_exercise_ids=(u.exercise_id,),
                strong_exercise_ids=(u.exercise_id,),
                muscles=tuple(sorted(set(u.muscles))),
                recommendation_key=f"{KIND_LEFT_RIGHT}.{weak_side}_behind",
                metrics={"weak_kg": weak, "strong_kg": strong, "asymmetry": asym},
            )
        )
    return findings


# --------------------------------------------------------------------------------------------
# Giriş noktası
# --------------------------------------------------------------------------------------------

_KIND_ORDER = {KIND_RESIDUAL: 0, KIND_RATIO: 1, KIND_LEFT_RIGHT: 2}


def analyze(
    scores: Sequence[ScoreInput],
    params: ImbalanceParams,
    unilateral: Sequence[UnilateralInput] = (),
) -> list[Finding]:
    """Tüm bulgular; sıra: şiddet (ağırdan hafife), tür, kural kimliği."""
    findings = (
        residual_findings(scores, params)
        + ratio_findings(scores, params)
        + left_right_findings(unilateral, params)
    )
    rank = {s: i for i, s in enumerate(SEVERITIES)}
    return sorted(findings, key=lambda f: (-rank[f.severity], _KIND_ORDER[f.kind], f.rule_id))
