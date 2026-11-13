"""`make train-b`: Aday B (LightGBM çeyreklik), kısıtlı + kısıtsız, ortak koşumla doğrulamada.

Çıktı: `reports/candidate_b.md`, `reports/candidate_b/` (grafikler, summary.json),
`runs/*-candidate_b/`.
Test kümesi kullanılmaz.
"""

from __future__ import annotations

import json

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import polars as pl  # noqa: E402

from gymml.data.cohort import LIFTS, ML_ROOT  # noqa: E402
from gymml.eval.baselines import _md  # noqa: E402
from gymml.eval.data import DataSpec, load_lift  # noqa: E402
from gymml.eval.runner import (  # noqa: E402
    LiftResult,
    evaluate_factory,
    plot_percentile_curves,
    plot_pit,
    split_info,
    summary_table,
)
from gymml.models.lgbm_quantile import (  # noqa: E402
    DEFAULT_PARAMS,
    NUM_ROUNDS,
    TAIL_POINTS,
    TAIL_SLOPE_BOUNDS,
    LGBMQuantile,
)
from gymml.utils.config import load_config  # noqa: E402
from gymml.utils.runs import Run  # noqa: E402

VARIANTS = {"lgbm_mono": True, "lgbm_free": False}
SIZE_LIMIT_BYTES = 1_000_000  # §4.3 madde 4
LATENCY_LIMIT_MS = 1.0


def deployment_rows(results: dict[str, list[LiftResult]], spec: DataSpec) -> pl.DataFrame:
    rows = []
    for lift in LIFTS:
        val = load_lift(lift, "val", spec)
        for name, rs in results.items():
            m = next(r for r in rs if r.lift == lift).model
            assert isinstance(m, LGBMQuantile)
            size = m.size_bytes()
            ms = m.single_inference_ms(val)
            rows.append(
                {
                    "model": name,
                    "lift": lift,
                    "kesişme_eğitim_%": 100 * m.crossing_rate,
                    "kesişme_doğrulama_%": 100 * m.measure_crossing(val),
                    "boyut_MB": size / 1e6,
                    "boyut<1MB": "✅" if size < SIZE_LIMIT_BYTES else "❌",
                    "tek_çıkarım_ms": ms,
                    "çıkarım<1ms": "✅" if ms < LATENCY_LIMIT_MS else "❌",
                }
            )
    return pl.DataFrame(rows)


def plot_steps(results: dict[str, list[LiftResult]], path) -> None:
    """Basamaklılığı gösteren yakın çekim: medyan, kiloya (0.1 kg) ve yaşa (0.1 yıl) karşı."""
    fig, axes = plt.subplots(2, len(LIFTS), figsize=(15, 7))
    bws = np.arange(70.0, 100.0, 0.1)
    ages = np.arange(18.0, 60.0, 0.1)
    xb = pl.DataFrame({"sex": ["M"] * len(bws), "age": [30.0] * len(bws), "bodyweight_kg": bws})
    xa = pl.DataFrame({"sex": ["M"] * len(ages), "age": ages, "bodyweight_kg": [90.0] * len(ages)})
    for j, lift in enumerate(LIFTS):
        for name, rs in results.items():
            m = next(r for r in rs if r.lift == lift).model
            axes[0, j].plot(bws, m.quantile(xb, np.array([0.5]))[:, 0], label=name)
            axes[1, j].plot(ages, m.quantile(xa, np.array([0.5]))[:, 0], label=name)
        axes[0, j].set_title(f"{lift} · medyan, M 30 yaş")
        axes[0, j].set_xlabel("vücut ağırlığı (kg)")
        axes[1, j].set_title(f"{lift} · medyan, M 90 kg")
        axes[1, j].set_xlabel("yaş")
    axes[0, 0].legend()
    fig.tight_layout()
    fig.savefig(path, dpi=110)
    plt.close(fig)


def baseline_table() -> pl.DataFrame | None:
    path = ML_ROOT / "reports/baselines/summary.json"
    if not path.exists():
        return None
    return pl.DataFrame(json.loads(path.read_text(encoding="utf-8")))


def comparison(table: pl.DataFrame, base: pl.DataFrame | None) -> pl.DataFrame:
    rows = []
    for lift in LIFTS:
        row: dict = {"lift": lift}
        for name in VARIANTS:
            row[name] = table.filter((pl.col("model") == name) & (pl.col("lift") == lift))[
                "pinball_kg"
            ].item()
        if base is not None:
            for name in ("cell_empirical", "dots_empirical"):
                b = base.filter((pl.col("model") == name) & (pl.col("lift") == lift))
                row[name] = b["pinball_kg"].item()
            best = min(row["cell_empirical"], row["dots_empirical"])
            row["mono_vs_en_iyi_temel_%"] = 100 * (row["lgbm_mono"] / best - 1)
        rows.append(row)
    return pl.DataFrame(rows)


def run() -> None:
    cfg = load_config(ML_ROOT / "configs/smoke.yaml")
    spec = DataSpec()
    results = {
        name: evaluate_factory(lambda mono=mono: LGBMQuantile(monotone=mono), spec)
        for name, mono in VARIANTS.items()
    }
    info = split_info()
    run_cfg = {
        "spec": spec.__dict__,
        "split": info,
        "num_rounds": NUM_ROUNDS,
        "params": DEFAULT_PARAMS,
        "tail": {"points": TAIL_POINTS, "slope_bounds": list(TAIL_SLOPE_BOUNDS)},
    }
    run_dir = Run(ML_ROOT / cfg.paths.runs, "candidate_b", run_cfg)
    table = summary_table(results)
    deploy = deployment_rows(results, spec)
    run_dir.write_metrics(
        {
            "metrics": {n: {r.lift: r.metrics for r in rs} for n, rs in results.items()},
            "deployment": deploy.to_dicts(),
            "fit_seconds": {n: {r.lift: r.fit_seconds for r in rs} for n, rs in results.items()},
        }
    )

    reports = ML_ROOT / "reports"
    figs = reports / "candidate_b"
    figs.mkdir(parents=True, exist_ok=True)
    plot_pit(results, figs / "pit.png")
    plot_percentile_curves(results, figs / "percentiles_M30.png", "M", 30.0)
    plot_percentile_curves(results, figs / "percentiles_F30.png", "F", 30.0)
    plot_steps(results, figs / "steps.png")

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
    comp = comparison(table, baseline_table())
    fit_s = {n: sum(r.fit_seconds for r in rs) for n, rs in results.items()}

    md = f"""# Aday B — LightGBM çeyreklik (P051)

Üretim: `make train-b` (`gymml/models/train_b.py`, model `gymml/models/lgbm_quantile.py`).
Koşum izi: `runs/*-candidate_b/`. Değerlendirme P049 ortak koşumu
(`gymml.eval.runner.evaluate_factory`),
**doğrulama** kümesi; test kümesi kullanılmadı. Bölme özeti `{info["digest"]}` (temel çizgilerle
aynı).

## Model

- Kaldırış başına 19 ayrı LightGBM (q = 0.05…0.95), girdiler cinsiyet, yaş, kilo, log-kilo.
- Hedef standartlaştırılmış log-yük; kayıtlar 2.5 kg adımlı olduğundan eğitimden önce ±1.25 kg
  titreştirilir
  (temel çizgilerle aynı varsayım). Örnek ağırlıkları `weight` (sporcu başına toplam 1).
- **Pinball kaybı özel hedef olarak** yazıldı: LightGBM'in yerleşik `quantile` hedefi
  `monotone_constraints` ile birlikte kullanılamıyor (yaprakları ağaç kurulduktan sonra yeniden
  hesaplar).
  Kısıtlı (`lgbm_mono`: kilo ve log-kilo artan) ve kısıtsız (`lgbm_free`) sürümler aynı hedefi ve
  aynı
  hiperparametreleri kullanır: {NUM_ROUNDS} tur, {DEFAULT_PARAMS}. Hiperparametre araması P053'te.
- Kesişme: 19 çeyrek satır başına yeniden sıralanır (izotonik yeniden sıralama). Oranlar aşağıda.
- Kuyruk (< 0.05, > 0.95): log Q – lojit(p) ölçeğinde doğrusal ekstrapolasyon; eğim her uçta en
  dıştaki
  {TAIL_POINTS} çeyreğin en küçük kareler doğrusundan, genel 5–95 eğiminin {TAIL_SLOPE_BOUNDS[0]}–
  {TAIL_SLOPE_BOUNDS[1]} katına kırpılarak. **Zayıflık:** kuyruk biçimi veriden öğrenilmez
  (yalnızca dış
  çeyreklerin eğimini taşır); P1–P4 ve P96–P99 skorları kaba ve satırdan satıra gürültülüdür; eğim
  kiloyla
  değiştiği için kuyruk bölgesinde kiloda monotonluk garanti değildir. İlk deneme (yalnızca iki
  komşu
  çeyreğin eğimi) sentetik veride Q99/Q95'i gerçeğin ~1.5 katı kadar şişirdi; bu yüzden kırpma
  eklendi.
- Sürekli CDF: 19 çeyrek lojit(p) ölçeğinde doğrusal enterpole edilip 0.005…0.995 ızgarasına
  taşınır,
  ızgarada doğrusal CDF (`QuantileGridMixin`).
- Toplam eğitim süresi (3 kaldırış): {", ".join(f"{n} {s:.0f} s" for n, s in fit_s.items())}.

## Metrikler (doğrulama kümesi)

{_md(table)}

### Temel çizgilerle pinball karşılaştırması (kg; `reports/baselines.md`)

{_md(comp)}

![PIT](candidate_b/pit.png)

## Kesişme, boyut ve çıkarım süresi

Boyut: 19 ağacın LightGBM metin dökümü toplamı (sıkıştırmasız). Tek çıkarım: Python'da bir satır
için
19 çeyrek + ızgara + enterpolasyon (50 tekrar ortalaması); cihazdaki Core ML süresi değildir.

{_md(deploy)}

## Akıl sağlığı testleri

{_md(pl.DataFrame(sanity_rows))}

## Dış doğrulama: van den Hoek 2024

{_md(ext_df)}

## Yüzdelik eğrileri

Aday A (P050) kodu henüz main'de olmadığından A ile yan yana grafik burada üretilmedi; P053'te
(model
yarışması) üç aday aynı `plot_percentile_curves` çağrısıyla birlikte çizilecek.

![erkek 30 yaş](candidate_b/percentiles_M30.png)

![kadın 30 yaş](candidate_b/percentiles_F30.png)

Basamaklılık (0.1 kg / 0.1 yıl adımla medyan):

![basamaklar](candidate_b/steps.png)

## Yorum

{_commentary(results, table, deploy, comp)}
"""
    (reports / "candidate_b.md").write_text(md, encoding="utf-8")
    (figs / "summary.json").write_text(
        json.dumps(
            {"metrics": table.to_dicts(), "deployment": deploy.to_dicts()},
            indent=2,
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    print(table)
    print(deploy)


def _commentary(results, table: pl.DataFrame, deploy: pl.DataFrame, comp: pl.DataFrame) -> str:
    lines = []
    if "cell_empirical" in comp.columns:
        beat = comp.filter(pl.col("mono_vs_en_iyi_temel_%") < 0)["lift"].to_list()
        gains = ", ".join(
            f"{r['lift']} {r['mono_vs_en_iyi_temel_%']:+.1f}%" for r in comp.iter_rows(named=True)
        )
        lines.append(
            f"- Pinball: `lgbm_mono` en iyi temel çizgiyi {len(beat)}/3 kaldırışta geçiyor"
            f" ({gains})."
        )
    mono = table.filter(pl.col("model") == "lgbm_mono")["pinball_kg"].to_numpy()
    free = table.filter(pl.col("model") == "lgbm_free")["pinball_kg"].to_numpy()
    lines.append(
        "- Kısıtlı vs kısıtsız: pinball farkı "
        f"{100 * (mono.sum() / free.sum() - 1):+.2f}% (kısıtın maliyeti). Kısıt 19 çeyreği kiloda"
        " azalmayan yapar; kilo testindeki kalan ihlal (en büyük CDF artışı 0.005–0.010, kısıtsızda"
        " 0.13–0.16) yalnızca P95 üstü kuyrukta: squat'ta M 20 yaş, 45→46 kg'da CDF 0.990 → 1.000"
        " (kuyruk eğimi kiloyla değişiyor ve ızgara 0.995'te bitiyor). Kuyruğu kiloda monoton"
        " yapmak (ör. eğimi kiloya göre sabitlemek) P053'e bırakıldı."
    )
    lines.append(
        "- Sıklet sınırı izi: kısıtsız medyan 74/83/93 kg civarında yükselip sınırın hemen üstünde"
        " 10–20 kg düşüyor (IPF sıklet sınırlarında tartıya en ağır gelenler daha güçlü; bir"
        " sonraki"
        " sıkletin en hafifleri daha zayıf). Bu, kohort verisinin yapısal bir yanlılığı; uygulama"
        " kullanıcısı için anlamsız. Kısıtlı sürüm dişleri yatay basamaklara çeviriyor"
        " (`steps.png`). Pürüzsüz adaylar (A, C) için de bu etki P053'te izlenmeli."
    )
    sanity_pass = {n: sum(s.passed for r in rs for s in r.sanity) for n, rs in results.items()}
    lines.append(
        f"- Akıl sağlığı (15 test, 3 kaldırış): {sanity_pass}. Ağaç modeli parçalı sabit olduğundan"
        " pürüzsüzlük (Δ² sınırı) ve yaş eğrisinin tek tepeliliği/yıllık sıçrama ölçütleri yapısal"
        " olarak karşılanamıyor — §4.2'deki 'basamaklı çıktı' eksisi burada ölçülmüş oluyor."
    )
    big = deploy["boyut_MB"].max()
    lines.append(
        f"- Dağıtım kısıtı (§4.3 madde 4): model boyutu {deploy['boyut_MB'].min():.1f}–"
        f"{big:.1f} MB, < 1 MB sınırının çok üstünde (19 × 400 ağaç). Tek çıkarım < 1 ms"
        " karşılanıyor. Boyut ancak"
        " çok daha az/sığ ağaçla (P053 araması) düşer; bu da doğruluğu düşürür."
    )
    xr = deploy["kesişme_doğrulama_%"]
    lines.append(
        f"- Kesişme: doğrulama satırlarının %{xr.min():.1f}–%{xr.max():.1f}'inde en az bir komşu"
        " çeyrek çifti kesişiyor; yeniden sıralama sonrası kesişme 0"
        " (metriklerdeki `crossing_rate`)."
    )
    lines.append(
        "- Kalibrasyon kapısı (§4.3, 2026-11-13 onaylı yorum: katman sapması ≤ max(2 puan, gürültü"
        " bandı), bandı aşan katman ≤ %10): "
        + ", ".join(
            f"{n}/{r.lift} {'✅' if r.metrics['coverage_gate_pass'] else '❌'}"
            f" (%{100 * r.metrics['strata_outside_share']:.0f} bant dışı)"
            for n, rs in results.items()
            for r in rs
        )
        + "."
    )
    return "\n".join(lines)


if __name__ == "__main__":
    run()
