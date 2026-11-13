"""Çapa dosyası (ml/data/anchors.csv) okuma ve doğrulama (P055, docs/03-ML-MODEL.md §5.2).

İki tür satır vardır:
- **Mutlak çapa:** `bodyweight_kg` dolu. (yüzdelik, kg) çifti doğrudan yer-ölçek modeline girer.
- **Yaşa göreli çapa:** `bodyweight_kg` boş. Yalnızca aynı kaynak/cinsiyet/kaldırış/yüzdelikteki
  referans bant (20-39) satırlarına oranı kullanılır; vücut ağırlığı bilinmeyen yaş tabloları ve el
  kavrama gücü (lift = grip) bu türdendir. `age_band = all` (yaş ayrımı olmayan tablolar) referans
  bant 20-39 kabul edilir.
"""

from __future__ import annotations

import csv
from dataclasses import dataclass, replace
from datetime import date
from pathlib import Path

from gymml.calibration.reference import AGE_BANDS, LIFTS, REF_BAND, SEXES

COLUMNS = ["population", "sex", "lift", "age_band", "bodyweight_kg", "percentile", "value_kg",
           "source_url", "accessed", "reliability", "note"]
POPULATIONS = ("gym", "general")
ANCHOR_LIFTS = (*LIFTS, "grip")


@dataclass(frozen=True)
class Anchor:
    population: str
    sex: str
    lift: str
    age_band: str          # "all" normalleştirilmiş: REF_BAND
    bodyweight_kg: float | None
    percentile: float      # 0–100
    value_kg: float
    source_url: str
    accessed: date
    reliability: int
    note: str

    @property
    def relative(self) -> bool:
        return self.bodyweight_kg is None

    @property
    def source(self) -> str:
        return self.source_url


class AnchorError(ValueError):
    pass


def parse_row(row: dict[str, str], line: int) -> Anchor:
    def bad(msg: str) -> AnchorError:
        return AnchorError(f"anchors.csv satır {line}: {msg}")

    pop, sex, lift = row["population"], row["sex"], row["lift"]
    if pop not in POPULATIONS:
        raise bad(f"population {pop!r}")
    if sex not in SEXES:
        raise bad(f"sex {sex!r}")
    if lift not in ANCHOR_LIFTS:
        raise bad(f"lift {lift!r}")
    band = row["age_band"]
    if band == "all":
        band = REF_BAND
    if band not in AGE_BANDS:
        raise bad(f"age_band {row['age_band']!r}")
    url = row["source_url"].strip()
    if not url.startswith("https://"):
        raise bad("source_url zorunlu (https)")
    try:
        accessed = date.fromisoformat(row["accessed"])
    except ValueError as e:
        raise bad("accessed YYYY-MM-DD olmalı") from e
    rel = int(row["reliability"])
    if rel not in (1, 2, 3):
        raise bad("reliability 1–3")
    p = float(row["percentile"])
    if not 0 < p < 100:
        raise bad("percentile (0, 100) aralığında olmalı")
    v = float(row["value_kg"])
    if v <= 0:
        raise bad("value_kg > 0")
    bw_raw = row["bodyweight_kg"].strip()
    bw = float(bw_raw) if bw_raw else None
    if lift == "grip" and bw is not None:
        raise bad("grip yalnızca yaşa göreli çapa olabilir (bodyweight_kg boş)")
    if bw is not None and not 30 <= bw <= 200:
        raise bad("bodyweight_kg 30–200")
    return Anchor(pop, sex, lift, band, bw, p, v, url, accessed, rel, row["note"])


def load_anchors(path: Path) -> list[Anchor]:
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        if reader.fieldnames != COLUMNS:
            raise AnchorError(f"anchors.csv sütunları {COLUMNS} olmalı, bulunan "
                              f"{reader.fieldnames}")
        anchors = [parse_row(r, i) for i, r in enumerate(reader, start=2)]
    validate_relative_groups(anchors)
    return anchors


def relative_key(a: Anchor) -> tuple[str, str, str, str, float]:
    return (a.source, a.population, a.sex, a.lift, a.percentile)


def validate_relative_groups(anchors: list[Anchor]) -> None:
    """Her göreli çapa grubunda en az bir referans bant satırı olmalı."""
    groups: dict[tuple, list[Anchor]] = {}
    for a in anchors:
        if a.relative:
            groups.setdefault(relative_key(a), []).append(a)
    for key, rows in groups.items():
        if not any(r.age_band == REF_BAND for r in rows):
            raise AnchorError(f"göreli çapa grubunda {REF_BAND} satırı yok: {key}")


def scale_source_bodyweight(anchors: list[Anchor], url: str, delta_kg: float) -> list[Anchor]:
    """Duyarlılık için: oran tablosundan varsayılan vücut ağırlığıyla türetilmiş satırları kaydırır
    (değer = oran × VA olduğundan değer de orantılı değişir)."""
    out = []
    for a in anchors:
        if a.source_url == url and a.bodyweight_kg is not None:
            bw = a.bodyweight_kg + delta_kg
            a = replace(a, bodyweight_kg=bw, value_kg=a.value_kg * bw / a.bodyweight_kg)
        out.append(a)
    return out
