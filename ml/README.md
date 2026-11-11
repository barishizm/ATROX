# ml/

Güç Skoru modelinin Python eğitim hattı (`uv` ile yönetilir). Çıktı: Core ML + `params.json` model paketi
ve `golden/*.json` altın vektörleri (Swift ile sayısal eşlik, tolerans 1e-4).

- `data/raw` ve `runs/` git dışıdır.
- Testler: `cd ml && uv run pytest`
- Tasarım: [`docs/03-ML-MODEL.md`](../docs/03-ML-MODEL.md)
