"""P057 yardımcıları: katalog yükleme, A modelinden çapa korelasyonu, örnek profil raporu.

python -m gymml.scoring_run corr       # params_draft/scoring.json → anchor_correlation
python -m gymml.scoring_run profiles   # reports/scoring_profiles.md
"""
# ruff: noqa: E501

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from datetime import date, timedelta
from pathlib import Path

import numpy as np
import polars as pl
import yaml
from scipy.stats import norm

from gymml.scoring import (
    LIFTS,
    ML_ROOT,
    PARAMS_DIR,
    AnchorModel,
    Exercise,
    LoggedSet,
    Params,
    User,
    current_strength,
    exercise_score,
    muscle_group_scores,
    overall_score,
)

REPO = ML_ROOT.parent
TAXONOMY = REPO / "tools/catalog/scoring_taxonomy.yaml"
BASE = REPO / "tools/catalog/out/exercises.base.json"


def load_catalog(taxonomy: Path = TAXONOMY, base: Path = BASE) -> dict[str, Exercise]:
    tax = yaml.safe_load(taxonomy.read_text(encoding="utf-8"))["exercises"]
    meta = {e["id"]: e for e in json.loads(base.read_text(encoding="utf-8"))}
    out = {}
    for t in tax:
        m = meta.get(t["id"], {})
        out[t["id"]] = Exercise(
            id=t["id"], movement_pattern=t.get("movement_pattern"), scoring_type=t["scoring_type"],
            load_convention=t.get("load_convention"), anchor=t.get("anchor"), ratio=t.get("ratio"),
            tau=t.get("tau"), ratio_confidence=t.get("ratio_confidence"), bw_fraction=t.get("bw_fraction"),
            ratio_source=t.get("ratio_source"),
            primary_muscles=tuple(m.get("primary_muscles", ())),
            secondary_muscles=tuple(m.get("secondary_muscles", ())), equipment=m.get("equipment"),
        )  # fmt: skip
    return out


def anchor_correlation(model: AnchorModel) -> dict:
    """SBD üçlüsü tam kayıtlarda (train) A modelinin z-skorlarının ağırlıklı korelasyonu (§4.4)."""
    from gymml.models.neural import load_sbd

    df = load_sbd("train")
    zs = []
    clip = model.clip
    for lift in LIFTS:
        f = model.models[lift].cdf(df, df[f"{lift}_kg"].to_numpy())
        zs.append(norm.ppf(np.clip(f, *clip)))
    z = np.vstack(zs)
    w = df["weight"].to_numpy() / df["weight"].sum()
    mu = (z * w).sum(axis=1, keepdims=True)
    c = ((z - mu) * w) @ (z - mu).T
    d = np.sqrt(np.diag(c))
    r = c / np.outer(d, d)
    return {
        "variables": list(LIFTS),
        "matrix": np.round(r, 4).tolist(),
        "source": f"P057: weighted Pearson correlation of Phi^-1(F_A(y|x)) on cohort_sbd train "
                  f"(Tested, no wraps), n={df.height}",
    }  # fmt: skip


def write_corr() -> dict:
    p = Params.load()
    corr = anchor_correlation(AnchorModel.load(p))
    path = PARAMS_DIR / "scoring.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    data["anchor_correlation"] = corr
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return corr


# ----------------------------------------------------------------------------------------------
# Örnek profiller
# ----------------------------------------------------------------------------------------------


@dataclass(frozen=True)
class Profile:
    label: str
    user: User
    lifts: dict[str, tuple[float, int]]  # id → (ağırlık, tekrar); reps_only için (0, tekrar)


AS_OF = date(2026, 11, 13)
EX_ORDER = ["barbell-full-squat", "barbell-bench-press-medium-grip", "barbell-deadlift",
            "standing-military-press", "bent-over-barbell-row", "pullups", "dumbbell-bench-press",
            "barbell-curl", "leg-press", "pushups"]  # fmt: skip


def _p(label, sex, age, bw, vals) -> Profile:
    return Profile(label, User(sex, age, bw), dict(zip(EX_ORDER, vals, strict=True)))


PROFILES = [
    _p(
        "Erkek yeni başlayan",
        "M",
        30,
        80,
        [(60, 5), (50, 5), (80, 5), (30, 5), (40, 8), (0, 3), (18, 8), (25, 8), (40, 10), (0, 15)],
    ),
    _p(
        "Erkek orta",
        "M",
        30,
        80,
        [
            (120, 5),
            (90, 5),
            (150, 5),
            (55, 5),
            (75, 8),
            (10, 6),
            (32, 8),
            (40, 8),
            (100, 10),
            (0, 35),
        ],
    ),
    _p(
        "Erkek ileri",
        "M",
        30,
        85,
        [
            (180, 3),
            (130, 3),
            (220, 3),
            (80, 3),
            (100, 6),
            (30, 5),
            (45, 8),
            (55, 6),
            (160, 8),
            (0, 55),
        ],
    ),
    _p(
        "Kadın yeni başlayan",
        "F",
        30,
        62,
        [(35, 5), (25, 5), (50, 5), (17.5, 5), (25, 8), (0, 1), (8, 8), (12, 8), (30, 10), (0, 5)],
    ),
    _p(
        "Kadın orta",
        "F",
        30,
        62,
        [(70, 5), (45, 5), (95, 5), (30, 5), (40, 8), (0, 3), (16, 8), (20, 8), (60, 10), (0, 18)],
    ),
    _p(
        "Kadın ileri",
        "F",
        30,
        62,
        [
            (115, 3),
            (70, 3),
            (145, 3),
            (45, 3),
            (60, 6),
            (10, 5),
            (25, 8),
            (30, 6),
            (100, 8),
            (0, 35),
        ],
    ),
    _p(
        "Cinsiyet belirtilmemiş orta",
        None,
        30,
        72,
        [
            (95, 5),
            (65, 5),
            (120, 5),
            (42.5, 5),
            (55, 8),
            (0, 5),
            (22, 8),
            (30, 8),
            (80, 10),
            (0, 25),
        ],
    ),
]


def score_profile(prof: Profile, catalog, model, p, population: str = "gym"):
    scores = []
    for ex_id, (w, reps) in prof.lifts.items():
        ex = catalog[ex_id]
        if ex.scoring_type == "reps_only":
            # Norm tablosu cinsiyetsiz değildir; belirtilmemişse karışım exercise_score içinde.
            s = exercise_score(ex, None, prof.user, model, p, population, reps=reps)  # type: ignore[arg-type]
        else:
            sets = [LoggedSet(AS_OF - timedelta(days=d), w, reps, rir=1) for d in (3, 10)]
            cs = current_strength(ex, sets, prof.user, AS_OF, p)
            s = exercise_score(ex, cs, prof.user, model, p, population)
        if s is not None:
            scores.append(s)
    return scores


def write_profiles(path: Path = ML_ROOT / "reports/scoring_profiles.md") -> Path:
    p = Params.load()
    catalog = load_catalog()
    model = AnchorModel.load(p)
    lines = [
        "# Örnek profil skorları (P057)",
        "",
        "Üretim: `python -m gymml.scoring_run profiles`. Her hareket için 2 oturum (3 ve 10 gün önce), aynı set, RIR 1.",
        "Referans grubu: salon (varsayılan); çapa hareketlerde yarışmacı referansı da verilir. Skor 1–99, bant = ±1",
        "belirsizlik (kalibrasyon bandı ⊕ oran τ). Seviye anahtarları uygulamada yerelleştirilir.",
        "",
    ]
    for prof in PROFILES:
        u = prof.user
        lines += [
            f"## {prof.label} (cinsiyet {u.sex or '—'}, {u.age:g} yaş, {u.bodyweight_kg:g} kg)",
            "",
        ]
        gym = score_profile(prof, catalog, model, p, "gym")
        comp = {s.exercise_id: s for s in score_profile(prof, catalog, model, p, "competitor")}
        lines += [
            "| hareket | set | salon skoru | bant | güven | seviye | yarışmacı skoru |",
            "|---|---|---|---|---|---|---|",
        ]
        for s in gym:
            w, r = prof.lifts[s.exercise_id]
            setx = (
                f"{r} tekrar"
                if catalog[s.exercise_id].scoring_type == "reps_only"
                else f"{w:g} kg × {r}"
            )
            c = comp.get(s.exercise_id)
            lines.append(
                f"| {s.exercise_id} | {setx} | {s.score:.0f} | {s.band[0]:.0f}–{s.band[1]:.0f} | "
                f"{s.confidence} | {s.level} | {c.score:.0f} |"
                if c
                else f"| {s.exercise_id} | {setx} | {s.score:.0f} | {s.band[0]:.0f}–{s.band[1]:.0f} | {s.confidence} | {s.level} | — |"
            )
        groups = muscle_group_scores(gym, catalog, p)
        ov = overall_score(gym, catalog, p)
        sel = ["chest", "quadriceps", "hamstrings", "lats", "shoulders", "biceps", "triceps"]
        lines += [
            "",
            "Kas grupları: " + ", ".join(f"{m} {groups[m].score:.0f}" for m in sel if m in groups),
        ]
        if ov:
            lines += [
                "",
                f"**Genel Güç Skoru: {ov.score:.0f}** ({ov.level}{', geçici' if ov.provisional else ''}; "
                f"kalıplar: {', '.join(ov.patterns)})",
                "",
            ]
    lines += [
        "## Notlar",
        "",
        "- Birleştirme §8 formülüyle: korelasyon 1'den küçükken eşit skorların birleşimi aynı yönde daha uçtur",
        "  (r = 0.6 iken iki 60 → ≈ 61; 50 her zaman 50). Bu yüzden kas grubu/genel skor tek tek hareket",
        "  skorlarının ortalamasından biraz daha uçta çıkar. Prompt'taki \"eşit iki skorun birleşimi aynı skor\"",
        "  özelliği yalnızca r = 1'de birebir sağlanır; gösterim kararı kullanıcıda.",
        "- C sınıfı oranlar yarışmacı ölçeğinde (s ≈ 0.2) uç skoru engeller; salon referansında yayılım κ ≈ 1.95 kat",
        "  geniş olduğundan τ = 0.4 büzülmesi zayıflar ve C sınıfı bir hareket 95'i aşabilir (ör. çok ağır askeri pres).",
        "  P056'nın `tau_c_min` hesabı yarışmacı yayılımına göre yapılmıştı; salon için gözden geçirilmeli.",
        "- `reps_only` (şınav) normları en fazla 80. yüzdeliğe kadar tablolu; bant 1–99 (düşük güven).",
        "",
    ]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return path


def main() -> None:
    ap = argparse.ArgumentParser(prog="gymml.scoring_run")
    ap.add_argument("step", choices=["corr", "profiles"])
    a = ap.parse_args()
    if a.step == "corr":
        print(json.dumps(write_corr(), indent=2))
    else:
        print(write_profiles())


if __name__ == "__main__":
    main()


__all__ = ["load_catalog", "anchor_correlation", "PROFILES", "pl"]
