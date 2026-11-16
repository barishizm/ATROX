# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Stack
Static HTML/CSS served from `web/` on Vercel (project `atrox-web`, domain `atrox.online`). No framework, no build step; confirmed by the existing codebase and the user's "minimal site" brief. The app itself is native iOS (SwiftUI) and is not part of this surface.

## Users
Recreational and serious gym lifters, mostly 16+, who log workouts and want to know how their strength really compares. Reached in the gap between "I added 5 kg" and "is that good for someone my size and age?". Visitors arrive from the App Store listing, a friend's invite link (`atrox.online/u/<username>`), or a search for the product name. Languages: Turkish and English. Markets named by the owner: Lithuania/EU (home), Türkiye, US.

## Product Purpose
ATROX is an iOS training tracker. The user logs workouts; a model the team trained produces a 0-100 Strength Score per lift: a percentile against gym lifters of the same sex, age and body weight. An optional AI Coach (DeepSeek-backed, behind the team's own proxy, only with consent) reads the user's data and proposes programs. Success for this site: a visitor understands the Strength Score in one look, trusts how data is handled, and either joins the waiting list or opens the App Store listing once it exists.

## Positioning
Strength is shown as a percentile among comparable lifters (same sex, age, body weight), not as a raw number or a generic level. The score is computed on the device by the team's own model. Neighbouring trackers log sets; they do not rank you against people like you.

## Operating Context
- The app is not on the App Store yet. The App Store ID is unknown; the listing link is a placeholder (`id0000000000`).
- Waiting list: until a form backend exists, the call to action is an email to `hello@atrox.online` (decision made 2026-11-16). A real form is a later step.
- Legal pages (`/privacy`, `/terms`, `/support`) are lawyer-reviewed and must stay linked. Controller: Mahmut Barış Akıntı, Vilnius, Lithuania.
- Universal links: `/u/<username>` friend invite page and `/.well-known/apple-app-site-association` (Team ID 5222NFFPX7) must keep working; `vercel.json` rewrites and headers stay.

## Capabilities and Constraints
- Strength Score 0-100 per movement, percentile vs comparable lifters. Weights stored in kg, lengths in cm; display units follow the user.
- Workout logging, programs, records, body weight, optional Apple Health, Friends (opt-in), AI Coach (opt-in, consent per user, no name/email/Health data sent to it), subscription (freemium, StoreKit 2; prices not announced).
- Turkish + English everywhere. Minimum iOS 26.
- Undecided / not to be claimed: prices, user counts, dataset size, model accuracy figures, awards, press, testimonials, App Store rating.

## Brand Commitments
- Name: ATROX (capitals). Brand colours already in the app: ground `#21232E`, blue `#105BFF`, orange `#FE8500`. Dark, athletic, data-led.
- A mascot with several emotions exists in `docs/mascot/` and the app's asset catalog.
- Voice: direct, a little dry, never hype. Turkish first-person-informal ("sen").

## Evidence on Hand
- Real app screenshots can be captured from the simulator build; an old pair exists in `docs/screenshots/`.
- Mascot artwork in `docs/mascot/emotions/`.
- Absent and not to be fabricated: testimonials, customer logos, press, ratings, benchmark numbers, pricing.

## Product Principles
1. Show the score before explaining it; the percentile is the product.
2. Say plainly what data goes where; privacy is part of the pitch, not a footer.
3. Never claim what the product does not have yet (no store rating, no user counts).
4. Two languages are equals, not a translation afterthought.
5. Quiet confidence over hype: no fitness-bro clichés, no motivational slogans.

## Accessibility & Inclusion
WCAG AA contrast, keyboard-reachable controls, readable at 200% zoom, `prefers-reduced-motion` respected. Visitors may be 16-17 years old; copy stays plain and non-shaming about bodies and weights.
