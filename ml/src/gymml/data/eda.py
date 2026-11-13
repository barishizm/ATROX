"""P048 keşif analizi: `reports/eda.md` + `reports/eda/*.png`.

`make eda` kohort tablolarını yeniden üretir (gymml.data.cohort) ve raporu yazar.
"""

from __future__ import annotations

import dataclasses
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import polars as pl  # noqa: E402

from gymml.data.cohort import (  # noqa: E402
    AGE_BAND_EDGES,
    BW_BAND_EDGES,
    LIFTS,
    ML_ROOT,
    CohortConfig,
    age_class_midpoint,
    band_labels,
    build,
    write,
)
from gymml.utils.config import load_config  # noqa: E402

SPARSE_N = 500  # P049 kalibrasyon katmanı alt sınırı (docs/03-ML-MODEL.md §4.3)
SEX_COLORS = {"M": "#1f6feb", "F": "#d1495b"}


def _md_table(df: pl.DataFrame, floatfmt: str = "{:.1f}") -> str:
    cols = df.columns
    lines = ["| " + " | ".join(cols) + " |", "|" + "---|" * len(cols)]
    for row in df.iter_rows():
        cells = []
        for v in row:
            if isinstance(v, float):
                cells.append(floatfmt.format(v))
            elif isinstance(v, int) and not isinstance(v, bool):
                cells.append(f"{v:,}")
            else:
                cells.append(str(v))
        lines.append("| " + " | ".join(cells) + " |")
    return "\n".join(lines)


def _raw(long: pl.DataFrame) -> pl.DataFrame:
    """Model hedefi: wraps'sız (squat için Raw) satırlar."""
    return long.filter(~pl.col("wraps"))


def age_imputation_effect(opl: pl.DataFrame, cfg: CohortConfig) -> tuple[str, dict]:
    """Yaşı boş kayıtlar için AgeClass orta noktası kullanmanın etkisi."""
    both = opl.filter(pl.col("age").is_not_null() & pl.col("age_class").is_not_null())
    err = (age_class_midpoint(pl.col("age_class")) - pl.col("age").cast(pl.Float64)).abs()
    e = both.select(err.mean().alias("mae"), err.quantile(0.9).alias("p90")).row(0, named=True)

    base = build(opl, dataclasses.replace(cfg, impute_age_from_class=False)).long
    imp = build(opl, dataclasses.replace(cfg, impute_age_from_class=True)).long
    imp_rows = _raw(imp).filter(pl.col("age_imputed"))
    exact_rows = _raw(imp).filter(~pl.col("age_imputed"))

    def med(d: pl.DataFrame, name: str) -> pl.DataFrame:
        return d.group_by("sex", "lift", "age_band").agg(
            pl.col("value_kg").median().alias(name), pl.len().alias(f"n_{name}")
        )

    cmp = (
        med(exact_rows, "exact")
        .join(med(imp_rows, "imputed"), on=["sex", "lift", "age_band"])
        .filter(pl.col("n_imputed") >= SPARSE_N)
        .with_columns(diff_pct=(pl.col("imputed") / pl.col("exact") - 1) * 100)
        .sort("sex", "lift", "age_band")
    )
    summary = (
        cmp.group_by("lift")
        .agg(
            pl.col("diff_pct").mean().alias("ortalama_fark_%"),
            pl.col("diff_pct").abs().max().alias("en_büyük_|fark|_%"),
        )
        .sort("lift")
    )
    stats = {
        "mae_years": e["mae"],
        "p90_years": e["p90"],
        "rows_without": base.height,
        "rows_with": imp.height,
        "imputed_rows": imp.filter(pl.col("age_imputed")).height,
        "mean_abs_diff_pct": float(cmp["diff_pct"].abs().mean()),
    }
    text = f"""Yaşı bilinen ve sınıfı da olan kayıtlarda orta noktanın hatası: ortalama {e["mae"]:.2f} yıl,
%90'lık {e["p90"]:.1f} yıl. Orta nokta kullanılırsa kohort {stats["rows_without"]:,} → {stats["rows_with"]:,}
satır olur ({stats["imputed_rows"]:,} satırın yaşı tahmini).

Aynı cinsiyet × kaldırış × yaş bandında, yaşı tahmini satırların medyanının gerçek yaşlı satırlara göre farkı
(yalnızca n ≥ {SPARSE_N} olan hücreler; ortalama |fark| %{stats["mean_abs_diff_pct"]:.1f}):

{_md_table(summary)}
"""
    return text, stats


def plot_distributions(long: pl.DataFrame, out: Path) -> None:
    fig, axes = plt.subplots(2, 3, figsize=(14, 7))
    for j, lift in enumerate(LIFTS):
        d = _raw(long).filter(pl.col("lift") == lift)
        for sex, color in SEX_COLORS.items():
            s = d.filter(pl.col("sex") == sex)
            axes[0, j].hist(
                s["value_kg"], bins=120, alpha=0.55, color=color, label=sex, density=True
            )
            axes[1, j].hist(
                (s["value_kg"] / s["bodyweight_kg"]),
                bins=120,
                alpha=0.55,
                color=color,
                label=sex,
                density=True,
            )
        axes[0, j].set_title(f"{lift} (kg)")
        axes[1, j].set_title(f"{lift} / vücut ağırlığı")
        axes[0, j].legend()
    fig.tight_layout()
    fig.savefig(out, dpi=110)
    plt.close(fig)


def median_curve(d: pl.DataFrame, x: str, step: float, min_n: int = 50) -> pl.DataFrame:
    return (
        d.with_columns(((pl.col(x) / step).floor() * step + step / 2).alias("bin"))
        .group_by("bin")
        .agg(
            pl.col("value_kg").quantile(0.1).alias("p10"),
            pl.col("value_kg").median().alias("p50"),
            pl.col("value_kg").quantile(0.9).alias("p90"),
            pl.len().alias("n"),
        )
        .filter(pl.col("n") >= min_n)
        .sort("bin")
    )


def plot_curves(long: pl.DataFrame, x: str, step: float, xlabel: str, out: Path) -> None:
    fig, axes = plt.subplots(1, 3, figsize=(15, 4.5))
    for j, lift in enumerate(LIFTS):
        d = _raw(long).filter(pl.col("lift") == lift)
        for sex, color in SEX_COLORS.items():
            c = median_curve(d.filter(pl.col("sex") == sex), x, step)
            axes[j].plot(c["bin"], c["p50"], color=color, label=f"{sex} medyan")
            axes[j].fill_between(c["bin"], c["p10"], c["p90"], color=color, alpha=0.15)
        axes[j].set_title(f"{lift}: medyan ve %10–90")
        axes[j].set_xlabel(xlabel)
        axes[j].set_ylabel("kg")
        axes[j].legend()
    fig.tight_layout()
    fig.savefig(out, dpi=110)
    plt.close(fig)


def peak_ages(long: pl.DataFrame, tol: float = 0.01) -> pl.DataFrame:
    rows = []
    for lift in LIFTS:
        for sex in ("M", "F"):
            c = median_curve(
                _raw(long).filter((pl.col("lift") == lift) & (pl.col("sex") == sex)),
                "age",
                1.0,
                200,
            )
            top = c["p50"].max()
            near = c.filter(pl.col("p50") >= top * (1 - tol))
            rows.append(
                {
                    "lift": lift,
                    "sex": sex,
                    "tepe_kg": top,
                    "tepe_yaş_aralığı": f"{near['bin'].min() - 0.5:.0f}–{near['bin'].max() - 0.5:.0f}",
                }
            )
    return pl.DataFrame(rows)


def tested_vs_all(long: pl.DataFrame) -> pl.DataFrame:
    d = _raw(long)
    a = d.group_by("sex", "lift").agg(
        pl.col("value_kg").median().alias("tümü_medyan"), pl.len().alias("n_tümü")
    )
    t = (
        d.filter(pl.col("tested"))
        .group_by("sex", "lift")
        .agg(pl.col("value_kg").median().alias("tested_medyan"), pl.len().alias("n_tested"))
    )
    # Kilo karışımı farkını ayıklamak için oranın da medyanı.
    r = d.with_columns(ratio=pl.col("value_kg") / pl.col("bodyweight_kg"))
    ra = r.group_by("sex", "lift").agg(pl.col("ratio").median().alias("oran_tümü"))
    rt = (
        r.filter(pl.col("tested"))
        .group_by("sex", "lift")
        .agg(pl.col("ratio").median().alias("oran_tested"))
    )
    return (
        a.join(t, on=["sex", "lift"])
        .join(ra, on=["sex", "lift"])
        .join(rt, on=["sex", "lift"])
        .with_columns(oran_farkı_pct=(pl.col("oran_tested") / pl.col("oran_tümü") - 1) * 100)
        .sort("sex", "lift")
    )


def cell_counts(long: pl.DataFrame) -> pl.DataFrame:
    return (
        _raw(long)
        .filter(pl.col("age_band").is_not_null() & pl.col("bodyweight_kg_band").is_not_null())
        .group_by("lift", "sex", "age_band", "bodyweight_kg_band")
        .agg(pl.len().alias("n"), pl.col("athlete_id").n_unique().alias("athletes"))
    )


def plot_heatmaps(cells: pl.DataFrame, out: Path) -> None:
    ages, bws = band_labels(AGE_BAND_EDGES), band_labels(BW_BAND_EDGES)
    fig, axes = plt.subplots(2, 3, figsize=(17, 9))
    for i, sex in enumerate(("M", "F")):
        for j, lift in enumerate(LIFTS):
            m = np.zeros((len(ages), len(bws)))
            sub = cells.filter((pl.col("sex") == sex) & (pl.col("lift") == lift))
            for row in sub.iter_rows(named=True):
                m[ages.index(row["age_band"]), bws.index(row["bodyweight_kg_band"])] = row["n"]
            ax = axes[i, j]
            ax.imshow(np.log10(m + 1), cmap="viridis", aspect="auto")
            for a in range(len(ages)):
                for b in range(len(bws)):
                    n = int(m[a, b])
                    ax.text(
                        b,
                        a,
                        f"{n / 1000:.0f}k" if n >= 1000 else str(n),
                        ha="center",
                        va="center",
                        fontsize=6,
                        color="red" if n < SPARSE_N else "white",
                    )
            ax.set_xticks(range(len(bws)), bws, rotation=60, fontsize=7)
            ax.set_yticks(range(len(ages)), ages, fontsize=7)
            ax.set_title(f"{sex} · {lift} (kırmızı: n < {SPARSE_N})")
    fig.tight_layout()
    fig.savefig(out, dpi=110)
    plt.close(fig)


def sbd_correlations(sbd: pl.DataFrame) -> pl.DataFrame:
    """Kilo ve yaş etkisi kabaca çıkarılmış log-kaldırış korelasyonları (§4.4 için ön bakış)."""
    rows = []
    for sex in ("M", "F"):
        d = sbd.filter((pl.col("sex") == sex) & ~pl.col("wraps"))
        X = np.column_stack(
            [
                np.ones(d.height),
                np.log(d["bodyweight_kg"].to_numpy()),
                d["age"].to_numpy(),
                d["age"].to_numpy() ** 2,
            ]
        )
        res = []
        for lift in LIFTS:
            y = np.log(d[f"{lift}_kg"].to_numpy())
            beta, *_ = np.linalg.lstsq(X, y, rcond=None)
            res.append(y - X @ beta)
        c = np.corrcoef(np.vstack(res))
        rows.append({"sex": sex, "n": d.height, "S–B": c[0, 1], "S–D": c[0, 2], "B–D": c[1, 2]})
    return pl.DataFrame(rows)


def run() -> Path:
    run_cfg = load_config(ML_ROOT / "configs/smoke.yaml")
    cfg = CohortConfig()
    opl = pl.read_parquet(ML_ROOT / run_cfg.data.opl_parquet)
    cohort = build(opl, cfg)
    write(cohort, ML_ROOT / run_cfg.paths.processed, cfg)

    reports = ML_ROOT / "reports"
    figs = reports / "eda"
    figs.mkdir(parents=True, exist_ok=True)
    long = cohort.long

    imputation_text, _ = age_imputation_effect(opl, cfg)
    plot_distributions(long, figs / "distributions.png")
    plot_curves(
        long, "bodyweight_kg", 2.5, "vücut ağırlığı (kg)", figs / "median_by_bodyweight.png"
    )
    plot_curves(long, "age", 1.0, "yaş", figs / "median_by_age.png")
    cells = cell_counts(long)
    plot_heatmaps(cells, figs / "cell_counts.png")

    flow = pl.DataFrame(cohort.flow).rename({"step": "adım", "rows": "satır"})
    per_lift = (
        long.group_by("lift", "wraps", "sex")
        .agg(
            pl.len().alias("satır"),
            pl.col("athlete_id").n_unique().alias("sporcu"),
            pl.col("value_kg").median().alias("medyan_kg"),
        )
        .sort("lift", "wraps", "sex")
    )
    sparse = cells.filter(pl.col("n") < SPARSE_N).sort(
        "lift", "sex", "age_band", "bodyweight_kg_band"
    )
    sparse_summary = (
        sparse.group_by("lift", "sex").agg(pl.len().alias("seyrek_hücre")).sort("lift", "sex")
    )
    total_cells = cells.group_by("lift", "sex").len().rename({"len": "dolu_hücre"})
    sparse_summary = sparse_summary.join(total_cells, on=["lift", "sex"]).select(
        "lift", "sex", "dolu_hücre", "seyrek_hücre"
    )
    peaks = peak_ages(long)
    corr = sbd_correlations(cohort.sbd)

    md = f"""# Keşif analizi (P048)

Üretim: `make eda` (`gymml/data/cohort.py` + `gymml/data/eda.py`). Kaynak: OpenPowerlifting
(`data/interim/opl.parquet`, bkz. `data/SOURCES.md`). Bu rapor ve grafikler komutla yeniden üretilir.

## Kohort tanımı

- Cinsiyet M/F; ekipman `Raw` ve `Wraps` (Wraps kategorisi yalnızca dizlik sargısıdır: squat satırlarında
  `wraps = true` bayrağı, bench/deadlift satırlarında Raw sayılır). Model hedefi `wraps = false` satırlardır.
- Sıra `DQ`, `DD` (doping), `G` (misafir), `NS` (gelmedi) olan kayıtlar çıkarıldı.
- Yaş {cfg.age_min:g}–{cfg.age_max:g}, vücut ağırlığı {cfg.bw_min:g}–{cfg.bw_max:g} kg, başarılı kaldırış > 0.
- Aykırı değer: kaldırış < {cfg.min_lift_kg:g} kg, mutlak üst sınır {cfg.max_lift_kg} kg (ham dünya rekorlarının
  biraz üstü) veya vücut ağırlığı katı {cfg.max_ratio_bw} üzerindeyse atılır.
- Sporcu × takvim yılı × kaldırış (× wraps) başına en iyi kayıt; o kaydın yaş ve kilosu kullanılır.
- Ağırlık (`weight`): sporcunun o kaldırıştaki yıl kayıtlarının toplam ağırlığı 1 (ters-frekans).
- `tested` sütunu korunur; varsayılan referans `tested = true`, tüm veri duyarlılık analizi (P053).
- Katmanlar (P049): yaş bantları {band_labels(AGE_BAND_EDGES)}, kilo bantları {band_labels(BW_BAND_EDGES)}.

## Süzgeç akışı

{_md_table(flow)}

Kaldırış başına kohort (`cohort_long.parquet`):

{_md_table(per_lift)}

SBD ortak tablosu (`cohort_sbd.parquet`): {cohort.sbd.height:,} sporcu-yıl. Bench/squat oranı
{cfg.bench_to_squat} veya deadlift/squat oranı {cfg.deadlift_to_squat} dışında kalan
{cohort.sbd_inconsistent_dropped:,} kayıt veri giriş hatası şüphesiyle bu tablodan çıkarıldı.

## Yaşı eksik kayıtlar: AgeClass orta noktası

{imputation_text}
**Karar:** varsayılan `impute_age_from_class = False`. Gerekçe: (1) yaş, modelin üç girdisinden biri ve orta nokta
yaşı bantlar içinde sabitler, eğri biçimini (§4.3 akıl sağlığı testi: 20'lerin ortasında tepe) yapay
basamaklarla bozar; (2) yaşı eksik kayıtlar rastgele değil, belirli federasyonlardan gelir — medyan farkı
tablosu bu kitlenin farklı olduğunu gösteriyor; (3) kalan veri ({long.height:,} satır) zaten bol. Seyrek yaşlı
bantlarda (70+) veri eksikse P053'te `impute_age_from_class = True` duyarlılık koşumu olarak denenebilir.

## Dağılımlar

![dağılımlar](eda/distributions.png)

Kaldırışlar sağa çarpık; kadın ve erkek dağılımları belirgin ayrık. Vücut ağırlığına oranlanınca çarpıklık
azalıyor, bu da log-kilo girdisini destekliyor.

## Vücut ağırlığı ve yaşa göre medyan eğrileri

![kiloya göre](eda/median_by_bodyweight.png)

![yaşa göre](eda/median_by_age.png)

Medyan kiloyla artıyor ama azalan hızla (ağır sıklette düzleşme). Uçlarda (çok hafif, 140 kg üstü, 70+ yaş)
bant genişliği ve gürültü artıyor.

Medyanın tepe yaptığı yaş (1 yıllık kutular; tepe değerin %1 yakınındaki yaş aralığı):

{_md_table(peaks)}

**Not (P049/P053 için):** ham veride tepe 20'lerin ortasında değil, daha geç ve geniş bir platoda (özellikle
bench'te 30'lar). §4.3'teki "beklenen medyan yaşta 20'lerin ortasında tepe yapmalı" akıl sağlığı testi bu
veriyle birebir uygulanırsa iyi bir model de kalabilir; testin "tepe ~20–40 arası, tek tepeli, ani sıçrama yok"
biçiminde yorumlanması kullanıcı onayına sunulmalı (kriter değişikliği P053 öncesi karara bağlanmalı).

Dağılım grafiğindeki tarak görüntüsü kayıtların 2.5 kg (ve lb dönüşümlü) adımlarla yuvarlanmasından gelir:
değerlendirmede (PIT, P049) bağlar için rastgele titreştirme gerekir.

## Tested ve tümü

{_md_table(tested_vs_all(long), "{:.3f}")}

`oran_farkı_pct`: testli kayıtların kaldırış/kilo oranı medyanının tüm veriye göre farkı (yüzde).

## Örneklem büyüklüğü: cinsiyet × yaş bandı × kilo bandı

![hücre sayıları](eda/cell_counts.png)

n < {SPARSE_N} olan hücreler (P049 kalibrasyon tablosuna girmez; model bu bölgelerde ekstrapolasyon yapar):

{_md_table(sparse_summary)}

Seyrek bölgeler (ısı haritasında kırmızı): erkeklerde 50 kg altı (her yaşta); kadınlarda 125 kg üstü (her yaşta)
ve 14–23 yaşta 110 kg üstü; iki cinsiyette 50+ yaşın uç kiloları ve 70+ yaşın çoğu hücresi. Bu bölgeler P049 akıl sağlığı testlerinde ("eğitim aralığı dışında makul
davranış") ve P052 girdi kırpma kuralında hedeflenmeli.

## SBD kaldırışları arası korelasyon (ön bakış)

Log-kaldırıştan log-kilo ve yaş² etkisi doğrusal olarak çıkarıldıktan sonra artıkların korelasyonu (raw):

{_md_table(corr, "{:.3f}")}

§4.4 ortak başlığı (P052) bu büyüklükleri yakalamalı.
"""
    path = reports / "eda.md"
    path.write_text(md, encoding="utf-8")
    print(path)
    return path


if __name__ == "__main__":
    run()
