"""catalog-taxonomy: exercises.base.json -> scoring_taxonomy.yaml + docs/CEKIRDEK-HAREKETLER.md (P025)."""
from __future__ import annotations

import argparse
import collections
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

from . import ratios as rt
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


ANCHOR_TR = {"squat": "squat", "bench": "bench", "deadlift": "deadlift"}


def _fmt(x: float | None, nd: int = 2) -> str:
    return "—" if x is None else f"{x:.{nd}f}".rstrip("0").rstrip(".") if nd else f"{x:.0f}"


def render_doc(doc: dict[str, Any], ratios: dict[str, Any] | None = None) -> str:
    ratios = ratios or {"sources": {}, "tau": {}, "consistency": {}}
    entries = doc["exercises"]
    core = [e for e in entries if e["is_core"]]
    unsure = [e for e in core if e["needs_review"]]
    by_pat = collections.Counter(e["movement_pattern"] for e in core)
    scored = [e for e in core if e["anchor"] is not None]
    grades = collections.Counter(e["ratio_confidence"] for e in scored)
    loads = rt.implied_table(doc)
    tau = ratios["tau"]
    lines = [
        "# Çekirdek hareketler (P025, oranlar P056)",
        "",
        "Güç Skoru'nun ilk sürümde hedeflediği ~150 hareket ve her birinin çapa oranı. Bu liste **onayını bekliyor**:",
        "kalıp/tür/yük kuralı değişiklikleri `tools/catalog/taxonomy_overrides.yaml`, oran/kaynak/güven değişiklikleri",
        "`tools/catalog/ratios.yaml` içine yazılır; ardından `cd tools/catalog && uv run catalog-taxonomy` bu dosyayı ve",
        "`scoring_taxonomy.yaml`'ı yeniden üretir, `uv run catalog-build` kataloğu.",
        "",
        f"- Çekirdek hareket sayısı: **{len(core)}** (katalogda toplam {len(entries)})",
        f"- Çapa oranı olan (skorlanan) çekirdek hareket: **{len(scored)}** — güven A: {grades.get('A', 0)}, "
        f"B: {grades.get('B', 0)}, C: {grades.get('C', 0)}",
        f"- Kuralla atanıp **belirsiz** işaretlenen çekirdek satır: **{len(unsure)}** (aşağıda ⚠ ile)",
        "- Tür: `weighted` = ağırlıklı, `bodyweight_loaded` = vücut ağırlığı + ek yük, `reps_only` = yalnızca tekrar",
        "  (`ml/data/rep_norms.csv`), `time` = süre, `none` = skorlanmaz. Çekirdek dışı hareketler skor üretmez.",
        "",
        "## Oranlar nasıl okunur",
        "",
        "- **ρ (oran):** kullanıcının bu harekette *yazdığı* sayının 1RM'i ≈ ρ × çapa hareketin 1RM'i. Yazılan sayı yük",
        "  kuralına göredir: `el başına` = tek dambıl, `taraf başına` = makinenin bir tarafındaki plakalar (kızak",
        "  eklenmez), `toplam` = bar dahil (Smith makinesinde Smith barı dahil), `vücut ağırlığı + ek yük` = efektif",
        "  yük `bw × vücut ağırlığı + ek yük`.",
        f"- **τ:** oranın kişiden kişiye log ölçekte yayılımı. Çapanın kendisi {tau.get('anchor')}, A {tau.get('A')}, "
        f"B {tau.get('B')}, C {tau.get('C')}, makine/kablo {tau.get('machine')} (satır özel değer verebilir).",
        "  Ölçek: OpenPowerlifting'te log(bench/squat) kişiler arası SS ≈ 0,15.",
        "- **Güven:** A = birden çok uyumlu birincil kaynak, B = tek birincil kaynak ya da A/B kaynakların çarpımı,",
        "  C = uzman tahmini. Makine ve kablo hareketleri en fazla C alır.",
        "- **C sınıfı uç skor veremez:** `s_max = "
        f"{ratios['consistency'].get('s_max')}` iken |z| = {ratios['consistency'].get('z_extreme')} bile "
        f"{ratios['consistency'].get('score_bounds')} aralığında kalır (test: `tests/test_ratios.py`).",
        "- **Ört. E / Ört. K:** örnek ortalama sporcu için ima edilen 1RM, yazılan birimde (kg). " + "; ".join(
            f"{p.label}: squat {p.squat:.0f}, bench {p.bench:.0f}, deadlift {p.deadlift:.0f}" for p in rt.PROFILES)
        + ". Vücut ağırlığı hareketlerinde ek yük (eksi = yardım gerekir).",
        "",
        "## Kalıba göre dağılım",
        "",
        "| Kalıp | Adet |",
        "|---|---|",
    ]
    for pat, n in sorted(by_pat.items(), key=lambda kv: (-kv[1], kv[0])):
        lines.append(f"| {PATTERN_TR[pat]} (`{pat}`) | {n} |")
    lines += ["", "## Çekirdek liste", "",
              "| # | Ad | Kalıp | Tür | Yük kuralı | Tek taraflı | Çapa | ρ | τ | Güven | bw | Ört. E | Ört. K "
              "| Kaynak | Not |",
              "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    order = {e["id"]: i for i, e in enumerate(core)}
    for e in sorted(core, key=lambda x: (x["movement_pattern"], order[x["id"]])):
        notes = []
        if e["needs_review"]:
            notes.append("⚠ " + "; ".join(e["review_notes"]))
        if e.get("ratio_note"):
            notes.append(e["ratio_note"])
        imp = loads.get(e["id"])
        lines.append(
            f"| {order[e['id']] + 1} | {e['name']} | {PATTERN_TR[e['movement_pattern']]} | {e['scoring_type']} | "
            f"{LOAD_TR[e['load_convention']]} | {'evet' if e['is_unilateral'] else 'hayır'} | "
            f"{ANCHOR_TR.get(e['anchor'], '—')} | {_fmt(e['ratio'], 3)} | {_fmt(e['tau'])} | "
            f"{e['ratio_confidence'] or '—'} | {_fmt(e['bw_fraction'])} | "
            f"{_fmt(imp[0]['logged'], 0) if imp else '—'} | {_fmt(imp[1]['logged'], 0) if imp else '—'} | "
            f"{(e.get('ratio_source') or '—').replace('; ', ', ')} | {' '.join(notes)} |")
    other_unsure = sum(1 for e in entries if e["needs_review"] and not e["is_core"])
    lines += ["", "## Kaynaklar", ""]
    for key, src in ratios["sources"].items():
        url = f" <{src['url']}>" if src.get("url") else ""
        acc = f" (erişim {src['accessed']})" if src.get("accessed") else ""
        lines.append(f"- `{key}` — {' '.join(src['cite'].split())}{url}{acc}")
    lines += ["", "## Çekirdek dışı", "",
              f"Çekirdek dışı {other_unsure} hareket kural tabanlı atandı ve `scoring_taxonomy.yaml` içinde "
              "`needs_review: true` ile işaretli; bunlar kaydedilir ama ilk sürümde yüzdelik skor üretmez.", ""]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--base", type=Path, default=ROOT / "out" / "exercises.base.json")
    ap.add_argument("--overrides", type=Path, default=ROOT / "taxonomy_overrides.yaml")
    ap.add_argument("--ratios", type=Path, default=tb.RATIOS_PATH)
    ap.add_argument("--out", type=Path, default=ROOT / "scoring_taxonomy.yaml")
    ap.add_argument("--doc", type=Path, default=DOC_PATH)
    a = ap.parse_args(argv)

    raw = a.base.read_bytes()
    exercises = json.loads(raw)
    ratios = tb.load_ratios(a.ratios)
    doc = tb.build(exercises, tb.load_overrides(a.overrides), hashlib.sha256(raw).hexdigest(), ratios)
    errors = tb.validate(doc, exercises) + rt.consistency_violations(doc) + rt.extreme_score_violations(
        doc, ratios["consistency"])
    if errors:
        print(f"{len(errors)} taxonomy errors:", *errors[:20], sep="\n  ", file=sys.stderr)
        return 1
    a.out.write_text(tb.render(doc), encoding="utf-8")
    a.doc.write_text(render_doc(doc, ratios), encoding="utf-8")
    n_core = sum(e["is_core"] for e in doc["exercises"])
    n_rev = sum(e["needs_review"] for e in doc["exercises"])
    print(f"{len(doc['exercises'])} exercises, {n_core} core, {n_rev} flagged for review -> {a.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
