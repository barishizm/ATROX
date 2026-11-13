# ruff: noqa: E501 — rapor şablonu (Markdown) uzun satırlar içerir.
"""`make train-c`: Aday C'yi (BCPE ve sinh-arcsinh başlıkları) ortak koşumla değerlendirir.

Çıktılar: `reports/candidate_c.md`, `reports/candidate_c/*.png|json`, `params_draft/correlation.json`,
`runs/<zaman>-candidate_c/` (yapılandırma, metrikler, ağırlıklar). Test kümesi kullanılmaz.
"""

from __future__ import annotations

import json
import time

import numpy as np
import polars as pl
import torch

from gymml.data.cohort import LIFTS, ML_ROOT
from gymml.eval.baselines import _md
from gymml.eval.data import DataSpec, load_lift
from gymml.eval.runner import (
    evaluate_factory,
    plot_percentile_curves,
    plot_pit,
    split_info,
    summary_table,
)
from gymml.eval.sanity import SanityConfig
from gymml.models.neural import (
    AGE_CENTER,
    AGE_SCALE,
    CLIP_QUANTILES,
    LOGBW_CENTER,
    LOGBW_SCALE,
    NeuralConfig,
    NeuralDistributional,
    _weighted_median,
    load_sbd,
    shared_factory,
)
from gymml.utils.runs import Run

REPORTS = ML_ROOT / "reports"
FIGS = REPORTS / "candidate_c"
PARAMS_DRAFT = ML_ROOT / "params_draft"
GRID_AGES = (20.0, 30.0, 45.0, 60.0)
GRID_BW = {"M": (70.0, 90.0, 120.0), "F": (55.0, 65.0, 90.0)}


def _x(rows) -> pl.DataFrame:
    return pl.DataFrame(rows, schema=["sex", "age", "bodyweight_kg"], orient="row")


def weighted_corr(z: np.ndarray, w: np.ndarray) -> np.ndarray:
    w = w / w.sum()
    zc = z - (w[:, None] * z).sum(0)
    cov = (w[:, None, None] * zc[:, :, None] * zc[:, None, :]).sum(0)
    d = np.sqrt(np.diag(cov))
    return cov / np.outer(d, d)


def _fmt_mat(m: np.ndarray) -> str:
    rows = ["| | " + " | ".join(LIFTS) + " |", "|---|---|---|---|"]
    for i, lift in enumerate(LIFTS):
        rows.append(f"| {lift} | " + " | ".join(f"{v:.3f}" for v in m[i]) + " |")
    return "\n".join(rows)


def _pairs(m: np.ndarray) -> dict[str, float]:
    return {"S-B": m[0, 1], "S-D": m[0, 2], "B-D": m[1, 2]}


def out_of_range_table(joint: NeuralDistributional) -> pl.DataFrame:
    rows = []
    cases = [
        ("çok genç", 10.0, None),
        ("çok yaşlı", 95.0, None),
        ("çok hafif", 30.0, 25.0),
        ("çok ağır", 30.0, 300.0),
        ("genç + ağır", 10.0, 300.0),
        ("yaşlı + hafif", 95.0, 25.0),
    ]
    for sex in ("M", "F"):
        for label, age, bw in cases:
            bw = bw if bw is not None else {"M": 90.0, "F": 65.0}[sex]
            x = _x([(sex, age, bw)])
            lo_a, hi_a = joint.clip.age
            lo_b, hi_b = joint.clip.bw[sex]
            xc = _x([(sex, float(np.clip(age, lo_a, hi_a)), float(np.clip(bw, lo_b, hi_b)))])
            for lift in LIFTS:
                q = joint.quantile(x, lift, np.array([0.05, 0.5, 0.95]))[0]
                qc = joint.quantile(xc, lift, np.array([0.05, 0.5, 0.95]))[0]
                rows.append(
                    {
                        "cinsiyet": sex,
                        "durum": label,
                        "yaş": age,
                        "kilo": bw,
                        "kaldırış": lift,
                        "Q05": q[0],
                        "Q50": q[1],
                        "Q95": q[2],
                        "sınırla_aynı": bool(np.allclose(q, qc, rtol=1e-12)),
                        "sonlu_sıralı": bool(np.all(np.isfinite(q)) and np.all(np.diff(q) > 0)),
                    }
                )
    return pl.DataFrame(rows)


def empirical_teen_jumps(spec: DataSpec) -> pl.DataFrame:
    """Ham train verisinde 16–20 yaş arası yıllık medyan değişimi (erkek 80–100 kg, kadın 57.5–72.5 kg)."""
    rows = []
    for lift in LIFTS:
        df = load_lift(lift, "train", spec)
        for sex, (lo, hi) in {"M": (80.0, 100.0), "F": (57.5, 72.5)}.items():
            meds = []
            for age in range(16, 21):
                d = df.filter(
                    (pl.col("sex") == sex)
                    & (pl.col("age") >= age)
                    & (pl.col("age") < age + 1)
                    & pl.col("bodyweight_kg").is_between(lo, hi)
                )
                meds.append(_weighted_median(d["value_kg"].to_numpy(), d["weight"].to_numpy()))
            m = np.array(meds)
            rows.append(
                {"kaldırış": lift, "cinsiyet": sex}
                | {
                    f"{a}→{a + 1}": float(v)
                    for a, v in zip(range(16, 20), np.diff(m) / m[:-1], strict=True)
                }
            )
    return pl.DataFrame(rows)


def inference_ms(joint: NeuralDistributional) -> float:
    x = _x([("M", 30.0, 90.0)])
    q = np.array([0.5])
    for _ in range(20):
        joint.quantile(x, "squat", q)
    t0 = time.perf_counter()
    n = 200
    for _ in range(n):
        joint.cdf(x, "squat", np.array([180.0]))
    return (time.perf_counter() - t0) / n * 1000


def run() -> None:
    torch.set_num_threads(max(1, torch.get_num_threads()))
    spec = DataSpec()
    sbd_train, sbd_val = load_sbd("train", spec), load_sbd("val", spec)
    joints: dict[str, NeuralDistributional] = {}
    results = {}
    for head in ("bcpe", "shash"):
        joint = NeuralDistributional(NeuralConfig(head=head, spec=spec))
        t0 = time.perf_counter()
        results[f"neural_{head}"] = evaluate_factory(shared_factory(joint, sbd_train), spec)
        print(head, "done in", round(time.perf_counter() - t0, 1), "s")
        joints[head] = joint

    table = summary_table(results)
    mean_pin = {
        h: float(np.mean([r.metrics["pinball"] for r in results[f"neural_{h}"]])) for h in joints
    }
    primary = min(mean_pin, key=mean_pin.get)
    pj = joints[primary]
    info = split_info()

    run_dir = Run(
        ML_ROOT / "runs",
        "candidate_c",
        {h: j.describe() for h, j in joints.items()} | {"split": info, "primary": primary},
    )
    run_dir.write_metrics(
        {name: {r.lift: dict(r.metrics) for r in rs} for name, rs in results.items()}
        | {"history": {h: j.history for h, j in joints.items()}}
    )
    for h, j in joints.items():
        torch.save(j.net.state_dict(), run_dir.dir / f"weights_{h}.pt")

    FIGS.mkdir(parents=True, exist_ok=True)
    plot_pit(results, FIGS / "pit.png")
    plot_percentile_curves(results, FIGS / "percentiles_M30.png", "M", 30.0)
    plot_percentile_curves(results, FIGS / "percentiles_F30.png", "F", 30.0)
    plot_percentile_curves(results, FIGS / "percentiles_M55.png", "M", 55.0)

    # Temel çizgilerle karşılaştırma (reports/baselines/summary.json, aynı val bölmesi).
    base = pl.DataFrame(json.loads((REPORTS / "baselines/summary.json").read_text()))
    both = pl.concat([base.select(table.columns), table])
    best_base = base.group_by("lift").agg(pl.col("pinball_kg").min().alias("en_iyi_temel"))
    gain = (
        table.join(best_base, on="lift")
        .with_columns(
            ((1 - pl.col("pinball_kg") / pl.col("en_iyi_temel")) * 100).alias("pinball_iyileşme_%")
        )
        .select("model", "lift", "pinball_kg", "en_iyi_temel", "pinball_iyileşme_%")
    )

    sanity_rows, ext = [], []
    for name, rs in results.items():
        for r in rs:
            for s in r.sanity:
                sanity_rows.append(
                    {
                        "model": name,
                        "lift": r.lift,
                        "test": s.name,
                        "sonuç": "✅" if s.passed else "❌",
                        "ayrıntı": s.detail,
                    }
                )
            ext.append(r.external.with_columns(pl.lit(name).alias("model")))
    ext_df = pl.concat(ext).select("model", pl.exclude("model"))

    oor = out_of_range_table(pj)
    teen = empirical_teen_jumps(spec)

    # Korelasyon.
    w_tr = sbd_train["weight"].to_numpy()
    R_pop = (pj.correlation(sbd_train) * (w_tr / w_tr.sum())[:, None, None]).sum(0)
    R_emp_val = weighted_corr(pj.sbd_scores(sbd_val), sbd_val["weight"].to_numpy())
    cop_val = {h: j.copula_nll(sbd_val) for h, j in joints.items()}
    grid_rows, grid_json = [], []
    for sex in ("M", "F"):
        for age in GRID_AGES:
            for bw in GRID_BW[sex]:
                R = pj.correlation(_x([(sex, age, bw)]))[0]
                p = _pairs(R)
                grid_rows.append({"cinsiyet": sex, "yaş": age, "kilo": bw} | p)
                grid_json.append(
                    {"sex": sex, "age": age, "bodyweight_kg": bw, "matrix": np.round(R, 4).tolist()}
                )
    grid_df = pl.DataFrame(grid_rows)
    lo_r, hi_r = (
        float(grid_df.select(["S-B", "S-D", "B-D"]).min_horizontal().min()),
        float(grid_df.select(["S-B", "S-D", "B-D"]).max_horizontal().max()),
    )
    in_range = 0.4 <= lo_r and hi_r <= 0.9 and np.all(np.linalg.eigvalsh(R_pop) > 0)

    PARAMS_DRAFT.mkdir(parents=True, exist_ok=True)
    corr_json = {
        "schema_version": 1,
        "module": "correlation",
        "status": "draft",
        "note": (
            "P052 Candidate C (neural, head="
            + primary
            + "). Gaussian-copula correlation of normal "
            "scores Phi^-1(F(y|x)) on complete SBD records (cohort_sbd, Tested=Yes, no wraps, train "
            "split). Replaces the placeholder in imbalance.json; P053 may refit with the winning "
            "marginals. P058 merges this into params.json."
        ),
        "variables": list(LIFTS),
        "matrix": np.round(R_pop, 4).tolist(),
        "matrix_source": "population average (sample-weighted mean of R(x) over train SBD rows)",
        "empirical_val_matrix": np.round(R_emp_val, 4).tolist(),
        "empirical_val_source": "weighted Pearson correlation of normal scores on the validation SBD rows",
        "conditional": {
            "parametrization": (
                "R(x) = L L^T, L lower-triangular with unit diagonal before row normalisation; "
                "off-diagonals (L10, L20, L21) = linear head on the shared trunk features."
            ),
            "grid": grid_json,
        },
        "input_clip": pj.clip.to_dict(),
    }
    (PARAMS_DRAFT / "correlation.json").write_text(
        json.dumps(corr_json, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )

    hist = {
        h: f"{len(j.history)} dönem, en iyi iç-ayrık NLL {min(e['holdout_nll'] for e in j.history):.4f}; "
        f"kopula {len(j.corr_history)} dönem"
        for h, j in joints.items()
    }
    ms = {h: inference_ms(j) for h, j in joints.items()}
    sc = SanityConfig()
    cfg = pj.cfg
    md = f"""# Aday C — Sinirsel dağılımsal regresyon (P052)

Üretim: `make train-c` (`gymml/models/neural_run.py`, model `gymml/models/neural.py`). Koşum izi:
`{run_dir.dir.relative_to(ML_ROOT)}/` (git-ignored). Değerlendirme P049 ortak koşumuyla (`evaluate_factory`)
**doğrulama** kümesinde; test kümesi kullanılmadı. Bölme özeti `{info["digest"]}` (temel çizgilerle aynı).

## Model

- Girdiler: erkek mi (0/1), `(yaş − {AGE_CENTER:g}) / {AGE_SCALE:g}`, `(ln kilo − ln 80) / {LOGBW_SCALE:g}`
  (merkez ln 80 = {LOGBW_CENTER:.4f}).
- Gövde: MLP {list(cfg.hidden)}, {cfg.activation}; üç kaldırış ortak gövde, kaldırış başına 4 çıkışlı başlık.
  Parametre sayısı: {", ".join(f"{h} {j.n_params():,}" for h, j in joints.items())} (hedef < 50 000; float32
  ile ≈ {pj.n_params() * 4 / 1024:.0f} KB).
- Başlıklar: **BCPE** (μ, σ, ν, τ; μ = exp, σ = softplus, ν ∈ (−3, 3), τ ∈ (1, 10)) ve **sinh-arcsinh**
  (log ölçekte μ, s, ε, δ). BCPE matematiği modülün kendisinde (scipy `gennorm`/`lognorm` ve sayısal
  integralle test edildi); P050'nin BCPE'si ile P053'te tekilleştirilebilir.
- Korelasyon başlığı: SBD tam kayıtlarında normal skorlar `Φ⁻¹(F(y|x))` için koşullu R(x); Cholesky
  parametreli (birim köşegen için satır normalize edilmiş alt üçgen), Gauss kopula olabilirliği; marjinaller
  donduruldıktan sonra gövde özellikleri üzerinde doğrusal başlık olarak eğitilir (IFM).
- Eğitim: ağırlıklı NLL (örnek ağırlıkları `weight`), her dönem yükler ±1.25 kg titreştirilir (2.5 kg
  yuvarlama), AdamW (lr {cfg.lr:g}, ağırlık azaltma {cfg.weight_decay:g}), kosinüs öğrenme hızı, batch
  {cfg.batch_size}, en çok {cfg.max_epochs} dönem, sabır {cfg.patience}. Erken durdurma train bölmesinden
  sporcu-gruplu ayrılan %{cfg.holdout_frac * 100:g}'luk iç kümeyle (val'e dokunulmaz).
- Cezalar: girdi-Jacobian (Hutchinson, λ = {cfg.lambda_jac:g}) — pürüzsüzlük; aynı yükte z-skoru kiloyla artarsa
  ReLU² cezası (λ = {cfg.lambda_mono:g}) — kiloda artmama testi için.
- Eğitim özeti: {"; ".join(f"{h}: {v}" for h, v in hist.items())}.
- Tek satır çıkarım (Python, torch ileri geçiş + scipy CDF): {", ".join(f"{h} {v:.2f} ms" for h, v in ms.items())}.
  Core ML/Swift'te çok daha hızlı olması beklenir; §4.3 dağıtım kısıtı P058'de ölçülecek.

### Girdi kırpma kuralı (Swift aynen uygular)

Model hiçbir zaman eğitim aralığının dışında değerlendirilmez: önce `clamp`, sonra standartlaştırma.
Sınırlar eğitim verisinin (üç kaldırış birleşik) desteği — dilim {CLIP_QUANTILES[0]:g} – {CLIP_QUANTILES[1]:g},
yani en küçük – en büyük gözlem — 0.5'e dışa yuvarlanmış; yaş tüm veri, kilo cinsiyete göre:

- yaş: {pj.clip.age[0]:g} – {pj.clip.age[1]:g}
- kilo (M): {pj.clip.bw["M"][0]:g} – {pj.clip.bw["M"][1]:g} kg, kilo (F): {pj.clip.bw["F"][0]:g} – {pj.clip.bw["F"][1]:g} kg

Sınırlar `params_draft/correlation.json` → `input_clip` alanında; P058 `params.json`'a taşır. Sonuç: aralık
dışında skor, en yakın sınır noktasının skoruyla aynıdır (örn. 300 kg'lık kişi {pj.clip.bw["M"][1]:g} kg gibi
değerlendirilir). Cinsiyeti belirtilmemiş kullanıcı için §4.5 karışımı üst katmanda yapılır.

İlk denemede sınırlar %0.1 – %99.9 dilimleriydi (yaş 14–79, kilo M 47–180, F 40–155). Kırpma noktasında
medyan eğrisinde eğim kırığı oluşur; bu noktalar olağan kullanıcı aralığının içinde kaldığı için pürüzsüzlük
testi (yaş 16–80, kilo 45–150) |Δ²medyan|/medyan ≈ 0.02–0.03 ile başarısız oldu — en büyük ikinci fark
tam olarak yaş 79 ve erkek kilo 47'deydi; kırık dışındaki değerler < 0.001. Bu yüzden kural destek sınırlarına
genişletildi: seyrek uçlarda model gövdenin pürüzsüz devamıdır (Jacobian cezası), dışarısı yine sabit.

## Metrikler (doğrulama kümesi) — temel çizgilerle birlikte

{_md(both)}

Birincil başlık (ortalama pinball'a göre): **{primary}**.

{_md(gain)}

![PIT](candidate_c/pit.png)

## Akıl sağlığı testleri

Ayarlar `SanityConfig` (temel çizgilerle aynı; tepe yaşı aralığı {sc.peak_age_range[0]:g}–{sc.peak_age_range[1]:g}, açık soru P049).

{_md(pl.DataFrame(sanity_rows))}

### Yaş testi ve gençlerde hızlı artış

Yaş testinin "yıllık sıçrama ≤ %{sc.max_year_jump * 100:g}" koşulu 16–80 yaş aralığının tamamına uygulanıyor.
Ham train verisinde (ağırlıklı medyan, tipik kilo bandı) 16–20 yaş arası yıllık değişim:

{_md(teen)}

Gençlerde yıllık artış verinin kendisinde %4'ün üzerinde olabildiğinden, veriye sadık bir model bu koşulu
16–17 yaşta ihlal edebilir. Kriter değiştirilmedi (§4.3); `docs/ILERLEME.md` Ertelenenler'e açık soru olarak yazıldı.

## Eğitim aralığı dışı davranış ({primary})

Kırpma sayesinde çıktı sonlu, pozitif ve sıralı; `sınırla_aynı` sütunu çıktının kırpılmış girdiyle birebir
aynı olduğunu gösterir. Birim testi: `tests/test_neural.py::test_out_of_range_inputs_do_not_explode`
(yaş 1–150, kilo 5–1000 kg).

{_md(oor, "{:.1f}")}

## Dış doğrulama: van den Hoek 2024

{_md(ext_df)}

## Yüzdelik eğrileri (A/B ile aynı grafik seti)

![erkek 30 yaş](candidate_c/percentiles_M30.png)

![kadın 30 yaş](candidate_c/percentiles_F30.png)

![erkek 55 yaş](candidate_c/percentiles_M55.png)

## Kaldırışlar arası korelasyon (§4.4)

Nüfus ortalaması R (train SBD satırları üzerinde ağırlıklı R(x) ortalaması; `params_draft/correlation.json`
→ `matrix`):

{_fmt_mat(R_pop)}

Karşılaştırma — doğrulama SBD satırlarında normal skorların ağırlıklı ampirik Pearson korelasyonu:

{_fmt_mat(R_emp_val)}

Doğrulama SBD kopula NLL (satır başına, 0 = bağımsızlık): {", ".join(f"{h} {v:.4f}" for h, v in cop_val.items())}.

Koşullu R(x) ızgarası ({primary}):

{_md(grid_df)}

Izgarada çift korelasyonları {lo_r:.3f} – {hi_r:.3f}; beklenen 0.4–0.9 aralığında ve pozitif tanımlı:
**{"evet" if in_range else "HAYIR"}**. P048 EDA artık korelasyonları (~0.70–0.84) ile uyumlu.

## Yorum

{_commentary(results, primary, gain)}
"""
    (REPORTS / "candidate_c.md").write_text(md, encoding="utf-8")
    (FIGS / "summary.json").write_text(
        json.dumps(table.to_dicts(), indent=2, ensure_ascii=False), encoding="utf-8"
    )
    print(both)
    print(_fmt_mat(R_pop))


def _commentary(results, primary, gain: pl.DataFrame) -> str:
    lines = []
    g = gain.filter(pl.col("model") == f"neural_{primary}")
    better = g.filter(pl.col("pinball_iyileşme_%") > 0)["lift"].to_list()
    lines.append(
        f"- Pinball'da birincil başlık en iyi temel çizgiyi {len(better)}/3 kaldırışta geçiyor "
        f"({', '.join(better) or '—'}); iyileşme "
        + ", ".join(f"{r['lift']} {r['pinball_iyileşme_%']:+.1f}%" for r in g.iter_rows(named=True))
        + "."
    )
    fails = sorted(
        {
            f"{name}/{r.lift}: {s.name}"
            for name, rs in results.items()
            for r in rs
            for s in r.sanity
            if not s.passed
        }
    )
    lines.append(
        "- Akıl sağlığı: "
        + ("tümü geçti." if not fails else "başarısız olanlar — " + "; ".join(fails) + ".")
    )
    gates = [
        f"{name}/{r.lift} {'✅' if r.metrics['coverage_gate_pass'] else '❌'} "
        f"(bant dışı {r.metrics['strata_failing_noise_aware']}/{r.metrics['strata']} = "
        f"%{r.metrics['strata_outside_share'] * 100:.0f})"
        for name, rs in results.items()
        for r in rs
    ]
    lines.append(
        "- Kalibrasyon kapısı (§4.3, onaylı yorum: katman sapması ≤ max(2 puan, gürültü bandı), bandı "
        "aşan katman ≤ %10): " + ", ".join(gates) + "."
    )
    lines.append(
        "- Hiperparametreler (genişlik/derinlik/aktivasyon/ağırlık azaltma/öğrenme hızı/başlık) P053'te Optuna ile\n"
        "  aranacak; bu rapor tek bir makul varsayılan yapılandırmayı gösterir."
    )
    return "\n".join(lines)


if __name__ == "__main__":
    run()
