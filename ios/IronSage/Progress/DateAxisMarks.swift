import Charts
import IronSageCore
import SwiftUI

/// The x-axis of a chart over time: marks on calendar boundaries from `DateAxis`, each
/// labeled short ("13", "Oct", "2026") and naming the month or year only where it
/// changes.
func dateAxisMarks(from start: Date, to end: Date, calendar: Calendar = .current) -> some AxisContent {
    let labels = Dictionary(
        DateAxis.ticks(from: start, to: end, calendar: calendar).map { ($0.date, $0.label) },
        uniquingKeysWith: { first, _ in first }
    )
    return AxisMarks(values: labels.keys.sorted()) { value in
        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
        // Centered under its line, as in Health, rather than starting at it.
        AxisValueLabel(anchor: .top, collisionResolution: .greedy(minimumSpacing: 6)) {
            if let date = value.as(Date.self), let label = labels[date] {
                Text(date, format: label.format)
            }
        }
    }
}

extension DateAxis.Label {
    var format: Date.FormatStyle {
        switch self {
        case .weekday: .dateTime.weekday(.abbreviated)
        case .day: .dateTime.day()
        case .monthDay: .dateTime.month(.abbreviated).day()
        case .month: .dateTime.month(.abbreviated)
        case .year: .dateTime.year()
        }
    }
}
