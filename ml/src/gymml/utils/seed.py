"""Tekrarlanabilirlik: tek giriş noktası."""

from __future__ import annotations

import os
import random

import numpy as np


def seed_everything(seed: int) -> None:
    """Python, NumPy ve (kuruluysa) PyTorch tohumlarını ayarlar; deterministik bayrakları açar."""
    os.environ["PYTHONHASHSEED"] = str(seed)
    # CUBLAS deterministik çalışması için gerekli.
    os.environ.setdefault("CUBLAS_WORKSPACE_CONFIG", ":4096:8")
    random.seed(seed)
    np.random.seed(seed)
    try:
        import torch
    except ImportError:  # pragma: no cover
        return
    torch.manual_seed(seed)
    torch.use_deterministic_algorithms(True, warn_only=True)
    torch.backends.cudnn.deterministic = True
    torch.backends.cudnn.benchmark = False
