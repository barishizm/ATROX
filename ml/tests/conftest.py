"""Test oturumu ayarları.

macOS'ta LightGBM (Homebrew libomp) ve torch (kendi libomp kopyası) aynı süreçte yüklenince ya torch
kilitlenir ya da LightGBM segfault verir (Linux CI'da ikisi de libgomp kullanır, sorun yok).
Bu yüzden macOS'ta LightGBM testleri ayrı bir pytest sürecinde koşar: `make test` bunu yapar
(ATROX_LGBM_TESTS=1 ile yalnızca o dosya).
"""

import os
import sys

LGBM_TESTS = "test_lgbm_quantile.py"

if sys.platform == "darwin" and os.environ.get("ATROX_LGBM_TESTS") != "1":
    collect_ignore = [LGBM_TESTS]
