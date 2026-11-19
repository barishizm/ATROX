# AI food-photo calorie tracking — design (2026-11-19)

Status: approved by the user's answers in chat (role, pricing, scope, data source). Items marked **(my call)** were
decided by the builder and can be changed cheaply.

## Intent
A lifter photographs a meal; the AI names the foods, estimates portions, calories and macros; the app tracks the day
against a calorie/macro target that follows the user's training goal. Like Cal AI, but connected to ATROX's coach.
Reverses `docs/00-KARARLAR.md` §6 ("nutrition tracking out of v1.0") by the user's request on 2026-11-19.

## Decided by the user
- **Role:** target derived from profile goal + body weight + training frequency, with the coach able to read the log.
  The user may instead **enter the target manually**; the app asks which at first use, and the manual path is a guided
  flow (calories, then protein/carbs/fat).
- **Pricing:** 3 free AI analyses per day; Pro unlimited. Manual entry and daily tracking are free.
- **Scope v1:** photo analysis + manual correction, macros, manual add/search, barcode scan.
- **Food data:** Open Food Facts for barcodes and packaged-product search; DeepSeek estimates for photos and free text.

## Goals / non-goals
Goals: photo → editable estimate in one tap flow; honest uncertainty; daily totals vs target; works offline for
viewing/manual logging; private (photo is not stored on the server).
Non-goals: micronutrients, meal plans/recipes, water tracking, restaurant databases, Health write-back, social sharing,
weight-loss coaching beyond target math. Anti-goal: an eating-disorder trigger (see safety).

## Approaches considered
1. **Dedicated `food-analyze` Edge Function (chosen).** Same proxy pattern as `coach-digest`: JWT, consent, quota, spend
   cap, usage row. Isolated prompt and schema; coach untouched except a read tool.
2. Route images through `coach-chat` as a tool. Rejected: couples quota/threads/streaming to a one-shot JSON job.
3. On-device vision model. Rejected: no accuracy/size path in repo, and the model decision (#9) is cloud DeepSeek.

## Design
**Backend.** `supabase/functions/food-analyze`: input `{kind: "photo"|"text", image_base64?, text?, locale, time_zone}`;
image JPEG ≤ 1.5 MB, sent as a base64 data URL with `detail: low` **(my call; cost)**. Order: JWT → schema →
`food_ai_sharing` consent → spend cap → atomic allowance (`food_consume` RPC: free 3/day, Pro 60/day soft cap, 6/min **(my call)**; every call the model answered counts, "not food" included; provider failures are refunded) →
one LLM call, thinking off, JSON output (json mode for text; for photos only when `FOOD_PHOTO_JSON_MODE=on`, because the vision guide does not say it works with images), Zod-validated and clamped (kcal ≤ 5000/item, ≤ 12 items) → usage row. The
image is never stored; responses are not cached. `ChatMessage` gains image content parts.
Migration `schema_28`: consent kind `food_ai_sharing`; `food_entries`, `nutrition_targets` (RLS owner-only, sync columns,
soft delete); `food_analyses` (per-call quota ledger); `food_consume()` / `food_refund()`; pgTAP; registries
(`USER_TABLES`, `tests.owner_tables()`).
**Data (DataKit, SchemaV8).** `FoodEntry` (eatenAt, meal, name, kcal, protein/carbs/fat g, grams, source
photo|text|barcode|manual, items JSON; a small local-only thumbnail), `NutritionTarget` (mode auto|manual, kcal, macros,
activity). Synced tables with deterministic LWW like the rest. `NutritionTargetCalculator` (pure): Mifflin-St Jeor ×
activity from weekly frequency, goal adjustment (build +10 %, cut −15 %, maintain 0), protein 1.8 g/kg, fat 25 %,
rest carbs. **Safety floor (my call):** never below 1500 kcal (men) / 1200 (women/unspecified); under 18 → maintenance
only, no deficit. Weights stay kg in the database.
**App.** Nutrition screen reached from a card on Today **(my call: no sixth tab)**: calorie ring, macro bars, meal list,
camera button. Flow: camera/library → analyzing → editable result (per-item grams slider, remove, add) → save.
Entry points: text description, barcode scanner (VisionKit `DataScannerViewController`; Open Food Facts looked up from the
device with a descriptive User-Agent), manual form. First use: consent screen (what goes to DeepSeek / Open Food Facts),
then target setup (auto vs manual).
**Coach.** New read tool `get_nutrition_summary(days)` (target + daily totals, no food names). It returns data only while the
latest `food_ai_sharing` consent is granted (the coach's own `ai_sharing` text does not cover meal data); the food consent text
says the coach can read totals. The coach's user-summary context is unchanged (the prompt is locked); the coach asks the tool
when it needs nutrition. Safety rules about extreme restriction already exist (`docs/04-AI-KOC.md` §6).
**Privacy.** New consent kind; update `VERI-ENVANTERI`, `APP-STORE-GIZLILIK`, camera usage string; photos leave the
device only on an explicit analyze tap.

## Left to the builder
Exact prompt wording, UI polish, string keys (TR/EN), test fixtures, thresholds above.

## Open / needs the user later
Real `deepseek-flash` vision accuracy and that images are accepted by that model id must be verified with the real
`DEEPSEEK_API_KEY` (documented in `docs/KURULUM.md`); the Edge Function is deployed by the user.
