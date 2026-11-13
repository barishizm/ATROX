"""`make baselines`: iki temel çizgiyi ortak koşumdan geçirir, `reports/baselines.md` yazar."""

from __future__ import annotations

import json

import polars as pl

from gymml.data.cohort import ML_ROOT
from gymml.eval.data import DataSpec
from gymml.eval.metrics import COVERAGE_GATE_PP, MAX_STRATA_OUTSIDE_SHARE, MIN_STRATUM_N
from gymml.eval.runner import (
    evaluate_factory,
    plot_percentile_curves,
    plot_pit,
    split_info,
    summary_table,
)
from gymml.eval.sanity import SanityConfig
from gymml.models.baselines import CellEmpirical, DotsEmpirical
from gymml.utils.config import load_config
from gymml.utils.runs import Run


def _md(df: pl.DataFrame, fmt: str = "{:.3f}") -> str:
    lines = ["| " + " | ".join(df.columns) + " |", "|" + "---|" * len(df.columns)]
    for row in df.iter_rows():
        cells = [
            fmt.format(v)
            if isinstance(v, float)
            else f"{v:,}"
            if isinstance(v, int) and not isinstance(v, bool)
            else str(v)
            for v in row
        ]
        lines.append("| " + " | ".join(cells) + " |")
    return "\n".join(lines)


def run() -> None:
    cfg = load_config(ML_ROOT / "configs/smoke.yaml")
    spec = DataSpec()
    results = {
        "cell_empirical": evaluate_factory(CellEmpirical, spec),
        "dots_empirical": evaluate_factory(DotsEmpirical, spec),
    }
    info = split_info()
    run_dir = Run(ML_ROOT / cfg.paths.runs, "baselines", {"spec": spec.__dict__, "split": info})
    table = summary_table(results)
    run_dir.write_metrics(
        {
            name: {r.lift: {k: v for k, v in r.metrics.items()} for r in rs}
            for name, rs in results.items()
        }
    )

    reports = ML_ROOT / "reports"
    figs = reports / "baselines"
    figs.mkdir(parents=True, exist_ok=True)
    plot_pit(results, figs / "pit.png")
    plot_percentile_curves(results, figs / "percentiles_M30.png", "M", 30.0)
    plot_percentile_curves(results, figs / "percentiles_F30.png", "F", 30.0)

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

    sc = SanityConfig()
    md = f"""# Temel çizgiler (P049)

Üretim: `make baselines` (`gymml/eval/baselines.py`). Koşum izi: `runs/*-baselines/`.
Adaylar (P050–P052) bu tablodaki **doğrulama** metriklerini geçmek zorundadır. Test kümesi burada kullanılmadı.

## Değerlendirme düzeni

- Veri: `cohort_long.parquet` (P048), referans tanımı `tested = true`, `wraps = false`; örnek ağırlıkları
  ters-frekans (sporcu başına toplam 1).
- Bölme: sporcu kimliğine göre gruplu %70/15/15, tohum `{20260101}`, dosya `data/processed/splits.parquet`
  (yoksa kohorttan aynı tohumla yeniden üretilir). Özet `{info["digest"]}`, sporcu sayıları {info["athletes"]}.
- Ortak arabirim `gymml.eval.interface.DistributionModel`: `fit(df)`, `quantile(x, q)`, `cdf(x, y)`, `params(x)`;
  kaldırış başına ayrı model.
- Metrikler (`gymml.eval.metrics`): 19 çeyrek (0.05…0.95) ortalama ağırlıklı pinball kaybı (kg); CRPS ≈ 2 ×
  pinball; rastgeleleştirilmiş PIT (gözlem ±1.25 kg titreştirilir, kayıtlar 2.5 kg adımlı) histogramı ve
  KS uzaklığı; katman (cinsiyet × yaş bandı × kilo bandı, n ≥ {MIN_STRATUM_N}) başına 10–90 çeyreklerinde
  |gözlenen − beklenen| kapsamanın en büyüğü. Kapı (§4.3, 2026-11-13 onayı): sapma ≤ max({COVERAGE_GATE_PP:g} puan,
  gürültü bandı), bandı aşan katman oranı ≤ %{MAX_STRATA_OUTSIDE_SHARE * 100:g}. Gürültü bandı 2.77·√(0.25/n_etkin)
  (9 çeyrekte Bonferroni ile katman başına %95, Kish etkin örneklemi). `2pp_üstü_katman` yalnızca bilgi içindir.
- Akıl sağlığı testleri (`gymml.eval.sanity`): yükte kesin artan CDF; aynı yükte kiloyla artmayan skor
  (tolerans {sc.bw_tolerance}); yaş eğrisi tek tepeli, tepe {sc.peak_age_range[0]:g}–{sc.peak_age_range[1]:g}, yıllık
  sıçrama ≤ %{sc.max_year_jump * 100:g}; pürüzsüzlük |Δ²medyan|/medyan ≤ {sc.max_rel_second_diff}; eğitim
  aralığı dışı (yaş {sc.extrapolation_ages}, kilo {sc.extrapolation_bws}) sonlu/pozitif/sıralı/fiziksel sınır içinde.
- Dış doğrulama (`gymml.eval.external`): van den Hoek 2024 özetindeki 90. yüzdelik göreli güç (18–35 ve >80
  yaş, kilo sınıfları toplu; `data/external/`). Model değeri, doğrulama kümesindeki aynı cinsiyet/yaş grubundaki
  kişiler üzerinden toplu göreli güç dağılımının 90. yüzdeliği. 18–35 için ölçüt ±%3.

## Metrikler (doğrulama kümesi)

{_md(table)}

![PIT](baselines/pit.png)

## Akıl sağlığı testleri

{_md(pl.DataFrame(sanity_rows))}

## Dış doğrulama: van den Hoek 2024

{_md(ext_df)}

## Yüzdelik eğrileri

![erkek 30 yaş](baselines/percentiles_M30.png)

![kadın 30 yaş](baselines/percentiles_F30.png)

## Yorum

{_commentary(results)}
"""
    (reports / "baselines.md").write_text(md, encoding="utf-8")
    (figs / "summary.json").write_text(
        json.dumps(table.to_dicts(), indent=2, ensure_ascii=False), encoding="utf-8"
    )
    print(table)


def _commentary(results) -> str:
    def pin(name):
        return {r.lift: r.metrics["pinball"] for r in results[name]}

    a, b = pin("cell_empirical"), pin("dots_empirical")
    better = [lift for lift in a if a[lift] < b[lift]]
    return (
        f"- Pinball'da hücre bazlı ampirik model {len(better)}/3 kaldırışta DOTS temel çizgisinden iyi "
        f"({', '.join(better) or '—'}): DOTS yaşı hiç kullanmaz ve kilo eğrisini tek bir formüle bağlar.\n"
        "- Hücre modeli bant sınırlarında basamaklıdır; pürüzsüzlük ve kiloda artmama testlerini bu yüzden\n"
        "  geçemeyebilir. DOTS kiloda pürüzsüz ama yaş etkisi olmadığından yaş testi ve gençlerde/yaşlılarda\n"
        "  kalibrasyon kapısı başarısız olur. Bunlar beklenen zayıflıklardır; adaylar hepsini birlikte\n"
        "  geçmelidir.\n"
        "- Kalibrasyon kapısı ve örnekleme gürültüsü: hücre modeli katmanlarla aynı hücrelerde eğitildiği hâlde\n"
        "  doğrulamada birçok katmanda 2 puanı aşıyor; sapma 1/√n ile ölçekleniyor (bench'te r ≈ 0.6). Ters-\n"
        "  frekans ağırlıklarıyla n = 500'lük katmanın etkin örneklemi daha da küçük, gürültü bandı 5–8 puan.\n"
        "  Bu yüzden §4.3 kapısı 2026-11-13'te kullanıcı onayıyla gürültüye duyarlı hâle getirildi.\n"
        "- Yaş tepesi ölçütü ham veride tepe 27–34 (bench 32–41) olduğundan onayla 20–40 aralığına çekildi.\n"
        "- vdH ölçütü P053'te ağırlıklandırma açık/kapalı iki sürümle raporlanır; karşılaştırma ağırlıksız sürümle."
    )


if __name__ == "__main__":
    run()
