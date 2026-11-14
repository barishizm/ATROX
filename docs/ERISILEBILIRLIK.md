# Accessibility (P097)

## What is in place
- **VoiceOver.** Interactive elements carry labels (audited per screen). The score ring reads "score / 100, level"; the
  muscle map exposes per-region elements with select actions. Set rows in the active workout expose **custom actions**
  (complete/undo, delete) on the row container, so they are reachable from the Actions rotor without locating the
  small controls.
- **Charts.** The four time-series charts (score over time, relative strength, bodyweight, e1RM history) attach an
  `AXChartDescriptor` (`DesignSystem/Tokens/Accessibility.swift`, `ChartAccessibility`): Audio Graph plays the line and
  a spoken summary (count, first, latest, lowest, highest) is read first. Weekly bars, the frequency heatmap and the
  distribution chart keep their text summaries/labels.
- **Dynamic Type.** At accessibility sizes the set row switches from a horizontal to a vertical layout, column heads are
  replaced by per-field captions, and field widths are minimums, not fixed. `TodayRootView` already switched layouts.
- **Colour.** Score levels always carry a text name (ring, chips, markers); no screen relies on colour alone. Palette
  contrast (text on every surface, accent/onAccent) is enforced by `PaletteTests` (≥ 4.5:1).
- **Reduce Motion.** `dsAnimation` / `dsTransition` replace motion with instant changes or a fade; the score ring,
  muscle map, image carousel and coach typing indicator already honoured it.
- **Reduce Transparency.** Liquid Glass (`dsGlass`) and `.bar`/`.regularMaterial` surfaces adapt automatically to an
  opaque background; no custom blur is used for content.
- **Touch targets.** Menus and buttons use `HitTarget.minimum` (44 pt) / `HitTarget.button` (52 pt).
  The active-workout keypad is bottom-anchored for one-handed use.

## Automated checks
- `AccessibilityAuditUITests` (XCUITest): `performAccessibilityAudit` on all five tabs and the active workout
  (contrast, element detection, hit region, description, trait), plus start → complete set at the largest
  accessibility size.
- `AccessibilityTests` (DesignSystem) and `ChartAccessibilityTests` (app) cover the descriptor logic.
- Audits exclude `.dynamicType` and `.textClipped`: system bars and Swift Charts annotations report false positives;
  large-text clipping is checked by the largest-size flow test instead.

## Not verified / remaining
- Written but **not run locally** (project rule: tests run on CI). The first CI run may surface audit findings on
  screens not touched here; fix those from the failure attachments.
- A full manual VoiceOver, Voice Control and Switch Control pass on a device is `[MANUEL]`.
- Fixed-size chart annotation fonts (`font(.system(size: 9))` in the score distribution chart) do not scale.
- Other screens were audited by reading code only; large-text layouts outside the set row (e.g. rest timer, keypad)
  need visual review at AX5.
