import DesignSystem
import SwiftUI

/// One month as a grid; days with a workout carry an accent dot.
struct MonthCalendarView: View {
    let month: Date
    let trainedDays: Set<Int>
    let calendar: Calendar

    private var days: [Int?] {
        guard let range = calendar.range(of: .day, in: .month, for: month),
              let first = calendar.dateInterval(of: .month, for: month)?.start else { return [] }
        let offset = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: offset) + range.map { Optional($0) }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    var body: some View {
        VStack(spacing: Spacing.xs) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: Spacing.xs) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(verbatim: symbol).font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        VStack(spacing: 2) {
                            Text(verbatim: "\(day)").font(DSFont.callout).monospacedDigit()
                                .foregroundStyle(trainedDays.contains(day) ? DSColor.textPrimary : DSColor.textSecondary)
                            Circle().fill(trainedDays.contains(day) ? DSColor.accent : .clear).frame(width: 6, height: 6)
                        }
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(trainedDays.contains(day) ? "history.calendar.trained \(day)" : "\(day)")
                    } else {
                        Color.clear.frame(height: 36)
                    }
                }
            }
        }
        .accessibilityIdentifier("history-calendar")
    }
}
