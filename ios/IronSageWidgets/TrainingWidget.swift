import SwiftUI
import WidgetKit

/// The next workout and this week, on the home screen (small, medium, large) and the
/// lock screen (circular, rectangular). The app writes what to show (`WidgetSnapshot`)
/// and reloads the widget after each change; at midnight a new day may start a new week.
struct TrainingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetStore.kind, provider: TrainingProvider()) { entry in
            TrainingWidgetView(entry: entry)
                .containerBackground(Brand.background, for: .widget)
        }
        .configurationDisplayName("IronSage")
        .description("Your next workout and this week's training.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular])
    }
}

struct TrainingEntry: TimelineEntry {
    let date: Date
    /// Nil until the app has written one (signed out, or never opened).
    let snapshot: WidgetSnapshot?
}

struct TrainingProvider: TimelineProvider {
    func placeholder(in context: Context) -> TrainingEntry {
        TrainingEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (TrainingEntry) -> Void) {
        completion(TrainingEntry(date: .now, snapshot: context.isPreview ? (WidgetStore.read() ?? .preview) : WidgetStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TrainingEntry>) -> Void) {
        let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
        completion(Timeline(entries: [TrainingEntry(date: .now, snapshot: WidgetStore.read())], policy: .after(midnight)))
    }
}

struct TrainingWidgetView: View {
    let entry: TrainingEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .accessoryCircular: CircularView(snapshot: snapshot)
            case .accessoryRectangular: RectangularView(snapshot: snapshot)
            case .systemMedium: MediumView(snapshot: snapshot)
            case .systemLarge: LargeView(snapshot: snapshot)
            default: SmallView(snapshot: snapshot)
            }
        } else {
            Text("Open IronSage to see your next workout.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .widgetURL(WidgetLink.today)
        }
    }
}

// MARK: Home screen

private struct SmallView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Caption(snapshot.labels.nextWorkout)
            NextDay(snapshot: snapshot)
            Spacer(minLength: 4)
            // Too narrow for one line: the count, then the streak.
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(snapshot.weekText)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Brand.accent)
                Text(snapshot.labels.thisWeek)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(snapshot.labels.streak)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(WidgetLink.today)
    }
}

private struct MediumView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Caption(snapshot.labels.nextWorkout)
                NextDay(snapshot: snapshot)
                ForEach(snapshot.nextExercises.prefix(3), id: \.self) { line in
                    Text(line)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Caption(snapshot.labels.thisWeek)
                Text(snapshot.weekText)
                    .font(.title.weight(.semibold))
                    .monospacedDigit()
                Text(snapshot.labels.streak)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let lastNight = snapshot.lastNight {
                    Text(lastNight)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(width: 110, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(WidgetLink.today)
    }
}

private struct LargeView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Caption(snapshot.labels.nextWorkout)
                    NextDay(snapshot: snapshot)
                }
                Spacer()
                if let start = snapshot.labels.start {
                    Link(destination: WidgetLink.startUpNext) {
                        Text(start)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Brand.accent, in: .capsule)
                    }
                }
            }
            ForEach(snapshot.nextExercises.prefix(3), id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .lineLimit(1)
            }
            Divider()
            HStack {
                Caption(snapshot.labels.setsPerMuscle)
                Spacer()
                WeekLine(snapshot: snapshot)
            }
            if snapshot.muscles.isEmpty {
                Text("No sets this week yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 7) {
                    ForEach(snapshot.muscles.prefix(6), id: \.name) { muscle in
                        GridRow {
                            Text(muscle.name)
                                .font(.caption)
                                .lineLimit(1)
                            MuscleBar(sets: muscle.sets, scale: snapshot.musclesScale)
                            Text(muscle.sets.formatted(.number.precision(.fractionLength(0...1))))
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .gridColumnAlignment(.trailing)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(WidgetLink.today)
    }
}

// MARK: Lock screen

private struct CircularView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        Gauge(value: Double(min(snapshot.weekDone, snapshot.weekPlanned ?? snapshot.weekDone)), in: 0...Double(max(snapshot.weekPlanned ?? max(snapshot.weekDone, 1), 1))) {
            Image(systemName: "dumbbell.fill")
        } currentValueLabel: {
            Text(snapshot.weekText)
                .monospacedDigit()
        }
        .gaugeStyle(.accessoryCircular)
        .widgetURL(WidgetLink.today)
    }
}

private struct RectangularView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(snapshot.labels.nextWorkout)
                .font(.caption2)
                .widgetAccentable()
            Text(snapshot.nextDay ?? snapshot.labels.noTemplate)
                .font(.headline)
                .lineLimit(1)
            Text(verbatim: "\(snapshot.labels.thisWeek) \(snapshot.weekText)")
                .font(.caption)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(WidgetLink.today)
    }
}

// MARK: Parts

private struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

private struct NextDay: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        if let day = snapshot.nextDay {
            Text(day)
                .font(.headline)
                .lineLimit(1)
            if let template = snapshot.nextTemplate {
                Text(template)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else {
            Text(snapshot.labels.noTemplate)
                .font(.subheadline)
                .lineLimit(3)
        }
    }
}

/// "3/4 · 2 weeks in a row".
private struct WeekLine: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: "\(snapshot.labels.thisWeek) \(snapshot.weekText)")
                .foregroundStyle(Brand.accent)
            Text(verbatim: "·")
                .foregroundStyle(.secondary)
            Text(snapshot.labels.streak)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

private struct MuscleBar: View {
    let sets: Double
    let scale: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Brand.track)
                Capsule()
                    .fill(Brand.accent)
                    .frame(width: max(proxy.size.width * min(sets, scale) / max(scale, 1), 6))
            }
        }
        .frame(height: 8)
        .frame(maxWidth: .infinity)
    }
}

extension WidgetSnapshot {
    /// For the widget gallery before the app has written anything.
    static let preview = WidgetSnapshot(
        nextDay: "Legs",
        nextTemplate: "Push / pull / legs ×2",
        nextExercises: ["Back squat 100 kg × 6", "Romanian deadlift 82.5 kg × 8", "Incline walk 15 min"],
        weekDone: 3,
        weekPlanned: 4,
        streakWeeks: 2,
        lastNight: "Slept 6 h 30 min · HRV 45 ms",
        muscles: [Muscle(name: "Glutes", sets: 5), Muscle(name: "Lats", sets: 4), Muscle(name: "Chest", sets: 3)],
        musclesScale: 20,
        labels: Labels(
            nextWorkout: "Next workout",
            thisWeek: "This week",
            streak: "2 weeks in a row",
            setsPerMuscle: "Sets per muscle",
            start: "Start Legs",
            noTemplate: "Start a workout from a template to see what's next."
        )
    )
}
