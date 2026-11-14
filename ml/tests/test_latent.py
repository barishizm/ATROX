"""P095 · latent factor prototype: fit recovers a known structure and beats the ratio tables on held-out lifts."""

from __future__ import annotations

import numpy as np

from gymml.research import latent


def _world():
    return latent.make_world(latent.catalog_rows(), seed=3)


def test_fold_in_matches_training_posterior_for_a_training_user():
    w = _world()
    d = latent.sample(w, 600, seed=4)
    pr = latent.Priors(w.b + 0.0, np.full(len(w.b), 0.2), w.group)
    m = latent.fit(d, 2, pr, iters=30)
    theta, _ = latent._user_step(d, m, d.x - m.x_mean)
    u = 5
    sel = d.u == u
    assert np.allclose(m.fold_in(d.e[sel], d.y[sel], d.x[u]), theta[u], atol=1e-8)


def test_prototype_recovers_structure_and_beats_tables():
    w = _world()
    r = latent.evaluate(w, 1500, seed=5, k=3, n_test=400)
    assert r["recovery"] > 0.85
    assert r["mae"]["latent"] < r["mae"]["table_updated"] < r["mae"]["table"]
    assert r["mae"]["latent"] < r["mae"]["covariates_only"]


def test_threshold_rule_needs_every_larger_size():
    def run(n, lat, upd, rec=0.95):
        return {"n_train": n, "mae": {"latent": lat, "table_updated": upd}, "recovery": rec}

    curve = [run(250, 0.14, 0.14), run(1000, 0.12, 0.14), run(5000, 0.13, 0.135), run(10000, 0.11, 0.14)]
    assert latent.threshold(curve) == 10000  # 5000 gains < 5 %
    curve[2] = run(5000, 0.12, 0.14)
    assert latent.threshold(curve) == 1000
    curve[1] = run(1000, 0.12, 0.14, rec=0.5)
    assert latent.threshold(curve) == 5000
