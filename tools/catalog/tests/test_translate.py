import json
import shutil
from pathlib import Path

import pytest
import yaml

from catalog import translate as T

ROOT = Path(__file__).resolve().parent.parent
GLOSSARY = T.Glossary.load(ROOT / "glossary.tr.yaml")
BASE = json.loads((ROOT / "out" / "exercises.base.json").read_text(encoding="utf-8"))


def ex(id_, name, steps=("Do it.", "Repeat.")):
    return {"id": id_, "name": name, "instructions": list(steps)}


def fake_client(calls=None, name_for=lambda e: e["name"].upper(), drop_step=False):
    def client(messages):
        if calls is not None:
            calls.append(messages)
        payload = json.loads(messages[1]["content"])
        rows = []
        for e in payload["exercises"]:
            steps = [f"tr:{s}" for s in e["instructions"]]
            rows.append({"id": e["id"], "name_tr": name_for(e), "aliases_tr": [], "aliases_en": [],
                         "instructions_tr": steps[:1] if drop_step else steps})
        return json.dumps({"exercises": rows})
    return client


def test_glossary_file_is_approved():
    assert GLOSSARY.approved is True


@pytest.mark.parametrize("name,expect", [
    ("Pullups", ["barfiks"]), ("Wide-Grip Pull-Up", ["barfiks", "geniş tutuş"]),
    ("Pushups", ["şınav"]), ("Standing Calf Raise", ["baldır kaldırma", "ayakta"]),
    ("Barbell Bench Press", ["bench press", "barbell"]), ("Wide-Grip Lat Pulldown", ["lat pulldown", "geniş tutuş"]),
])
def test_glossary_matching(name, expect):
    got = [t["tr"] for t in GLOSSARY.match(name)]
    for e in expect:
        assert e in got


def test_longest_match_consumes_overlapping_terms():
    got = [t["tr"] for t in GLOSSARY.match("Standing Calf Raise")]
    assert "baldır kaldırma" in got and "kaldırma" not in got


def test_glossary_violations_detected():
    assert GLOSSARY.violations("Pullups", "Barfiks") == []
    assert GLOSSARY.violations("Pullups", "Çekiş")


def test_every_glossary_term_is_well_formed():
    for t in GLOSSARY.terms:
        assert t["en"] and t["tr"]


def test_fold_ascii_turkish():
    assert T.fold_ascii("Barfiks Çekiş Şınav Ördek ı İ") == "Barfiks Cekis Sinav Ordek i I"


def test_aliases_include_tr_en_and_ascii_without_own_name():
    tr = {"name_tr": "Şınav", "aliases_tr": [], "aliases_en": ["Push-up"]}
    a = T.aliases_for("Pushups", tr, "Şınav")
    assert "Pushups" in a and "Push-up" in a and "Sinav" in a and "Şınav" not in a
    en = T.aliases_for("Pushups", tr, "Pushups")
    assert "Şınav" in en and "Pushups" not in en


def test_translate_caches_and_never_retranslates(tmp_path):
    cache = T.Cache(tmp_path / "c.json")
    items = [ex("a", "Pullups"), ex("b", "Pushups")]
    calls = []
    names = {"a": "Barfiks", "b": "Şınav"}
    st = T.translate_missing(items, GLOSSARY, cache, fake_client(calls, name_for=lambda e: names[e["id"]]))
    assert st["requested"] == 2 and len(calls) == 1
    st2 = T.translate_missing(items, GLOSSARY, T.Cache(tmp_path / "c.json"), fake_client(calls))
    assert st2["cached"] == 2 and st2["requested"] == 0 and len(calls) == 1


def test_cache_key_changes_with_glossary_and_input():
    a = T.Cache.key(ex("a", "Pullups"), GLOSSARY, T.MODEL)
    assert a != T.Cache.key(ex("a", "Pullups", ("x",)), GLOSSARY, T.MODEL)
    g2 = T.Glossary({**yaml.safe_load((ROOT / "glossary.tr.yaml").read_text(encoding="utf-8")),
                     "terms": [{"en": ["pullup"], "tr": "çekme"}]})
    assert a != T.Cache.key(ex("a", "Pullups"), g2, T.MODEL)


def test_invalid_responses_are_retried_then_reported(tmp_path):
    cache = T.Cache(tmp_path / "c.json")
    calls = []
    st = T.translate_missing([ex("a", "Pullups")], GLOSSARY, cache, fake_client(calls, drop_step=True), attempts=2)
    assert st["failed"] == ["a"] and len(calls) == 2 and not cache.data


def test_parse_response_rejects_bad_shapes():
    batch = [ex("a", "X")]
    for raw in ("not json", json.dumps({"exercises": []}), json.dumps({"exercises": [{"id": "a"}]})):
        with pytest.raises(ValueError):
            T.parse_response(raw, batch)
    good = json.dumps({"exercises": [{"id": "a", "name_tr": "X", "aliases_tr": [], "aliases_en": [],
                                      "instructions_tr": ["1", "2"]}]})
    assert T.parse_response("```json\n" + good + "\n```", batch)["a"]["name_tr"] == "X"


def test_glossary_violation_is_recorded(tmp_path):
    cache = T.Cache(tmp_path / "c.json")
    T.translate_missing([ex("a", "Pullups")], GLOSSARY, cache, fake_client(name_for=lambda e: "Çekiş"))
    assert next(iter(cache.data.values()))["glossary_violations"]


def test_prompt_contains_only_relevant_glossary_terms():
    msgs = T.build_messages([ex("a", "Pullups")], GLOSSARY)
    g = json.loads(msgs[1]["content"])["glossary"]["terms"]
    assert [t["tr"] for t in g] == ["barfiks"]


def test_locked_rows_win_and_survive_review_rewrite(tmp_path):
    base = {"a": ex("a", "Pullups"), "b": ex("b", "Pushups")}
    resolved = {"a": {"name_tr": "LLM", "aliases_tr": [], "aliases_en": [], "instructions_tr": ["1", "2"]},
                "b": {"name_tr": "Şınav", "aliases_tr": ["Sinav"], "aliases_en": [], "instructions_tr": ["1", "2"]}}
    p = tmp_path / "r" / "tr_core.csv"
    T.write_review(p, ["a", "b"], base, resolved, {})
    assert T.load_locked(p) == {}
    # the reviewer fixes row a by hand and approves it
    import csv
    rows = list(csv.DictReader(p.open(encoding="utf-8", newline="")))
    rows[0]["name_tr"], rows[0]["approved"] = "Barfiks", "yes"
    with p.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, T.CSV_COLUMNS)
        w.writeheader()
        w.writerows(rows)
    locked = T.load_locked(p)
    assert list(locked) == ["a"] and locked["a"]["name_tr"] == "Barfiks"
    assert locked["a"]["instructions_tr"] == ["1", "2"]
    # a later LLM change must not touch the approved row
    resolved["a"]["name_tr"] = "Changed"
    T.write_review(p, ["a", "b"], base, resolved, locked)
    assert T.load_locked(p)["a"]["name_tr"] == "Barfiks"
    out = T.resolve_all([ex("a", "Pullups")], GLOSSARY, T.Cache(tmp_path / "x.json"), locked)
    assert out["a"]["name_tr"] == "Barfiks"


def test_assemble_flags_missing_and_mismatched():
    ok = {"name_tr": "T", "aliases_tr": [], "aliases_en": [], "instructions_tr": ["1", "2"]}
    bad = {**ok, "instructions_tr": ["1"]}
    tr, en, problems = T.assemble([ex("a", "A"), ex("b", "B"), ex("c", "C")], {"a": ok, "b": bad})
    assert [t["id"] for t in tr] == ["a"] and len(problems) == 2 and en[0]["name"] == "A"


def test_sample_table_has_n_rows():
    en = [{"id": str(i), "name": f"E{i}", "instructions": ["x"]} for i in range(30)]
    tr = [{"id": str(i), "name": f"T{i}", "instructions": ["y"]} for i in range(30)]
    t = T.sample_table(en, tr, 20, 1)
    assert len(t.strip().splitlines()) == 22 and t == T.sample_table(en, tr, 20, 1)


def _workdir(tmp_path, exercises):
    for f in ("glossary.tr.yaml", "scoring_taxonomy.yaml"):
        shutil.copy(ROOT / f, tmp_path / f)
    (tmp_path / "out").mkdir()
    (tmp_path / "out" / "exercises.base.json").write_text(json.dumps(exercises), encoding="utf-8")


def test_run_requires_approved_glossary_and_key(tmp_path, monkeypatch, capsys):
    _workdir(tmp_path, BASE)
    g = tmp_path / "glossary.tr.yaml"
    g.write_text(g.read_text(encoding="utf-8").replace("approved: true", "approved: false", 1), encoding="utf-8")
    monkeypatch.delenv("OPENROUTER_API_KEY", raising=False)
    assert T.main(["run", "--root", str(tmp_path), "--limit", "1"]) == 2
    assert "not approved" in capsys.readouterr().err
    assert T.main(["run", "--root", str(tmp_path), "--limit", "1", "--allow-unapproved-glossary"]) == 2
    assert "OPENROUTER_API_KEY" in capsys.readouterr().err
    args = ["run", "--root", str(tmp_path), "--limit", "1", "--allow-unapproved-glossary", "--provider", "deepseek"]
    monkeypatch.delenv("DEEPSEEK_API_KEY", raising=False)
    assert T.main(args) == 2
    assert "DEEPSEEK_API_KEY" in capsys.readouterr().err


def test_end_to_end_with_fake_llm(tmp_path, monkeypatch):
    small = BASE[:12]
    _workdir(tmp_path, small)
    monkeypatch.setattr(T, "llm_client", lambda url, key, model: fake_client())
    monkeypatch.setenv("OPENROUTER_API_KEY", "k")
    assert T.main(["run", "--root", str(tmp_path), "--allow-unapproved-glossary"]) == 0
    tr = json.loads((tmp_path / "out" / "exercises.tr.json").read_text(encoding="utf-8"))
    en = json.loads((tmp_path / "out" / "exercises.en.json").read_text(encoding="utf-8"))
    assert len(tr) == len(en) == 12
    assert all(len(a["instructions"]) == len(b["instructions"]) for a, b in zip(tr, small))


def test_violation_check_is_not_turkish_dotless_i():
    assert GLOSSARY.violations("Incline Dumbbell Press", "Incline Dumbbell Press") == []
    assert GLOSSARY.violations("Jerk Dip Squat", "Jerk Dip Squat") == []
    assert GLOSSARY.violations("Donkey Calf Raises", "Donkey Baldır Kaldırma") == []


def test_keep_english_names_keeps_turkish_as_alias():
    tr = {"name_tr": "Barfiks", "aliases_tr": [], "aliases_en": [], "instructions_tr": ["1", "2"]}
    out, _, _ = T.assemble([ex("a", "Pullups")], {"a": tr}, keep_english_names=True)
    assert out[0]["name"] == "Pullups" and "Barfiks" in out[0]["aliases"] and "Pullups" not in out[0]["aliases"]
    assert GLOSSARY.keep_english_names is True
