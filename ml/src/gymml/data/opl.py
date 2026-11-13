"""OpenPowerlifting toplu CSV'sini içe aktarır (P047).

Akış: (indir) -> arşivi doğrula + lisansı belgele -> CSV'yi şemayla oku -> sporcu kimliği üret,
ad sütununu at -> data/interim/opl.parquet. Sütun belgeleri:
https://openpowerlifting.gitlab.io/opl-csv/bulk-csv-docs.html
"""

from __future__ import annotations

import argparse
import hashlib
import re
import shutil
import urllib.request
import zipfile
from datetime import date
from pathlib import Path

import polars as pl

from gymml.utils.config import ML_ROOT, load_config

# Projenin kendi veri sayfasının (openpowerlifting.gitlab.io/opl-csv) sunduğu toplu arşiv.
# Sayfanın anlattığı data.openpowerlifting.org adresi 2026-11-13'te çözümlenmedi.
BULK_URL = "https://openpowerlifting.gitlab.io/opl-csv/files/openpowerlifting-latest.zip"
DATA_PAGE_URL = "https://openpowerlifting.gitlab.io/opl-csv/"
ID_DOMAIN = "atrox-opl-v1"

# Ham CSV'nin tam şeması (bulk-csv-docs). Bilinmeyen sütun gelirse içe aktarma durur.
RAW_SCHEMA: dict[str, pl.DataType] = {
    "Name": pl.String,
    "Sex": pl.String,
    "Event": pl.String,
    "Equipment": pl.String,
    "Age": pl.Float32,
    "AgeClass": pl.String,
    "BirthYearClass": pl.String,
    "Division": pl.String,
    "BodyweightKg": pl.Float32,
    "WeightClassKg": pl.String,
    **{f"{lift}{n}Kg": pl.Float32 for lift in ("Squat", "Bench", "Deadlift") for n in (1, 2, 3, 4)},
    "Best3SquatKg": pl.Float32,
    "Best3BenchKg": pl.Float32,
    "Best3DeadliftKg": pl.Float32,
    "TotalKg": pl.Float32,
    "Place": pl.String,
    "Dots": pl.Float32,
    "Wilks": pl.Float32,
    "Glossbrenner": pl.Float32,
    "Goodlift": pl.Float32,
    "Tested": pl.String,
    "Country": pl.String,
    "State": pl.String,
    "Federation": pl.String,
    "ParentFederation": pl.String,
    "Date": pl.String,
    "MeetCountry": pl.String,
    "MeetState": pl.String,
    "MeetTown": pl.String,
    "MeetName": pl.String,
    "Sanctioned": pl.String,
}
# Sütun sırası CSV başlığıyla birebir olmalı; SBD dilimleri README'deki sıradadır.
RAW_COLUMNS = [
    "Name", "Sex", "Event", "Equipment", "Age", "AgeClass", "BirthYearClass", "Division",
    "BodyweightKg", "WeightClassKg",
    "Squat1Kg", "Squat2Kg", "Squat3Kg", "Squat4Kg", "Best3SquatKg",
    "Bench1Kg", "Bench2Kg", "Bench3Kg", "Bench4Kg", "Best3BenchKg",
    "Deadlift1Kg", "Deadlift2Kg", "Deadlift3Kg", "Deadlift4Kg", "Best3DeadliftKg",
    "TotalKg", "Place", "Dots", "Wilks", "Glossbrenner", "Goodlift", "Tested", "Country", "State",
    "Federation", "ParentFederation", "Date", "MeetCountry", "MeetState", "MeetTown", "MeetName",
    "Sanctioned",
]  # fmt: skip

# Çıktıda tuttuğumuz sütunlar (docs: ml/reports/data_dictionary.md). Ad yok; toplantı adı/şehri yok.
KEEP_COLUMNS = [
    "athlete_id", "Sex", "Event", "Equipment", "Age", "AgeClass", "BodyweightKg",
    "Best3SquatKg", "Best3BenchKg", "Best3DeadliftKg", "TotalKg", "Place", "Dots", "Tested",
    "Country", "Federation", "ParentFederation", "Date",
]  # fmt: skip

RENAME = {
    "Sex": "sex", "Event": "event", "Equipment": "equipment", "Age": "age", "AgeClass": "age_class",
    "BodyweightKg": "bodyweight_kg", "Best3SquatKg": "squat_kg", "Best3BenchKg": "bench_kg",
    "Best3DeadliftKg": "deadlift_kg", "TotalKg": "total_kg", "Place": "place", "Dots": "dots",
    "Country": "country", "Federation": "federation", "ParentFederation": "parent_federation",
    "Date": "date",
}  # fmt: skip
OUT_COLUMNS = [
    "athlete_id", "sex", "event", "equipment", "age", "age_class", "bodyweight_kg", "squat_kg",
    "bench_kg", "deadlift_kg", "total_kg", "place", "dots", "tested", "country", "federation",
    "parent_federation", "date",
]  # fmt: skip


def athlete_id(name: str) -> str:
    """Kararlı sporcu kimliği: ad (OPL'nin '#n' ayırıcısı dahil) üzerinden SHA-256, 16 hex.

    Takma adlandırmadır, anonimleştirme değil: aynı ad aynı kimliği verir (tekrarlı ölçümleri
    bağlamak için gerekli). Ad hiçbir ara dosyaya yazılmaz.
    """
    norm = " ".join(name.split()).casefold()
    return hashlib.sha256(f"{ID_DOMAIN}|{norm}".encode()).hexdigest()[:16]


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def download(dest: Path, url: str = BULK_URL) -> Path:
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(".part")
    with urllib.request.urlopen(url, timeout=120) as r, tmp.open("wb") as f:  # noqa: S310
        shutil.copyfileobj(r, f, 1 << 20)
    tmp.replace(dest)
    return dest


def read_license(zip_path: Path) -> tuple[str, str]:
    """Arşivdeki LICENSE.txt ve README.txt metnini (birebir) döndürür."""
    with zipfile.ZipFile(zip_path) as z:
        names = z.namelist()

        def find(suffix: str) -> str:
            matches = [n for n in names if n.endswith(suffix)]
            if not matches:
                raise FileNotFoundError(f"arşivde {suffix} yok")
            return z.read(matches[0]).decode("utf-8")

        return find("LICENSE.txt"), find("README.txt")


def is_public_domain(license_text: str) -> bool:
    """Lisans kamu malı değilse veya belirsizse False (içe aktarma DURUR)."""
    t = " ".join(license_text.lower().split())
    return "contributed to the public domain" in t and "waived of all copyright" in t


def write_sources(path: Path, zip_path: Path, license_text: str, today: date | None = None) -> None:
    quoted = "\n".join(f"> {line}".rstrip() for line in license_text.strip().splitlines())
    body = f"""# Veri kaynakları

## OpenPowerlifting toplu CSV

| Alan | Değer |
|---|---|
| Veri sayfası | <{DATA_PAGE_URL}> |
| İndirme adresi | <{BULK_URL}> |
| İndirme tarihi | {(today or date.today()).isoformat()} |
| Dosya | `{zip_path.name}` ({zip_path.stat().st_size} bayt) |
| SHA-256 | `{sha256_file(zip_path)}` |
| Lisans durumu | **Kamu malı** (arşivdeki `LICENSE.txt`) |

Not: Sayfanın kendi metni verinin `https://data.openpowerlifting.org` adresinden indirilebileceğini
söyler; bu ad 2026-11-13'te çözümlenmediği için aynı projenin kendi sitesindeki arşiv kullanıldı.

### Arşivdeki `LICENSE.txt` (birebir)

{quoted}

Atıf zorunlu değildir; yine de uygulamanın "Hakkında" ekranında şu metin yer alacaktır:
"This page uses data from the OpenPowerlifting project, https://www.openpowerlifting.org."

Yeniden indirmek hash'i değiştirir (veri her gün güncellenir); bu dosya her içe aktarmada yenilenir.
"""
    path.write_text(body, encoding="utf-8")


def find_csv(zip_path: Path, out_dir: Path) -> Path:
    """Arşivdeki dev CSV'yi (yalnızca) ham klasöre akışla açar."""
    with zipfile.ZipFile(zip_path) as z:
        csvs = [n for n in z.namelist() if re.search(r"openpowerlifting-.*\.csv$", n)]
        if len(csvs) != 1:
            raise ValueError(f"arşivde tam bir CSV beklenir, bulunan: {csvs}")
        target = out_dir / "openpowerlifting.csv"
        with z.open(csvs[0]) as src, target.open("wb") as dst:
            shutil.copyfileobj(src, dst, 1 << 20)
    return target


def check_header(csv_path: Path) -> None:
    header = csv_path.open(encoding="utf-8").readline().rstrip("\n").split(",")
    if header != RAW_COLUMNS:
        missing = set(RAW_COLUMNS) ^ set(header)
        raise ValueError(f"CSV başlığı beklenen şemayla uyuşmuyor; fark: {sorted(missing)}")


def transform(csv_path: Path) -> pl.DataFrame:
    """CSV -> temiz Parquet çerçevesi. Ad bu fonksiyonun içinde kimliğe çevrilir ve atılır."""
    check_header(csv_path)
    lf = pl.scan_csv(csv_path, schema=RAW_SCHEMA, quote_char=None, null_values=[""])
    names = lf.select("Name").unique().collect()["Name"].to_list()
    mapping = pl.DataFrame({"Name": names, "athlete_id": [athlete_id(n) for n in names]})
    out = (
        lf.join(mapping.lazy(), on="Name", how="left")
        .select(KEEP_COLUMNS)  # Name burada elenir
        .with_columns(
            pl.col("Tested").eq("Yes").fill_null(False).alias("tested"),
            pl.col("Date").str.to_date("%Y-%m-%d"),
        )
        .drop("Tested")
        .collect()
    )
    return out.rename(RENAME).select(OUT_COLUMNS)


def run(config_path: Path | None = None, *, skip_download: bool = False) -> Path:
    cfg = load_config(config_path or ML_ROOT / "configs/smoke.yaml")
    zip_path = ML_ROOT / cfg.data.opl_zip
    out_path = ML_ROOT / cfg.data.opl_parquet
    if not zip_path.exists():
        if skip_download:
            raise FileNotFoundError(zip_path)
        print(f"indiriliyor: {BULK_URL}")
        download(zip_path)
    license_text, _ = read_license(zip_path)
    if not is_public_domain(license_text):
        raise SystemExit(
            "DUR: lisans kamu malı olarak doğrulanamadı. LICENSE.txt'i okuyup kullanıcıya bildirin."
        )
    write_sources(ML_ROOT / "data/SOURCES.md", zip_path, license_text)
    csv_path = find_csv(zip_path, zip_path.parent)
    try:
        df = transform(csv_path)
    finally:
        csv_path.unlink(missing_ok=True)  # ad içeren ham CSV'yi diskte bırakma
    if df.height < cfg.data.min_rows:
        raise ValueError(f"satır sayısı {df.height} < alt sınır {cfg.data.min_rows}")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    df.write_parquet(out_path, compression="zstd")
    print(f"{out_path}: {df.height} satır")
    return out_path


def main() -> None:
    p = argparse.ArgumentParser(prog="gymml.data.opl")
    p.add_argument("--skip-download", action="store_true")
    run(skip_download=p.parse_args().skip_download)


if __name__ == "__main__":
    main()
