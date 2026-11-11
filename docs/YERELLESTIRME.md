# Localization and units

## Languages
- Source language: **English** (`en`). Translation: **Turkish** (`tr`). Development region is `en`.
- Catalogs: `ios/App/Resources/Localizable.xcstrings` (app) and
  `ios/Packages/DesignSystem/Sources/DesignSystem/Resources/Localizable.xcstrings` (shared components).
- Every user-visible string lives in a catalog. No literal UI text in Swift
  (exceptions: `Text(verbatim:)` for numbers/symbols/native language names, and the DEBUG-only
  component gallery, whose sample content is developer-facing).

## Key naming: `feature.screen.item`
- Lower camelCase segments, dot separated: `auth.signin.title`, `shell.tabbar.today`, `workout.summary.setCount %lld`.
- `feature` = folder under `App/Features` (or `shell`, `common`, `settings`, `debug`).
- Shared DesignSystem strings use `ds.<component>.<item>` (`ds.errorState.retry`).
- Keys with arguments keep the format specifier in the key (`%lld`), which is how SwiftUI interpolation resolves them.
- Never reuse one key for two different meanings; reuse is only for identical text in identical context.

## Plurals
Use catalog plural variations (`one` / `other`; add `zero`/`few` etc. only where the language needs them).
Example: `workout.summary.setCount %lld` — EN "1 set / 5 sets", TR "1 set / 5 set".
Tested in `CatalogTests`.

## In-app language
`LanguageSettings` (`App/Sources/Settings`) persists `system | tr | en` in UserDefaults (`settings.language`).
`ContentView` injects the effective locale via `.environment(\.locale, …)`. DesignSystem strings that bypass SwiftUI
lookup must use a locale-aware API (`ScoreLevel.localizedName(locale:)`).
Known limitation: a navigation title that is already on screen is not re-localized until it is re-pushed.

## Units (`App/Sources/Units`)
- Storage is always **kg** and **cm**; conversion happens only at display/input.
- `WeightUnit` (kg/lb), `LengthUnit` (cm / ft-in) are `Measurement`-based. `WeightFormat` / `LengthFormat` format and parse with locale-aware separators.
- Foundation's pound constant is 0.453592 kg (≈4e-5 kg error per 100 lb) — acceptable for display input.
- `PlateRounding` rounds in the user's unit to 2.5 kg / 5 lb and returns kg (`nearest`, `down`, `up`).
