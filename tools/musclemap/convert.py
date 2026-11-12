#!/usr/bin/env python3
"""One-off converter: react-native-body-highlighter SVG data -> Swift source for DesignSystem.MuscleMapView.

Usage:
    python3 tools/musclemap/convert.py --source /path/to/react-native-body-highlighter \
        [--out ios/Packages/DesignSystem/Sources/DesignSystem/Components/MuscleMap/MuscleMapData.swift]

Reads `assets/bodyFront.ts`, `assets/bodyBack.ts` and the outline paths in `components/SvgMaleWrapper.tsx`
(male model only), refuses to run unless the source LICENSE is MIT, converts every SVG path to a normalized
absolute `M/L/C/Q/Z` form (arcs become cubic Béziers, the back view is shifted to x=0), maps the upstream
regions onto ATROX's 17 catalog muscles and prints a coverage report. Standard library only.
See tools/musclemap/README.md and SOURCES.md for provenance.
"""
from __future__ import annotations

import argparse
import math
import re
import subprocess
import sys
from pathlib import Path

VIEW_WIDTH = 724
VIEW_HEIGHT = 1448
BACK_X_OFFSET = 724  # the upstream back view lives at x = 724...1448 of the same canvas

# The 17 catalog muscles (docs/00-KARARLAR.md, free-exercise-db vocabulary, snake_case as stored in Postgres).
MUSCLES = [
    "abdominals", "abductors", "adductors", "biceps", "calves", "chest", "forearms", "glutes", "hamstrings",
    "lats", "lower_back", "middle_back", "neck", "quadriceps", "shoulders", "traps", "triceps",
]

# muscle -> [(view, upstream slug, exactness)]. Several entries per muscle = one-to-many; a slug used by several
# muscles = shared region (the app shows the strongest intensity and reports the strongest muscle on tap).
MUSCLE_REGIONS = {
    "abdominals": [("front", "abs", "exact"), ("front", "obliques", "exact")],
    "abductors": [("back", "gluteal", "approximate")],  # no hip-abductor region upstream; gluteus medius sits in "gluteal"
    "adductors": [("front", "adductors", "exact"), ("back", "adductors", "exact")],
    "biceps": [("front", "biceps", "exact")],
    "calves": [("front", "calves", "exact"), ("back", "calves", "exact")],
    "chest": [("front", "chest", "exact")],
    "forearms": [("front", "forearm", "exact"), ("back", "forearm", "exact")],
    "glutes": [("back", "gluteal", "exact")],
    "hamstrings": [("back", "hamstring", "exact")],
    "lats": [("back", "upper-back", "shared")],  # upstream has one upper-back region for lats + middle back
    "lower_back": [("back", "lower-back", "exact")],
    "middle_back": [("back", "upper-back", "shared")],
    "neck": [("front", "neck", "exact"), ("back", "neck", "exact")],
    "quadriceps": [("front", "quadriceps", "exact")],
    "shoulders": [("front", "deltoids", "exact"), ("back", "deltoids", "exact")],
    "traps": [("front", "trapezius", "exact"), ("back", "trapezius", "exact")],
    "triceps": [("front", "triceps", "exact"), ("back", "triceps", "exact")],
}

# Drawn as neutral (non-interactive) body parts: none of our 17 muscles lives there.
NEUTRAL_NOTE = "head/hair/hands/feet/ankles/knees/tibialis have no catalog muscle and are drawn neutral"


# --------------------------------------------------------------------------- licence gate


def verify_mit_license(source: Path) -> str:
    text = (source / "LICENSE").read_text(encoding="utf-8")
    normalized = " ".join(text.split())
    required = [
        "MIT License",
        "Permission is hereby granted, free of charge",
        "The above copyright notice and this permission notice shall be included in all copies",
    ]
    if not all(r in normalized for r in required):
        sys.exit("LICENSE is not the MIT license text - stop and pick an alternative source.")
    match = re.search(r"Copyright \(c\) [^\n]+", text)
    return match.group(0) if match else "Copyright (c) <unknown>"


# --------------------------------------------------------------------------- upstream TS parsing


def parse_regions(ts_source: str) -> list[tuple[str, list[str]]]:
    """Returns [(slug, [path d strings])] in file order (left/right/common merged)."""
    regions = []
    for chunk in re.split(r"\bslug:\s*", ts_source)[1:]:
        slug = re.match(r'"([^"]+)"', chunk)
        if not slug:
            continue
        paths = []
        for _, body in re.findall(r"\b(left|right|common):\s*\[(.*?)\]", chunk, flags=re.S):
            paths.extend(re.findall(r'"([^"]+)"', body))
        regions.append((slug.group(1), paths))
    return regions


def parse_outlines(wrapper_source: str) -> dict[str, str]:
    """Front/back outline `d` strings from SvgMaleWrapper.tsx (guarded by `side === "front"` / `"back"`)."""
    out = {}
    for side in ("front", "back"):
        match = re.search(r'side === "%s" && \(\s*<Path[^>]*?\sd="([^"]+)"' % side, wrapper_source, flags=re.S)
        if not match:
            sys.exit("outline path for %s not found in SvgMaleWrapper.tsx" % side)
        out[side] = match.group(1)
    return out


# --------------------------------------------------------------------------- SVG path -> absolute M/L/C/Q/Z

_NUM = re.compile(r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?")
_SEP = re.compile(r"[\s,]*")
_ARGC = {"M": 2, "L": 2, "H": 1, "V": 1, "C": 6, "S": 4, "Q": 4, "T": 2, "A": 7, "Z": 0}


class _Reader:
    """Character-level SVG path reader (arc flags may be packed: `a1 1 0 012.9 1.1`)."""

    def __init__(self, d: str):
        self.d, self.pos = d, 0

    def skip(self):
        self.pos = _SEP.match(self.d, self.pos).end()

    def at_end(self) -> bool:
        self.skip()
        return self.pos >= len(self.d)

    def peek_command(self):
        self.skip()
        if self.pos < len(self.d) and self.d[self.pos].isalpha():
            ch = self.d[self.pos]
            self.pos += 1
            return ch
        return None

    def number(self) -> float:
        self.skip()
        m = _NUM.match(self.d, self.pos)
        if not m:
            raise ValueError("expected number at %d in %r" % (self.pos, self.d[:50]))
        self.pos = m.end()
        return float(m.group(0))

    def flag(self) -> float:
        self.skip()
        if self.pos >= len(self.d) or self.d[self.pos] not in "01":
            raise ValueError("expected arc flag at %d in %r" % (self.pos, self.d[:50]))
        self.pos += 1
        return float(self.d[self.pos - 1])

    def args(self, upper: str):
        if upper == "A":
            return [self.number(), self.number(), self.number(), self.flag(), self.flag(), self.number(), self.number()]
        return [self.number() for _ in range(_ARGC[upper])]


def _arc_to_cubics(x1, y1, rx, ry, phi_deg, large, sweep, x2, y2):
    if rx == 0 or ry == 0 or (x1 == x2 and y1 == y2):
        return [("L", [x2, y2])] if (x1, y1) != (x2, y2) else []
    rx, ry = abs(rx), abs(ry)
    phi = math.radians(phi_deg % 360)
    cp, sp = math.cos(phi), math.sin(phi)
    dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
    x1p, y1p = cp * dx + sp * dy, -sp * dx + cp * dy
    lam = x1p ** 2 / rx ** 2 + y1p ** 2 / ry ** 2
    if lam > 1:
        s = math.sqrt(lam)
        rx, ry = rx * s, ry * s
    num = rx ** 2 * ry ** 2 - rx ** 2 * y1p ** 2 - ry ** 2 * x1p ** 2
    den = rx ** 2 * y1p ** 2 + ry ** 2 * x1p ** 2
    coef = math.sqrt(max(0.0, num / den)) if den else 0.0
    if bool(large) == bool(sweep):
        coef = -coef
    cxp, cyp = coef * rx * y1p / ry, -coef * ry * x1p / rx
    cx, cy = cp * cxp - sp * cyp + (x1 + x2) / 2, sp * cxp + cp * cyp + (y1 + y2) / 2

    def angle(ux, uy, vx, vy):
        a = math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        return a

    theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    dtheta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if not sweep and dtheta > 0:
        dtheta -= 2 * math.pi
    elif sweep and dtheta < 0:
        dtheta += 2 * math.pi
    segments = max(1, int(math.ceil(abs(dtheta) / (math.pi / 2) - 1e-9)))
    delta = dtheta / segments
    t = 4 / 3 * math.tan(delta / 4)
    result = []
    for i in range(segments):
        a1, a2 = theta1 + i * delta, theta1 + (i + 1) * delta
        c1x, c1y = math.cos(a1) - t * math.sin(a1), math.sin(a1) + t * math.cos(a1)
        c2x, c2y = math.cos(a2) + t * math.sin(a2), math.sin(a2) - t * math.cos(a2)
        ex, ey = math.cos(a2), math.sin(a2)

        def project(px, py):
            px, py = px * rx, py * ry
            return cp * px - sp * py + cx, sp * px + cp * py + cy

        p1, p2, p3 = project(c1x, c1y), project(c2x, c2y), project(ex, ey)
        result.append(("C", [p1[0], p1[1], p2[0], p2[1], p3[0], p3[1]]))
    result[-1][1][-2:] = [x2, y2]  # kill accumulated float drift on the end point
    return result


def normalize_path(d: str, dx: float = 0.0, dy: float = 0.0):
    """Parse an SVG path and return absolute commands [(letter, [numbers])] with letters in M L C Q Z only."""
    reader = _Reader(d)
    out = []
    cmd = None
    x = y = sx = sy = 0.0
    last_c2 = None  # last cubic control point (for S)
    last_q = None  # last quad control point (for T)
    while not reader.at_end():
        letter = reader.peek_command()
        if letter is not None:
            cmd = letter
            if cmd in "Zz":
                out.append(("Z", []))
                x, y = sx, sy
                last_c2 = last_q = None
                continue
        elif cmd is None or cmd in "Zz":
            raise ValueError("path data does not start with a command: %r" % d[:40])
        upper = cmd.upper()
        a = reader.args(upper)
        rel = cmd.islower()
        if upper == "M":
            nx, ny = (x + a[0], y + a[1]) if rel else (a[0], a[1])
            out.append(("M", [nx, ny]))
            x, y, sx, sy = nx, ny, nx, ny
            cmd = "l" if rel else "L"  # implicit lineto after the first pair
            last_c2 = last_q = None
        elif upper == "L":
            nx, ny = (x + a[0], y + a[1]) if rel else (a[0], a[1])
            out.append(("L", [nx, ny]))
            x, y = nx, ny
            last_c2 = last_q = None
        elif upper == "H":
            nx = x + a[0] if rel else a[0]
            out.append(("L", [nx, y]))
            x = nx
            last_c2 = last_q = None
        elif upper == "V":
            ny = y + a[0] if rel else a[0]
            out.append(("L", [x, ny]))
            y = ny
            last_c2 = last_q = None
        elif upper == "C":
            p = [a[0] + x, a[1] + y, a[2] + x, a[3] + y, a[4] + x, a[5] + y] if rel else a
            out.append(("C", p))
            last_c2 = (p[2], p[3])
            x, y = p[4], p[5]
            last_q = None
        elif upper == "S":
            p = [a[0] + x, a[1] + y, a[2] + x, a[3] + y] if rel else a
            c1 = (2 * x - last_c2[0], 2 * y - last_c2[1]) if last_c2 else (x, y)
            out.append(("C", [c1[0], c1[1], p[0], p[1], p[2], p[3]]))
            last_c2 = (p[0], p[1])
            x, y = p[2], p[3]
            last_q = None
        elif upper == "Q":
            p = [a[0] + x, a[1] + y, a[2] + x, a[3] + y] if rel else a
            out.append(("Q", p))
            last_q = (p[0], p[1])
            x, y = p[2], p[3]
            last_c2 = None
        elif upper == "T":
            ex, ey = (x + a[0], y + a[1]) if rel else (a[0], a[1])
            c = (2 * x - last_q[0], 2 * y - last_q[1]) if last_q else (x, y)
            out.append(("Q", [c[0], c[1], ex, ey]))
            last_q = c
            x, y = ex, ey
            last_c2 = None
        elif upper == "A":
            ex, ey = (x + a[5], y + a[6]) if rel else (a[5], a[6])
            out.extend(_arc_to_cubics(x, y, a[0], a[1], a[2], a[3] != 0, a[4] != 0, ex, ey))
            x, y = ex, ey
            last_c2 = last_q = None
    # translate + return
    shifted = []
    for letter, nums in out:
        moved = [v - (dx if k % 2 == 0 else dy) for k, v in enumerate(nums)]
        shifted.append((letter, moved))
    return shifted


def _fmt(v: float) -> str:
    text = ("%.1f" % v).rstrip("0").rstrip(".")
    return "0" if text in ("-0", "") else text


def serialize(commands) -> str:
    parts = []
    for letter, nums in commands:
        parts.append(letter + (" " + " ".join(_fmt(v) for v in nums) if nums else ""))
    return " ".join(parts)


def bounds(commands):
    xs = [v for _, nums in commands for k, v in enumerate(nums) if k % 2 == 0]
    ys = [v for _, nums in commands for k, v in enumerate(nums) if k % 2 == 1]
    return (min(xs), min(ys), max(xs), max(ys)) if xs else (0, 0, 0, 0)


# --------------------------------------------------------------------------- mapping + report


def region_muscles(view: str, slug: str) -> list[str]:
    found = []
    for muscle in MUSCLES:
        for v, s, _ in MUSCLE_REGIONS[muscle]:
            if v == view and s == slug:
                found.append(muscle)
    return found


def camel(name: str) -> str:
    head, *tail = name.split("_")
    return head + "".join(t.capitalize() for t in tail)


def swift_ident(slug: str) -> str:
    return camel(slug.replace("-", "_"))


def build_report(regions_by_view: dict[str, list[tuple[str, list[str]]]]) -> tuple[str, list[str]]:
    problems = []
    lines = ["Muscle map coverage (source regions -> 17 ATROX muscles)", ""]
    available = {(v, s) for v, regs in regions_by_view.items() for s, _ in regs}
    for muscle in MUSCLES:
        entries = MUSCLE_REGIONS[muscle]
        missing = [(v, s) for v, s, _ in entries if (v, s) not in available]
        if missing:
            problems.append("%s references missing source regions %s" % (muscle, missing))
        flags = sorted({e for _, _, e in entries})
        where = ", ".join("%s:%s" % (v, s) for v, s, _ in entries)
        lines.append("  %-12s -> %-40s [%s]" % (muscle, where, "/".join(flags)))
    lines.append("")
    unmapped_muscles = [m for m in MUSCLES if not MUSCLE_REGIONS[m]]
    lines.append("Muscles with no region: %s" % (", ".join(unmapped_muscles) or "none"))
    approx = [m for m in MUSCLES if any(e == "approximate" for _, _, e in MUSCLE_REGIONS[m])]
    lines.append("Approximate mappings (no dedicated region upstream): %s" % (", ".join(approx) or "none"))
    shared = sorted({s for m in MUSCLES for v, s, e in MUSCLE_REGIONS[m] if e == "shared"})
    lines.append("Shared regions (one region, several muscles): %s" % (", ".join(shared) or "none"))
    neutral = sorted({"%s:%s" % (v, s) for v, regs in regions_by_view.items() for s, _ in regs
                      if not region_muscles(v, s)})
    lines.append("Neutral regions (%s):" % NEUTRAL_NOTE)
    lines.append("  " + ", ".join(neutral))
    return "\n".join(lines), problems


# --------------------------------------------------------------------------- Swift emission

HEADER = """// GENERATED by tools/musclemap/convert.py - DO NOT EDIT BY HAND.
//
// Body-region outlines derived from react-native-body-highlighter (MIT, %(copyright)s),
// https://github.com/HichamELBSI/react-native-body-highlighter @ %(commit)s.
// See SOURCES.md and the in-app licenses screen. Coordinates: 724 x 1448 canvas per view, y down.
// Path strings use absolute M/L/C/Q/Z commands only (parsed by MuscleMapPathParser).

"""


def emit_swift(regions_by_view, outlines, copyright_line, commit) -> str:
    out = [HEADER % {"copyright": copyright_line.replace("Copyright (c) ", ""), "commit": commit}]
    out.append("import Foundation\n\n")
    out.append("enum MuscleMapData {\n")
    out.append("    struct Region: Sendable {\n")
    out.append("        /// Upstream slug, stable and used for tests/identifiers.\n")
    out.append("        let id: String\n")
    out.append("        /// Catalog muscles this region represents; empty = neutral body part.\n")
    out.append("        let muscles: [Muscle]\n")
    out.append("        /// One path string per sub-shape (left + right sides are separate sub-shapes).\n")
    out.append("        let paths: [String]\n")
    out.append("    }\n\n")
    out.append("    static let canvas = (width: %d.0, height: %d.0)\n\n" % (VIEW_WIDTH, VIEW_HEIGHT))
    for view in ("front", "back"):
        dx = BACK_X_OFFSET if view == "back" else 0
        out.append("    static let %sOutline = %s\n\n" % (view, swift_string(serialize(normalize_path(outlines[view], dx, 0)))))
        out.append("    static let %s: [Region] = [\n" % view)
        for slug, paths in regions_by_view[view]:
            muscles = ", ".join("." + camel(m) for m in region_muscles(view, slug))
            joined = ",\n".join("            " + swift_string(serialize(normalize_path(p, dx, 0))) for p in paths)
            out.append('        Region(id: "%s-%s", muscles: [%s], paths: [\n%s\n        ]),\n' % (view, slug, muscles, joined))
        out.append("    ]\n\n")
    out.append("}\n")
    return "".join(out)


def swift_string(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", required=True, type=Path, help="checkout of react-native-body-highlighter")
    default_out = (Path(__file__).resolve().parents[2]
                   / "ios/Packages/DesignSystem/Sources/DesignSystem/Components/MuscleMap/MuscleMapData.swift")
    parser.add_argument("--out", type=Path, default=default_out)
    parser.add_argument("--report-only", action="store_true", help="print the coverage report without writing")
    args = parser.parse_args(argv)

    copyright_line = verify_mit_license(args.source)
    try:
        commit = subprocess.run(["git", "-C", str(args.source), "rev-parse", "HEAD"], capture_output=True,
                                text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        commit = "unknown"

    regions_by_view = {
        "front": parse_regions((args.source / "assets/bodyFront.ts").read_text(encoding="utf-8")),
        "back": parse_regions((args.source / "assets/bodyBack.ts").read_text(encoding="utf-8")),
    }
    outlines = parse_outlines((args.source / "components/SvgMaleWrapper.tsx").read_text(encoding="utf-8"))

    report, problems = build_report(regions_by_view)
    print(report)
    if problems:
        print("\nERRORS:\n  " + "\n  ".join(problems), file=sys.stderr)
        return 1
    if args.report_only:
        return 0

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(emit_swift(regions_by_view, outlines, copyright_line, commit), encoding="utf-8")
    print("\nwrote %s (%d bytes)" % (args.out, args.out.stat().st_size))
    return 0


if __name__ == "__main__":
    sys.exit(main())
