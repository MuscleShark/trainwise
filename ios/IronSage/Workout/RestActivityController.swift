import ActivityKit
import Foundation
import IronSageCore
import IronSageStore
import os

/// Shows the rest countdown on the lock screen and in the Dynamic Island while the app
/// isn't on screen (`RestLiveActivity` in the widget extension draws it). One activity
/// at a time: a new rest updates it, skipping or ending the workout removes it.
@MainActor
enum RestActivityController {
    private static let log = Logger(subsystem: "app.ironsage.IronSage", category: "rest-activity")

    private static var current: Activity<RestActivityAttributes>? {
        Activity<RestActivityAttributes>.activities.first
    }

    /// Starts or updates the countdown. Turned off in Settings › IronSage › Live
    /// Activities, it does nothing; the rest-over notification still comes.
    static func show(_ timer: RestTimer, next: String) {
        let state = RestActivityAttributes.ContentState(
            startedAt: timer.endsAt.addingTimeInterval(-TimeInterval(max(timer.totalSeconds, 1))),
            endsAt: timer.endsAt,
            next: next
        )
        // At the stale date the views say rest is over, with nothing to send.
        let content = ActivityContent(state: state, staleDate: timer.endsAt)
        if let id = current?.id {
            // Looked up inside the task: an activity can't be handed to one.
            Task {
                for activity in Activity<RestActivityAttributes>.activities where activity.id == id {
                    await activity.update(content)
                }
            }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
        } catch {
            log.error("Starting the rest Live Activity failed: \(error, privacy: .public)")
        }
    }

    /// Removes the countdown, and any left from a run of the app that was closed.
    static func end() {
        guard !Activity<RestActivityAttributes>.activities.isEmpty else { return }
        Task {
            for activity in Activity<RestActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private static var attributes: RestActivityAttributes {
        RestActivityAttributes(
            restTitle: String(appLocalized: "Rest"),
            overTitle: String(appLocalized: "Rest is over"),
            overDetail: String(appLocalized: "Get ready for your next set."),
            lessLabel: String(appLocalized: "−15 s"),
            moreLabel: String(appLocalized: "+15 s"),
            skipLabel: String(appLocalized: "Skip")
        )
    }
}
