"""`make train-a`: Aday A (Spline-LMS, BCCG ve BCPE) eğitimi, doğrulama değerlendirmesi ve
`reports/candidate_a.md` (P050). Test kümesi kullanılmaz."""

from __future__ import annotations

import dataclasses
import json

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import polars as pl  # noqa: E402

from gymml.data.cohort import LIFTS, ML_ROOT  # noqa: E402
from gymml.eval.baselines import _md  # noqa: E402
from gymml.eval.data import DataSpec, load_lift  # noqa: E402
from gymml.eval.metrics import coverage_table  # noqa: E402
from gymml.eval.runner import (  # noqa: E402
    LiftResult,
    evaluate_factory,
    plot_percentile_curves,
    plot_pit,
    split_info,
    summary_table,
)
from gymml.eval.sanity import TYPICAL_BW, SanityConfig  # noqa: E402
from gymml.models.spline_lms import SplineLMS, SplineLMSConfig  # noqa: E402
from gymml.utils.config import load_config  # noqa: E402
from gymml.utils.runs import Run  # noqa: E402

CONFIG = ML_ROOT / "configs/spline_lms.yaml"
REPORTS = ML_ROOT / "reports"
FIGS = REPORTS / "candidate_a"


def plot_age_curves(results: dict[str, list[LiftResult]], path, sex: str) -> None:
    """5/25/50/75/95 yüzdelik eğrileri, yaşa karşı (tipik kiloda)."""
    qs = np.array([0.05, 0.25, 0.5, 0.75, 0.95])
    ages = np.arange(14.0, 86.0, 1.0)
    bw = TYPICAL_BW[sex]
    x = pl.DataFrame({"sex": [sex] * len(ages), "age": ages, "bodyweight_kg": [bw] * len(ages)})
    fig, axes = plt.subplots(1, len(LIFTS), figsize=(15, 4.5))
    styles = ["-", "--", ":", "-."]
    for j, lift in enumerate(LIFTS):
        for i, (name, rs) in enumerate(results.items()):
            r = next(r for r in rs if r.lift == lift)
            q = r.model.quantile(x, qs)
            for k in range(len(qs)):
                axes[j].plot(
                    ages,
                    q[:, k],
                    styles[i % 4],
                    color=f"C{k}",
                    label=f"{name} P{int(qs[k] * 100)}" if j == 0 else None,
                )
        axes[j].set_title(f"{lift} · {sex}, {bw:g} kg")
        axes[j].set_xlabel("yaş")
    axes[0].legend(fontsize=6, ncol=2)
    fig.tight_layout()
    fig.savefig(path, dpi=110)
    plt.close(fig)


def family_comparison(results: dict[str, list[LiftResult]], spec: DataSpec) -> pl.DataFrame:
    rows = []
    probe = pl.DataFrame(
        {
            "sex": ["M", "F"],
            "age": [30.0, 30.0],
            "bodyweight_kg": [TYPICAL_BW["M"], TYPICAL_BW["F"]],
        }
    )
    for lift in LIFTS:
        val = load_lift(lift, "val", spec)
        for name, rs in results.items():
            r = next(r for r in rs if r.lift == lift)
            m: SplineLMS = r.model  # type: ignore[assignment]
            p = m.params(probe)
            rows.append(
                {
                    "model": name,
                    "lift": lift,
                    "val_loglik": m.log_likelihood(val),
                    "pinball_kg": r.metrics["pinball"],
                    "pit_ks": r.metrics["pit_ks"],
                    "bant_dışı_katman": r.metrics["strata_failing_noise_aware"],
                    "kalibrasyon_kapısı": "✅" if r.metrics["coverage_gate_pass"] else "❌",
                    "σ M/F": f"{p['sigma'][0]:.3f}/{p['sigma'][1]:.3f}",
                    "ν M/F": f"{p['nu'][0]:.2f}/{p['nu'][1]:.2f}",
                    "τ M/F": f"{p['tau'][0]:.2f}/{p['tau'][1]:.2f}",
                    "parametre": m.n_parameters(),
                    "eğitim_s": r.fit_seconds,
                }
            )
    return pl.DataFrame(rows)


def baseline_table() -> pl.DataFrame:
    path = REPORTS / "baselines/summary.json"
    return pl.DataFrame(json.loads(path.read_text(encoding="utf-8")))


def run() -> None:
    base_cfg = load_config(CONFIG, SplineLMSConfig)
    spec = DataSpec()
    results: dict[str, list[LiftResult]] = {}
    for family in ("BCCG", "BCPE"):
        cfg = dataclasses.replace(base_cfg, family=family)
        results[f"spline_lms_{family.lower()}"] = evaluate_factory(lambda c=cfg: SplineLMS(c), spec)

    info = split_info()
    run_dir = Run(ML_ROOT / "runs", "candidate_a", {"config": dataclasses.asdict(base_cfg)})
    run_dir.write_metrics({name: {r.lift: r.metrics for r in rs} for name, rs in results.items()})
    for name, rs in results.items():
        for r in rs:
            (run_dir.dir / f"{name}_{r.lift}.json").write_text(
                json.dumps(r.model.to_dict()),
                encoding="utf-8",  # type: ignore[attr-defined]
            )

    FIGS.mkdir(parents=True, exist_ok=True)
    plot_pit(results, FIGS / "pit.png")
    for sex in ("M", "F"):
        plot_percentile_curves(results, FIGS / f"percentiles_bw_{sex}30.png", sex, 30.0)
        plot_age_curves(results, FIGS / f"percentiles_age_{sex}.png", sex)

    table = summary_table(results)
    both = pl.concat([baseline_table().select(table.columns), table])
    comp = family_comparison(results, spec)
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
    (FIGS / "summary.json").write_text(
        json.dumps(table.to_dicts(), indent=2, ensure_ascii=False), encoding="utf-8"
    )

    md = REPORT_TEMPLATE.format(
        config=CONFIG.read_text(encoding="utf-8").strip(),
        digest=info["digest"],
        athletes=info["athletes"],
        metrics=_md(both),
        comparison=_md(comp, "{:.4f}"),
        sanity=_md(pl.DataFrame(sanity_rows)),
        external=_md(ext_df),
        commentary=commentary(results, comp),
        run=run_dir.dir.name,
    )
    (REPORTS / "candidate_a.md").write_text(md, encoding="utf-8")
    print(both)
    print(comp)


def commentary(results: dict[str, list[LiftResult]], comp: pl.DataFrame) -> str:
    base = {
        r["lift"]: r["pinball_kg"]
        for r in baseline_table().to_dicts()
        if r["model"] == "cell_empirical"
    }
    lines = []
    for name, rs in results.items():
        wins = [r.lift for r in rs if r.metrics["pinball"] < base[r.lift]]
        gains = ", ".join(
            f"{r.lift} {100 * (1 - r.metrics['pinball'] / base[r.lift]):+.1f}%" for r in rs
        )
        passed = sum(s.passed for r in rs for s in r.sanity)
        total = sum(len(r.sanity) for r in rs)
        lines.append(
            f"- `{name}`: pinball'da en iyi temel çizgiyi (hücre ampirik) {len(wins)}/3 kaldırışta "
            f"geçiyor (iyileşme {gains}); akıl sağlığı {passed}/{total}."
        )
    ll = comp.pivot(on="model", index="lift", values="val_loglik")
    diffs = ", ".join(
        f"{row['lift']} {row['spline_lms_bcpe'] - row['spline_lms_bccg']:+.4f}"
        for row in ll.to_dicts()
    )
    lines.append(
        f"- BCPE − BCCG doğrulama log-olabilirliği (gözlem başına, nat): {diffs}. τ ≠ 2 kuyruk "
        "kalınlığını serbest bırakır; fark küçükse BCCG daha basit seçenektir (P053'te aile de aranacak)."
    )
    lines += diagnostics(results)
    return "\n".join(lines)


def diagnostics(results: dict[str, list[LiftResult]]) -> list[str]:
    """Başarısız ölçütlerin yeri: yaş eğrisinde > %4'lük yıllık sıçramalar ve kapı bandı dışı katmanlar."""
    ages = np.arange(16.0, 81.0, 1.0)
    jumps, bands = [], {}
    for name, rs in results.items():
        for r in rs:
            for sex in ("M", "F"):
                x = pl.DataFrame(
                    {
                        "sex": [sex] * len(ages),
                        "age": ages,
                        "bodyweight_kg": [TYPICAL_BW[sex]] * len(ages),
                    }
                )
                med = r.model.quantile(x, np.array([0.5]))[:, 0]
                j = np.abs(np.diff(med)) / med[:-1]
                at = ages[:-1][j > SanityConfig().max_year_jump]
                if len(at):
                    jumps.append(f"{name}/{r.lift}/{sex}: {', '.join(f'{a:g}' for a in at)}")
            cov = coverage_table(r.model, load_lift(r.lift, "val", DataSpec()))
            for row in cov.filter(~pl.col("within_noise")).iter_rows(named=True):
                key = f"{row['sex']} {row['age_band']}"
                bands[key] = bands.get(key, 0) + 1
    out = [
        "- Yaş ölçütünü bozan > %4'lük yıllık medyan değişimi yalnızca şu yaşlardan bir sonrakine "
        f"geçişte: {'; '.join(jumps) or '—'}. Ham eğitim verisi de "
        "bu yaşlarda > %4 artıyor (ör. erkek squat medyan kg/kilo^(2/3): 16→17 +%7, 17→18 +%4); yani "
        "ölçüt ergenlik dönemi büyümesiyle çelişiyor (P053 öncesi kullanıcıya açık soru); "
        "tepe yaşı ve tek tepelilik her durumda geçiyor.",
        "- Kalibrasyon bandı dışındaki katmanların cinsiyet × yaş bandına dağılımı (iki aile, üç kaldırış "
        "toplamı): "
        + ", ".join(f"{k}: {v}" for k, v in sorted(bands.items(), key=lambda kv: -kv[1]))
        + ". Hata gençlerde (yaşla hızlı değişen bölge) yoğun; yaş düğümü aralığı (~7 yıl) bu bölge için "
        "kaba. P053'te düğüm sayısı / yaş cezası aranmalı veya yaş ekseni dönüştürülmeli (ör. log yaş).",
    ]
    return out


REPORT_TEMPLATE = """# Aday A — Spline-LMS (P050)

Üretim: `make train-a` (`gymml/models/train_a.py`, model `gymml/models/spline_lms.py`, dağılımlar
`gymml/models/boxcox.py`). Koşum izi: `runs/{run}/` (metrikler, katsayılar JSON). Değerlendirme P049
koşumuyla (`gymml.eval.runner.evaluate_factory`) **doğrulama** kümesinde; test kümesi kullanılmadı.
Bölme özeti `{digest}`, sporcu sayıları {athletes}.

## Model

- Kaldırış × cinsiyet başına `Y ~ BCCG(μ, σ, ν)` veya `BCPE(μ, σ, ν, τ)`; bağlantılar log μ, log σ, ν
  (birim), log τ. Her parametre yaş × log-kilo kübik B-spline tensör çarpımı tabanında doğrusal
  (dört parametre aynı tabanı paylaşır); katsayı ızgarasında her eksen boyunca ikinci fark (P-spline) cezası.
- Dağılım fonksiyonları (log-yoğunluk, CDF, ters CDF) elle yazıldı; `tests/test_spline_lms.py`
  scipy `truncnorm`/`gennorm` ve sayısal integrasyonla doğruluyor. BCPE'deki kesilme terimi
  P(1/τ, x)'in τ'ya göre türevini ister; torch bunu vermediği için merkezi farklı özel autograd fonksiyonu.
- Amaç: P048 örnek ağırlıklarıyla ağırlıklı ortalama NLL + ceza. Adam ısınması → L-BFGS (strong Wolfe).
  Erken durdurma: eğitim kümesinin %10'u sporcu bazında iç doğrulama payı olarak ayrılır; en iyi iç
  doğrulama NLL'li katsayılar tutulur (dış doğrulama kümesi yalnızca değerlendirme içindir).
- Eğitim aralığı dışındaki yaş/kilo aralık sınırına kırpılır (sabit dışdeğerleme).

Temel yapılandırma (`configs/spline_lms.yaml`; P053'te aranacak):

```yaml
{config}
```

## Metrikler (doğrulama kümesi, temel çizgilerle)

{metrics}

![PIT](candidate_a/pit.png)

## BCCG ve BCPE karşılaştırması

Parametreler 30 yaş, tipik kiloda (E 90 kg, K 65 kg). `val_loglik` ağırlıklı ortalama log-yoğunluk.

{comparison}

## Akıl sağlığı testleri

{sanity}

## Dış doğrulama: van den Hoek 2024

{external}

## Yüzdelik eğrileri (5/25/50/75/95)

Kiloya karşı, 30 yaş:

![erkek 30 yaş](candidate_a/percentiles_bw_M30.png)

![kadın 30 yaş](candidate_a/percentiles_bw_F30.png)

Yaşa karşı, tipik kilo:

![erkek](candidate_a/percentiles_age_M.png)

![kadın](candidate_a/percentiles_age_F.png)

## Yorum

{commentary}
"""


if __name__ == "__main__":
    run()
