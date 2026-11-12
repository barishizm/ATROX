import json

import pytest

from catalog import cli, ids, mapping, source, validate


def raw(**kw):
    base = {"id": "Ab_Roller", "name": "Ab Roller", "force": "pull", "level": "beginner", "mechanic": "compound",
            "equipment": "body only", "primaryMuscles": ["lower back"], "secondaryMuscles": [],
            "instructions": [" Roll out. "], "category": "strength", "images": ["Ab_Roller/0.jpg"]}
    base.update(kw)
    return base


def test_mapping_normalizes_enums():
    e = mapping.map_exercise(raw(equipment="e-z curl bar", primaryMuscles=["middle back"]), "ab-roller")
    assert e["equipment"] == "ez_bar" and e["primary_muscles"] == ["middle_back"]
    assert e["instructions"] == ["Roll out."] and e["id"] == "ab-roller" and e["source_id"] == "Ab_Roller"


def test_mapping_keeps_nulls_and_rejects_unknown():
    assert mapping.map_exercise(raw(force=None, equipment=None), "x")["force"] is None
    with pytest.raises(mapping.MappingError):
        mapping.map_exercise(raw(level="godlike"), "x")
    with pytest.raises(mapping.MappingError):
        mapping.map_exercise(raw(primaryMuscles=["wings"]), "x")


def test_all_17_muscles_mapped():
    assert len(mapping.MUSCLES) == 17


def test_slugify():
    assert ids.slugify("3_4_Sit-Up") == "3-4-sit-up"
    assert ids.slugify("Ab_Roller") == "ab-roller"


def test_ids_are_stable_and_locked(tmp_path):
    lock, _ = ids.assign_ids(["A_B", "C"], {})
    again, notes = ids.assign_ids(["C", "A_B", "D"], lock)
    assert again["A_B"] == lock["A_B"] and again["C"] == lock["C"] and again["D"] == "d" and notes == []
    p = tmp_path / "lock.json"
    ids.save_lock(p, again)
    assert ids.load_lock(p) == again


def test_locked_id_survives_slug_rule_change():
    lock = {"Ab_Roller": "legacy-slug"}
    out, _ = ids.assign_ids(["Ab_Roller"], lock)
    assert out["Ab_Roller"] == "legacy-slug"


def test_slug_collision_gets_suffix():
    out, notes = ids.assign_ids(["A_B", "A-B"], {})
    assert sorted(out.values()) == ["a-b", "a-b-2"] and len(notes) == 1


def test_duplicate_source_ids_rejected():
    with pytest.raises(ValueError):
        ids.assign_ids(["A", "A"], {})


def ex(**kw):
    return {**mapping.map_exercise(raw(), "ab-roller"), **kw}


def test_validate_clean():
    assert validate.validate([ex()], {"Ab_Roller/0.jpg"}) == []


def test_validate_catches_problems():
    bad = [ex(primary_muscles=[]), ex(id="b", name="ab  roller!", images=["nope.jpg"], level=None)]
    errs = "\n".join(validate.validate(bad, {"Ab_Roller/0.jpg"}))
    assert "no primary muscle" in errs and "image file missing nope.jpg" in errs
    assert "missing required field level" in errs and "duplicate name" in errs


def test_empty_instructions_and_images_are_warnings():
    warns: list[str] = []
    errs = validate.validate([ex(instructions=[], images=[])], None, warns)
    assert errs == [] and warns == ["ab-roller: empty instructions", "ab-roller: empty images"]


def test_license_check():
    source.check_license("This is free and unencumbered software released into the public domain.\nsee https://unlicense.org")
    with pytest.raises(source.LicenseError):
        source.check_license("MIT License")


def test_build_end_to_end(tmp_path):
    src = source.Source([raw(), raw(id="Push_Up", name="Push-Up", images=["Push_Up/0.jpg"], force=None)],
                        "", {"Ab_Roller/0.jpg", "Push_Up/0.jpg"}, "h")
    exercises, lock, rep = cli.build(src, {})
    assert [e["id"] for e in exercises] == ["ab-roller", "push-up"]
    assert rep["total"] == 2 and rep["null_fields"]["force"] == 1 and rep["validation_errors"] == []
    assert lock == {"Ab_Roller": "ab-roller", "Push_Up": "push-up"}


def test_real_dataset_if_cached():
    """Runs against the real pinned dataset once `catalog-import` has populated the cache."""
    if not (cli.ROOT / "cache").exists():
        pytest.skip("cache not populated")
    src = source.load_cached(cli.ROOT / "cache")
    exercises, _, rep = cli.build(src, ids.load_lock(cli.ROOT / "id_lock.json"))
    assert len(exercises) >= 800 and rep["validation_errors"] == []
