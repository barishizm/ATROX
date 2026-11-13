"""P055 koşumu: kestirim, bootstrap, LOSO, duyarlılık, BMI deneyi → rapor + params taslağı.

    uv run python -m gymml.calibration.run          (make calibrate)
"""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from datetime import date
from pathlib import Path

import numpy as np

from gymml.calibration import fit as F
from gymml.calibration.anchors import POPULATIONS, Anchor, load_anchors, scale_source_bodyweight
from gymml.calibration.bmi import BMICorrection
from gymml.calibration.reference import (
    AGE_BANDS,
    LIFTS,
    REF_BAND,
    SEXES,
    CompetitorReference,
    EmpiricalOPLReference,
    ModelReference,
    age_band_of,
)

ML_ROOT = Path(__file__).resolve().parents[3]
COOPER_URL = ("https://www.acefitness.org/images/webcontent/assets/certification/ace-answers/"
              "forms/pt/38_Bench-Press_Assessment_Protocol.pdf")
# BMI deneyi: çapalarda boy yok → varsayım (birincil: 177/164 cm; alternatif: Fernandez Ortega
# 2022 örnekleminin ortalama boyları 170.5/158.2 cm).
ASSUMED_HEIGHTS = {"M": 177.0, "F": 164.0}
ALT_HEIGHTS = {"M": 170.5, "F": 158.2}


@dataclass(frozen=True)
class User:
    label: str
    sex: str
    age: int
    bodyweight_kg: float
    lift: str
    kg: float


TYPICAL_USERS = [
    User("Erkek 30 y, 80 kg, bench 80", "M", 30, 80, "bench", 80),
    User("Erkek 30 y, 80 kg, squat 100", "M", 30, 80, "squat", 100),
    User("Erkek 30 y, 80 kg, deadlift 140", "M", 30, 80, "deadlift", 140),
    User("Erkek 50 y, 90 kg, bench 90", "M", 50, 90, "bench", 90),
    User("Kadın 30 y, 65 kg, bench 40", "F", 30, 65, "bench", 40),
    User("Kadın 30 y, 65 kg, squat 70", "F", 30, 65, "squat", 70),
]


def short(url: str) -> str:
    names = {
        "bench-press/kg": "StrengthLevel-bench",
        "squat/kg": "StrengthLevel-squat",
        "deadlift/kg": "StrengthLevel-deadlift",
        "Assessment_Protocol.pdf": "Cooper(ACE)",
        "PMC9180020/": "FernandezOrtega2022",
        "PMC7197498/": "Perna2016-NHANES-grip",
        "PMC11679921/": "Stratton2024",
    }
    for k, v in names.items():
        if url.endswith(k):
            return v
    return url


def score(cal: F.Calibration, ref: CompetitorReference, pop: str, u: User,
          bw_fn=None) -> float:
    bw = bw_fn(u.sex, u.bodyweight_kg) if bw_fn else u.bodyweight_kg
    return cal.percentile(ref, pop, u.sex, u.lift, age_band_of(u.age), bw, u.kg)


def calibration_section(cal: F.Calibration, boots: list[F.Calibration], band: dict,
                        bmi: dict, ref_note: str) -> dict:
    def q(vals: list[float]) -> list[float]:
        return [round(float(x), 4) for x in np.percentile(vals, [5, 50, 95])]

    delta: dict = {}
    delta_ci: dict = {}
    kappa: dict = {}
    kappa_ci: dict = {}
    for pop in POPULATIONS:
        delta[pop], delta_ci[pop], kappa[pop], kappa_ci[pop] = {}, {}, {}, {}
        for sex in SEXES:
            kappa[pop][sex] = round(cal.kappa(pop, sex), 4)
            kappa_ci[pop][sex] = q([b.kappa(pop, sex) for b in boots])
            delta[pop][sex], delta_ci[pop][sex] = {}, {}
            for lift in LIFTS:
                delta[pop][sex][lift] = {b: round(cal.delta(pop, sex, lift, b), 4)
                                         for b in AGE_BANDS}
                delta_ci[pop][sex][lift] = {b: q([x.delta(pop, sex, lift, b) for x in boots])
                                            for b in AGE_BANDS}
    return {
        "calibration": {
            "schema": "p055-draft-1",
            "status": "draft — awaiting user approval; P057 merges into params.json",
            "generated": date.today().isoformat(),
            "model": "log-scale location-scale: m_g = m_c - delta_g(sex, lift, age_band); "
                     "s_g = kappa_g(sex) * s_c; z_g = (ln kg - m_c + delta) / (kappa * s_c)",
            "competitor_reference": cal.reference_name,
            "competitor_reference_note": ref_note,
            "age_bands": list(AGE_BANDS),
            "reference_age_band": REF_BAND,
            "populations": {"competitor": "delta = 0, kappa = 1"},
            "delta": delta,
            "kappa": kappa,
            "bootstrap_90ci": {"delta": delta_ci, "kappa": kappa_ci, "n_boot": len(boots)},
            "uncertainty_band_pct_points": band,
            "bmi_correction": bmi,
            "anchors_file": "ml/data/anchors.csv",
            "fit_params": {k: round(v, 5) for k, v in cal.theta.items()},
        }
    }


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--opl", type=Path, default=ML_ROOT / "data/interim/opl.parquet")
    ap.add_argument("--anchors", type=Path, default=ML_ROOT / "data/anchors.csv")
    ap.add_argument("--report", type=Path, default=ML_ROOT / "reports/calibration.md")
    ap.add_argument("--params", type=Path, default=ML_ROOT / "params_draft/calibration.json")
    ap.add_argument("--n-boot", type=int, default=500)
    ap.add_argument("--reference", choices=["model", "opl"], default="model",
                    help="model: P053 kazananı (runs/bakeoff/model_A_*.pkl); opl: ampirik OPL")
    args = ap.parse_args(argv)

    anchors = load_anchors(args.anchors)
    if args.reference == "model":
        ref = ModelReference.from_pickles(ML_ROOT / "runs/bakeoff")
    else:
        ref = EmpiricalOPLReference.from_parquet(args.opl, tested_only=True)
    ref_all = EmpiricalOPLReference.from_parquet(args.opl, tested_only=False)

    cal = F.fit(anchors, ref)
    boots = F.bootstrap(anchors, ref, n_boot=args.n_boot)
    loso = F.leave_one_source_out(anchors, ref)

    # --- Duyarlılık senaryoları (kaynak ve yöntem seçimleri) ---
    scenarios: dict[str, tuple[F.Calibration, CompetitorReference]] = {"temel": (cal, ref)}
    for src, (c, _) in loso.items():
        scenarios[f"−{short(src)}"] = (c, ref)
    scenarios["eşit ağırlık"] = (F.fit(anchors, ref, weights_mode="equal"), ref)
    scenarios["yalnız reliability"] = (F.fit(anchors, ref, weights_mode="reliability"), ref)
    scenarios["OPL tümü (tested+untested)"] = (F.fit(anchors, ref_all), ref_all)
    for d in (-10, 10):
        moved = scale_source_bodyweight(anchors, COOPER_URL, d)
        scenarios[f"Cooper VA {d:+d} kg"] = (F.fit(moved, ref), ref)

    rows = []
    band_gym, band_gen = [], []
    for u in TYPICAL_USERS:
        for pop in POPULATIONS:
            base = score(cal, ref, pop, u)
            sc = {k: score(c, r, pop, u) for k, (c, r) in scenarios.items()}
            bs = [score(b, ref, pop, u) for b in boots]
            b5, b95 = np.percentile(bs, [5, 95])
            lo = min(min(sc.values()), b5)
            hi = max(max(sc.values()), b95)
            half = (hi - lo) / 2
            (band_gym if pop == "gym" else band_gen).append(half)
            src_lo = min(sc, key=sc.get)
            src_hi = max(sc, key=sc.get)
            rows.append((u.label, pop, base, b5, b95, sc[src_lo], src_lo, sc[src_hi], src_hi, half))

    band = {
        "gym": {"median_half_width": round(float(np.median(band_gym)), 1),
                "max_half_width": round(float(np.max(band_gym)), 1)},
        "general": {"median_half_width": round(float(np.median(band_gen)), 1),
                    "max_half_width": round(float(np.max(band_gen)), 1)},
        "definition": "half of the envelope [min, max] over source/method scenarios and "
                      "bootstrap 5-95%, for the typical users in reports/calibration.md",
    }

    # --- BMI deneyi ---
    bmi_results = {}
    for label, heights in (("varsayılan boy 177/164", ASSUMED_HEIGHTS),
                           ("FO boyu 170.5/158.2", ALT_HEIGHTS)):
        for beta in (0.5, 0.25):
            fn = BMICorrection(beta=beta).with_assumed_height(heights)
            c = F.fit(anchors, ref, bodyweight_fn=fn)
            lo_b = F.leave_one_source_out(anchors, ref, bodyweight_fn=fn)
            bmi_results[f"{label}, β={beta}"] = (c.meta["weighted_rss"], _loso_mae(lo_b))
    base_rss, base_mae = cal.meta["weighted_rss"], _loso_mae(loso)
    improves = any(r < base_rss * 0.95 and m < base_mae - 1.0 for r, m in bmi_results.values())
    heavy = _heavy_residuals(cal, anchors, ref)
    bmi = {"enabled": False if not improves else "review", "threshold_bmi": 25.0, "beta": 0.5,
           "reason": "no improvement in weighted RSS (>=5%) and LOSO percentile MAE (>=1 pt); "
                     "anchors carry no height, so the test relies on assumed heights"
           if not improves else "improvement seen; needs user review before enabling"}

    ref_note = ("P053 winner (Spline-LMS BCPE, seed 1): log median and (q84.13-q15.87)/2 at the "
                "age-band representative age (gymml.calibration.reference.BAND_AGE)."
                if args.reference == "model" else
                "OpenPowerlifting empirical conditional distribution (Raw, Tested, sex x age band "
                "x 5 kg bodyweight bin; log median and (q84.13-q15.87)/2).")
    section = calibration_section(cal, boots, band, bmi, ref_note)
    args.params.parent.mkdir(parents=True, exist_ok=True)
    args.params.write_text(json.dumps(section, indent=2, ensure_ascii=False) + "\n")

    report = render_report(anchors, cal, boots, loso, rows, band, bmi_results, base_rss,
                           base_mae, heavy, improves, ref, scenarios)
    args.report.write_text(report)
    print(f"yazıldı: {args.report} ve {args.params}")
    print(json.dumps(band, ensure_ascii=False))


def _loso_mae(loso) -> float:
    errs = [abs(h.percentile_error) for _, held in loso.values() for h in held
            if h.percentile_error is not None]
    return float(np.mean(errs))


def _heavy_residuals(cal, anchors, ref) -> list[tuple[str, float, float]]:
    """Strength Level erkek medyan satırlarında VA'ya göre yüzdelik hatası (BMI vekili)."""
    out = []
    for a in anchors:
        if (not a.relative and a.population == "gym" and a.sex == "M" and a.percentile == 50
                and "strengthlevel" in a.source_url):
            p = cal.percentile(ref, "gym", "M", a.lift, a.age_band, a.bodyweight_kg, a.value_kg)
            out.append((a.lift, a.bodyweight_kg, p - 50))
    return sorted(out)


def _fmt(x: float, nd: int = 1) -> str:
    return f"{x:.{nd}f}"


def render_report(anchors: list[Anchor], cal, boots, loso, rows, band, bmi_results, base_rss,
                  base_mae, heavy, improves, ref, scenarios) -> str:
    src_counts: dict[str, list[Anchor]] = {}
    for a in anchors:
        src_counts.setdefault(a.source_url, []).append(a)
    L: list[str] = []
    w = L.append
    w("# P055 — Nüfus kalibrasyonu raporu\n")
    w("> Otomatik üretildi: `make calibrate` (`gymml.calibration.run`). Elle düzenlemeyin; metin "
      "değişiklikleri `run.py` içindeki şablona yapılır.\n")
    w("## Özet\n")
    g, gn = band["gym"], band["general"]
    w(f"- **Salon referansı belirsizlik bandı:** tipik kullanıcılarda medyan "
      f"**±{g['median_half_width']}"
      f"** yüzdelik puan (en kötü ±{g['max_half_width']}).")
    w(f"- **Genel nüfus referansı:** medyan ±{gn['median_half_width']}, en kötü "
      f"±{gn['max_half_width']} puan — çapası az ve dağınık; salon referansından belirgin "
      "şekilde daha belirsiz.")
    w("- Dokümandaki ±8–12 tahmini bu ölçümle değiştirildi (`docs/03-ML-MODEL.md` §5.3).")
    w(f"- Yarışmacı referansı: `{cal.reference_name}` (P057'den itibaren varsayılan P053 kazananı "
      "Spline-LMS; `--reference opl` ampirik OPL referansını kullanır). \"OPL tümü\" senaryosu "
      "ampirik tested+untested referansıyla karşılaştırır.")
    w(f"- BMI düzeltmesi: **{'kapalı' if not improves else 'inceleme gerekli'}** (aşağıda).\n")

    w("## Model\n")
    w("Log-kg ölçeğinde yer-ölçek (§5.1): `m_g = m_c − δ_g`, `s_g = κ_g · s_c`, skor "
      "`Φ((ln kg − m_c + δ) / (κ s_c))`. Parametrizasyon:\n")
    w("```\nδ_g(cinsiyet, kaldırış, bant) = D_g(cinsiyet) + L(cinsiyet, kaldırış) + A_g(cinsiyet, "
      "bant)"
      "\nκ_g (nüfus başına tek)\n```\n")
    w("- `L` bench için 0 ve iki nüfusta ortak (genel nüfusta deadlift çapası yok; kaldırışlar "
      "arası "
      "fark salon çapalarından öğrenilir).")
    w("- `A` referans bantta (20-39) 0. Yaş ofsetleri yaşa göreli çapalardan (Strength Level yaş "
      "tabloları, NHANES el kavrama) ve Cooper yaş bantlarından gelir.")
    w("- Tahmin parametrelerde doğrusal → ağırlıklı en küçük kareler; ağırlık = reliability / "
      "√(kaynağın satır sayısı); nominal çapa hatası σ₀ = 0.05 log. Zayıf önseller: A ~ N(0, "
      "0.5²), "
      "κ ~ N(1, 1²), D, L ~ N(0, 2²) — yalnızca çapası olmayan hücreleri tanımlı tutar.")
    w("- Yaşa göreli çapa (VA'sı olmayan satır): aynı kaynak/cinsiyet/kaldırış/yüzdeliğin 20-39 "
      "satırına log farkı, yarışmacının aynı farkıyla karşılaştırılır. El kavrama gücü için "
      "yarışmacı farkı üç kaldırışın ortalamasıdır (varsayım: genel nüfusta kaldırış gücü yaşla el "
      "kavrama gücüyle aynı oranda düşer).")
    w("- `age_band = all` olan tablolar (Strength Level vücut ağırlığı tabloları) 20-39 kabul "
      "edilir.\n")

    w("## Çapa dosyası\n")
    w(f"`ml/data/anchors.csv`: {len(anchors)} satır, {len(src_counts)} kaynak. Her satırda URL ve "
      "erişim tarihi var; tüm kaynaklar açılıp okundu (2026-11-13).\n")
    w("| Kaynak | Nüfus | Satır | Güven | Ne alındı |")
    w("|---|---|---|---|---|")
    desc = {
        "StrengthLevel-bench": "VA tablosu (80 kg erkek 5 seviye; 60/100/120 kg medyan; kadın 60 "
        "kg "
                               "5/50/95, 80 kg medyan) + yaş tablosu medyanları",
        "StrengthLevel-squat": "aynı desen",
        "StrengthLevel-deadlift": "aynı desen",
        "Cooper(ACE)": "1RM bench / VA oran normları (Cooper Institute, ACE'nin izinli yeniden "
                       "basımı); VA varsayımı E 85 / K 68 kg",
        "FernandezOrtega2022": "kuvvet antrenmanı yapmayan aktif öğrenciler, ort ± SS → log-normal",
        "Perna2016-NHANES-grip": "NHANES 2011-12 el kavrama medyanları, yalnızca yaş şekli",
        "Stratton2024": "direnç antrenmanlı yetişkinler (n=12+12), ort → medyan",
    }
    for url, rs in src_counts.items():
        s = short(url)
        rel = sorted({r.reliability for r in rs})
        w(f"| [{s}]({url}) | {rs[0].population} | {len(rs)} | {'/'.join(map(str, rel))} | "
          f"{desc.get(s, '')} |")
    w("")
    w("### Bulunan ve bulunamayan çapa türleri (§5.2)\n")
    w("- **Yayımlanmış salon standartları — bulundu:** Strength Level (seviye = 5/20/50/80/95. "
      "yüzdelik). Kendi kullanıcılarının girdiği kaldırışlardan türetilmiş; kullanıcı kitlesi "
      "salon nüfusundan güçlü tarafa yanlı olabilir (gönüllü kayıt). Yaş tabloları VA'dan bağımsız "
      "tek tablo — yaş eğrisi büyük olasılıkla modelden türetilmiş, ham veri değil.")
    w("- **Akademik salon kohortları — kısmen:** yalnızca küçük, giriş eşiğiyle kesilmiş "
      "örneklemler "
      "bulundu. Stratton 2024 (n=24, bench ≥ 0.85/0.4 × VA) güven 1 ile alındı. Macarilla 2022 "
      "(n=17, bench ≥ 1.25 × VA ve squat ≥ 1.5 × VA) salon medyanına yakın bir eşikle kesildiği "
      "için **alınmadı**. Büyük, kesilmemiş bir \"düzenli salon kullanıcısı\" 1RM kohortu "
      "bulunamadı.")
    w("- **Nüfus normları — kısmen:** Cooper Institute bench/VA normları (ACE'nin izinli yeniden "
      "basımı; asıl monografa erişilemedi). Kadın tablosunun sütunları düzensiz (60+ \"Superior\" "
      "> "
      "50-59) → güven 1. Leg press normları alınmadı (çapa hareketi değil). Squat/deadlift için "
      "nüfus normu bulunamadı. Genç, antrenmansız aktif yetişkin kohortu (Fernandez Ortega 2022, "
      "n=355) genel nüfus çapası olarak alındı; tam (derin) squat güç kaldırma derinliği değildir "
      "→ "
      "squat satırları güven 1.")
    w("- **Yaş eğrisi — bulundu:** NHANES 2011-12 el kavrama (Perna 2016). Ham değerler lb, "
      "kg'ye çevrildi.")
    w("- **Bulunamayan / kullanılmayan:** ikincil derleme siteleri (fitnessnorms vb.) birincil "
      "kaynak olmadığı için alınmadı; CDC vücut ölçüleri sayfası erişimi reddetti (Cooper VA "
      "varsayımı bu yüzden kaynaksız bir varsayım olarak duyarlılıkta ±10 kg oynatıldı); van den "
      "Hoek 2024 yarışmacı nüfusudur — P053 akıl sağlığı testinde kullanılır, kalibrasyon çapası "
      "değildir.\n")

    w("## Kestirim sonucu\n")
    w(f"Ağırlıklı ortalama kare artık: {base_rss:.4f} (log², σ₀ birimsiz). Bootstrap: kaynak "
      f"içinde "
      f"tabakalı satır yeniden örneklemesi, B = {len(boots)}.\n")
    w("| Nüfus | Cinsiyet | κ (5–95%) | δ bench 20-39 (5–95%) | δ squat 20-39 | δ deadlift 20-39 |")
    w("|---|---|---|---|---|---|")
    for pop in POPULATIONS:
        for sex in SEXES:
            kq = np.percentile([b.kappa(pop, sex) for b in boots], [5, 95])
            dq = np.percentile([b.delta(pop, sex, "bench", REF_BAND) for b in boots], [5, 95])
            w(f"| {pop} | {sex} | {cal.kappa(pop, sex):.2f} ({kq[0]:.2f}–{kq[1]:.2f}) | "
              f"{cal.delta(pop, sex, 'bench', REF_BAND):.3f} ({dq[0]:.3f}–{dq[1]:.3f}) | "
              f"{cal.delta(pop, sex, 'squat', REF_BAND):.3f} | "
              f"{cal.delta(pop, sex, 'deadlift', REF_BAND):.3f} |")
    w("")
    w("δ = 0.25 → salon medyanı yarışmacı medyanının e^−0.25 ≈ %78'i. κ > 1 → salon nüfusu "
      "yarışmacılardan daha geniş yayılır (beklenen: yarışmacılar seçilmiş, homojen bir uçtur).\n")
    w("Yaş ofsetleri A (δ'ya eklenir; pozitif = o yaşta yarışmacılara göre daha fazla düşüş):\n")
    w("| Nüfus | Cinsiyet | " + " | ".join(b for b in AGE_BANDS if b != REF_BAND) + " |")
    w("|---|---|" + "---|" * (len(AGE_BANDS) - 1))
    for pop in POPULATIONS:
        for sex in SEXES:
            vals = [cal.theta[f"A|{pop}|{sex}|{b}"] for b in AGE_BANDS if b != REF_BAND]
            w(f"| {pop} | {sex} | " + " | ".join(f"{v:+.3f}" for v in vals) + " |")
    w("")
    w("Not: salon (Strength Level) yaş tabloları yarışmacılardan daha dik, genel nüfus (el "
      "kavrama) "
      "daha yatık bir düşüş ima ediyor. Yaşlı yarışmacılar seçilmiş güçlü bir gruptur, bu yüzden "
      "genel nüfus için bu yön beklenir; salon yönü Strength Level'ın yaş çarpanlarından gelir ve "
      "tek kaynaklıdır.\n")

    w("## Birini dışarıda bırak (kaynak bazında)\n")
    w("Her kaynak çıkarılır, kalanlarla kestirilir, çıkarılan kaynağın mutlak çapalarının "
      "yüzdeliği tahmin edilir (hata = tahmin − yayımlanan yüzdelik). Yaşa göreli çapalar için log "
      "hatası.\n")
    w("| Çıkarılan kaynak | Satır | Ort. mutlak yüzdelik hatası | log RMSE |")
    w("|---|---|---|---|")
    for src, (_, held) in loso.items():
        pe = [abs(h.percentile_error) for h in held if h.percentile_error is not None]
        rm = float(np.sqrt(np.mean([h.log_error ** 2 for h in held])))
        w(f"| {short(src)} | {len(held)} | {_fmt(float(np.mean(pe))) if pe else '— (göreli)'} | "
          f"{rm:.3f} |")
    w("")
    w(f"Tüm kaynaklar üzerinden ortalama mutlak yüzdelik hatası: **{base_mae:.1f}** puan. "
      "Yorum: tek kaynağın taşıdığı parametreler (ör. squat'ın kaldırış farkı yalnızca Strength "
      "Level-squat'tan, genel nüfus bench seviyesi Cooper ile Fernandez Ortega arasında) o kaynak "
      "çıkınca önsele düşer — büyük hatalar kaynak sayısının azlığını gösterir, bir kaynağın "
      "\"yanlış\" olduğunu değil. Bu yüzden bant LOSO kestirimlerini de kapsar.\n")

    w("## Duyarlılık: tipik kullanıcılar\n")
    w("Senaryolar: temel; her kaynağın çıkarılması (7); eşit ağırlık; yalnız reliability ağırlığı; "
      "yarışmacı referansı olarak tüm OPL (tested + untested); Cooper VA varsayımı ±10 kg; "
      "bootstrap 5–95%. Bant = bu zarfın yarı genişliği.\n")
    w("| Kullanıcı | Nüfus | Temel skor | Bootstrap 5–95 | En düşük (senaryo) | En yüksek "
      "(senaryo) | ± |")
    w("|---|---|---|---|---|---|---|")
    for lab, pop, base, b5, b95, lo, slo, hi, shi, half in rows:
        w(f"| {lab} | {pop} | {base:.1f} | {b5:.1f}–{b95:.1f} | {lo:.1f} ({slo}) | "
          f"{hi:.1f} ({shi}) | {half:.1f} |")
    w("")
    u = TYPICAL_USERS[0]
    comp = cal.percentile(ref, "competitor", u.sex, u.lift, REF_BAND, u.bodyweight_kg, u.kg)
    w(f"Karşılaştırma: aynı kullanıcı ({u.label}) yarışmacı referansında {comp:.1f}. yüzdelikte.\n")

    w("## Boy / BMI düzeltmesi deneyi (§7)\n")
    w("`bw_eff = 25·h² + β·(bw − 25·h²)` (BMI > 25 ise). Çapaların hiçbirinde bireysel boy yok; "
      "deney varsayılan boylarla yapıldı. Ölçütler: ağırlıklı RSS ve LOSO ortalama mutlak "
      "yüzdelik hatası.\n")
    w("| Varyant | Ağırlıklı RSS | LOSO MAE (puan) |")
    w("|---|---|---|")
    w(f"| düzeltme yok | {base_rss:.4f} | {base_mae:.1f} |")
    for k, (r, m) in bmi_results.items():
        w(f"| {k} | {r:.4f} | {m:.1f} |")
    w("")
    w("Vekil kontrol: Strength Level erkek medyan satırlarında yüzdelik hatası VA'ya göre "
      "(ağır kullanıcılarda sistematik sapma BMI etkisine işaret ederdi):\n")
    w("| Kaldırış | VA | Hata (puan) |")
    w("|---|---|---|")
    for lift, bw, e in heavy:
        w(f"| {lift} | {bw:.0f} | {e:+.1f} |")
    w("")
    if improves:
        w("**Sonuç:** en az bir varyant iyileşme gösterdi; açılmadan önce kullanıcı onayı "
          "gerekir.\n")
    else:
        w("**Sonuç: kapalı.** Düzeltme RSS'i ve LOSO hatasını iyileştirmedi, tersine kötüleştirdi. "
          "Nedenleri: (1) çapalar bireysel boy taşımıyor (yalnızca varsayılan boy) ve yarışmacı "
          "verisinde de boy yok; (2) vekil tablo düzeltmenin varsaydığının tersini gösteriyor — "
          "Strength Level'da ağır kullanıcıların medyanı yarışmacı VA eğrisinin öngördüğünden "
          "*yüksek* (hata VA ile artıyor); BMI düzeltmesi ağır kullanıcının etkin VA'sını düşürüp "
          "bu farkı büyütür. Bu eğim tek kaynaklıdır (Strength Level'ın kendi tablo modeli "
          "olabilir). "
          "Boy toplanmaya devam eder; v2'de uygulama verisiyle (boy × e1RM) yeniden denenir "
          "(`bmi_correction.enabled = false`).\n")

    w("## Sınırlar\n")
    w("- Çapa sayısı az ve kaynaklar heterojen; özellikle genel nüfus ve kadın tarafı zayıf.")
    w("- Strength Level kullanıcıları salon nüfusunun güçlü tarafına yanlı olabilir → salon "
      "skorları muhtemelen olması gerekenden biraz düşük.")
    w("- κ nüfus başına tek değer (cinsiyet/kaldırış başına değil; ayrı kestirimde genel nüfus "
      "kadın κ'sı tanımsız kaldı); yaşa ve VA'ya göre ölçek değişimi yalnızca yarışmacı ölçeğinden "
      "gelir.")
    w("- δ VA'ya bağlı değil (§5.1). Strength Level satırları yarışmacılardan daha dik bir VA "
      "eğimi ima ediyor (BMI bölümündeki vekil tablo): 60 kg'da skor fazla, 120 kg'da az tahmin "
      "ediliyor olabilir. δ'ya bir log-VA terimi eklemek model biçimini değiştirir → kullanıcı "
      "kararına bırakıldı (ILERLEME Ertelenenler).")
    w("- Yarışmacı referansı ampirik hücre çeyrekleridir; uç kuyruk şekli log-normal varsayımıyla "
      "(z = (ln y − m_c)/s_c) yaklaşıklanır. P053 modeli takılınca yeniden kestirilmelidir.")
    w("- Faz 10'da uygulama verisi bu δ/κ'yı önsel olarak kullanıp Bayesçi günceller (§12).")
    return "\n".join(L) + "\n"


if __name__ == "__main__":
    main()
