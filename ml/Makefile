# ATROX ML hattı. Her hedef `uv run` ile çalışır.
.PHONY: data eda baselines train-a train-b train-c tune bakeoff export test lint smoke

data:        ## P047: OpenPowerlifting'i indir/içe aktar -> data/interim/opl.parquet
	uv run python -m gymml.data.opl

eda:         ## P048: kohort tabloları (data/processed/) + reports/eda.md
	uv run python -m gymml.data.eda

baselines:   ## P049: ortak değerlendirme koşumu + temel çizgiler -> reports/baselines.md
	uv run python -m gymml.eval.baselines

train-a:     ## P050
	@echo "baselines:   ## P049: ortak değerlendirme koşumu + temel çizgiler -> reports/baselines.md
	uv run python -m gymml.eval.baselines

train-a: P050'de eklenecek"; exit 1

train-b:     ## P051
	@echo "train-b: P051'de eklenecek"; exit 1

train-c:     ## P052: Aday C (sinirsel BCPE/SHASH + kopula) -> reports/candidate_c.md, params_draft/correlation.json
	uv run python -m gymml.models.neural_run

tune:        ## P053
	@echo "tune: P053'te eklenecek"; exit 1

bakeoff:     ## P054
	@echo "bakeoff: P054'te eklenecek"; exit 1

export:      ## P058
	@echo "export: P058'de eklenecek"; exit 1

smoke:
	uv run python -m gymml.cli smoke

lint:
	uv run ruff check src tests

test:
	uv run pytest
