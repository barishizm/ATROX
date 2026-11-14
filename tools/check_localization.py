#!/usr/bin/env python3
"""Audit the String Catalogs (P099): every key translated in every language, format specifiers identical.

Usage: python3 tools/check_localization.py [catalog.xcstrings ...]   (defaults to all catalogs under ios/)
Exit code 1 when a problem is found. Keys marked shouldTranslate=false and stale keys are skipped.
"""
import json
import re
import sys
from pathlib import Path

REQUIRED = ("en", "tr")
SPEC = re.compile(r"%(?:(\d+)\$)?[-+ 0#]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|h|ll|l|q|z|t|j)?([@dDiIuUfFeEgGsScCxXoOpaA])")


def specifiers(text):
    """(position, conversion) pairs, ignoring literal %%. Unnumbered specifiers get their running position."""
    found, next_position = [], 1
    for m in SPEC.finditer(text.replace("%%", "")):
        position = int(m.group(1)) if m.group(1) else next_position
        next_position = position + 1
        found.append((position, m.group(2)))
    return found


def compatible(a_text, b_text):
    """Same arguments with the same types. Numbered strings may leave an argument unused (a language can drop one)."""
    a, b = specifiers(a_text), specifiers(b_text)
    if sorted(a) == sorted(b):
        return True
    return "$" in a_text and "$" in b_text and (set(a) <= set(b) or set(b) <= set(a))


def units(localization):
    """Yield every string unit (plain, plural and device variations) of one localization."""
    if "stringUnit" in localization:
        yield localization["stringUnit"]
    for group in localization.get("variations", {}).values():
        for variant in group.values():
            yield from units(variant)
    for sub in localization.get("substitutions", {}).values():
        yield from units(sub)


def check(path):
    problems = []
    catalog = json.loads(path.read_text(encoding="utf-8"))
    for key, entry in catalog.get("strings", {}).items():
        if entry.get("shouldTranslate") is False or entry.get("extractionState") == "stale":
            continue
        locs = entry.get("localizations", {})
        for lang in REQUIRED:
            if lang not in locs:
                problems.append(f"{path.name}: '{key}' has no '{lang}' translation")
                continue
            for unit in units(locs[lang]):
                if unit.get("state", "translated") != "translated":
                    problems.append(f"{path.name}: '{key}' [{lang}] state is '{unit.get('state')}'")
                if not unit.get("value", "").strip():
                    problems.append(f"{path.name}: '{key}' [{lang}] is empty")
        if all(lang in locs for lang in REQUIRED):
            base = [u.get("value", "") for u in units(locs["en"])]
            for lang in REQUIRED[1:]:
                other = [u.get("value", "") for u in units(locs[lang])]
                if len(base) != len(other):
                    problems.append(f"{path.name}: '{key}' en/{lang} plural variants differ")
                    continue
                for a, b in zip(base, other):
                    if not compatible(a, b):
                        problems.append(f"{path.name}: '{key}' format specifiers differ: en={a!r} {lang}={b!r}")
    return problems


def main(argv):
    root = Path(__file__).resolve().parent.parent / "ios"
    paths = [Path(a) for a in argv] or sorted(p for p in root.rglob("*.xcstrings") if ".build" not in p.parts)
    problems = [p for path in paths for p in check(path)]
    for line in problems:
        print(line)
    print(f"checked {len(paths)} catalog(s): {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
