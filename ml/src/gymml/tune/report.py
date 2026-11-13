"""P053 raporu: `reports/bakeoff.md` §3 ve sonrası (§1–2 ön kayıt, dokunulmaz)."""
# ruff: noqa: E501

from __future__ import annotations

import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402

from gymml.data.cohort import AGE_BAND_EDGES, LIFTS, ML_ROOT, band_labels  # noqa: E402
from gymml.eval.metrics import class_band_labels  # noqa: E402

OUT = ML_ROOT / "reports/bakeoff"
REPORT = ML_ROOT / "reports/bakeoff.md"
MARK = "## 3. Arama sonuçları"
NAMES = {"A": "A · Spline-LMS", "B": "B · LightGBM", "C": "C · Sinirsel"}
SIMPLICITY = {"A": 0, "C": 1, "B": 2}
SIZE_LIMIT = 1_000_000
LATENCY_LIMIT = 1.0
VDH_TOL = 3.0
TIE = 0.01


def _load(name: str):
    p = OUT / name
    return json.loads(p.read_text()) if p.exists() else None


def _md(rows: list[dict]) -> str:
    if not rows:
        return "_(veri yok)_"
    cols = list(rows[0])
    out = ["| " + " | ".join(cols) + " |", "|" + "---|" * len(cols)]
    for r in rows:
        cells = []
        for c in cols:
            v = r[c]
            if isinstance(v, bool):
                cells.append("✅" if v else "❌")
            elif isinstance(v, float):
                cells.append(f"{v:.4g}")
            else:
                cells.append(str(v))
        out.append("| " + " | ".join(cells) + " |")
    return "\n".join(out)


def _ms(xs) -> str:
    xs = np.asarray(xs, float)
    return f"{xs.mean():.3f} ± {xs.std(ddof=1) if len(xs) > 1 else 0:.3f}"


def search_section(keys) -> str:
    parts = []
    for k in keys:
        s = _load(f"search_{k}.json")
        if not s:
            parts.append(f"### {NAMES[k]}\n\n_(arama bitmedi)_")
            continue
        rows = [
            {"deneme": t["number"], "pinball_ort": t["pinball_mean"], "kapı": t["gate"],
             "boyut_KB": t["size_bytes"] / 1024, "budandı": t["pruned"], "süre_dk": t["seconds"] / 60,
             "yapılandırma": json.dumps(t["config"], ensure_ascii=False)}
            for t in s["trials"]
        ]  # fmt: skip
        note = " **Bütün denemeler budandı**; en düşük pinball'lu deneme kullanıldı." if s.get("all_pruned") else ""
        best = s.get("best", {})
        parts.append(
            f"### {NAMES[k]}\n\n{_md(rows)}\n\nSeçilen: deneme {best.get('number')} "
            f"`{json.dumps(best.get('config'), ensure_ascii=False)}`.{note}"
        )
    return "\n\n".join(parts)


def _split_rows(final: dict, split: str) -> list[dict]:
    rows = []
    seeds = sorted(final.get(split, {}))
    for lift in LIFTS:
        vals = [final[split][s]["lifts"][lift]["metrics"] for s in seeds if lift in final[split][s]["lifts"]]
        if not vals:
            continue
        rows.append({
            "lift": lift, "tohum": len(vals),
            "pinball_kg": _ms([v["pinball"] for v in vals]),
            "crps_kg": _ms([v["crps"] for v in vals]),
            "pit_ks": _ms([v["pit_ks"] for v in vals]),
            "bant_dışı_oran": _ms([v["strata_outside_share"] for v in vals]),
            "kapı_geçen_tohum": f"{sum(v['coverage_gate_pass'] for v in vals)}/{len(vals)}",
        })  # fmt: skip
    return rows


def _pinball_mean(final: dict, split: str) -> float:
    return float(np.mean([
        final[split][s]["lifts"][lift]["metrics"]["pinball"]
        for s in final[split] for lift in final[split][s]["lifts"]
    ]))  # fmt: skip


def _gate_all(final: dict, split: str) -> bool:
    return all(
        final[split][s]["lifts"][lift]["metrics"]["coverage_gate_pass"]
        for s in final[split] for lift in final[split][s]["lifts"]
    )  # fmt: skip


def _sanity(final: dict) -> dict[str, list[dict]]:
    seed = sorted(final["val"])[0]
    return {lift: final["val"][seed]["lifts"][lift]["sanity"] for lift in final["val"][seed]["lifts"]}


def _vdh_rows(lifts_block: dict, label: str) -> list[dict]:
    rows = []
    for lift, r in lifts_block.items():
        for e in r["external"]:
            if e["age_group"] != "18-35":
                continue
            rows.append({"sürüm": label, "lift": lift, "sex": e["sex"], "vdh": e["vdh"],
                         "model": e["model_oran"], "fark_%": e["fark_%"],
                         "geçti": abs(e["fark_%"]) <= VDH_TOL})  # fmt: skip
    return rows


def heatmap(k: str, final: dict, path: Path) -> None:
    strata = final.get("test_strata")
    if not strata:
        return
    ages = band_labels(AGE_BAND_EDGES)
    fig, axes = plt.subplots(2, 3, figsize=(16, 8))
    for i, sex in enumerate(("M", "F")):
        bws = class_band_labels(sex)
        for j, lift in enumerate(LIFTS):
            m = np.full((len(ages), len(bws)), np.nan)
            for r in strata.get(lift, []):
                if r["sex"] == sex:
                    m[ages.index(r["age_band"]), bws.index(r["bodyweight_kg_band"])] = r["max_dev_pp"] / max(2.0, r["noise_pp"])
            ax = axes[i, j]
            im = ax.imshow(m, cmap="RdYlGn_r", vmin=0, vmax=2, aspect="auto")
            for a in range(len(ages)):
                for b in range(len(bws)):
                    if not np.isnan(m[a, b]):
                        ax.text(b, a, f"{m[a, b]:.1f}", ha="center", va="center", fontsize=6)
            ax.set_xticks(range(len(bws)), bws, rotation=60, fontsize=7)
            ax.set_yticks(range(len(ages)), ages, fontsize=7)
            ax.set_title(f"{NAMES[k]} · {sex} · {lift}")
    fig.colorbar(im, ax=axes, shrink=0.6, label="sapma / izin verilen (>1 = bant dışı)")
    fig.savefig(path, dpi=100, bbox_inches="tight")
    plt.close(fig)


def decide(finals: dict, sens: dict) -> tuple[str, list[dict]]:
    rows = []
    for k, f in finals.items():
        if not f or not f.get("test"):
            continue
        seed = sorted(f["val"])[0]
        sanity_ok = all(t["passed"] for lst in _sanity(f).values() for t in lst)
        unw = (sens.get(k) or {}).get("variants", {}).get("ağırlıksız")
        vdh = _vdh_rows(unw, "ağırlıksız") if unw else []
        vdh_ok = bool(vdh) and all(r["geçti"] for r in vdh)
        size = f["val"][seed]["size_bytes"]
        lat = f["val"][seed]["latency_ms"]
        gate = _gate_all(f, "test")
        sanity_only = all(
            t["passed"] for lst in _sanity(f).values() for t in lst if not t["name"].startswith("van")
        )
        rows.append({
            "aday": NAMES[k], "key": k, "test_pinball": _pinball_mean(f, "test"),
            "kalibrasyon_kapısı": gate, "akıl_sağlığı": sanity_ok and sanity_only, "vdH_±3%": vdh_ok,
            "boyut<1MB": size < SIZE_LIMIT, "çıkarım<1ms": lat < LATENCY_LIMIT,
        })  # fmt: skip
    for r in rows:
        r["uygun"] = all(r[c] for c in ("kalibrasyon_kapısı", "akıl_sağlığı", "vdH_±3%", "boyut<1MB", "çıkarım<1ms"))
    eligible = [r for r in rows if r["uygun"]]
    if not eligible:
        return "", rows
    best = min(eligible, key=lambda r: r["test_pinball"])
    ties = [r for r in eligible if r["test_pinball"] <= best["test_pinball"] * (1 + TIE)]
    winner = min(ties, key=lambda r: SIMPLICITY[r["key"]])
    return winner["key"], rows


def write_report() -> Path:
    keys = ("A", "B", "C")
    finals = {k: _load(f"final_{k}.json") for k in keys}
    sens = {k: _load(f"sens_{k}.json") for k in keys}
    head = REPORT.read_text().split(MARK)[0].rstrip()

    val_parts, test_parts, sanity_parts, deploy_rows, vdh_rows, sens_rows = [], [], [], [], [], []
    for k in keys:
        f = finals[k]
        if not f:
            continue
        val_parts.append(f"### {NAMES[k]}\n\n{_md(_split_rows(f, 'val'))}")
        if f.get("test"):
            test_parts.append(f"### {NAMES[k]}\n\n{_md(_split_rows(f, 'test'))}\n\n![{k}](bakeoff/strata_{k}.png)")
            heatmap(k, f, OUT / f"strata_{k}.png")
        for lift, lst in _sanity(f).items():
            for t in lst:
                sanity_parts.append({"aday": NAMES[k], "lift": lift, "test": t["name"], "sonuç": t["passed"], "ayrıntı": t["detail"]})
        seed = sorted(f["val"])[0]
        deploy_rows.append({"aday": NAMES[k], "boyut_KB": f["val"][seed]["size_bytes"] / 1024,
                            "çıkarım_ms (Python)": f["val"][seed]["latency_ms"]})  # fmt: skip
        vdh_rows += _vdh_rows(f["val"][seed]["lifts"], f"{k} ağırlıklı")
        s = sens[k]
        if s:
            unw = s["variants"].get("ağırlıksız")
            if unw:
                vdh_rows += _vdh_rows(unw, f"{k} ağırlıksız")
            base = {lift: f["val"][seed]["lifts"][lift]["metrics"]["pinball"] for lift in f["val"][seed]["lifts"]}
            for name, block in s["variants"].items():
                for lift, r in block.items():
                    sens_rows.append({"aday": NAMES[k], "varyant": name, "lift": lift,
                                      "pinball": r["metrics"]["pinball"], "temel": base.get(lift),
                                      "bant_dışı_oran": r["metrics"]["strata_outside_share"]})  # fmt: skip

    winner, decision = decide(finals, sens)
    verdict = (
        f"**Kazanan: {NAMES[winner]}** (§1 kurallarına göre: uygun adaylar arasında en düşük test pinball'ı; "
        f"%1 içindeki eşitlikte daha basit model)." if winner else
        "**Hiçbir aday §1'deki bütün kapıları geçmedi.** Kazanan ilan edilmedi; karar kullanıcıya bırakıldı."
    )
    body = f"""{head}

{MARK}

Aday başına {N_TRIALS_TEXT} deneme (doğrulama kümesi, tohum 1).

{search_section(keys)}

## 4. Tohum tekrarı (doğrulama, 3 tohum, ortalama ± sd)

{chr(10).join(val_parts)}

## 5. Akıl sağlığı testleri (doğrulama, tohum 1)

{_md(sanity_parts)}

## 6. Boyut ve hız

{_md(deploy_rows)}

Boyut: A için modelin pickle boyutu (üst sınır), B için 19 ağacın metin dökümü, C için ortak gövdenin float32
parametreleri. Çıkarım: tek satır, 19 çeyrek, Python'da 50 tekrar ortalaması (Core ML süresi değildir).

## 7. Test kümesi (tek bakış, 3 tohum)

{chr(10).join(test_parts)}

Isı haritası: test kümesinde (tohum 1) katman başına en büyük kapsama sapmasının izin verilen sınıra
(`max(2 puan, gürültü bandı)`) oranı; 1'in üstü bant dışı.

## 8. van den Hoek 2024 (18–35, 90. yüzdelik)

{_md(vdh_rows)}

Kullanıcı onayı gereği ±%3 ölçütü **ağırlıksız** sürümle değerlendirilir; ağırlıklı sürüm bilgi içindir.

## 9. Duyarlılık (doğrulama, tohum 1)

{_md(sens_rows)}

## 10. Karar

{_md(decision)}

{verdict}
"""
    commentary = OUT / "commentary.md"
    if commentary.exists():
        body += "\n" + commentary.read_text(encoding="utf-8")
    REPORT.write_text(body, encoding="utf-8")
    return REPORT


N_TRIALS_TEXT = "10"
