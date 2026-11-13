# ml/

Güç Skoru modelinin Python eğitim hattı (`uv` ile yönetilir). Çıktı: Core ML + `params.json` model paketi
ve `golden/*.json` altın vektörleri (Swift ile sayısal eşlik, tolerans 1e-4).

- `data/raw` ve `runs/` git dışıdır.
- Testler: `cd ml && uv run pytest`
- Tasarım: [`docs/03-ML-MODEL.md`](../docs/03-ML-MODEL.md)

## Hızlı başlangıç
```bash
cd ml
uv sync          # Python 3.12 + kilitli bağımlılıklar
make test        # birim testleri
make smoke       # örnek çalıştırma -> runs/<zaman>-smoke/
make data        # P047: OpenPowerlifting içe aktarma
```
macOS'ta LightGBM (P051, `make train-b`) OpenMP ister: `brew install libomp`.
Yapı: `src/gymml/{data,features,models,eval,export,utils}`, `configs/`, `reports/`, `golden/`,
`data/{raw,interim,processed}` (raw ve interim git dışı), `runs/` (git dışı).
