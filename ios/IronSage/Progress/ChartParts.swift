import Charts
import IronSageCore
import SwiftUI

// The progress charts are drawn the way trading apps draw a price: one line, no axes
// or grid; the period is picked under it; touching it shows a line and the date at that
// point, the number above changes to that point's value, and what comes after it dims.

/// The period under a chart: 1W 1M 3M 1Y All.
struct ChartRangeButtons: View {
    @Binding var range: BodyTrend.Range
    var options: [BodyTrend.Range] = BodyTrend.Range.allCases

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == range
                Button {
                    range = option
                } label: {
                    Text(option.short)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.chartMark : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(isSelected ? Color.chartMark.opacity(0.12) : .clear, in: .capsule)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                }
                // Plain, so each one takes its own tap in a list row.
                .buttonStyle(.plain)
                .accessibilityLabel(Text(option.label))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("range.\(option.rawValue)")
            }
        }
    }
}

extension BodyTrend.Range {
    /// "1M", under the chart.
    var short: LocalizedStringResource {
        switch self {
        case .week: "1W"
        case .month: "1M"
        case .quarter: "3M"
        case .year: "1Y"
        case .all: "All"
        }
    }

    /// "Month", for VoiceOver.
    var label: LocalizedStringResource {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .quarter: "3 months"
        case .year: "Year"
        case .all: "All"
        }
    }

    /// "the last month", for VoiceOver.
    var spoken: LocalizedStringResource {
        switch self {
        case .week: "the last 7 days"
        case .month: "the last month"
        case .quarter: "the last 3 months"
        case .year: "the last year"
        case .all: "all time"
        }
    }
}

extension Date {
    /// "Oct 25" over the touched point, with the year when it isn't this year.
    var chartDay: Date.FormatStyle {
        Calendar.current.isDate(self, equalTo: .now, toGranularity: .year)
            ? .dateTime.month(.abbreviated).day()
            : .dateTime.year().month(.abbreviated).day()
    }
}

/// The date over the line at the touched point.
struct ChartDateLabel: View {
    let date: Date

    var body: some View {
        Text(date, format: date.chartDay)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize()
            .accessibilityIdentifier("chartDate")
    }
}

/// The touched point: a dot with a ring in the card's color.
struct ChartTouchDot: View {
    var body: some View {
        Circle()
            .fill(Color.chartMark)
            .overlay { Circle().strokeBorder(Color(.secondarySystemGroupedBackground), lineWidth: 2.5) }
            .frame(width: 13, height: 13)
    }
}

/// The dates a chart's line covers: from the first point to the last, so it runs the
/// whole width whatever the period; a single point sits in the middle.
func chartSpan(_ dates: [Date]) -> ClosedRange<Date> {
    guard let first = dates.min(), let last = dates.max(), first < last else {
        let day = dates.first ?? .now
        return day.addingTimeInterval(-43_200)...day.addingTimeInterval(43_200)
    }
    return first...last
}

extension Array {
    /// The element whose date is nearest to `date`.
    func nearest(to date: Date, by key: (Element) -> Date) -> Element? {
        self.min { abs(key($0).timeIntervalSince(date)) < abs(key($1).timeIntervalSince(date)) }
    }
}
