import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The rest countdown on the lock screen (and the Always-On display) and in the
/// Dynamic Island. The system counts it down by itself; at zero (the activity's stale
/// date) it shows the time trained so far instead, until the app starts the next rest
/// or ends it. That rest is over is the notification's to say, so it isn't said twice.
struct RestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            RestLockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(WidgetLink.today)
        } dynamicIsland: { context in
            let isResting = Self.isResting(context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(isResting ? context.attributes.restTitle : context.attributes.workoutTitle, systemImage: "dumbbell.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Brand.onDark)
                        .labelStyle(.titleAndIcon)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RestClock(context: context, isResting: isResting)
                        .font(.title.weight(.semibold))
                        .foregroundStyle(Brand.accentOnDark)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if isResting {
                        HStack(spacing: 8) {
                            Button(intent: ExtendRestIntent(seconds: -15)) {
                                Text(context.attributes.lessLabel).frame(maxWidth: .infinity)
                            }
                            Button(intent: ExtendRestIntent(seconds: 15)) {
                                Text(context.attributes.moreLabel).frame(maxWidth: .infinity)
                            }
                            Button(intent: SkipRestIntent()) {
                                Text(context.attributes.skipLabel).frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .tint(.white)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 4)
                    }
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(Brand.accentOnDark)
            } compactTrailing: {
                RestClock(context: context, isResting: isResting)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isResting ? Brand.accentOnDark : Brand.onDark)
                    .frame(maxWidth: 52)
            } minimal: {
                if isResting {
                    RestClock(context: context, isResting: true)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Brand.accentOnDark)
                        .minimumScaleFactor(0.6)
                } else {
                    Image(systemName: "dumbbell.fill")
                        .foregroundStyle(Brand.onDark)
                }
            }
            .widgetURL(WidgetLink.today)
            .keylineTint(Brand.accentOnDark)
        }
    }

    static func isResting(_ context: ActivityViewContext<RestActivityAttributes>) -> Bool {
        !context.isStale && context.state.endsAt > .now
    }
}

/// Counted by the system: the rest left, or once rest is over the time trained so far.
private struct RestClock: View {
    let context: ActivityViewContext<RestActivityAttributes>
    let isResting: Bool
    /// A timer takes the width of its longest time, so its side is set here.
    var alignment: TextAlignment = .trailing

    var body: some View {
        Group {
            if isResting {
                Text(timerInterval: context.state.startedAt...context.state.endsAt, countsDown: true, showsHours: false)
            } else {
                // Up to a day: the system ends an activity long before that.
                let start = context.attributes.workoutStartedAt
                Text(timerInterval: start...start.addingTimeInterval(86_400), countsDown: false)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(alignment)
        .minimumScaleFactor(0.8)
    }
}

private struct RestLockScreenView: View {
    let context: ActivityViewContext<RestActivityAttributes>

    var body: some View {
        let isResting = RestLiveActivity.isResting(context)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("IronSage", systemImage: "dumbbell.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Brand.onDarkSecondary)
                Spacer()
                Text(isResting ? context.attributes.restTitle : context.attributes.workoutTitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Brand.onDarkSecondary)
            }
            RestClock(context: context, isResting: isResting, alignment: .leading)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Brand.onDark)
            if isResting {
                ProgressView(timerInterval: context.state.startedAt...context.state.endsAt, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(Brand.accentOnDark)
            }
        }
        .padding(16)
    }
}
