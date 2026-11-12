import DataKit
import DesignSystem
import SwiftUI

extension ActiveWorkoutView {
    /// Understated record chip in the "previous" column: trophy, label, one bounce.
    func recordBadge(_ kind: RecordKind, celebrations: Int) -> some View {
        Label {
            Text(Self.recordName(kind))
        } icon: {
            Image(systemName: "trophy.fill").symbolEffect(.bounce, value: celebrations)
        }
        .font(DSFont.callout.weight(.semibold))
        .foregroundStyle(DSColor.accent)
        .frame(maxWidth: .infinity)
        .transition(.scale.combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("set-record-badge")
    }

    static func recordName(_ kind: RecordKind) -> LocalizedStringKey {
        switch kind {
        case .weight: "workout.record.weight"
        case .reps: "workout.record.reps"
        case .e1rm: "workout.record.e1rm"
        case .volume: "workout.record.volume"
        }
    }
}
