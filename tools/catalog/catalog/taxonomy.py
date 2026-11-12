"""Rule-based scoring taxonomy assignment (P025, docs/03-ML-MODEL.md §6).

For every catalog exercise this assigns `movement_pattern`, `scoring_type`, `load_convention` and `is_unilateral`.
The rules look at category, equipment, mechanic, primary muscle and name patterns. Whenever a rule had to fall back
to a guess (or the name is genuinely ambiguous) the entry gets `needs_review: true` plus a note instead of being
silently accepted. Hand decisions live in `taxonomy_overrides.yaml` and always win over the rules.

anchor / ratio / tau / ratio_confidence / bw_fraction stay null here; P056 fills them.
"""
from __future__ import annotations

import re
from typing import Any

MOVEMENT_PATTERNS = [
    "horizontal_push", "vertical_push", "horizontal_pull", "vertical_pull", "squat", "hip_hinge", "core",
    "isolation_biceps", "isolation_triceps", "isolation_forearms", "isolation_shoulders", "isolation_chest",
    "isolation_back", "isolation_quads", "isolation_hamstrings", "isolation_glutes", "isolation_calves",
    "isolation_hips", "isolation_neck",
    # patterns that are recorded but have no strength-anchor logic
    "olympic", "carry", "plyometric", "cardio", "mobility", "other",
]
SCORING_TYPES = ["weighted", "bodyweight_loaded", "reps_only", "time", "none"]
LOAD_CONVENTIONS = ["total", "per_hand", "per_side", "machine_stack", "bodyweight_plus"]

_ISOLATION_BY_MUSCLE = {
    "biceps": "isolation_biceps", "triceps": "isolation_triceps", "forearms": "isolation_forearms",
    "shoulders": "isolation_shoulders", "chest": "isolation_chest", "lats": "isolation_back",
    "middle_back": "isolation_back", "traps": "isolation_back", "lower_back": "isolation_back",
    "quadriceps": "isolation_quads", "hamstrings": "isolation_hamstrings", "glutes": "isolation_glutes",
    "calves": "isolation_calves", "abductors": "isolation_hips", "adductors": "isolation_hips",
    "neck": "isolation_neck", "abdominals": "core",
}
_COMPOUND_GUESS_BY_MUSCLE = {
    "chest": "horizontal_push", "shoulders": "vertical_push", "triceps": "horizontal_push",
    "lats": "vertical_pull", "middle_back": "horizontal_pull", "traps": "horizontal_pull",
    "biceps": "horizontal_pull", "quadriceps": "squat", "hamstrings": "hip_hinge", "glutes": "hip_hinge",
    "lower_back": "hip_hinge", "abdominals": "core", "calves": "isolation_calves",
    "adductors": "squat", "abductors": "squat", "forearms": "isolation_forearms", "neck": "isolation_neck",
}


def _rx(*words: str) -> re.Pattern[str]:
    return re.compile("|".join(words), re.I)


# (rule id, regex on the exercise name, pattern). First match wins, so order matters.
_NAME_RULES: list[tuple[str, re.Pattern[str], str]] = [
    ("cardio_like", _rx(r"sprint", r"air bike", r"battling rope", r"jump rope", r"jumping jack"), "cardio"),
    ("clean_snatch_jerk", _rx(r"\bclean\b(?! grip)", r"\bsnatch\b", r"\bjerk\b"), "olympic"),
    ("carry", _rx(r"farmer", r"\bcarry\b", r"\byoke\b", r"atlas stone", r"\bsled\b", r"tire flip", r"log lift",
                  r"\bdrag\b"), "carry"),
    ("core", _rx(r"crunch", r"sit[- ]?up", r"plank", r"leg raise", r"knee raise", r"russian twist", r"wood ?chop",
                 r"ab wheel", r"rollout", r"roll[- ]?out", r"bicycle", r"v[- ]?up", r"flutter", r"scissor",
                 r"mountain climber", r"side bend", r"\bab\b", r"abdominal", r"hollow", r"dead bug", r"toe touch",
                 r"jackknife", r"pallof", r"windshield", r"bridge", r"\btwist", r"oblique", r"torso rotation",
                 r"hanging", r"stir the pot", r"l-sit", r"\bhold\b", r"suitcase"), "core"),
    ("hip_hinge", _rx(r"deadlift", r"good morning", r"hip thrust", r"glute bridge", r"hyperextension",
                      r"back extension", r"pull[- ]?through", r"kettlebell swing", r"\bswing\b", r"rack pull",
                      r"reverse hyper", r"romanian"), "hip_hinge"),
    ("leg_curl", _rx(r"leg curl", r"hamstring curl", r"glute[- ]ham raise"), "isolation_hamstrings"),
    ("leg_extension", _rx(r"leg extension"), "isolation_quads"),
    ("calf", _rx(r"calf", r"calves", r"donkey"), "isolation_calves"),
    ("hip_abd_add", _rx(r"abduct", r"adduct", r"clamshell", r"fire hydrant"), "isolation_hips"),
    ("squat", _rx(r"squat", r"leg press", r"hack", r"lunge", r"step[- ]?up", r"pistol", r"\bwall sit"), "squat"),
    ("neck", _rx(r"\bneck\b"), "isolation_neck"),
    ("shrug", _rx(r"shrug"), "isolation_back"),
    ("wrist", _rx(r"wrist", r"finger curl", r"forearm"), "isolation_forearms"),
    ("triceps_iso", _rx(r"triceps? extension", r"pushdown", r"push[- ]?down", r"skull", r"kickback",
                        r"french press", r"tricep"), "isolation_triceps"),
    ("biceps_iso", _rx(r"\bcurl", r"preacher"), "isolation_biceps"),
    ("shoulder_iso", _rx(r"lateral raise", r"front raise", r"side raise", r"rear delt", r"reverse (machine )?fl",
                         r"bent[- ]over (dumbbell )?(raise|fl)", r"face pull", r"external rotation",
                         r"internal rotation", r"cuban", r"\braise\b"), "isolation_shoulders"),
    ("chest_iso", _rx(r"\bfly\b", r"\bflyes?\b", r"pec deck", r"crossover", r"cross-over", r"cross over", r"pullover"),
     "isolation_chest"),
    ("vertical_pull", _rx(r"pull[- ]?up", r"chin[- ]?up", r"\bchins?\b", r"pull[- ]?down", r"pulldown", r"muscle[- ]up",
                          r"upright .*row", r"\blat\b", r"rope climb"), "vertical_pull"),
    ("horizontal_pull", _rx(r"\brow\b", r"\brows\b", r"seated cable", r"inverted"), "horizontal_pull"),
    ("vertical_push", _rx(r"overhead press", r"shoulder press", r"military press", r"push press",
                          r"arnold", r"handstand", r"overhead", r"\bpress\b.*\b(behind|seated)\b",
                          r"standing press", r"z press", r"landmine press", r"jammer"), "vertical_push"),
    ("horizontal_push", _rx(r"bench", r"push[- ]?up", r"pushup", r"chest press", r"floor press", r"\bdips?\b",
                            r"pec"), "horizontal_push"),
    ("generic_press", _rx(r"\bpress\b"), "press_by_muscle"),
]

_TIME_RX = _rx(r"\bplank\b", r"side bridge", r"wall sit", r"\bhold\b", r"isometric", r"hollow", r"l-sit",
               r"dead hang", r"flexor kegel")
_REPS_ONLY_RX = _rx(r"push[- ]?up", r"pushup", r"sit[- ]?up", r"crunch", r"leg raise", r"knee raise", r"v[- ]?up",
                    r"flutter", r"scissor", r"bicycle", r"mountain climber", r"russian twist")
_BW_LOADED_RX = _rx(r"pull[- ]?up", r"chin[- ]?up", r"\bchins?\b", r"muscle[- ]up", r"\bdips?\b", r"rope climb",
                    r"inverted row")
_UNILATERAL_RX = _rx(r"single[- ]?(arm|leg)", r"one[- ]?(arm|leg)", r"alternating", r"alternate\b", r"unilateral", r"lunge",
                     r"split squat", r"step[- ]?up", r"bulgarian", r"pistol", r"concentration", r"\bhammer curl\b.*alt",
                     r"one[- ]handed", r"single", r"kickback", r"side lunge", r"cross[- ]?body", r"hydrant",
                     r"clamshell", r"\bleg\b.*\b(left|right)\b", r"windmill", r"suitcase", r"\bkneeling\b.*arm")
_PLATE_LOADED_RX = _rx(r"leg press", r"hack squat", r"t-bar", r"plate[- ]loaded", r"calf press")
_AMBIGUOUS = {
    "dips": _rx(r"\bdips?\b"),            # chest-dip vs triceps-dip changes the push direction
    "upright_row": _rx(r"upright .*row"),   # vertical pull by shoulder path, but trained as a shoulder lift
    "face_pull": _rx(r"face pull"),       # pull direction vs rear-delt isolation
    "pullover": _rx(r"pullover"),         # lat vs chest dominant
    "landmine": _rx(r"landmine", r"jammer"),
    "smith": _rx(r"smith"),
    "kettlebell_swing": _rx(r"swing"),
    "step_up": _rx(r"step[- ]?up"),
    "hanging": _rx(r"hanging"),
    "bridge": _rx(r"bridge"),
}


def classify(ex: dict[str, Any]) -> dict[str, Any]:
    """Return the taxonomy fields for one base-catalog exercise."""
    name: str = ex["name"]
    category = ex["category"]
    equipment = ex["equipment"]
    primary = ex["primary_muscles"][0] if ex["primary_muscles"] else None
    notes: list[str] = []
    rule = ""

    pattern: str | None = None
    if category == "cardio":
        pattern, rule = "cardio", f"category:{category}"
    elif category == "stretching":
        pattern, rule = "mobility", f"category:{category}"
    elif category == "plyometrics":
        pattern, rule = "plyometric", f"category:{category}"
    else:
        for rid, rx, pat in _NAME_RULES:
            if rx.search(name):
                pattern, rule = pat, f"name:{rid}"
                if pat == "press_by_muscle":
                    pattern = {"shoulders": "vertical_push", "chest": "horizontal_push",
                               "triceps": "horizontal_push"}.get(primary or "", "horizontal_push")
                    if primary not in ("shoulders", "chest", "triceps"):
                        notes.append(f"generic press; direction guessed from primary muscle ({primary})")
                break
        if pattern is None:
            if category == "strongman":
                pattern, rule = "carry", "category:strongman"
                notes.append("strongman event with no name rule; pattern is a category default")
            elif ex["mechanic"] == "isolation" and primary in _ISOLATION_BY_MUSCLE:
                pattern, rule = _ISOLATION_BY_MUSCLE[primary], "mechanic:isolation+muscle"
                notes.append(f"isolation pattern guessed from primary muscle ({primary})")
            elif primary in _COMPOUND_GUESS_BY_MUSCLE:
                pattern, rule = _COMPOUND_GUESS_BY_MUSCLE[primary], "fallback:muscle"
                notes.append(f"pattern guessed from primary muscle ({primary}); name matched no rule")
            else:
                pattern, rule = "other", "fallback:other"
                notes.append("no rule and no primary muscle")
    if category == "olympic_weightlifting" and pattern not in ("olympic", "squat", "hip_hinge", "vertical_push"):
        notes.append("olympic-category lift with an unusual pattern; confirm")
    for key, rx in _AMBIGUOUS.items():
        if rx.search(name) and category not in ("cardio", "stretching", "plyometrics"):
            notes.append(f"ambiguous name pattern: {key}")

    # ---- scoring type -------------------------------------------------------------------------------------------
    if category in ("cardio", "stretching", "plyometrics") or pattern == "cardio":
        scoring = "none"
    elif _TIME_RX.search(name):
        scoring = "time"
    elif equipment in ("body_only", "other", None) and _BW_LOADED_RX.search(name) and \
            not re.search(r"machine", name, re.I):
        scoring = "bodyweight_loaded"
    elif _BW_LOADED_RX.search(name) and re.search(r"weighted|assisted", name, re.I):
        scoring = "bodyweight_loaded"
    elif re.search(r"ab (roller|wheel)|rollout|roll-out", name, re.I) and equipment in ("other", None):
        scoring = "reps_only"
    elif equipment == "body_only" and _REPS_ONLY_RX.search(name):
        scoring = "reps_only"
    elif equipment == "body_only":
        scoring = "reps_only"
        notes.append("bodyweight exercise outside the push-up/sit-up families treated as reps_only")
    elif equipment == "foam_roll":
        scoring = "none"
        notes.append("foam rolling treated as unscored")
    else:
        scoring = "weighted"
    if scoring in ("weighted", "bodyweight_loaded") and equipment is None:
        notes.append("equipment missing in source")

    # ---- load convention ----------------------------------------------------------------------------------------
    load: str | None
    if scoring == "bodyweight_loaded":
        load = "bodyweight_plus"
    elif scoring != "weighted":
        load = None
    elif re.search(r"smith", name, re.I):
        load = "total"
        notes.append("smith machine: bar is counterbalanced, so `total` may overstate the load")
    elif _PLATE_LOADED_RX.search(name) and equipment in ("machine", "other", None, "barbell"):
        load = "per_side" if equipment != "barbell" else "total"
        notes.append("plate-loaded machine assumed (`per_side`); confirm loading convention")
    elif equipment in ("barbell", "ez_bar"):
        load = "total"
    elif equipment in ("dumbbell", "kettlebell"):
        load = "per_hand"
        if equipment == "kettlebell" and re.search(r"swing|goblet|turkish", name, re.I):
            load = "total"
            notes.append("single-implement kettlebell lift treated as `total`")
    elif equipment in ("machine", "cable"):
        load = "machine_stack"
    elif equipment in ("bands", "medicine_ball", "exercise_ball", "other", None):
        load = "total"
        notes.append(f"load convention assumed `total` for equipment `{equipment}`")
    else:
        load = "total"

    unilateral = bool(_UNILATERAL_RX.search(name))
    if unilateral and re.search(r"^single$|alternating", name, re.I):
        notes.append("alternating/single wording; confirm unilateral")

    return {
        "movement_pattern": pattern,
        "scoring_type": scoring,
        "load_convention": load,
        "is_unilateral": unilateral,
        "rule": rule,
        "needs_review": bool(notes),
        "review_notes": notes,
    }
