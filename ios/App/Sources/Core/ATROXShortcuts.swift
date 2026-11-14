import AppIntents

/// The three actions that show up in Shortcuts, Spotlight and Siri without any setup (P096). The phrases (EN + TR)
/// live in `App/Resources/AppShortcuts.xcstrings`; every phrase has to contain the app name.
struct ATROXShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartWorkoutIntent(),
            phrases: [
                "Start my workout in \(.applicationName)",
                "Start a workout in \(.applicationName)",
                "Begin training in \(.applicationName)",
            ],
            shortTitle: "intent.start.short",
            systemImageName: "dumbbell.fill"
        )
        AppShortcut(
            intent: LogWeightIntent(),
            phrases: [
                "Log my weight in \(.applicationName)",
                "Record my body weight in \(.applicationName)",
            ],
            shortTitle: "intent.weight.short",
            systemImageName: "scalemass.fill"
        )
        AppShortcut(
            intent: ShowScoreIntent(),
            phrases: [
                "Show my strength score in \(.applicationName)",
                "What is my score in \(.applicationName)",
            ],
            shortTitle: "intent.score.short",
            systemImageName: "gauge.with.dots.needle.67percent"
        )
    }
}
