---
name: ATROX
description: One powerlifting meet scoresheet, ruled and lit in the dark, where every lift ends in a percentile.
colors:
  ground: "#21232e"
  ground-deep: "#1a1c25"
  rule: "#3b3f52"
  rule-strong: "#5a5f78"
  ink: "#eef0f5"
  ink-2: "#aeb2c4"
  blue: "#105bff"
  blue-ink: "#7aa2ff"
  orange: "#fe8500"
  orange-hover: "#ffa033"
  lamp-on: "#f4f5f8"
typography:
  display:
    fontFamily: "Archivo, system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "clamp(3.25rem, 11.5vw, 6rem)"
    fontWeight: 800
    lineHeight: 0.9
    letterSpacing: "-0.01em"
    fontVariation: "wdth 62"
  headline:
    fontFamily: "Archivo, system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "clamp(2.25rem, 6vw, 3.75rem)"
    fontWeight: 800
    lineHeight: 0.95
    letterSpacing: "-0.005em"
    fontVariation: "wdth 62"
  figure:
    fontFamily: "Archivo, system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "clamp(2rem, 6vw, 3.5rem)"
    fontWeight: 800
    lineHeight: 1
    fontVariation: "wdth 75"
  title:
    fontFamily: "Archivo, system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "clamp(1.4rem, 4.2vw, 2.25rem)"
    fontWeight: 800
    lineHeight: 1
    letterSpacing: "0.04em"
    fontVariation: "wdth 62"
  body:
    fontFamily: "Archivo, system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "1.0625rem"
    fontWeight: 400
    lineHeight: 1.55
    fontVariation: "wdth 100"
  label:
    fontFamily: "Archivo, system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "0.72rem"
    fontWeight: 700
    lineHeight: 1.55
    letterSpacing: "0.1em"
    fontVariation: "wdth 70"
rounded:
  none: "0px"
  lamp: "50%"
spacing:
  hairline: "1px"
  cell-x: "0.9rem"
  cell-y: "0.7rem"
  block-gap: "clamp(4rem, 9vw, 7rem)"
  gutter: "1.25rem"
components:
  button-primary:
    backgroundColor: "{colors.orange}"
    textColor: "{colors.ground}"
    typography: "{typography.title}"
    rounded: "{rounded.none}"
    padding: "0.5rem 1.6rem"
    height: "3.25rem"
  button-primary-hover:
    backgroundColor: "{colors.orange-hover}"
    textColor: "{colors.ground}"
  switch-button:
    backgroundColor: "transparent"
    textColor: "{colors.ink-2}"
    rounded: "{rounded.none}"
    size: "2.75rem"
  switch-button-pressed:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.ground}"
  sheet:
    backgroundColor: "{colors.ground}"
    textColor: "{colors.ink}"
    rounded: "{rounded.none}"
  sheet-total-row:
    backgroundColor: "{colors.ground-deep}"
    textColor: "{colors.orange}"
  lamp:
    backgroundColor: "{colors.lamp-on}"
    rounded: "{rounded.lamp}"
    size: "1.25rem"
  percentile-bar:
    backgroundColor: "{colors.blue}"
    height: "4px"
---

# Design System: ATROX

## Overview

**Creative North Star: "The Meet Scoresheet"**

The home site is one powerlifting scoresheet seen once, not a landing page that quotes one. A night-gym ground (#21232e) carries a ruled grid of boxed fields, one condensed grotesque used across a wide width range, and three round referee lamps. Recognisable with every word removed: hairline boxes and three white circles. The offer is a filled-in attempt card whose last column is the percentile; the signup is the sheet's signature box.

The build confirms the contract. Everything is ruled, nothing floats. Sections below the sheet reuse the same boxed grid (rows, close box) instead of switching to a second vocabulary. Density is high in the sheet (fixed table, tabular numerals) and loosens only in the vertical gaps between blocks. The surface is dark only; there is no light theme (`color-scheme: dark`).

The legal pages and the invite page inherit the same tokens and the same type roles with a quieter layout (single column, no sheet).

**Key Characteristics:**
- Hairline-ruled boxes in two tints; the grid is the ornament.
- One family, Archivo variable, with the width axis (`wdth` 62 to 100) doing the work of a type pairing.
- Numerals are tabular everywhere (set on `body`), so kg and percentile columns align.
- Three inks only beyond neutrals: white lamps, blue for the score bar, orange for the action and the total.
- Zero radius on every box; only the lamps are round.
- Bilingual by markup: every string exists twice (`lang="en"` / `lang="tr"`), the root `data-l` attribute hides one.

## Colors

A night-gym neutral ground, a cool grey-violet rule system, and two brand inks used sparingly.

### Primary
- **Meter Blue** (#105bff): the percentile bar fill only. Never text, never a button. Too dark for text on the ground, so it stays a graphic.
- **Signal Orange** (#fe8500): the one action color. Primary button fill, the SAMPLE flag value, the total row's percentile and its bar, text selection background, the draft-note border on legal pages. Its rarity is how the eye finds the button.

### Secondary
- **Link Blue** (#7aa2ff): the readable blue. Links and the focus ring (3px outline, 3px offset). Hover on a link goes to Ink.

### Neutral
- **Night Gym** (#21232e): page ground, button text, text on selected switch.
- **Deep Ground** (#1a1c25): the total row's fill, the only tonal step in the system.
- **Rule** (#3b3f52): inner dividers between fields and rows; empty bar track; unlit lamp start state; footer top border.
- **Rule Strong** (#5a5f78): outer sheet borders, the head and header-row dividers, scrollbar thumb.
- **Ink** (#eef0f5): primary text, pressed switch fill, hover text.
- **Ink Soft** (#aeb2c4): secondary text, field captions, column headers, footer.
- **Lamp White** (#f4f5f8): lit referee lamp.
- **Orange Lift** (#ffa033): button hover only.

### Named Rules
**The Three-Ink Rule.** Beyond neutrals, only white lamps, blue and orange appear, and each owns one job: lamps count a lift, blue measures the percentile, orange acts. A fourth hue is a new system, not an extension.

**The Blue Is Graphic Rule.** `#105bff` is never used for text; reading blue is `#7aa2ff`.

## Typography

**Display Font:** Archivo variable (self-hosted woff2, latin and latin-ext, weight 100 to 900, `font-stretch` 62% to 125%), with system-ui fallbacks
**Body Font:** the same Archivo at `wdth` 100
**Label/Mono Font:** none; tabular numerals on the same family

**Character:** One grotesque speaking in two registers. Condensed caps (wdth 62 to 75, weight 700 to 800) are the scoresheet's printed form; normal width at 400 is the lifter's plain sentence. The width axis replaces a second font.

### Hierarchy
- **Display** (800, clamp 3.25rem to 6rem, 0.9, wdth 62, uppercase, -0.01em): the sheet title only ("Strength Score"). Balanced wrap.
- **Headline** (800, clamp 2.25rem to 3.75rem, 0.95, wdth 62, uppercase): section h2s, including inside the close box.
- **Figure** (800, clamp 2rem to 3.5rem, 1, wdth 75): the percentile numeral in each lift row. The largest numbers after the title.
- **Title** (800, clamp 1.4rem to 2.25rem, 1, wdth 62, uppercase, 0.04em): lift names in row headers (SQUAT, BENCH, DEADLIFT, Score). The button label uses the same register at wdth 75, 1.15rem, 0.06em.
- **Body** (400, 1.0625rem, 1.55, wdth 100): paragraphs; secondary copy in Ink Soft; measure 62ch for row text, 46 to 52ch for sheet and close copy; `text-wrap: pretty`.
- **Label** (700, 0.72rem, 0.1em, wdth 70, uppercase): field captions and table headers in Ink Soft. Row keys in the explainer lists are the same register enlarged (800, 1.15rem, 0.06em).
- **Mark** (800, 1.5rem, 0.12em, wdth 62): the ATROX wordmark, text only. Back-link on legal pages is the same at 1.25rem.

### Named Rules
**The Width Axis Rule.** Hierarchy comes from `font-stretch` and weight on one family, never from adding a second typeface.

**The Tabular Rule.** Numbers align in columns; `font-variant-numeric: tabular-nums` is set once on `body` and not overridden.

## Layout

A single centered column, `min(72rem, 100% - 2.5rem)`, with a 1.25rem minimum gutter. The sheet is a stack of boxed bands: a four-field head (1.4fr 1fr 1fr auto), a title band, a fixed-layout table (three columns at 28% each, the lamps column takes the rest), and a foot band with copy left and the button right. Cell padding is .7rem by .9rem; the same .9rem inset is used for the bar and the field text so everything hangs on one vertical.

Blocks below the sheet are separated by `clamp(4rem, 9vw, 7rem)`. The explainer lists (`.rows`) split into a key column and a value column whose first column is `calc(28% + .504rem)`, deliberately lining up with the table's first column. The close box is one bordered panel with generous padding (2.5rem by 1.5rem) and a wrapping row of the button and the mailto link.

Responsive steps, both observed in the stylesheet:
- **760px:** sheet head becomes a 2-by-2 grid with re-ruled borders; table cell padding tightens to .6rem; lamps shrink to .95rem; foot stacks and the button goes full width; explainer rows stack key above value.
- **460px:** table column widths retune to 27/25/26%, header labels drop to .6rem, lift names to 1.2rem, kg to .95rem, percentile to 1.9rem, lamps to .7rem, and the bar inset shrinks from .9rem to .4rem to match the tighter cell padding.

Touch targets: switch buttons are 2.75rem square, the primary button 3.25rem high.

Legal pages: one column at 46rem, 62ch text measure, h2 at 1.4rem, ruled tables with bottom hairlines only. Invite page: a centered 30rem column.

## Elevation & Depth

Flat, with no shadows, no gradients, no blur and no layering effect. Depth is conveyed by two hairline weights (Rule inside, Rule Strong at the outer edge) and one tonal step (Deep Ground on the total row). The only motion that implies depth is a 1px press translate on the button.

### Named Rules
**The Hairline Depth Rule.** Hierarchy of containment is expressed by border tint: inner dividers in Rule, container edges in Rule Strong. Never by shadow.

## Shapes

Everything is a rectangle with square corners (radius 0), including the button and the switch. The one curve is the referee lamp, a perfect circle (1.25rem, 50%). The percentile bar is a flat 4px stroke on a 4px track of the same width. The focus ring has a 2px radius, the only incidental softening.

## Components

### Sheet
A bordered container (1px Rule Strong) with banded children separated by hairlines. Head holds four boxed fields: a Label caption over a 1.05rem 600 value; the SAMPLE field's value is Signal Orange. The sheet is the only container on the page.

### Lifts table
Fixed layout, tabular. Row headers in Title register, kg cells in 500 weight, percentile cells in Figure register. The total row sits on Deep Ground with an orange percentile and orange bar and an empty lamp cell; it carries the same bottom rule as the header.

### Percentile bar
A 4px track (Rule) drawn as a `::before` on the percentile cell, with a Meter Blue fill (`<i class="bar" style="--p:NN">`) at `(100% - 1.8rem) * p / 100`, inset .9rem both sides, .5rem from the cell bottom. Orange on the total row.

### Lamps
Three white circles per lift, 1.25rem with .35rem gaps. On load each lamp animates from Rule grey to Lamp White over .35s with a Signal ease (`cubic-bezier(.16, 1, .3, 1)`), delayed by `index * 140ms + .35s`, so nine lamps light in one left-to-right, top-to-bottom sequence, once. They are decorative (`aria-hidden`); the lit end state is the default style, so without animation they read as counted.

### Button
One primary only. Signal Orange fill, Night Gym text, Title-register caps, square, 3.25rem high, padding .5rem 1.6rem. Hover lifts to Orange Lift; active translates 1px down; both transition .2s. Full width at 760px and below. A secondary variant appears only on the invite page, as a transparent button with an inset 1px Rule Strong outline that fills with Ink on hover.

### Language switch
Two square 2.75rem buttons (EN, TR) in Label-adjacent register with a 1px Rule border; the pressed one fills Ink with Night Gym text. State is carried by `aria-pressed`.

### Explainer rows
A bordered list; each row is a two-column grid with a caps key and an Ink Soft value, `strong` in Ink 600. No bullets, no cards, hairline between rows, none after the last.

### Close box
A single bordered panel holding a Headline, one line of copy and the button beside a plain mailto link. It is the sheet's last box, not a banner.

### Navigation
There is none beyond the wordmark (text link to `/`) and the footer's three text links (Privacy, Terms, Support) in Ink Soft, hover Ink, separated by a top hairline.

## Do's and Don'ts

### Do:
- **Do** build every new surface from boxed, hairline-ruled fields: Rule inside, Rule Strong on the outer edge.
- **Do** use one family with `font-stretch` for hierarchy: wdth 62 for titles, 70 for labels, 75 for figures and buttons, 100 for reading text.
- **Do** keep orange for the single action and the total; blue only for measuring bars.
- **Do** keep numerals tabular and aligned to the same .9rem inset as the field text.
- **Do** light lamps once, in sequence, and disable the animation under `prefers-reduced-motion` (which also removes button and switch transitions and smooth scroll).
- **Do** ship both languages in the markup and let `data-l` select.
- **Do** label demonstration data as SAMPLE in the sheet head.

### Don't:
- **Don't** introduce cards, icons, gradients, shadows, glows or rounded boxes; the first viewport must stay a scoresheet.
- **Don't** add kicker or eyebrow lines above headings; field captions belong to a field box, not to a heading.
- **Don't** set text in Meter Blue (#105bff); use Link Blue (#7aa2ff).
- **Don't** add a second typeface or a light theme.
- **Don't** add a second primary button style or more than one orange action per band.
- **Don't** use more than one lamp sequence or loop it.

## Not Canonized

Defects and one-offs the build carries that future surfaces should not inherit: the legal pages' `.draft` banner and `.fill` highlight (#3a2a10 / #ffd9a0) are leftovers of draft-stage placeholders and are not part of the palette; the invite page's secondary button uses an inset `box-shadow` as a border, which is a border trick and not an elevation token; legal h2s use 1.4rem with `letter-spacing: .02em` in the condensed caps register and are not a step in the display scale.
