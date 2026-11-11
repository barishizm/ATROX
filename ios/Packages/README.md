# ios/Packages/

Local Swift packages (created in P004), wired into `ios/project.yml`. Responsibilities: [`docs/02-MIMARI.md`](../../docs/02-MIMARI.md) §2.1.

| Package | Dependencies |
|---|---|
| `StrengthKit` | Foundation only (Core ML code goes behind `#if canImport(CoreML)`); must build on Linux |
| `DataKit` | supabase-swift 2.55.6 |
| `DesignSystem` | SwiftUI |
| `CoachKit` | Foundation |

Run tests per package: `swift test --package-path ios/Packages/<Name>`.
