"""P095 · v2 latent factor model, research prototype (docs/03-ML-MODEL.md §12 "v2 araştırma izi").

    uv run python -m gymml.research.latent            # all experiments -> reports/v2-latent-model.md
    uv run python -m gymml.research.latent --quick    # smaller grid (a few seconds)

Model (MAP of a hierarchical Gaussian model, fitted by alternating ridge regressions):

    log e1RM_{u,e} = b_e + λ_e · θ_u + ε,   ε ~ N(0, σ²)
    θ_u ~ N(Γ x_u, I_K),   x_u = [male, (age − 35)/15, log(bw / 75), (height − 172)/10]
    λ_e ~ N(0, s_λ² I_K)

This is not production code: nothing here ships. The world it is tested on is synthetic (a known K = 3 structure,
realistic missingness), so the thresholds it produces are conditional on that world; see the report.
"""

from __future__ import annotations

import argparse
import math
import time
from collections.abc import Mapping
from dataclasses import dataclass

import numpy as np

from gymml.scoring import ML_ROOT

REPORT = ML_ROOT / "reports" / "v2-latent-model.md"
PATTERN_FACTOR = {  # true loading direction: 0 = push, 1 = pull, 2 = lower body
    "horizontal_push": 0, "vertical_push": 0, "isolation_triceps": 0, "isolation_chest": 0,
    "isolation_shoulders": 0, "horizontal_pull": 1, "vertical_pull": 1, "isolation_biceps": 1,
    "isolation_forearms": 1, "isolation_back": 1, "squat": 2, "hip_hinge": 2, "isolation_quads": 2,
    "isolation_hamstrings": 2, "isolation_calves": 2, "isolation_hips": 2, "olympic": 2, "core": 2, "carry": 1,
}
TABLE_ERROR_SD = {"A": 0.03, "B": 0.07, "C": 0.20}  # error of the P056 ratio table, as in retrain.yaml prior_sd


# ------------------------------------------------------------------------------------------------- world


@dataclass(frozen=True)
class World:
    """Ground truth: exercise parameters, covariate effects and the popularity used for missingness."""

    b: np.ndarray          # (E,)
    lam: np.ndarray        # (E, K)
    gamma: np.ndarray      # (K, P)
    factor_corr: np.ndarray  # (K, K) residual correlation of θ
    idio_sd: float         # person × exercise specialisation
    noise_sd: float        # e1RM estimate noise
    popularity: np.ndarray  # (E,) selection weights
    grade: tuple[str, ...]  # P056 grade of each exercise (table error)
    anchor_of: np.ndarray   # (E,) index of the exercise's anchor lift
    names: tuple[str, ...]
    group: np.ndarray       # (E,) movement pattern index (known to the fit)


@dataclass(frozen=True)
class Data:
    u: np.ndarray
    e: np.ndarray
    y: np.ndarray
    x: np.ndarray  # (N, P) covariates
    n_users: int
    n_ex: int


def make_world(catalog_rows: list[Mapping], seed: int = 0, idio_sd: float = 0.10, noise_sd: float = 0.05) -> World:
    """`catalog_rows`: dicts with id, movement_pattern, anchor, ratio, grade, is_anchor (real catalog)."""
    rng = np.random.default_rng(seed)
    k = 3
    rows = list(catalog_rows)
    e_n = len(rows)
    lam = np.zeros((e_n, k))
    for i, r in enumerate(rows):
        f = PATTERN_FACTOR.get(r["movement_pattern"], 2)
        w = np.full(k, 0.25) + rng.normal(0, 0.12, k)
        w[f] = 1.0
        lam[i] = rng.uniform(0.13, 0.22) * w
    b = np.log(np.array([r["ratio"] for r in rows], float)) + np.log(
        np.array([{"squat": 110.0, "bench": 80.0, "deadlift": 140.0}[r["anchor"]] for r in rows]))
    gamma = np.array([
        [2.6, -0.25, 1.4, 0.15],   # push: male, age, log bw, height
        [2.2, -0.20, 1.2, 0.20],   # pull
        [1.9, -0.35, 1.3, 0.10],   # lower
    ])
    corr = np.full((k, k), 0.7)
    np.fill_diagonal(corr, 1.0)
    order = sorted(range(e_n), key=lambda i: (not rows[i]["is_anchor"], rows[i]["grade"], rng.random()))
    rank = np.empty(e_n)
    rank[order] = np.arange(e_n)
    pop = 1.0 / (rank + 4.0)
    anchors = {r["anchor"]: i for i, r in enumerate(rows) if r["is_anchor"]}
    patterns = sorted({r["movement_pattern"] for r in rows})
    return World(b, lam, gamma, corr, idio_sd, noise_sd, pop / pop.sum(), tuple(r["grade"] for r in rows),
                 np.array([anchors[r["anchor"]] for r in rows]), tuple(r["id"] for r in rows),
                 np.array([patterns.index(r["movement_pattern"]) for r in rows]))


def covariates(n: int, rng: np.random.Generator) -> np.ndarray:
    male = rng.random(n) < 0.6
    age = rng.uniform(18, 65, n)
    bw = np.where(male, rng.lognormal(math.log(82), 0.15, n), rng.lognormal(math.log(65), 0.15, n))
    height = np.where(male, rng.normal(178, 7, n), rng.normal(165, 6, n))
    return np.column_stack([male.astype(float), (age - 35) / 15, np.log(bw / 75), (height - 172) / 10])


def sample(world: World, n: int, seed: int, lifts: tuple[int, int] = (5, 15)) -> Data:
    rng = np.random.default_rng(seed)
    x = covariates(n, rng)
    k = world.lam.shape[1]
    theta = x @ world.gamma.T + rng.multivariate_normal(np.zeros(k), world.factor_corr, n)
    theta -= world.gamma @ np.array([0.6, 0.0, 0.0, 0.0])  # centre males/females around 0
    us, es = [], []
    for u in range(n):
        m = int(rng.integers(lifts[0], lifts[1] + 1))
        chosen = rng.choice(len(world.b), size=m, replace=False, p=world.popularity)
        us.append(np.full(m, u))
        es.append(chosen)
    u = np.concatenate(us)
    e = np.concatenate(es)
    y = (world.b[e] + np.einsum("ij,ij->i", world.lam[e], theta[u])
         + rng.normal(0, world.idio_sd, len(u)) + rng.normal(0, world.noise_sd, len(u)))
    return Data(u, e, y, x, n, len(world.b))


# ------------------------------------------------------------------------------------------------- model


@dataclass
class LatentModel:
    b: np.ndarray
    lam: np.ndarray
    gamma: np.ndarray
    sigma2: float
    x_mean: np.ndarray
    psi_inv: np.ndarray  # (K, K) precision of θ around Γx

    def fold_in(self, e: np.ndarray, y: np.ndarray, x: np.ndarray) -> np.ndarray:
        """Posterior mean of one user's θ from their lifts: a K×K ridge solve (what the device would run)."""
        L = self.lam[e]
        a = L.T @ L / self.sigma2 + self.psi_inv
        r = L.T @ (y - self.b[e]) / self.sigma2 + self.psi_inv @ self.gamma @ (x - self.x_mean)
        return np.linalg.solve(a, r)

    def prior_theta(self, x: np.ndarray) -> np.ndarray:
        return self.gamma @ (x - self.x_mean)

    def predict(self, e: int, theta: np.ndarray) -> float:
        return float(self.b[e] + self.lam[e] @ theta)


@dataclass(frozen=True)
class Priors:
    """Known structure the fit may lean on: the P056 table (b_e prior) and the movement pattern (λ_e prior)."""

    b_mean: np.ndarray      # (E,) table offset at the average person
    b_sd: np.ndarray        # (E,) table error by grade
    group: np.ndarray       # (E,) movement pattern index
    s_lam_group: float = 0.05   # SD of λ_e around its pattern mean
    s_lam_global: float = 0.5   # SD of the pattern means around 0


def _user_step(d: Data, m: LatentModel, xc: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Posterior means of θ and the mean posterior covariance (for the Ψ update)."""
    k = m.lam.shape[1]
    L = m.lam[d.e]
    a = np.zeros((d.n_users, k, k))
    np.add.at(a, d.u, L[:, :, None] * L[:, None, :])
    a = a / m.sigma2 + m.psi_inv
    r = np.zeros((d.n_users, k))
    np.add.at(r, d.u, L * (d.y - m.b[d.e])[:, None])
    r = r / m.sigma2 + xc @ (m.psi_inv @ m.gamma).T
    return np.linalg.solve(a, r[:, :, None])[:, :, 0], np.linalg.inv(a).mean(axis=0)


def _group_means(lam: np.ndarray, counts: np.ndarray, pr: Priors) -> np.ndarray:
    """Pattern mean of λ (count weighted), itself shrunk to 0 with `s_lam_global`."""
    out = np.zeros_like(lam)
    for g in np.unique(pr.group):
        m = pr.group == g
        w = counts[m].astype(float)
        if w.sum() == 0:
            continue
        mean = (w[:, None] * lam[m]).sum(0) / w.sum()
        shrink = w.sum() / (w.sum() + (pr.s_lam_group / pr.s_lam_global) ** 2)
        out[m] = shrink * mean
    return out


def _exercise_step(d: Data, theta: np.ndarray, m: LatentModel, pr: Priors, counts: np.ndarray) -> None:
    k = theta.shape[1]
    z = np.column_stack([np.ones(len(d.u)), theta[d.u]])
    a = np.zeros((d.n_ex, k + 1, k + 1))
    np.add.at(a, d.e, z[:, :, None] * z[:, None, :])
    a /= m.sigma2
    r = np.zeros((d.n_ex, k + 1))
    np.add.at(r, d.e, z * d.y[:, None])
    r /= m.sigma2
    lam0 = _group_means(m.lam, counts, pr)
    prec_b = 1.0 / pr.b_sd**2
    a[:, 0, 0] += prec_b
    r[:, 0] += prec_b * pr.b_mean
    idx = np.arange(1, k + 1)
    a[:, idx, idx] += 1.0 / pr.s_lam_group**2
    r[:, 1:] += lam0 / pr.s_lam_group**2
    sol = np.linalg.solve(a, r[:, :, None])[:, :, 0]
    m.b, m.lam = sol[:, 0], sol[:, 1:]


def fit(d: Data, k: int, pr: Priors, iters: int = 100, seed: int = 0) -> LatentModel:
    rng = np.random.default_rng(seed)
    x_mean = d.x.mean(axis=0)
    xc = d.x - x_mean
    counts = np.bincount(d.e, minlength=d.n_ex)
    m = LatentModel(pr.b_mean.copy(), rng.normal(0, 0.1, (d.n_ex, k)), np.zeros((k, d.x.shape[1])), 0.05, x_mean,
                    np.eye(k))
    for _ in range(iters):
        theta, post_cov = _user_step(d, m, xc)
        _exercise_step(d, theta, m, pr, counts)
        m.gamma = np.linalg.lstsq(xc, theta, rcond=None)[0].T
        dev = theta - xc @ m.gamma.T
        psi = dev.T @ dev / d.n_users + post_cov  # EM update of the residual covariance of θ
        # The scale of θ is fixed by the λ prior only weakly: keep Ψ a correlation matrix (scale goes to λ).
        sd = np.sqrt(np.diag(psi))
        m.psi_inv = np.linalg.inv(psi / np.outer(sd, sd) + 1e-6 * np.eye(k))
        resid = d.y - m.b[d.e] - np.einsum("ij,ij->i", m.lam[d.e], theta[d.u])
        m.sigma2 = float(max(np.mean(resid**2), 1e-4))
    return m


# ------------------------------------------------------------------------------------------------- baselines


def table_offsets(world: World, rng: np.random.Generator, x_mean: np.ndarray) -> np.ndarray:
    """P056-style table: each exercise's log offset at the average person, with grade-sized error."""
    theta_bar = world.gamma @ x_mean - world.gamma @ np.array([0.6, 0.0, 0.0, 0.0])
    true = world.b + world.lam @ theta_bar
    err = np.array([rng.normal(0, TABLE_ERROR_SD[g]) for g in world.grade])
    err[world.anchor_of == np.arange(len(true))] = 0.0  # anchors are exact
    return true + err


def fit_offsets(d: Data, prior: np.ndarray, grade: tuple[str, ...], iters: int = 30) -> np.ndarray:
    """P094-style data update of the table: two-way model y = a_u + c_e, c_e shrunk to the table by grade."""
    c = prior.copy()
    prec_prior = np.array([1.0 / TABLE_ERROR_SD[g] ** 2 for g in grade])
    for _ in range(iters):
        a = np.bincount(d.u, weights=d.y - c[d.e], minlength=d.n_users) / np.maximum(
            np.bincount(d.u, minlength=d.n_users), 1)
        r = d.y - a[d.u]
        var = max(float(np.var(r - c[d.e])), 1e-4)
        num = np.bincount(d.e, weights=r, minlength=d.n_ex) / var + prec_prior * prior
        den = np.bincount(d.e, minlength=d.n_ex) / var + prec_prior
        c = num / den
    return c


def predict_offsets(c: np.ndarray, anchor_of: np.ndarray, e_obs: np.ndarray, y_obs: np.ndarray, e: int) -> float:
    """Anchor-equivalent averaging: same-anchor lifts if the user has any, otherwise all lifts."""
    same = anchor_of[e_obs] == anchor_of[e]
    use = same if same.any() else np.ones(len(e_obs), bool)
    return float(c[e] + np.mean(y_obs[use] - c[e_obs][use]))


# ------------------------------------------------------------------------------------------------- evaluation


def split_users(d: Data, test_users: np.ndarray) -> tuple[Data, list[tuple[np.ndarray, np.ndarray, np.ndarray]]]:
    is_test = np.isin(d.u, test_users)
    keep = ~is_test
    remap = -np.ones(d.n_users, int)
    train_users = np.setdiff1d(np.arange(d.n_users), test_users)
    remap[train_users] = np.arange(len(train_users))
    train = Data(remap[d.u[keep]], d.e[keep], d.y[keep], d.x[train_users], len(train_users), d.n_ex)
    tests = []
    for u in test_users:
        m = d.u == u
        tests.append((d.e[m], d.y[m], d.x[u]))
    return train, tests


def evaluate(world: World, n_train: int, seed: int, k: int, n_test: int = 1000) -> dict:
    rng = np.random.default_rng(seed + 1000)
    d = sample(world, n_train + n_test, seed)
    train, tests = split_users(d, np.arange(n_train, n_train + n_test))
    table = table_offsets(world, rng, train.x.mean(axis=0))
    updated = fit_offsets(train, table, world.grade)
    pr = Priors(table, np.array([TABLE_ERROR_SD[g] for g in world.grade]), world.group)
    model = fit(train, k, pr, seed=seed)
    err = {"latent": [], "table": [], "table_updated": [], "covariates_only": []}
    per_ex: dict[int, list[tuple[float, float]]] = {}
    for e_obs, y_obs, x in tests:
        if len(e_obs) < 2:
            continue
        j = int(rng.integers(len(e_obs)))
        e, y = int(e_obs[j]), float(y_obs[j])
        rest = np.arange(len(e_obs)) != j
        theta = model.fold_in(e_obs[rest], y_obs[rest], x)
        lat = model.predict(e, theta) - y
        upd = predict_offsets(updated, world.anchor_of, e_obs[rest], y_obs[rest], e) - y
        err["latent"].append(lat)
        err["table"].append(predict_offsets(table, world.anchor_of, e_obs[rest], y_obs[rest], e) - y)
        err["table_updated"].append(upd)
        err["covariates_only"].append(model.predict(e, model.prior_theta(x)) - y)
        per_ex.setdefault(e, []).append((abs(lat), abs(upd)))
    n_obs = np.bincount(train.e, minlength=train.n_ex)
    return {
        "n_train": n_train, "seed": seed, "k": k,
        "mae": {key: float(np.mean(np.abs(v))) for key, v in err.items()},
        "within10": {key: float(np.mean(np.abs(v) <= math.log(1.1))) for key, v in err.items()},
        "per_exercise": {e: (int(n_obs[e]), float(np.mean([a for a, _ in v])), float(np.mean([b for _, b in v])))
                         for e, v in per_ex.items()},
        "recovery": subspace_cos(world.lam, model.lam, n_obs >= 1),
    }


def subspace_cos(true: np.ndarray, est: np.ndarray, mask: np.ndarray) -> float:
    """Cosine of the largest principal angle between the true and fitted loading subspaces (1 = same span)."""
    k = min(true.shape[1], est.shape[1])
    qa, _ = np.linalg.qr(true[mask])
    qb, _ = np.linalg.qr(est[mask])
    s = np.linalg.svd(qa.T @ qb, compute_uv=False)
    return float(np.sort(s)[::-1][k - 1])


# ------------------------------------------------------------------------------------------------- experiments


def catalog_rows() -> list[dict]:
    from gymml.scoring_run import load_catalog

    out = []
    for ex in sorted(load_catalog().values(), key=lambda e: e.id):
        if ex.scorable and ex.scoring_type != "reps_only" and ex.anchor and ex.ratio:
            out.append({"id": ex.id, "movement_pattern": ex.movement_pattern, "anchor": ex.anchor,
                        "ratio": ex.ratio, "grade": "A" if ex.is_anchor else (ex.ratio_confidence or "C"),
                        "is_anchor": ex.is_anchor})
    return out


def run_all(quick: bool = False) -> dict:
    world = make_world(catalog_rows())
    sizes = [250, 1000, 2500] if quick else [250, 500, 1000, 2500, 5000, 10000, 20000]
    seeds = [1] if quick else [1, 2, 3]
    t0 = time.time()
    curve = [evaluate(world, n, s, k=3) for n in sizes for s in seeds]
    k_sel = [evaluate(world, n, 1, k=k) for n in ([1000] if quick else [1000, 5000]) for k in (1, 2, 3, 4, 5)]
    big = max(sizes)
    per_ex = [r for r in curve if r["n_train"] == big]
    sens_n = 1000 if quick else 5000
    sens = [(idio, evaluate(World(**{**world.__dict__, "idio_sd": idio}), sens_n, 1, k=k))
            for idio in (0.05, 0.10, 0.15) for k in (1, 3)]
    return {"world": world, "curve": curve, "k_selection": k_sel, "per_exercise_runs": per_ex,
            "sensitivity": sens, "sizes": sizes, "seeds": seeds, "seconds": time.time() - t0}


def _pct(mae: float) -> str:
    return f"%{100 * (math.exp(mae) - 1):.1f}"


def _by_size(curve: list[dict]) -> dict[int, dict]:
    out: dict[int, dict] = {}
    for n in sorted({r["n_train"] for r in curve}):
        rs = [r for r in curve if r["n_train"] == n]
        out[n] = {key: float(np.mean([r["mae"][key] for r in rs])) for key in rs[0]["mae"]}
        out[n]["within10_latent"] = float(np.mean([r["within10"]["latent"] for r in rs]))
        out[n]["within10_table_updated"] = float(np.mean([r["within10"]["table_updated"] for r in rs]))
        out[n]["recovery"] = float(np.mean([r["recovery"] for r in rs]))
    return out


MIN_GAIN = 0.05       # latent MAE at least 5 % below the data-updated table ...
MIN_RECOVERY = 0.90   # ... and the loading subspace recovered (shipped λ must be stable to be interpreted)


def gains(curve: list[dict]) -> dict[int, list[float]]:
    out: dict[int, list[float]] = {}
    for r in curve:
        out.setdefault(r["n_train"], []).append(1 - r["mae"]["latent"] / r["mae"]["table_updated"])
    return out


def threshold(curve: list[dict], min_gain: float = MIN_GAIN, min_recovery: float = MIN_RECOVERY) -> int | None:
    """Smallest N from which, at that N and every larger N, *every seed* has gain ≥ `min_gain` and recovery ≥
    `min_recovery`."""
    ok = {n for n in {r["n_train"] for r in curve}
          if all(1 - r["mae"]["latent"] / r["mae"]["table_updated"] >= min_gain and r["recovery"] >= min_recovery
                 for r in curve if r["n_train"] == n)}
    sizes = sorted({r["n_train"] for r in curve})
    for n in sizes:
        if all(m in ok for m in sizes if m >= n):
            return n
    return None


def per_exercise_bins(runs: list[dict]) -> list[tuple[str, int, float, float]]:
    bins = [(0, 100), (100, 300), (300, 1000), (1000, 3000), (3000, 10**9)]
    out = []
    for lo, hi in bins:
        lat, upd, n = [], [], 0
        for r in runs:
            for _, (cnt, a, b) in r["per_exercise"].items():
                if lo <= cnt < hi:
                    lat.append(a)
                    upd.append(b)
                    n += 1
        label = f"{lo}–{hi - 1}" if hi < 10**9 else f"≥ {lo}"
        if lat:
            out.append((label, n, float(np.mean(lat)), float(np.mean(upd))))
    return out


def render(res: dict) -> str:
    bs = _by_size(res["curve"])
    thr = threshold(res["curve"])
    g = gains(res["curve"])
    thr10 = threshold(res["curve"], min_gain=0.10)
    bins = per_exercise_bins(res["per_exercise_runs"])
    ex_thr = next((label for label, _, a, b in bins if a <= b), None)
    w = res["world"]
    lines = [
        "# P095 — v2 gizil faktör modeli: araştırma raporu",
        "",
        "> Otomatik üretildi: `make latent` (`gymml.research.latent`). Tablolar betikten; karar bölümü de betiğin "
        "eşik kuralından türetilir. Üretim kodu değildir.",
        "",
        "## Karar özeti",
        "",
        f"- **Etkinleştirme eşiği: {f'{thr:,}' if thr else '> ' + f'{max(bs):,}'} katkıcı** (önceki tahmin ~5.000). Kural: o "
        f"büyüklükte ve daha büyük her büyüklükte, *her tohumda* gizil model P094'ün veriyle güncellenen oran tablosundan "
        f"en az %{100 * MIN_GAIN:.0f} daha düşük hata verir ve yükleme uzayı geri kazanımı ≥ {MIN_RECOVERY}. Kazanç "
        f"büyüklüğe göre: " + ", ".join(f"{n:,}: %{100 * min(v):.0f}–{100 * max(v):.0f}" for n, v in sorted(g.items()))
        + f". %10 kuralıyla eşik {f'{thr10:,}' if thr10 else 'bulunamıyor'}: kazanç N ile büyümüyor (tablo da veriyle "
        "iyileşiyor), bu yüzden eşiği veri miktarından çok yapının geri kazanımı belirliyor.",
        ("- **Hareket başına koşul:** gizil model en az gözlemli bantta bile güncellenmiş tabloyu geçiyor; "
         "§12'deki \"hareket başına ≥ 300 gözlem\" koşulu gerekmiyor, çünkü b_e'nin önseli oran tablosu ve λ_e kalıp "
         "ortalamasına büzülüyor: az gözlemli hareket kendiliğinden tabloya düşer. Koşul yerine bu önseller zorunlu."
         if bins and ex_thr == bins[0][0] else
         f"- **Hareket başına koşul:** gizil model güncellenmiş tabloyu ilk **{ex_thr or 'hiçbir'}** gözlem bandında "
         "yakalıyor; altındaki hareketler için oran tablosu kullanılmaya devam eder (karma mod)."),
        "- Sentetik eşik yalnızca *denemeye değer* noktayı söyler; etkinleştirme, aynı ölçüt gerçek katkılarda (P094 "
        "dışarıda tutulan katkıcılar) sağlandığında ve P094 kalite kapılarıyla yapılır.",
        "- Seçilen biçim: düzenlileştirilmiş matris ayrıştırma + kovaryatlı önsel (hiyerarşik Gauss modelinin MAP'i); "
        "b_e önseli oran tablosu, λ_e önseli kalıp ortalaması. K veriyle seçilir: bu dünyada tahmin için K = 1–2 yetiyor, "
        "K = 3 ancak kişi × hareket uzmanlaşması küçükse kazanıyor (§3 duyarlılık) — dengesizlik yorumu için K ≥ 2 şart. "
        "Tam hiyerarşik Bayes (MCMC) şimdilik gereksiz: kestirim sunucuda, cihazda yalnızca K×K çözüm var.",
        "- **Öneri:** v2'yi ürünleştirmeden önce P094 hattına bir *gölge* adım ekle: her yeniden eğitimde gizil model de "
        "uyarlanır ve gerçek dışarıda tutulan katkılarda aynı hareket-gizleme ölçütüyle raporlanır; eşik gerçek veride "
        "sağlanınca (ve kullanıcı onayıyla) başlangıç ağırlığı önerisinden başlayarak açılır.",
        "",
        "## 1. Model",
        "",
        "```",
        "log e1RM_{u,e} = b_e + λ_e · θ_u + ε,      ε ~ N(0, σ²)",
        "θ_u ~ N(Γ x_u, I_K),  x_u = [erkek, (yaş − 35)/15, log(kilo/75), (boy − 172)/10]",
        "λ_e ~ N(0, s_λ² I_K)",
        "```",
        "",
        "- `b_e` hareketin zorluk sabiti (log ölçek), `λ_e` yükleme vektörü, `θ_u` kullanıcının güç vektörü "
        "(itiş / çekiş / alt vücut gibi yorumlanabilir ama dönmeye kadar belirlidir).",
        "- **Seçenekler:** (a) hiyerarşik Bayes (Stan/NumPyro; belirsizlik doğal, ama 10⁵–10⁶ gözlemde dakikalar–saatler "
        "ve CI'da ağır); (b) düzenlileştirilmiş matris ayrıştırma (ALS, saniyeler; belirsizlik θ'nın Laplace "
        "yaklaşımıyla: (ΛᵀΛ/σ² + I)⁻¹). Prototip (b); (a) yalnızca kalibrasyon kontrolü için önerilir.",
        "- Kovaryatlar θ'nın önsel ortalamasına girer: hiç hareket kaydetmemiş kullanıcı için tahmin Γx'tir "
        "(başlangıç ağırlığı), her yeni kayıt θ'yı kişiye doğru çeker.",
        "",
        "## 2. Sentetik dünya",
        "",
        f"- Gerçek katalogdaki {len(w.b)} skorlanan çapalı hareket; doğru yapı K = 3 (itiş / çekiş / alt), "
        "faktörler arası 0,7 korelasyon (genel güç), yüklemeler kalıptan + gürültü, log ölçekte hareket başına "
        "0,13–0,22 yayılım (P056: hücre içi SS 0,19–0,26 ile uyumlu).",
        f"- Kişi × hareket uzmanlaşması SS {w.idio_sd}, e1RM tahmin gürültüsü SS {w.noise_sd}: hiçbir modelin aşamayacağı "
        f"taban hata ≈ {_pct(math.sqrt(w.idio_sd**2 + w.noise_sd**2) * math.sqrt(2 / math.pi))} (MAE).",
        "- Eksiklik: her kullanıcı 5–15 hareket; seçim olasılığı popülerlik sırasıyla Zipf (çapalar ve A/B sınıfı önde) "
        "→ uzun kuyruktaki hareketler az gözlenir (gerçek uygulamadaki gibi).",
        "- Karşılaştırma: (1) P056 oran tablosu (sınıfına göre hata: A 0,03 / B 0,07 / C 0,20 log), (2) P094 gibi veriyle "
        "güncellenen tablo (iki yönlü model y = a_u + c_e, c_e tabloya büzülür), (3) gizil model, (4) yalnızca kovaryat.",
        "",
        "## 3. Değerlendirme: hiç yapılmamış hareketin e1RM tahmini",
        "",
        "Test kullanıcıları (1.000, eğitimde yok) için gözlenen hareketlerden biri gizlenir, kalanlardan tahmin edilir. "
        "Gizil modelde θ cihazdaki gibi katlanır (fold-in). Hata log ölçekte MAE, yüzde olarak gösterilir.",
        "",
        "| Katkıcı | Oran tablosu | Güncellenmiş tablo | Gizil (K=3) | Yalnız kovaryat | ±%10 içinde (gizil / tablo) | Yapı geri kazanımı |",
        "|---|---|---|---|---|---|---|",
    ]
    for n, v in bs.items():
        lines.append(f"| {n:,} | {_pct(v['table'])} | {_pct(v['table_updated'])} | {_pct(v['latent'])} | "
                     f"{_pct(v['covariates_only'])} | %{100 * v['within10_latent']:.0f} / %{100 * v['within10_table_updated']:.0f} | "
                     f"{v['recovery']:.3f} |")
    lines += [
        "",
        f"Her satır {len(res['seeds'])} tohumun ortalaması. Yapı geri kazanımı: gerçek ve kestirilen yükleme uzaylarının "
        "en büyük asal açısının kosinüsü (1 = aynı uzay).",
        "",
        "### Gizil boyut sayısı",
        "",
        "| Katkıcı | K | Gizil MAE | Güncellenmiş tablo MAE |",
        "|---|---|---|---|",
    ]
    for r in res["k_selection"]:
        lines.append(f"| {r['n_train']:,} | {r['k']} | {_pct(r['mae']['latent'])} | {_pct(r['mae']['table_updated'])} |")
    best = {}
    for r in res["k_selection"]:
        if r["n_train"] not in best or r["mae"]["latent"] < best[r["n_train"]][1]:
            best[r["n_train"]] = (r["k"], r["mae"]["latent"])
    lines += [
        "",
        "En iyi K: " + ", ".join(f"{n:,} katkıcıda K = {k}" for n, (k, _) in best.items())
        + ". Üretimde K, P094'teki dışarıda tutulan katkıcılarla aynı hareket-gizleme ölçütüyle seçilir; doğru K'dan "
        "büyük K, düzenlileştirme sayesinde az zarar verir.",
        "",
        "### Duyarlılık: kişi × hareket uzmanlaşması",
        "",
        "| Uzmanlaşma SS | K | Gizil MAE | Güncellenmiş tablo MAE | Yapı geri kazanımı |",
        "|---|---|---|---|---|",
        *[f"| {idio} | {r['k']} | {_pct(r['mae']['latent'])} | {_pct(r['mae']['table_updated'])} | {r['recovery']:.3f} |"
          for idio, r in res["sensitivity"]],
        "",
        "Uzmanlaşma büyüdükçe faktörler arası fark (itiş/çekiş/alt) az sayıda kayıttan ayırt edilemez ve K = 1 öne geçer. "
        "Gerçek veride bu SS, P094'teki oran kalıntılarından (`between_sd`) üst sınırla kestirilebilir.",
        "",
        f"### Hareket başına gözlem sayısı ({max(res['sizes']):,} katkıcı)",
        "",
        "| Eğitimdeki gözlem | Hareket × tohum | Gizil MAE | Güncellenmiş tablo MAE |",
        "|---|---|---|---|",
    ]
    for label, n, a, b in bins:
        lines.append(f"| {label} | {n} | {_pct(a)} | {_pct(b)} |")
    lines += [
        "",
        "## 4. Ürün etkisi",
        "",
        "- **Başlangıç ağırlığı önerisi:** bugün çapası olmayan bir harekete ilk girişte öneri yok ya da oran tablosundan "
        "kaba bir değer var. Gizil modelle tahmin, kullanıcının yaptığı *tüm* hareketlerden gelir (yukarıdaki tablo); "
        "8 tekrarlık öneri = e1RM⁻¹(tahmin, 8) × 0,9 güvenlik payı, ilk sette RIR sorusu. Hiç kaydı olmayan kullanıcıda "
        "Γx (kovaryat) tahmini kullanılır — hatası büyük, yalnızca \"hafif başla\" aralığı olarak gösterilmeli.",
        "- **Dengesizlik:** P059 kalıntı tabanlıydı; gizil modelde θ'nın bileşenleri (itiş/çekiş/alt) doğrudan karşılaştırılır "
        "ve kişinin kendi kovaryatlı beklentisine (Γx) göre sapma ölçülür; az hareketli kullanıcıda önsel baskın olduğu için "
        "yanlış alarm azalır.",
        "- **Genel skor:** §8 korelasyonlu birleştirme yerine θ'nın kovaryatlı nüfustaki yüzdeliği (Λ ağırlıklı) kullanılabilir. "
        "Geçişte iki skor bir süre paralel hesaplanır; P094'ün kayma kapısı (medyan ≤ 5 puan) aynen uygulanır.",
        "- **Hareket skoru:** değişmez (gözlenen e1RM'den yüzdelik); gizil model yalnızca *gözlenmemiş* hareketlere ve "
        "oranların yerine geçen b_e + λ_e θ̄ ofsetlerine dokunur.",
        "",
        "## 5. Cihazda çalışma",
        "",
        "- Paket `params.json`'a `latent` bloğu: b (E), Λ (E×K), Γ (K×P), σ², s_λ. K = 3, E ≈ 150 → ~600 sayı (~10 KB).",
        "- Kullanıcı vektörü cihazda kestirilir: θ̂ = (ΛₒᵀΛₒ/σ² + I)⁻¹ (Λₒᵀ(y − bₒ)/σ² + Γx); K×K (3×3) çözüm, "
        "mikro saniyeler. Belirsizlik aynı matrisin tersinden (güven rozeti). Ağ veya sunucu gerekmez; gizlilik modeli "
        "değişmez (θ cihazdan çıkmaz).",
        "- Swift tarafı StrengthKit'te ~100 satır (Accelerate/simd gerekmez, 3×3 Cholesky). Altın vektörlerle (1e-4) eşlik "
        "aynı yolla test edilir.",
        "",
        "## 6. Boy ve Core AI",
        "",
        "- Boy prototipte zaten kovaryat (x'in 4. bileşeni). Etkisi kilo verildiğinde küçüktür (kaldıraç kolu: uzun "
        "kullanıcılar squat/bench'te dezavantajlı, deadlift'te nötr) — modelde hareket başına işaretini λ_e·Γ belirler. "
        "Katkı şemasında `height_band` (5 cm) var; tam kovaryat için ek alan gerekmez. Çapa modeli (yarışmacı verisi) boy "
        "içermediği için boy yalnızca gizil modelde ve salon kalibrasyonunda kullanılabilir.",
        "- Core ML/Core AI: model küçük doğrusal cebir; bir ağ çerçevesine ihtiyacı yok. Apple'ın Core ML yerine geçen "
        "Core AI çerçevesine geçiş bu model için gerekmez; sinirsel bir çapa (P052 aday C) yeniden gündeme gelirse dönüşüm "
        "`coremltools` yerine yeni araç zinciriyle yapılmalı ve paket biçimi (`anchor.kind = coreml`) güncellenmeli.",
        "",
        "## 7. Sınırlar",
        "",
        "- Eşikler sentetik dünyaya koşulludur: gerçek veride yapı K = 3'ten karmaşık, uzmanlaşma daha büyük ve katkıcılar "
        "(P094) yanlı olabilir. Bu yüzden etkinleştirme, P094 hattında **gerçek** dışarıda tutulan katkılarla aynı ölçüt "
        "yeniden geçildiğinde yapılır; buradaki sayı yalnızca ne zaman denemeye değeceğini söyler.",
        "- Tek ay/tek set katkı biçimi kişi içi gürültüyü küçümseyebilir (bkz. P094 1RM eğrisi notu).",
        "- Seçim yanlılığı (güçlü olduğu hareketi yapma) modellenmedi; gerçek veride gizil modelin üstünlüğü azalabilir.",
        "",
        f"_Süre: {res['seconds']:.0f} sn; tohumlar {res['seeds']}; boyutlar {res['sizes']}._",
    ]
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="gymml.research.latent")
    ap.add_argument("--quick", action="store_true")
    args = ap.parse_args(argv)
    res = run_all(args.quick)
    REPORT.write_text(render(res), encoding="utf-8")
    print(f"report: {REPORT} ({res['seconds']:.0f} s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
