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
    static func show(_ timer: RestTimer, workoutStartedAt: Date) {
        let state = RestActivityAttributes.ContentState(
            startedAt: timer.endsAt.addingTimeInterval(-TimeInterval(max(timer.totalSeconds, 1))),
            endsAt: timer.endsAt
        )
        // At the stale date the views switch to the time trained, with nothing to send.
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
            _ = try Activity.request(attributes: attributes(workoutStartedAt: workoutStartedAt), content: content, pushType: nil)
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

    private static func attributes(workoutStartedAt: Date) -> RestActivityAttributes {
        RestActivityAttributes(
            workoutStartedAt: workoutStartedAt,
            restTitle: String(appLocalized: "Rest"),
            workoutTitle: String(appLocalized: "Workout"),
            lessLabel: String(appLocalized: "−15 s"),
            moreLabel: String(appLocalized: "+15 s"),
            skipLabel: String(appLocalized: "Skip")
        )
    }
}
