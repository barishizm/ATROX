# ios/Widgets/

WidgetKit extension (`ATROXWidgets`): the workout Live Activity and Dynamic Island (P038) and the home-screen,
Lock Screen and Control Center surfaces (P096).

- `Sources/WorkoutLiveActivity.swift` — the activity's views (Lock Screen, compact, minimal, expanded).
- `Sources/ATROXWidgets.swift` — Strength Score, Today's workout and Weekly goal widgets.
- `Sources/SnapshotProvider.swift` — timeline provider shared by the three widgets; reads the snapshot, never SwiftData.
- `Sources/StartWorkoutControl.swift` — "Start workout" control (Control Center, Action Button).
- `Resources/` — String Catalog of the extension (en + tr).
- `../Shared/` — compiled into both the app and the extension: `WorkoutActivityAttributes`, the rest intents,
  `WidgetSnapshot` (the JSON the app writes into the app group), and the App Intents (`ATROXIntents.swift`).
- Manual verification steps: `docs/TEST-NOTLARI.md`.
