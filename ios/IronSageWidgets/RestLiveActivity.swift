import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The rest countdown on the lock screen (and the Always-On display) and in the
/// Dynamic Island. The system counts it down by itself; at zero (the activity's stale
/// date) it says rest is over, until the app starts the next rest or ends it.
struct RestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            RestLockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(WidgetLink.today)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.isStale ? context.attributes.overTitle : context.attributes.restTitle, systemImage: "dumbbell.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Brand.onDark)
                        .labelStyle(.titleAndIcon)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RestCountdown(state: context.state, isOver: context.isStale)
                        .font(.title.weight(.semibold))
                        .foregroundStyle(Brand.accentOnDark)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(context.isStale ? context.attributes.overDetail : context.state.next)
                            .font(.subheadline)
                            .foregroundStyle(Brand.onDark)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(Brand.accentOnDark)
            } compactTrailing: {
                RestCountdown(state: context.state, isOver: context.isStale)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.accentOnDark)
                    .frame(maxWidth: 52)
            } minimal: {
                RestCountdown(state: context.state, isOver: context.isStale, short: true)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Brand.accentOnDark)
            }
            .widgetURL(WidgetLink.today)
            .keylineTint(Brand.accentOnDark)
        }
    }
}

/// The time left, counted down by the system; a check mark once rest is over.
private struct RestCountdown: View {
    let state: RestActivityAttributes.ContentState
    let isOver: Bool
    var short = false

    var body: some View {
        if isOver || state.endsAt <= .now {
            Image(systemName: "checkmark")
        } else {
            Text(timerInterval: state.startedAt...state.endsAt, countsDown: true, showsHours: false)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .minimumScaleFactor(short ? 0.6 : 0.8)
        }
    }
}

private struct RestLockScreenView: View {
    let context: ActivityViewContext<RestActivityAttributes>

    var body: some View {
        let isOver = context.isStale || context.state.endsAt <= .now
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("IronSage", systemImage: "dumbbell.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Brand.onDarkSecondary)
                Spacer()
                if !isOver {
                    Text(context.attributes.restTitle)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Brand.onDarkSecondary)
                }
            }
            if isOver {
                Text(context.attributes.overTitle)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(Brand.onDark)
            } else {
                Text(timerInterval: context.state.startedAt...context.state.endsAt, countsDown: true, showsHours: false)
                    .font(.system(size: 40, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Brand.onDark)
                ProgressView(timerInterval: context.state.startedAt...context.state.endsAt, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(Brand.accentOnDark)
            }
            Text(isOver ? context.attributes.overDetail : context.state.next)
                .font(.subheadline)
                .foregroundStyle(Brand.onDark)
                .lineLimit(2)
        }
        .padding(16)
    }
}
