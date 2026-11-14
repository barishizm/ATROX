# ATROX ML hattı. Her hedef `uv run` ile çalışır.
.PHONY: data calibrate eda baselines profiles train-a train-b train-c tune bakeoff export retrain retrain-synthetic latent test lint smoke

data:        ## P047: OpenPowerlifting'i indir/içe aktar -> data/interim/opl.parquet
	uv run python -m gymml.data.opl

calibrate:   ## P055: nüfus kalibrasyonu -> reports/calibration.md, params_draft/calibration.json
	uv run python -m gymml.calibration.run

eda:         ## P048: kohort tabloları (data/processed/) + reports/eda.md
	uv run python -m gymml.data.eda

baselines:   ## P049: ortak değerlendirme koşumu + temel çizgiler -> reports/baselines.md
	uv run python -m gymml.eval.baselines

train-a:     ## P050: Spline-LMS (BCCG + BCPE) -> reports/candidate_a.md
	uv run python -m gymml.models.train_a

train-b:     ## P051: Aday B LightGBM çeyreklik (kısıtlı + kısıtsız) -> reports/candidate_b.md
	uv run python -m gymml.models.train_b

train-c:     ## P052: Aday C (sinirsel BCPE/SHASH + kopula) -> reports/candidate_c.md, params_draft/correlation.json
	uv run python -m gymml.models.neural_run

tune:        ## P053: aday başına Optuna + 3 tohum + tek test bakışı + duyarlılık (adaylar ayrı süreçte)
	for c in A B C; do uv run python -m gymml.tune.bakeoff all --cand $$c; done

bakeoff:     ## P053: reports/bakeoff.md (§3 ve sonrası) reports/bakeoff/*.json'dan
	uv run python -m gymml.tune.bakeoff report

profiles:    ## P057: A modelinden çapa korelasyonu + örnek profil skorları -> reports/scoring_profiles.md
	uv run python -m gymml.scoring_run corr
	uv run python -m gymml.scoring_run profiles

export:      ## P060: imzalı model paketi (dist/) + altın vektörler (golden/) + gömülü paket (StrengthKit)
	uv run python -m gymml.export.bundle

retrain:     ## P094: ml_contributions (servis rolü) -> k-anonimlik -> δ/κ + oran güncellemesi -> kapılar -> dist/ + reports/retrain-<sürüm>.md
	uv run python -m gymml.retrain.run --fetch --sign

retrain-synthetic: ## P094: aynı hat sentetik katkılarla (runs/ altına; imzasız, MODEL_CARD'a dokunmaz)
	uv run python -m gymml.retrain.run --synthetic 6000

latent:      ## P095: v2 gizil faktör modeli araştırma prototipi -> reports/v2-latent-model.md
	uv run python -m gymml.research.latent

smoke:
	uv run python -m gymml.cli smoke

lint:
	uv run ruff check src tests

test:        ## macOS'ta LightGBM testleri ayrı süreçte koşar (bkz. tests/conftest.py)
	uv run pytest
	@if [ "$$(uname)" = "Darwin" ]; then ATROX_LGBM_TESTS=1 uv run pytest tests/test_lgbm_quantile.py; fi
