# ios/

iOS uygulaması: XcodeGen projesi (`project.yml`), uygulama hedefi ve yerel Swift paketleri.

| Dizin | Amaç |
|---|---|
| `App/` | Uygulama hedefi: `Features/*` ve kompozisyon kökü |
| `Packages/` | Yerel paketler: `StrengthKit` (skor motoru), `DataKit` (SwiftData + senkronizasyon), `DesignSystem`, `CoachKit` |
| `Widgets/` | WidgetKit + Live Activity hedefi |

`.xcodeproj` commit edilmez; `cd ios && xcodegen generate` ile üretilir (P003).
Ayrıntı: [`docs/02-MIMARI.md`](../docs/02-MIMARI.md).
