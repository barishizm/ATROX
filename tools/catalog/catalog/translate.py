"""catalog-translate (P026): Turkish names, aliases and instructions for the exercise catalog.

Pipeline: glossary (must be approved) -> batched LLM translation via OpenRouter -> JSON-schema validation
-> content-addressed cache -> locked human-approved core rows -> out/exercises.{tr,en}.json.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import random
import re
import sys
import time
import unicodedata
import urllib.error
import urllib.request
from pathlib import Path
from typing import Callable

import jsonschema
import yaml

ROOT = Path(__file__).resolve().parent.parent
MODEL = "deepseek/deepseek-v4.1-flash"
PROVIDERS = {  # name -> (chat-completions URL, API-key env var, default model)
    "openrouter": ("https://openrouter.ai/api/v1/chat/completions", "OPENROUTER_API_KEY", MODEL),
    "deepseek": ("https://api.deepseek.com/chat/completions", "DEEPSEEK_API_KEY", "deepseek-flash"),
}
PROMPT_VERSION = 2
APPROVED_VALUES = {"1", "yes", "y", "true", "x", "evet", "e"}
CSV_COLUMNS = ["id", "name_en", "name_tr", "aliases_tr", "aliases_en", "instructions_tr", "approved"]

Client = Callable[[list[dict]], str]

RESPONSE_SCHEMA = {
    "type": "object",
    "required": ["exercises"],
    "additionalProperties": False,
    "properties": {"exercises": {"type": "array", "items": {
        "type": "object",
        "required": ["id", "name_tr", "aliases_tr", "aliases_en", "instructions_tr"],
        "additionalProperties": False,
        "properties": {
            "id": {"type": "string", "minLength": 1},
            "name_tr": {"type": "string", "minLength": 1},
            "aliases_tr": {"type": "array", "items": {"type": "string", "minLength": 1}},
            "aliases_en": {"type": "array", "items": {"type": "string", "minLength": 1}},
            "instructions_tr": {"type": "array", "items": {"type": "string", "minLength": 1}},
        },
    }}},
}

SYSTEM_PROMPT = """You translate gym exercise data from English to Turkish for a Turkish fitness app.
Write the way Turkish gym-goers actually talk: keep widespread English gym terms (bench press, lat pulldown, ...).
Rules:
1. The GLOSSARY lists mandatory terms. If an English name contains a glossary `en` term, the Turkish name MUST
   contain the glossary `tr` text. Use the instruction_terms wording in instructions.
2. Use Title Case for names (Turkish casing: İ/ı). Keep numbers and proper nouns (Arnold, Smith, Zottman).
3. Instructions: address the reader with the informal singular imperative ("sen": "otur", "tut", "kaldır"), never the
   formal/plural form ("oturun", "tutun"). Use "halter" and "dambıl" for barbell/dumbbell inside instructions
   (names keep the glossary form). Translate every English word that has a normal Turkish equivalent
   (stretch → esneme, raise → kaldırma); keep only glossary terms that stay English.
   `instructions_tr` MUST have exactly the same number of items, in the same order, as the source `instructions`.
   Translate each step as one natural, imperative Turkish sentence. Do not merge, split or add steps.
4. `aliases_tr`: other Turkish names people search for (max 3). `aliases_en`: common alternative English names or
   spellings of the same exercise (max 3, e.g. "Pull-up" for "Pullups"). Never repeat the main name.
5. Reply with ONE JSON object only: {"exercises":[{"id","name_tr","aliases_tr","aliases_en","instructions_tr"}]}
   with every input id exactly once. No markdown, no commentary."""


# ---------------------------------------------------------------- text helpers

_TR_FOLD = str.maketrans({"ç": "c", "ğ": "g", "ı": "i", "ö": "o", "ş": "s", "ü": "u",
                          "Ç": "C", "Ğ": "G", "İ": "I", "I": "I", "Ö": "O", "Ş": "S", "Ü": "U"})


def fold_ascii(text: str) -> str:
    """Accent-free spelling ('Barfiks Çekiş' -> 'Barfiks Cekis')."""
    text = text.translate(_TR_FOLD)
    return "".join(c for c in unicodedata.normalize("NFKD", text) if not unicodedata.combining(c))


def tr_lower(text: str) -> str:
    """Case-insensitive comparison key. Plain I -> i (not Turkish dotless ı) so English terms like 'Incline' match."""
    return text.replace("İ", "i").replace("ı", "i").lower()


def _stem(token: str) -> str:
    return token[:-1] if len(token) > 3 and token.endswith("s") else token


def _tokens(text: str) -> list[str]:
    return [_stem(t) for t in re.split(r"[^a-z0-9]+", text.lower()) if t]


# ---------------------------------------------------------------- glossary

class Glossary:
    def __init__(self, data: dict):
        self.approved = bool(data.get("approved"))
        self.version = data.get("version", 1)
        self.terms = data.get("terms") or []
        self.instruction_terms = data.get("instruction_terms") or []
        self._patterns: list[tuple[tuple[str, ...], dict]] = []
        for term in self.terms:
            for pat in term["en"]:
                self._patterns.append((tuple(_tokens(pat)), term))
        # longest pattern first so "calf raise" wins over "raise"
        self._patterns.sort(key=lambda p: -len(p[0]))
        self.fingerprint = hashlib.sha256(json.dumps(data, sort_keys=True, ensure_ascii=False).encode()).hexdigest()[:16]

    @classmethod
    def load(cls, path: Path) -> "Glossary":
        return cls(yaml.safe_load(path.read_text(encoding="utf-8")))

    def match(self, name: str) -> list[dict]:
        """Glossary terms that apply to an English exercise name (longest, non-overlapping matches)."""
        toks = _tokens(name)
        used = [False] * len(toks)
        found: list[dict] = []
        for pat, term in self._patterns:
            n = len(pat)
            if not n:
                continue
            for i in range(len(toks) - n + 1):
                if tuple(toks[i:i + n]) == pat and not any(used[i:i + n]):
                    for j in range(i, i + n):
                        used[j] = True
                    if term not in found:
                        found.append(term)
        return found

    def violations(self, name_en: str, name_tr: str) -> list[str]:
        low = tr_lower(name_tr)
        return [f"'{t['en'][0]}' requires '{t['tr']}'" for t in self.match(name_en) if tr_lower(t["tr"]) not in low]

    def prompt_subset(self, exercises: list[dict]) -> dict:
        terms = {}
        for ex in exercises:
            for t in self.match(ex["name"]):
                terms[t["en"][0]] = {"en": t["en"], "tr": t["tr"]}
        return {"terms": list(terms.values()), "instruction_terms": self.instruction_terms}


# ---------------------------------------------------------------- LLM

def llm_client(url: str, api_key: str, model: str, retries: int = 4) -> Client:
    def call(messages: list[dict]) -> str:
        body = json.dumps({"model": model, "messages": messages, "temperature": 0,
                           "response_format": {"type": "json_object"}}).encode()
        req = urllib.request.Request(url, data=body, headers={
            "Authorization": f"Bearer {api_key}", "Content-Type": "application/json",
            "X-Title": "atrox-catalog"})  # generic client name only
        for attempt in range(retries):
            try:
                with urllib.request.urlopen(req, timeout=180) as r:
                    return json.loads(r.read())["choices"][0]["message"]["content"]
            except (urllib.error.URLError, TimeoutError, KeyError, json.JSONDecodeError) as e:
                retryable = not isinstance(e, urllib.error.HTTPError) or e.code in (408, 429, 500, 502, 503, 504)
                if attempt == retries - 1 or not retryable:
                    raise
                time.sleep(2 ** attempt)
        raise RuntimeError("unreachable")
    return call


def build_messages(batch: list[dict], glossary: Glossary) -> list[dict]:
    payload = {
        "glossary": glossary.prompt_subset(batch),
        "exercises": [{"id": e["id"], "name": e["name"], "instructions": e["instructions"]} for e in batch],
    }
    return [{"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": json.dumps(payload, ensure_ascii=False)}]


def parse_response(raw: str, batch: list[dict]) -> dict[str, dict]:
    """Parse + validate one LLM reply against the schema and the source batch. Raises ValueError on any defect."""
    text = raw.strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*|\s*```$", "", text)
    try:
        data = json.loads(text)
        jsonschema.validate(data, RESPONSE_SCHEMA)
    except (json.JSONDecodeError, jsonschema.ValidationError) as e:
        raise ValueError(f"invalid response: {str(e).splitlines()[0]}") from e
    got = {r["id"]: r for r in data["exercises"]}
    want = {e["id"]: e for e in batch}
    if len(got) != len(data["exercises"]) or set(got) != set(want):
        raise ValueError(f"id mismatch: missing={sorted(set(want) - set(got))} extra={sorted(set(got) - set(want))}")
    for id_, row in got.items():
        if len(row["instructions_tr"]) != len(want[id_]["instructions"]):
            raise ValueError(f"{id_}: {len(row['instructions_tr'])} instruction steps, expected {len(want[id_]['instructions'])}")
    return got


# ---------------------------------------------------------------- cache

class Cache:
    def __init__(self, path: Path):
        self.path = path
        self.data: dict[str, dict] = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}

    @staticmethod
    def key(ex: dict, glossary: Glossary, model: str) -> str:
        blob = json.dumps({"v": PROMPT_VERSION, "model": model, "name": ex["name"], "instructions": ex["instructions"],
                           "glossary": glossary.prompt_subset([ex])}, sort_keys=True, ensure_ascii=False)
        return hashlib.sha256(blob.encode()).hexdigest()

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps(self.data, indent=1, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")


def translate_missing(exercises: list[dict], glossary: Glossary, cache: Cache, client: Client | None, *,
                      model: str = MODEL, batch_size: int = 8, attempts: int = 3,
                      log: Callable[[str], None] = lambda s: None) -> dict:
    """Translate every exercise without a cache hit. Returns stats; failures are listed, not raised."""
    todo = [e for e in exercises if Cache.key(e, glossary, model) not in cache.data]
    stats = {"cached": len(exercises) - len(todo), "requested": 0, "calls": 0, "failed": []}
    if not todo:
        return stats
    if client is None:
        stats["failed"] = [e["id"] for e in todo]
        return stats
    for i in range(0, len(todo), batch_size):
        batch = todo[i:i + batch_size]
        rows, err = None, ""
        for _ in range(attempts):
            stats["calls"] += 1
            try:
                rows = parse_response(client(build_messages(batch, glossary)), batch)
                break
            except ValueError as e:
                err = str(e)
        if rows is None:
            log(f"batch {i // batch_size} failed: {err}")
            stats["failed"] += [e["id"] for e in batch]
            continue
        for ex in batch:
            row = dict(rows[ex["id"]])
            row["glossary_violations"] = glossary.violations(ex["name"], row["name_tr"])
            cache.data[Cache.key(ex, glossary, model)] = row
            stats["requested"] += 1
        cache.save()
        log(f"translated {min(i + batch_size, len(todo))}/{len(todo)}")
    return stats


# ---------------------------------------------------------------- locked review rows

def _split(cell: str) -> list[str]:
    return [p.strip() for p in cell.split(" | ") if p.strip()]


def load_locked(path: Path) -> dict[str, dict]:
    if not path.exists():
        return {}
    locked: dict[str, dict] = {}
    with path.open(encoding="utf-8", newline="") as f:
        for r in csv.DictReader(f):
            if (r.get("approved") or "").strip().lower() in APPROVED_VALUES:
                locked[r["id"]] = {
                    "name_tr": r["name_tr"].strip(),
                    "aliases_tr": _split(r["aliases_tr"]),
                    "aliases_en": _split(r["aliases_en"]),
                    "instructions_tr": [s.strip() for s in r["instructions_tr"].split("\n") if s.strip()],
                }
    return locked


def write_review(path: Path, core_ids: list[str], base: dict[str, dict], resolved: dict[str, dict],
                 previous: dict[str, dict]) -> int:
    """Write review/tr_core.csv for the core set. Approved rows keep their (possibly hand-edited) text."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, CSV_COLUMNS)
        w.writeheader()
        for id_ in core_ids:
            approved = id_ in previous
            tr = previous[id_] if approved else resolved.get(id_)
            if tr is None:
                continue
            w.writerow({"id": id_, "name_en": base[id_]["name"], "name_tr": tr["name_tr"],
                        "aliases_tr": " | ".join(tr["aliases_tr"]), "aliases_en": " | ".join(tr["aliases_en"]),
                        "instructions_tr": "\n".join(tr["instructions_tr"]), "approved": "yes" if approved else ""})
    return len(previous)


# ---------------------------------------------------------------- assembly

def _dedupe(values: list[str], exclude: str) -> list[str]:
    seen = {tr_lower(exclude)}
    out = []
    for v in values:
        v = v.strip()
        if v and tr_lower(v) not in seen:
            seen.add(tr_lower(v))
            out.append(v)
    return out


def aliases_for(name_en: str, tr: dict, own_name: str) -> list[str]:
    """Search aliases: Turkish name, common English names, accent-free spellings. Excludes the entry's own name."""
    cands = [tr["name_tr"], name_en, *tr["aliases_tr"], *tr["aliases_en"]]
    cands += [fold_ascii(c) for c in cands]
    return _dedupe(cands, own_name)


def assemble(exercises: list[dict], resolved: dict[str, dict]) -> tuple[list[dict], list[dict], list[str]]:
    tr_out, en_out, problems = [], [], []
    for ex in exercises:
        tr = resolved.get(ex["id"])
        if tr is None:
            problems.append(f"{ex['id']}: no translation")
            continue
        if len(tr["instructions_tr"]) != len(ex["instructions"]):
            problems.append(f"{ex['id']}: instruction count {len(tr['instructions_tr'])} != {len(ex['instructions'])}")
            continue
        tr_out.append({"id": ex["id"], "name": tr["name_tr"], "aliases": aliases_for(ex["name"], tr, tr["name_tr"]),
                       "instructions": tr["instructions_tr"]})
        en_out.append({"id": ex["id"], "name": ex["name"], "aliases": aliases_for(ex["name"], tr, ex["name"]),
                       "instructions": ex["instructions"]})
    return tr_out, en_out, problems


def resolve_all(exercises: list[dict], glossary: Glossary, cache: Cache, locked: dict[str, dict],
                model: str = MODEL) -> dict[str, dict]:
    resolved = {}
    for ex in exercises:
        if ex["id"] in locked:
            resolved[ex["id"]] = locked[ex["id"]]
        elif (hit := cache.data.get(Cache.key(ex, glossary, model))) is not None:
            resolved[ex["id"]] = hit
    return resolved


def sample_table(en: list[dict], tr: list[dict], n: int, seed: int) -> str:
    tr_by = {t["id"]: t for t in tr}
    picks = random.Random(seed).sample(en, min(n, len(en)))
    lines = ["| # | EN | TR | EN step 1 | TR step 1 |", "|---|---|---|---|---|"]
    for i, e in enumerate(picks, 1):
        t = tr_by[e["id"]]
        s_en = (e["instructions"][:1] or [""])[0].replace("|", "\\|")
        s_tr = (t["instructions"][:1] or [""])[0].replace("|", "\\|")
        lines.append(f"| {i} | {e['name']} | {t['name']} | {s_en} | {s_tr} |")
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------- CLI

def _load(root: Path):
    base = json.loads((root / "out" / "exercises.base.json").read_text(encoding="utf-8"))
    tax = yaml.safe_load((root / "scoring_taxonomy.yaml").read_text(encoding="utf-8"))["exercises"]
    core_ids = [t["id"] for t in tax if t["is_core"]]
    return base, core_ids


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("command", choices=["run", "review", "sample", "check"])
    ap.add_argument("--root", type=Path, default=ROOT)
    ap.add_argument("--provider", choices=sorted(PROVIDERS), default="openrouter")
    ap.add_argument("--model", help="default depends on --provider")
    ap.add_argument("--batch-size", type=int, default=8)
    ap.add_argument("--limit", type=int, help="run: translate only the first N untranslated exercises")
    ap.add_argument("--dry-run", action="store_true", help="run: count what would be requested, call nothing")
    ap.add_argument("--allow-unapproved-glossary", action="store_true")
    ap.add_argument("-n", type=int, default=20, help="sample: how many exercises")
    ap.add_argument("--seed", type=int, default=26)
    a = ap.parse_args(argv)

    url, key_env, default_model = PROVIDERS[a.provider]
    a.model = a.model or default_model
    root = a.root
    base, core_ids = _load(root)
    by_id = {e["id"]: e for e in base}
    glossary = Glossary.load(root / "glossary.tr.yaml")
    cache = Cache(root / "translations" / "cache.json")
    review_csv = root / "review" / "tr_core.csv"
    locked = load_locked(review_csv)
    out = root / "out"

    if a.command == "run":
        need = [e for e in base if e["id"] not in locked and Cache.key(e, glossary, a.model) not in cache.data]
        if a.limit:
            need = need[:a.limit]
        print(f"{len(base)} exercises, {len(locked)} locked, {len(need)} to translate")
        if a.dry_run or not need:
            pass
        else:
            if not glossary.approved and not a.allow_unapproved_glossary:
                print("glossary.tr.yaml is not approved (approved: false); get it approved first.", file=sys.stderr)
                return 2
            key = os.environ.get(key_env)
            if not key:
                print(f"{key_env} is not set.", file=sys.stderr)
                return 2
            st = translate_missing(need, glossary, cache, llm_client(url, key, a.model), model=a.model,
                                   batch_size=a.batch_size, log=print)
            print(f"requested={st['requested']} calls={st['calls']} failed={len(st['failed'])}")
        resolved = resolve_all(base, glossary, cache, locked, a.model)
        tr_out, en_out, problems = assemble(base, resolved)
        viol = [i for i, r in resolved.items() if r.get("glossary_violations")]
        if viol:
            print(f"{len(viol)} translations violate the glossary (see cache 'glossary_violations'): {viol[:5]}...")
        if problems:
            print(f"{len(problems)} exercises incomplete; outputs not written. First: {problems[:3]}", file=sys.stderr)
            return 1
        out.mkdir(parents=True, exist_ok=True)
        for name, rows in (("exercises.tr.json", tr_out), ("exercises.en.json", en_out)):
            (out / name).write_text(json.dumps(rows, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"wrote {len(tr_out)} exercises to {out}")
        return 0

    resolved = resolve_all(base, glossary, cache, locked, a.model)
    if a.command == "review":
        n = write_review(review_csv, core_ids, by_id, resolved, locked)
        missing = [i for i in core_ids if i not in resolved]
        print(f"{review_csv}: {len(core_ids)} core ids, {n} approved/locked, {len(missing)} not yet translated")
        return 0
    tr_out, en_out, problems = assemble(base, resolved)
    if a.command == "sample":
        if problems:
            print("incomplete translations; run `run` first", file=sys.stderr)
            return 1
        print(sample_table(en_out, tr_out, a.n, a.seed))
        return 0
    # check
    core_unapproved = [i for i in core_ids if i not in locked]
    print(f"translated {len(tr_out)}/{len(base)}; core approved {len(core_ids) - len(core_unapproved)}/{len(core_ids)}; "
          f"glossary approved={glossary.approved}")
    return 0 if not problems and not core_unapproved and glossary.approved else 1


if __name__ == "__main__":
    raise SystemExit(main())
