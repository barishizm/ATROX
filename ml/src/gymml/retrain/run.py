"""P094 · `make retrain`: contributions → k-anonymity → calibration + ratio update → gates → bundle + report.

    uv run python -m gymml.retrain.run --fetch                      # SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY
    uv run python -m gymml.retrain.run --contributions export.parquet [--version 1.1.0] [--sign]
    uv run python -m gymml.retrain.run --synthetic 6000             # end-to-end on synthetic data (runs/)

The base is the shipped bundle (StrengthKit embedded bundle: anchor tables + params) and the repository drafts it
was built from (`params_draft/`, `scoring_taxonomy.yaml`); the golden gate proves the two agree. The anchor
distribution model is not retrained (competitor data, P053). A failing gate writes the report and no bundle.
Publishing stays a separate, manual step (P063): `gymml.export.publish <bundle> --rollout 10`.
"""
# ruff: noqa: E501

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import tempfile
from dataclasses import dataclass, field
from datetime import UTC, date, datetime
from pathlib import Path

import polars as pl
import yaml

from gymml import imbalance, progress
from gymml.export import anchor_tables, golden, keys, params
from gymml.export.bundle import DIST, EMBEDDED, FORMAT, _dump
from gymml.retrain import calibration, contributions, curve, gates, ratios, synthetic
from gymml.retrain.contributions import InsufficientData
from gymml.scoring import ML_ROOT, PARAMS_DIR, AnchorModel, Params
from gymml.scoring_run import TAXONOMY, load_catalog

CONFIG = ML_ROOT / "configs" / "retrain.yaml"
REPORTS = ML_ROOT / "reports"
PROCESSED = ML_ROOT / "data" / "processed" / "retrain"
MODEL_CARD = ML_ROOT / "MODEL_CARD.md"


@dataclass
class Result:
    passed: bool
    version: str
    gates: list[gates.Gate]
    report: Path
    bundle: Path | None = None
    summary: dict = field(default_factory=dict)


def load_config(path: Path = CONFIG) -> dict:
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def _bump_minor(v: str) -> str:
    major, minor, _ = (int(x) for x in v.split("."))
    return f"{major}.{minor + 1}.0"


def _base(base_bundle: Path) -> tuple[Params, dict, AnchorModel, dict, dict]:
    p = Params.load()
    tables = json.loads((base_bundle / "anchor_tables.json").read_text(encoding="utf-8"))
    model = AnchorModel(anchor_tables.table_models(tables), p)
    manifest = json.loads((base_bundle / keys.MANIFEST).read_text(encoding="utf-8"))
    shipped = json.loads((base_bundle / "params.json").read_text(encoding="utf-8"))
    return p, load_catalog(), model, manifest, shipped


def _candidate_params_dir(tmp: Path, cal: dict, version: str) -> Path:
    d = tmp / "params_draft"
    shutil.copytree(PARAMS_DIR, d)
    doc = json.loads((d / "calibration.json").read_text(encoding="utf-8"))
    doc["calibration"] = dict(cal, status=f"P094 retrain v{version}: gym δ/κ updated from app contributions")
    (d / "calibration.json").write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return d


def _progress_imbalance():
    pp = progress.params_from_dict(json.loads(progress.DEFAULT_PARAMS_PATH.read_text(encoding="utf-8")))
    ip = imbalance.ImbalanceParams.from_dict(params.imbalance_draft_with_bundle_correlation())
    return pp, ip


def _write_bundle(out: Path, version: str, base_bundle: Path, base_manifest: dict, input_clip: dict,
                  params_dir: Path, cand: gates.Candidate, metrics: dict, training: dict, sign: bool,
                  public_key_b64: str = keys.PUBLIC_KEY_B64) -> Path:
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    pj = params.build_params(input_clip, params_dir)
    params.validate(pj, "params.schema.json")
    _dump(out / "params.json", pj)
    shutil.copy2(base_bundle / "anchor_tables.json", out / "anchor_tables.json")
    tax_rows = {r["id"]: r for r in yaml.safe_load(TAXONOMY.read_text(encoding="utf-8"))["exercises"]}
    _dump(out / "taxonomy.json", params.build_taxonomy(cand.catalog, tax_rows))
    pp, ip = _progress_imbalance()
    with tempfile.TemporaryDirectory() as tmp:
        golden.write_all(cand.catalog, cand.model, cand.params, pp, ip, out=Path(tmp))
        e2e = json.loads((Path(tmp) / "end_to_end.json").read_text(encoding="utf-8"))
    e2e["cases"] = e2e["cases"][:5]
    _dump(out / "smoke.json", e2e)
    manifest = {
        "format": FORMAT,
        "version": version,
        "schemaVersion": params.PARAMS_SCHEMA_VERSION,
        "minAppVersion": base_manifest["minAppVersion"],
        "createdAt": date.today().isoformat(),
        "anchor": base_manifest["anchor"],
        "files": {f.name: keys.sha256(f) for f in sorted(out.iterdir())},
        "trainingData": {**base_manifest["trainingData"], "retrain": training},
        "metrics": {**base_manifest["metrics"], "retrain": metrics},
    }
    params.validate(manifest, "manifest.schema.json")
    _dump(out / keys.MANIFEST, manifest)
    if sign:
        keys.sign_bundle(out, keys.load_private())
        keys.verify_bundle(out, public_key_b64)  # signed with the key the app trusts
    return out


def retrain(raw: pl.DataFrame, cfg: dict, version: str | None = None, out_root: Path = DIST,
            report_dir: Path = REPORTS, base_bundle: Path = EMBEDDED, sign: bool = False,
            golden_ref: Path = golden.GOLDEN_DIR, processed_dir: Path | None = PROCESSED,
            source: str = "ml_contributions", update_model_card: bool = False,
            public_key_b64: str = keys.PUBLIC_KEY_B64) -> Result:
    p, cat, model, base_manifest, shipped = _base(base_bundle)
    version = version or _bump_minor(base_manifest["version"])
    ex_cfg, g_cfg = cfg["export"], cfg["gates"]

    filtered, frep = contributions.k_anonymize(raw, ex_cfg["k_anonymity"], ex_cfg["weight_band_kg"])
    anchor_ids = {e.id for e in cat.values() if e.is_anchor}
    sufficiency = contributions.check_sufficient(filtered, anchor_ids, ex_cfg)  # raises InsufficientData
    if processed_dir is not None:
        processed_dir.mkdir(parents=True, exist_ok=True)
        filtered.write_parquet(processed_dir / f"contributions-{date.today().isoformat()}.parquet")

    held = contributions.holdout_mask(filtered, ex_cfg["holdout_fraction"], ex_cfg["seed"])
    train, hold = filtered.filter(~held), filtered.filter(held)

    obs = calibration.anchor_observations(contributions.latest_per_lift(train), cat, model, p)
    new_cal, cal_rep = calibration.update(obs, p, cfg["calibration"])
    pairs = ratios.paired_log_ratios(train, cat)
    new_cat, ratio_rows = ratios.update(pairs, cat, p, cfg["ratios"])
    ratio_problems = ratios.implausible(ratio_rows, cfg["ratios"]["max_ratio_change"])

    pp, ip = _progress_imbalance()
    gate_list: list[gates.Gate] = []
    with tempfile.TemporaryDirectory() as tmp_s:
        tmp = Path(tmp_s)
        params_dir = _candidate_params_dir(tmp, new_cal, version)
        cand = gates.Candidate(Params.load(params_dir), new_cat, model)
        base = gates.Candidate(p, cat, model)

        g = gates.golden_gate(lambda out: golden.write_all(cat, model, p, pp, ip, out=out),
                              g_cfg["golden_tolerance"], golden_ref)
        rebuilt = params.build_params(shipped["inputClip"])
        if (m := gates._numbers_close(rebuilt, shipped, g_cfg["golden_tolerance"])) is not None:
            g.passed = False
            g.detail["mismatches"]["params.json"] = m
        gate_list.append(g)

        rows = contributions.latest_per_lift(hold)
        if rows.height > g_cfg["max_rows"]:
            rows = rows.sample(g_cfg["max_rows"], seed=ex_cfg["seed"])
        old = gates.score_rows(rows, base)
        new = gates.score_rows(rows, cand)
        gate_list.append(gates.calibration_gate(hold, base, cand, g_cfg))
        gate_list.append(gates.drift_gate(old, new, g_cfg))
        gate_list.append(gates.sanity_gate(new, cand, cfg["calibration"]["kappa_bounds"], ratio_problems,
                                           g_cfg["monotonic_grid"]))
        passed = all(x.passed for x in gate_list)

        summary = {
            "filter": frep.as_dict(), "sufficiency": sufficiency,
            "split": {"train_contributors": train["contribution_key"].n_unique(),
                      "holdout_contributors": hold["contribution_key"].n_unique()},
            "calibration": cal_rep, "ratios": ratios.summary(ratio_rows), "curve": curve.identifiability(train),
            "gates": {x.name: {"passed": x.passed, **x.detail} for x in gate_list},
        }
        bundle = None
        if passed:
            metrics = {k: summary[k] for k in ("filter", "split", "ratios")}
            metrics["gates"] = summary["gates"]
            training = {"source": source, "exported": date.today().isoformat(),
                        "contributors": frep.contributors_out, "rows": frep.rows_out,
                        "k_anonymity": ex_cfg["k_anonymity"]}
            bundle = _write_bundle(out_root / f"model-bundle-v{version}", version, base_bundle, base_manifest,
                                   shipped["inputClip"], params_dir, cand, metrics, training, sign,
                                   public_key_b64)

    report_dir.mkdir(parents=True, exist_ok=True)
    report = report_dir / f"retrain-{version}.md"
    report.write_text(render(version, base_manifest["version"], summary, ratio_rows, bundle, cfg, source),
                      encoding="utf-8")
    if passed and update_model_card:
        _model_card_row(version, summary, source)
    return Result(passed, version, gate_list, report, bundle, summary)


def _f(x, nd: int = 3) -> str:
    return "—" if x is None else f"{x:.{nd}f}"


def render(version: str, base_version: str, s: dict, ratio_rows: list[dict], bundle: Path | None, cfg: dict,
           source: str) -> str:
    f, cal, rs, cv = s["filter"], s["calibration"], s["ratios"], s["curve"]
    ok = bundle is not None
    lines = [
        f"# P094 — Yeniden eğitim raporu v{version}",
        "",
        "> Otomatik üretildi: `make retrain` (`gymml.retrain.run`). Elle düzenlemeyin.",
        "",
        "## Özet",
        "",
        f"- Sonuç: **{'GEÇTİ — paket yazıldı' if ok else 'KALDI — paket yazılmadı, yayınlanmaz'}** (temel sürüm v{base_version}).",
        f"- Kaynak: `{source}`; {f['contributors_in']} katkıcı / {f['rows_in']} satır → k-anonimlik süzgecinden sonra "
        f"{f['contributors_out']} katkıcı / {f['rows_out']} satır.",
        f"- Süzülen hücre: **{f['cells_dropped']} / {f['cells_in']}** (cinsiyet × yaş bandı × "
        f"{cfg['export']['weight_band_kg']} kg kilo bandı × hareket, hücre başına < {cfg['export']['k_anonymity']} katkıcı).",
        f"- Ayrım: {s['split']['train_contributors']} eğitim / {s['split']['holdout_contributors']} dışarıda tutulan katkıcı (anahtara göre).",
        f"- Oranlar: {rs['updated']} hareket güncellendi, {rs['upgraded']} sınıf yükseldi, {rs['conflicts']} önsel–veri çelişkisi.",
        "",
        "## Kalite kapıları",
        "",
        "| Kapı | Sonuç | Ayrıntı |",
        "|---|---|---|",
    ]
    for name, g in s["gates"].items():
        detail = ", ".join(f"{k}={_f(v) if isinstance(v, float) else v}" for k, v in g.items() if k != "passed")
        lines.append(f"| {name} | {'✅' if g['passed'] else '❌'} | {detail} |")
    lines += [
        "",
        "## Kalibrasyon güncellemesi (salon nüfusu)",
        "",
        f"Önsel ağırlığı w = max({cfg['calibration']['prior_weight_floor']}, n0 / (n0 + n)), n0 = "
        f"{cfg['calibration']['prior_pseudo_n']}. Önsel **sıfırlanmaz**: uygulama kullanıcıları rastgele bir salon örneği "
        "değildir (her seti kaydeden kişi ortalamadan daha ciddidir, bırakanlar veriden çıkar, e1RM kullanıcının "
        "girdiği setten gelir). P055 çapaları bu yüzden veri ne kadar büyürse büyüsün en az taban payını korur. "
        f"Genel nüfus (`general`) uygulama verisiyle güncellenmez; hücre başına < {cfg['calibration']['min_cell_contributors']} "
        "katkıcıda önsel aynen kalır. Belirsizlik bandı (P055) değişmedi.",
        "",
        "| Cinsiyet | Kaldırış | Yaş bandı | n | Önsel δ | Veri δ̂ | w_önsel | Sonsal δ |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for c in cal["cells"]:
        lines.append(f"| {c['sex']} | {c['lift']} | {c['band']} | {c['n']} | {_f(c['prior'], 4)} | "
                     f"{_f(c['estimate'], 4)} | {_f(c['w_prior'], 2)} | {_f(c['posterior'], 4)} |")
    lines += ["", "| Cinsiyet | n | Önsel κ | Veri κ̂ | Sonsal κ |", "|---|---|---|---|---|"]
    for sex, k in cal["kappa"].items():
        lines.append(f"| {sex} | {k['n']} | {_f(k['prior'], 4)} | {_f(k['estimate'], 4)} | {_f(k['posterior'], 4)} |")
    changed = [r for r in ratio_rows if r["changed"]]
    lines += [
        "",
        "## Oran güncellemesi",
        "",
        "Aynı ay hem hareketi hem çapasını kaydeden katkıcılardan d = log e1RM_e − log e1RM_çapa. log ρ için normal önsel "
        "(sınıf SS'si) + veri; τ² için ölçekli ters ki-kare (ν0 = "
        f"{cfg['ratios']['tau_pseudo_df']}). τ yeni sınıfın tabanının altına inmez; makine/kablo C'de kalır; sınıf düşmez.",
        "",
        "| Hareket | n | Önsel ρ | Yeni ρ | Önsel τ | Yeni τ | Sınıf | Not |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for r in changed[:60]:
        lines.append(f"| {r['exercise_id']} | {r['n']} | {r['prior_ratio']} | {r['ratio']} | {r['prior_tau']} | "
                     f"{r['tau']} | {r['prior_grade']}→{r['grade']} | {r['note']} |")
    if len(changed) > 60:
        lines.append(f"| … {len(changed) - 60} hareket daha | | | | | | | |")
    lines += [
        "",
        "## 1RM eğrisi",
        "",
        "Eğri **yeniden kestirilmedi**. Öz-denetimli kayıp (P054) aynı kişinin aynı hareketini yakın zamanda farklı "
        "tekrarlarla görmeyi gerektirir; katkı satırı ay başına tek sayı (en iyi e1RM, eski eğriyle hesaplanmış) ve o "
        "setin tekrarını taşır. Ay içi karşıtlık yok; aylar arası tekrar farkı gelişimle karışık.",
        "",
        f"- Katkıcı × hareket: {cv['contributor_lifts']}; ≥ 2 ay: {cv['with_two_or_more_months']}; "
        f"≥ 2 farklı tekrar sayısı: {cv['with_two_or_more_rep_counts']}; ay içi karşıtlık: {cv['within_month_contrasts']}.",
        f"- Önerilen en küçük şema eki (kullanıcı kararı): `{curve.PROPOSAL['field']}` — {curve.PROPOSAL['shape']}. "
        f"{curve.PROPOSAL['meaning']}. Gizlilik: {curve.PROPOSAL['privacy']}.",
        "",
        "## Yayın",
        "",
    ]
    if ok:
        lines += [
            f"Paket: `{bundle.relative_to(ML_ROOT) if bundle.is_relative_to(ML_ROOT) else bundle}`. Yayın P063 betiğiyle, "
            f"önce %{cfg['rollout']['initial_percent']} kademeli dağıtım:",
            "",
            "```bash",
            f"uv run python -m gymml.export.publish dist/model-bundle-v{version} --rollout {cfg['rollout']['initial_percent']} --activate",
            "```",
            "",
            "Kademeli dağıtımda skor değişim şikâyeti / duman testi hatası yoksa `model_versions.rollout_percent` 100'e çekilir.",
        ]
    else:
        lines.append("Kapıdan geçemeyen paket yazılmadı. Mevcut paket yayında kalır.")
    return "\n".join(lines) + "\n"


def _model_card_row(version: str, s: dict, source: str) -> None:
    text = MODEL_CARD.read_text(encoding="utf-8")
    g = s["gates"]
    row = (f"| {version} | {date.today().isoformat()} | {source}: {s['filter']['contributors_out']} katkıcı "
           f"(k ≥ 20) | Salon δ/κ + {s['ratios']['updated']} oran güncellendi | KS {_f(g['calibration']['ks_candidate'])}, "
           f"kayma medyanı {_f(g['drift']['median_abs_change'], 2)} | `reports/retrain-{version}.md`; %10 kademeli |")
    MODEL_CARD.write_text(text.rstrip("\n") + "\n" + row + "\n", encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="gymml.retrain.run")
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--contributions", type=Path, help="Parquet / CSV / JSON export of ml_contributions")
    src.add_argument("--fetch", action="store_true", help="read ml_contributions with the service role")
    src.add_argument("--synthetic", type=int, metavar="N", help="N synthetic contributors (writes under runs/)")
    ap.add_argument("--version")
    ap.add_argument("--sign", action="store_true")
    ap.add_argument("--config", type=Path, default=CONFIG)
    args = ap.parse_args(argv)
    cfg = load_config(args.config)

    kwargs: dict = {"version": args.version, "sign": args.sign}
    if args.synthetic:
        p, cat, model, _, _ = _base(EMBEDDED)
        truth = synthetic.Truth(delta_shift=0.05, kappa_factor=0.9)
        raw = synthetic.generate(args.synthetic, cat, model, p, truth, seed=cfg["export"]["seed"])
        run_dir = ML_ROOT / "runs" / f"{datetime.now(UTC):%Y%m%dT%H%M%SZ}-retrain-synthetic"
        kwargs.update(out_root=run_dir, report_dir=run_dir, processed_dir=None, source="synthetic")
    elif args.fetch:
        url, key = os.environ.get("SUPABASE_URL"), os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
        if not url or not key:
            print("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set", file=sys.stderr)
            return 2
        raw = contributions.fetch(url, key)
        kwargs["update_model_card"] = True
    else:
        raw = contributions.read(args.contributions)
        kwargs["update_model_card"] = True
    try:
        res = retrain(raw, cfg, **kwargs)
    except InsufficientData as e:
        print(f"retrain stopped: {e}", file=sys.stderr)
        return 3
    for g in res.gates:
        print(f"{'PASS' if g.passed else 'FAIL'} {g.name}: {json.dumps(g.detail, default=str)[:300]}")
    print(f"report: {res.report}")
    if not res.passed:
        print("quality gates failed: no bundle written", file=sys.stderr)
        return 1
    print(f"bundle: {res.bundle}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
