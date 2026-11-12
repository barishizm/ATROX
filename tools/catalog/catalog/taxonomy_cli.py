"""catalog-taxonomy: exercises.base.json -> scoring_taxonomy.yaml + docs/CEKIRDEK-HAREKETLER.md (P025)."""
from __future__ import annotations

import argparse
import collections
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

from . import taxonomy_build as tb

ROOT = tb.ROOT
DOC_PATH = ROOT.parent.parent / "docs" / "CEKIRDEK-HAREKETLER.md"

PATTERN_TR = {
    "horizontal_push": "yatay itiş", "vertical_push": "dikey itiş", "horizontal_pull": "yatay çekiş",
    "vertical_pull": "dikey çekiş", "squat": "squat", "hip_hinge": "kalça menteşesi", "core": "gövde",
    "isolation_biceps": "izolasyon-biceps", "isolation_triceps": "izolasyon-triceps",
    "isolation_forearms": "izolasyon-önkol", "isolation_shoulders": "izolasyon-omuz",
    "isolation_chest": "izolasyon-göğüs", "isolation_back": "izolasyon-sırt/trapez",
    "isolation_quads": "izolasyon-ön bacak", "isolation_hamstrings": "izolasyon-arka bacak",
    "isolation_glutes": "izolasyon-kalça", "isolation_calves": "izolasyon-baldır",
    "isolation_hips": "izolasyon-kalça yanı/iç", "isolation_neck": "izolasyon-boyun",
    "olympic": "olimpik kaldırış", "carry": "taşıma", "plyometric": "pliometrik", "cardio": "kardiyo",
    "mobility": "esneme/mobilite", "other": "diğer",
}
LOAD_TR = {
    "total": "toplam (bar dahil)", "per_hand": "el başına", "per_side": "taraf başına (plaka)",
    "machine_stack": "makine/kablo ağırlığı", "bodyweight_plus": "vücut ağırlığı + ek yük", None: "—",
}


def render_doc(doc: dict[str, Any]) -> str:
    entries = doc["exercises"]
    core = [e for e in entries if e["is_core"]]
    unsure = [e for e in core if e["needs_review"]]
    by_pat = collections.Counter(e["movement_pattern"] for e in core)
    lines = [
        "# Çekirdek hareketler (P025)",
        "",
        "Güç Skoru'nun ilk sürümde hedeflediği ~150 hareket. Bu liste **onayını bekliyor**: satırları gözden geçir,",
        "değişiklikleri `tools/catalog/taxonomy_overrides.yaml` içine yaz (`core` listesi ve `overrides`), ardından",
        "`cd tools/catalog && uv run catalog-taxonomy` ile bu dosyayı ve `scoring_taxonomy.yaml`'ı yeniden üret.",
        "",
        f"- Çekirdek hareket sayısı: **{len(core)}** (katalogda toplam {len(entries)})",
        f"- Kuralla atanıp **belirsiz** işaretlenen çekirdek satır: **{len(unsure)}** (aşağıda ⚠ ile)",
        "- `anchor`, `ratio`, `tau`, `bw_fraction` bilerek boş; P056'da doldurulacak.",
        "- Tür: `weighted` = ağırlıklı, `bodyweight_loaded` = vücut ağırlığı + ek yük, `reps_only` = yalnızca tekrar,",
        "  `time` = süre, `none` = skorlanmaz.",
        "",
        "## Kalıba göre dağılım",
        "",
        "| Kalıp | Adet |",
        "|---|---|",
    ]
    for pat, n in sorted(by_pat.items(), key=lambda kv: (-kv[1], kv[0])):
        lines.append(f"| {PATTERN_TR[pat]} (`{pat}`) | {n} |")
    lines += ["", "## Çekirdek liste", "",
              "| # | Ad | Kalıp | Tür | Yük kuralı | Tek taraflı | Not |", "|---|---|---|---|---|---|---|"]
    order = {e["id"]: i for i, e in enumerate(core)}
    for e in sorted(core, key=lambda x: (x["movement_pattern"], order[x["id"]])):
        note = ("⚠ " + "; ".join(e["review_notes"])) if e["needs_review"] else ""
        lines.append(
            f"| {order[e['id']] + 1} | {e['name']} | {PATTERN_TR[e['movement_pattern']]} | {e['scoring_type']} | "
            f"{LOAD_TR[e['load_convention']]} | {'evet' if e['is_unilateral'] else 'hayır'} | {note} |")
    other_unsure = sum(1 for e in entries if e["needs_review"] and not e["is_core"])
    lines += ["", "## Çekirdek dışı", "",
              f"Çekirdek dışı {other_unsure} hareket kural tabanlı atandı ve `scoring_taxonomy.yaml` içinde "
              "`needs_review: true` ile işaretli; bunlar kaydedilir ama ilk sürümde yüzdelik skor üretmez.", ""]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--base", type=Path, default=ROOT / "out" / "exercises.base.json")
    ap.add_argument("--overrides", type=Path, default=ROOT / "taxonomy_overrides.yaml")
    ap.add_argument("--out", type=Path, default=ROOT / "scoring_taxonomy.yaml")
    ap.add_argument("--doc", type=Path, default=DOC_PATH)
    a = ap.parse_args(argv)

    raw = a.base.read_bytes()
    exercises = json.loads(raw)
    doc = tb.build(exercises, tb.load_overrides(a.overrides), hashlib.sha256(raw).hexdigest())
    errors = tb.validate(doc, exercises)
    if errors:
        print(f"{len(errors)} taxonomy errors:", *errors[:20], sep="\n  ", file=sys.stderr)
        return 1
    a.out.write_text(tb.render(doc), encoding="utf-8")
    a.doc.write_text(render_doc(doc), encoding="utf-8")
    n_core = sum(e["is_core"] for e in doc["exercises"])
    n_rev = sum(e["needs_review"] for e in doc["exercises"])
    print(f"{len(doc['exercises'])} exercises, {n_core} core, {n_rev} flagged for review -> {a.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
