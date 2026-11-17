---
name: ATROX
description: A night-gym dark page where one rounded blue stage paints a lifter population as dots, and a single orange dot is you.
colors:
  ground: "#21232e"
  ground-deep: "#191b24"
  card: "#2a2d3c"
  card-2: "#323649"
  line: "rgba(238, 240, 245, 0.11)"
  ink: "#eef0f5"
  ink-soft: "#b4b8c9"
  ink-faint: "#8f94a9"
  blue: "#105bff"
  blue-ink: "#7aa2ff"
  blue-deep: "#0d2160"
  on-deep: "#eef2ff"
  sky-top: "#0a1a52"
  sky-mid: "#0f3cc2"
  sky-low: "#2a52c9"
  orange: "#fe8500"
  orange-hover: "#ffa033"
  orange-light: "#ffb255"
  wordmark-ghost: "#2b2e3d"
typography:
  display:
    fontFamily: "Archivo, system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "clamp(2.5rem, 5.8vw, 4.5rem)"
    fontWeight: 700
    lineHeight: 0.98
    letterSpacing: "-0.035em"
    fontVariation: "font-stretch 78%"
  headline:
    fontFamily: "Archivo, system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "clamp(2.1rem, 4.6vw, 3.5rem)"
    fontWeight: 650
    lineHeight: 1.02
    letterSpacing: "-0.03em"
    fontVariation: "font-stretch 80%"
  title:
    fontFamily: "Archivo, system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "clamp(1.25rem, 1.8vw, 1.5rem)"
    fontWeight: 600
    lineHeight: 1.18
    letterSpacing: "-0.02em"
    fontVariation: "font-stretch 85%"
  body:
    fontFamily: "Archivo, system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.55
    fontFeature: "tabular-nums"
  label:
    fontFamily: "Archivo, system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "0.78rem"
    fontWeight: 700
    letterSpacing: "0.08em"
    fontVariation: "font-stretch 75%"
  wordmark:
    fontFamily: "Archivo, system-ui, sans-serif"
    fontSize: "clamp(5rem, 22vw, 17rem)"
    fontWeight: 800
    lineHeight: 0.82
    letterSpacing: "-0.02em"
    fontVariation: "font-stretch 62%"
rounded:
  pill: "999px"
  stage: "26px"
  panel: "22px"
  feature: "20px"
  result: "16px"
spacing:
  gutter: "clamp(16px, 3.4vw, 40px)"
  section: "clamp(72px, 9vw, 120px)"
  grid-gap: "12px"
components:
  button-primary:
    backgroundColor: "{colors.orange}"
    textColor: "{colors.ground}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "0 20px"
    height: "40px"
  button-primary-hover:
    backgroundColor: "{colors.orange-hover}"
  button-on-stage:
    backgroundColor: "#ffffff"
    textColor: "{colors.sky-top}"
    rounded: "{rounded.pill}"
    height: "46px"
  lang-switch-active:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.ground}"
    rounded: "{rounded.pill}"
    height: "32px"
  stage:
    backgroundColor: "{colors.sky-mid}"
    textColor: "#ffffff"
    rounded: "{rounded.stage}"
  feature-field:
    backgroundColor: "{colors.blue-deep}"
    textColor: "{colors.on-deep}"
    rounded: "{rounded.feature}"
    padding: "22px"
  feature-deep:
    backgroundColor: "{colors.card}"
    textColor: "{colors.ink}"
    rounded: "{rounded.feature}"
    padding: "22px"
  step-card:
    backgroundColor: "{colors.card}"
    textColor: "{colors.ink}"
    rounded: "{rounded.panel}"
  calc-box:
    backgroundColor: "{colors.blue-deep}"
    textColor: "{colors.on-deep}"
    rounded: "{rounded.stage}"
  join-form:
    backgroundColor: "#ffffff"
    textColor: "{colors.ground}"
    rounded: "{rounded.pill}"
    padding: "6px"
---

# Design System: ATROX

Home page (web/index.html with web/home.css and web/home.js, EN and TR). The legal pages and the /u/ invite page still use the older web/site.css; see the last section.

## Overview

**Creative North Star: "The Population in Dots"**

ATROX tells a lifter how strong they are against people like them, so the page draws that answer instead of describing it. One rounded blue stage holds a lifter population painted as a field of dots, a histogram, with a single orange dot standing for you and two authored weight plates floating in front. Everything after the stage is quieter: a night-gym ground (#21232e), deep-blue and slate panels, and orange kept for the one thing that is yours (the action, the you-dot, the active progress bar).

The density is calm and rounded. Panels are large soft rectangles on a dark ground, type is Archivo pulled narrow for headings and left at normal width for reading, and sections are separated by generous vertical air (72 to 120px) rather than rules. Motion is slow and decelerated; nothing bounces. The page walks a fixed sequence: stage, what it is, three asymmetric feature panels, tabbed steps with a timed bar, an illustrative score calculator, FAQ, a join band that repeats the stage, and a giant ghost wordmark.

It refuses the default SaaS look: no grid of equal icon cards, no kickers or eyebrows, no glow halos, no gradient text, no stock-photo hero.

**Key Characteristics:**
- One saturated blue stage with painted dot fields and parallax; the rest of the page is dark neutral plus deep-blue panels.
- Orange (#fe8500) is the single action and "you" ink; it never decorates.
- Archivo variable width axis does the hierarchy: narrow caps-feeling headings, normal-width body.
- Pill controls, 20 to 26px panels, no hard edges.
- Dark only (`color-scheme: dark`); no light theme.
- EN and TR render the same structure; only one language is visible at a time (`html[data-l]`).

## Colors

A deep slate ground, one electric-blue sky, one deep-blue panel, and a single orange.

### Primary
- **Meter Blue** (#105bff): the brand blue. Appears in the stage sky ramp, art washes (rgba of it) and the app's identity; on the dark ground the readable version is Blue Ink.
- **Blue Ink** (#7aa2ff): link text, focus ring, line-art and the chart viz tint on dark surfaces.
- **Deep Field Blue** (#0d2160): the field feature panel and the calculator box. Text on it is Cold White (#eef2ff) and a 74% variant for secondary copy.
- **Sky Ramp** (#0a1a52 top, #0f3cc2 middle, #2a52c9 low): the stage and join-band gradient, top to bottom. Used only inside those two rounded boxes.

### Secondary
- **Lift Orange** (#fe8500): primary pill buttons, the "you" dot, the selected-tab progress bar, slider fill, toggle on-state, open-FAQ plus, text selection, the one emphasized phrase in the statement. Hover lightens to #ffa033; large result numbers on deep blue use #ffb255.

### Neutral
- **Night Gym** (#21232e): page ground and button text on orange.
- **Under Ground** (#191b24): defined as `--bg-deep`; reserved, not yet used in rules.
- **Slate Card** (#2a2d3c) and **Slate Card Lift** (#323649): step cards and the dark feature panel. `--card-2` is defined but unused.
- **Ink** (#eef0f5): primary text on the ground. **Soft Ink** (#b4b8c9): body and secondary text. **Faint Ink** (#8f94a9): footnotes, inactive tabs, footer headings.
- **Hairline** (rgba(238,240,245,0.11)): section and list dividers, the scrolled-nav underline.
- **Ghost Wordmark** (#2b2e3d): the footer wordmark only. See Do's and Don'ts.

### Named Rules
**The One Orange Rule.** Orange marks what is yours or what to press: the action pill, the you-dot, the active timer bar. If it is decorative, it is not orange.

**The Stage Blue Rule.** Saturated blue (the sky ramp) lives only in the two rounded stage boxes. Everywhere else blue is the deep #0d2160 panel or Blue Ink line-work.

## Typography

**Display Font:** Archivo (variable, self-hosted woff2, weight 100-900, width 62-125%), fallback system-ui, -apple-system, Segoe UI, sans-serif.
**Body Font:** the same Archivo at `font-stretch: 100%`.
**Label/Mono Font:** none; numbers use `font-variant-numeric: tabular-nums` globally.

**Character:** One family, two voices. Headings are squeezed with the width axis (70 to 85%) into a tall athletic condensed; body is the family's normal width. The width axis replaces a second typeface.

### Hierarchy
- **Display** (700, clamp 2.5-4.5rem, 0.98, -0.035em, stretch 78%): the stage headline (`.h1`).
- **Headline** (650, clamp 2.1-3.5rem, 1.02, -0.03em, stretch 80%): section titles (`.h2`); calculator title steps down to 1.9-2.8rem.
- **Title** (600, 1.1-1.5rem, ~1.18, -0.02em, stretch 85%): feature panel and step card headings, tab titles.
- **Statement** (400, clamp 1.1-1.45rem, 1.32, -0.015em): the what-is paragraph, with one orange phrase.
- **Body** (400, 0.82-1rem, 1.45-1.6): lede 0.95rem capped at 30em; FAQ answers 0.92rem at max 60ch; card copy 0.88rem at 27em.
- **Label** (700, 0.78rem, 0.08em, stretch 75%): the EN/TR switch. Brand wordmark in the nav is stretch 70%, weight 800, tracking 0.12em, 1.1rem. Result numbers and amounts are stretch 80%, weight 650.
- **Footer wordmark** (800, clamp 5-17rem, 0.82, stretch 62%): decorative, aria-hidden.

### Named Rules
**The Width-Axis Rule.** Hierarchy comes from `font-stretch` and weight within Archivo, not from adding a second family. Headings 70-85%, reading text 100%.

## Layout

A single centered column (`.wrap`, max 1240px, side padding clamp 16-40px). Sections are separated by padding only: 72 to 120px between major blocks, 40 to 64px before the join band and footer. Nav is sticky with a three-column grid (brand, centered links, switch plus orange pill) and gains an 88% ground blur and a hairline after scroll.

Section grids are deliberately asymmetric: what-is 1.25fr / 1fr, features 2.15fr / 1fr / 1fr with 12px gaps, steps 1fr / 1fr (tabs left, card stack right), calculator .92fr / 1.08fr inside the deep-blue box, FAQ 1fr / 1.35fr, footer 1.4fr plus three equal columns.

Responsive steps: at 980px features become two columns with the field panel spanning; at 900px the nav collapses to a menu button and drawer and the calculator stacks; at 860px steps, FAQ and footer collapse (footer to two columns); at 640px the stage grows to 600px tall and the plates move; at 560px features and the what-is grid go single column.

Below-the-fold sections fade up (`.pre` to `.rv`, translateY 22px, 0.9s) once JS runs.

## Elevation & Depth

Depth is tonal and by layering, not by shadow. Slate cards sit one step above the ground; deep-blue panels read as a different material; the stage is a gradient with parallax dot layers behind and in front of the plates. The nav gets a backdrop blur only when scrolled.

### Shadow Vocabulary
- **Plate lift** (`filter: drop-shadow(0 16px 14px rgba(5,12,50,.45))`): under the floating weight plates, the one soft ground-contact shadow.
- **Hairline inset** (`inset 0 0 0 1px rgba(255,255,255,.1)`): the chart box edge.
- **Slider thumb ring** (`0 0 0 6px rgba(254,133,0,.3)` plus a small drop): the range thumb. This is a halo; see Do's and Don'ts.
- **Form focus ring** (`0 0 0 3px #fe8500`): the join form when focused.

### Named Rules
**The Tonal Depth Rule.** A panel is raised by a lighter slate or a different blue, never by a card shadow. Only the plates, the slider thumb and the chart dot carry a shadow, and each is an object, not a surface.

## Shapes

Soft and round. Controls are full pills (999px): buttons, the language switch, nav links, the form, segmented control, toggles. Panels step by size: the stage, join band and calculator 26px (stage scales clamp 18-26px), step cards 22px, feature panels 20px, result tiles 16px, chart box 20px. Small circular affordances (plus, arrow chip, slider thumb) are 50%. Plates are circular SVG objects. Hairlines are 1px at 11% ink; the only underline accents are the 2px orange tab bar and 4px slider track.

## Components

### Buttons
- **Shape:** pill (999px), 40px tall (46px large), padding 0 20px (0 26px large).
- **Primary:** Lift Orange fill, Night Gym text, 0.85rem, weight 700.
- **Hover / Focus:** lightens to #ffa033 and lifts 1px; active drops back and scales .98. Focus-visible is a 2px Blue Ink outline, offset 3px.
- **On stage:** inside the hero the button inverts to white with Sky Top text; in the join band it stays orange.

### Navigation
Sticky, brand left (narrow caps wordmark plus a mark that rotates 90 degrees on hover), four centered pill links (Soft Ink, Ink on hover or current), right side holds the **EN/TR switch** (translucent pill track, active segment solid Ink with ground text) and the orange waiting-list pill. At 900px links and pill hide behind a 40px round menu button that morphs to an X and opens a max-height drawer.

### Stage (signature)
A rounded blue box, height clamp 520-700px, holding three stacked canvas dot fields (two behind, one in front) and a plates layer, all moving by `--px`/`--py` pointer parallax at different depths. Centered copy sits on top: display headline, one sentence, white pill. Two authored plates (blue, orange) bob on a 7s loop; click or tap flips one (rotateY 720deg, 1.1s) and shows a white pill with a sample number. The join band repeats the sky and dot fields with a smaller headline and the form.

### Feature panels
Three asymmetric panels, min-height 240-280px, 20px radius, 12px gap. One wide Deep Field Blue panel carries a painted dot field; two Slate Card panels carry a small line-art viz (a check that redraws on hover, a toggle that switches). Titles in Title style, copy 0.82rem. Hover lifts 4px. Not icon cards: each panel has a different internal drawing.

### Tabs with progress bar
Left column is a ruled list of numbered rows (title, arrow, number); the selected row indents and shows an orange 2px bar that fills over 8s linearly and advances the tab; hover or focus pauses it. Right column stacks cards (Slate Card, 22px) that cross-fade and rise 14px, each with copy on top and a Blue Ink line-art figure over a faint blue wash at the bottom.

### Calculator
A Deep Field Blue box. Left: title, lede, labelled **sliders** (4px track, orange fill, white 22px thumb with a soft orange ring), a **segmented control** (translucent pill track, selected segment white with deep-blue text), two result tiles (white at 7%, 16px radius; the highlighted number in #ffb255) and a comparison sentence. Right: a chart box with a legend, an SVG distribution curve, a white percentile tag that tracks the position and an orange you-dot with a white ring. It is labelled as an illustration, not a prediction (`.disc`).

### FAQ accordion
Ruled rows (hairline top, last row bottom). Question 0.95-1.08rem with a 30px circular plus; open state rotates 180 degrees, fills orange with ground ink and flattens to a minus. Answers open by animating grid rows 0fr to 1fr (.45s), capped at 60ch.

### Join form
A white pill (max 440px, 6px padding) holding the email field and the orange button. Focus-within draws a 3px orange ring. The error state shakes the pill and turns the note #ffd2dd.

### Footer
Brand and tagline, three link columns (Faint Ink headings, Soft Ink links that underline on hover), a ghost wordmark at up to 17rem (62% width, 800 weight, #2b2e3d on the ground, aria-hidden, cropped by `overflow: hidden`), and a hairline-topped bar with legal links.

## Motion

Easing is `cubic-bezier(.2,.7,.2,1)` (decelerate, no overshoot); the intro and flip use close variants. Intro (`data-intro="play"`): dot layers and plates grow in from 60px below (1.6 to 1.9s, staggered .12-.3s) while hero copy rises in 1.1s steps. Plates bob 7s ease-in-out and flip on click. Tab bar fills 8s linear. Canvases fade in over 1.1s once drawn. A `prefers-reduced-motion: reduce` block kills every animation and transition (`!important`), sets smooth-scroll off and un-hides `.pre` content.

## Do's and Don'ts

### Do:
- **Do** keep the ground #21232e and put text in Ink (#eef0f5), Soft Ink (#b4b8c9) or Faint Ink (#8f94a9); Faint Ink is for footnotes and inactive states only.
- **Do** use orange only for the action pill, the you-dot, the active tab bar, slider fill, toggle on-state and the single emphasized phrase.
- **Do** set hierarchy with Archivo `font-stretch` (70-85% for headings, 100% for body) and tabular numerals everywhere.
- **Do** use pill radius (999px) for every control and 20, 22 or 26px for panels.
- **Do** show every claim that is a number as an illustration or sample, labelled as such, and keep EN and TR copy structurally identical.
- **Do** keep every new animation under the reduced-motion kill switch and use the decelerating `--ease`.
- **Do** mark decorative layers (canvases, plates art, ghost wordmark) `aria-hidden`.

### Don't:
- **Don't** build rows of equal icon-on-top cards; the features are asymmetric and each carries its own drawing.
- **Don't** add kickers, eyebrows or small-caps label lines above headings.
- **Don't** add glow halos, neon blurs, gradient text or bounce or elastic easing.
- **Don't** use saturated sky blue outside the stage and join band, or a light theme.
- **Don't** reuse the footer's #2b2e3d for any text; it is below contrast on purpose because that wordmark is decorative.
- **Don't** add backer logos, prices, ratings, counts or user claims the product does not have yet, or app screenshots until they exist.

### Known leftovers (not rules)
- The range thumb ring (orange at 30%, 6px, 9px on hover) is a soft halo that the no-halo rule would otherwise forbid; it is a slider affordance, left as built, not a pattern to copy.
- `--bg-deep` and `--card-2` are declared and not used; `.chartdot` sits outside the file's section order at the end of home.css.
- The footer wordmark (#2b2e3d on #21232e) is about 1.2:1 contrast by design.

## Second, older surface: web/site.css

The legal pages (/privacy, /terms, /support) and the /u/ invite page still use `web/site.css`, a ruled-scoresheet system from the previous direction. It shares the ground (#21232e), Ink, Blue (#105bff), Blue Ink (#7aa2ff), Orange (#fe8500) and the same self-hosted Archivo, but uses hairline rules (#3b3f52), condensed caps, three referee lamps and a 62ch measure instead of pills and rounded panels. It is not the home page system and should not be extended with home components; when those pages are redesigned they should adopt the home tokens above.
