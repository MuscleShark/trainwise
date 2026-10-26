import Foundation
import IronSageCore
import IronSageStore
import OSLog

private let log = Logger(subsystem: "app.ironsage.IronSage", category: "coach")

/// Asks the AI coach about the next session and keeps track of its answer.
///
/// Nothing is sent until the user turns the coach on (CoachConsentView), and nothing
/// after they turn it off: requests still queued are cancelled, and the sync checks
/// again before sending one. The server is told too (`CoachSettings`), since it writes
/// the weekly summary on its own and only while the coach is on. While it is on, `refresh()` runs after each sync and asks
/// once per plan (`Coach.planKey`): the template day due next, its planned sets, the
/// last workout and last night's sleep. It asks on the day of the session, not on the
/// evening before, so the morning's sleep is known. The answer comes back with a later
/// sync, so `refresh()` syncs a few more times while it waits.
@MainActor
@Observable
final class CoachService {
    /// The user agreed to send their data to the coach.
    private(set) var isEnabled: Bool
    /// The user answered the question once, either way.
    private(set) var hasDecided: Bool

    @ObservationIgnored private let store: LocalStore
    @ObservationIgnored private let sync: SyncEngine
    @ObservationIgnored private let defaults: UserDefaults
    /// False in demo mode: nothing is sent.
    @ObservationIgnored private let isOnline: Bool
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var refreshAgain = false

    private enum Keys {
        static let enabled = "IronSage.coach.enabled"
        static let decided = "IronSage.coach.decided"
        /// Workout id → the recommendation whose advice its sets started from.
        static let applied = "IronSage.coach.applied"
        /// When the account last gained access (a purchase or restore): refusals from
        /// before it no longer count.
        static let accessSince = "IronSage.coach.accessSince"
    }

    /// Seconds between the syncs that pick up an answer, and how many of them.
    static let followUpDelay: Duration = .seconds(5)
    static let followUps = 6

    init(store: LocalStore, sync: SyncEngine, isOnline: Bool, defaults: UserDefaults = .standard) {
        self.store = store
        self.sync = sync
        self.isOnline = isOnline
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Keys.enabled)
        hasDecided = defaults.bool(forKey: Keys.decided)
        // Also for installs that turned it on before the server knew, and after the
        // app's language changed (iOS restarts the app for that).
        if hasDecided {
            reportSetting()
        }
    }

    func turnOn() {
        set(enabled: true)
        Task { await refresh() }
    }

    func turnOff() {
        set(enabled: false)
        store.cancelPendingRecommendations()
    }

    /// "Not now": stop offering it; it stays available in Settings.
    func notNow() {
        hasDecided = true
        defaults.set(true, forKey: Keys.decided)
    }

    /// Signing out or switching accounts: ask again. The next account to sync is told
    /// the coach is off on this phone until the user turns it on here.
    func reset() {
        isEnabled = false
        hasDecided = false
        for key in [Keys.enabled, Keys.decided, Keys.applied, Keys.accessSince] {
            defaults.removeObject(forKey: key)
        }
        reportSetting()
    }

    /// Before signing out, while the account can still be reached: tells the server the
    /// coach is off, so no weekly summary is written for an account nobody is signed
    /// in to here. Best effort; it doesn't change the setting on the phone.
    func withdrawBeforeSignOut() async {
        guard isOnline, isEnabled else { return }
        store.save(CoachSettings(enabled: false, language: AppLanguage.isChinese ? "zh" : "en"))
        await sync.sync()
    }

    private func set(enabled: Bool) {
        isEnabled = enabled
        hasDecided = true
        defaults.set(enabled, forKey: Keys.enabled)
        defaults.set(true, forKey: Keys.decided)
        reportSetting()
        // Turning it off reaches the server before next Monday's summary.
        if !enabled && isOnline {
            Task { await sync.sync() }
        }
    }

    /// Queues the setting for the server; the store skips it when unchanged.
    private func reportSetting() {
        store.save(CoachSettings(enabled: isEnabled, language: AppLanguage.isChinese ? "zh" : "en"))
    }

    // MARK: Weekly summary

    /// Last week's summary, while the coach is on.
    var weeklySummary: WeeklySummary? {
        isEnabled ? Coach.weeklySummary(in: store.weeklySummaries) : nil
    }

    /// The account gained access (subscribed or restored): ask again, even today.
    func accessGained() {
        defaults.set(Date.now, forKey: Keys.accessSince)
        Task { await refresh() }
    }

    // MARK: Advice

    /// The account can't use the coach (the server answered 402): no subscription, or it ended.
    var isUnavailable: Bool {
        guard let latest = store.recommendations.first else { return false }
        return latest.error == "not_allowed" && !isOutdatedRefusal(latest)
    }

    /// A 402 from before the account gained access.
    private func isOutdatedRefusal(_ recommendation: Recommendation) -> Bool {
        guard recommendation.error == "not_allowed", let since = defaults.object(forKey: Keys.accessSince) as? Date
        else { return false }
        return (recommendation.requestedAt ?? .distantPast) < since
    }

    /// Today's request for the plan due next, whatever its state.
    var current: Recommendation? {
        guard let plan = currentPlan() else { return nil }
        return store.recommendations.first {
            $0.forDate == HealthDays.key(.now) && $0.planKey == plan.key && !isOutdatedRefusal($0)
        }
    }

    /// The advice to start `day` with: the coach's answer for exactly the plan due now.
    func advice(for day: TemplateDay) -> Recommendation? {
        guard isEnabled, store.upNext?.day.id == day.id, let current, current.status == .ready, current.output != nil
        else { return nil }
        return current
    }

    /// Notes that a workout's sets started from this advice, so the workout shows its
    /// reasons and no other advice's.
    func recordApplied(_ recommendation: Recommendation, to workoutID: UUID) {
        var applied = defaults.dictionary(forKey: Keys.applied) as? [String: String] ?? [:]
        applied[workoutID.uuidString] = recommendation.id.uuidString
        defaults.set(applied, forKey: Keys.applied)
    }

    /// The advice a workout's sets started from, if any.
    func appliedAdvice(for workoutID: UUID) -> CoachAdvice? {
        guard isEnabled,
              let id = (defaults.dictionary(forKey: Keys.applied) as? [String: String])?[workoutID.uuidString]
        else { return nil }
        return store.recommendations.first { $0.id.uuidString == id }?.output
    }

    private struct Plan {
        let day: TemplateDay
        let request: CoachRequest
        let key: String
    }

    private func currentPlan() -> Plan? {
        guard let day = store.upNext?.day else { return nil }
        let today = HealthDays.key(.now)
        guard let request = Coach.request(
            for: day,
            exercises: store.exercises,
            context: store.nextSessionContext(),
            readiness: ReadinessComparison.compare(store.readiness, on: today),
            profile: store.profile,
            chinese: AppLanguage.isChinese
        ) else { return nil }
        let key = Coach.planKey(day: day, lastWorkout: store.finishedWorkouts.first, readiness: store.readiness[today], request: request)
        return Plan(day: day, request: request, key: key)
    }

    // MARK: Asking

    /// Asks about the plan due next unless it was asked already, and waits a little
    /// for the answer. Call it after each sync; a call during a running one runs again
    /// after it.
    func refresh() async {
        guard isOnline, isEnabled else { return }
        guard !isRefreshing else {
            refreshAgain = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshAgain = false
            await askIfNeeded()
        } while refreshAgain && isEnabled
    }

    private func askIfNeeded() async {
        guard store.activeWorkout == nil, let plan = currentPlan() else { return }
        let today = HealthDays.key(.now)
        if let asked = current {
            // The answer never came (the worker died): send it again, and the server
            // marks it timed out, so the app stops waiting.
            if asked.isWaiting, let sentAt = asked.sentAt, Date.now.timeIntervalSince(sentAt) > Coach.answerTimeout {
                store.save(asked)
                await sync.sync()
            }
            await waitForAnswer()
            return
        }
        // A workout done today: the next one is another day, so ask that morning,
        // with that night's sleep.
        if let last = store.finishedWorkouts.first, HealthDays.key(last.startedAt) == today {
            return
        }
        // No access, or the day's limit: don't ask again today.
        let todays = store.recommendations.filter { $0.forDate == today && !isOutdatedRefusal($0) }
        if todays.contains(where: { ["not_allowed", "limit_reached"].contains($0.error) }) || todays.count >= Coach.dailyRequests {
            return
        }
        log.info("Asking the coach about \(plan.day.name, privacy: .public)")
        store.save(Recommendation(forDate: today, request: plan.request, planKey: plan.key, requestedAt: .now))
        await sync.sync()
        await waitForAnswer()
    }

    private func waitForAnswer() async {
        for _ in 0..<Self.followUps {
            guard isEnabled, current?.isWaiting == true else { return }
            try? await Task.sleep(for: Self.followUpDelay)
            guard isEnabled else { return }
            await sync.sync()
        }
    }
}
