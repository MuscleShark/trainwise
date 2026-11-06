import Foundation

// Compiled into both the app and the widget extension. The app writes what the widgets
// show to the App Group after each change; the widgets only read it, offline.

/// What the home and lock screen widgets show, worked out by the app in its language.
nonisolated struct WidgetSnapshot: Codable, Hashable, Sendable {
    nonisolated struct Muscle: Codable, Hashable, Sendable {
        var name: String
        var sets: Double
    }

    /// The template day due next ("Legs") and its template ("Push / pull / legs ×2");
    /// nil when no workout has followed a template yet.
    var nextDay: String?
    var nextTemplate: String?
    /// Its first exercises with the suggested top set: "Back squat 100 kg × 6".
    var nextExercises: [String]
    /// Workouts this week, and the training days planned in the profile.
    var weekDone: Int
    var weekPlanned: Int?
    var streakWeeks: Int
    /// "Slept 6 h 30 min · HRV 45 ms", when last night was recorded.
    var lastNight: String?
    /// This week's sets per muscle, most first.
    var muscles: [Muscle]
    /// The track the muscle bars run on: 20 sets, or the most when more.
    var musclesScale: Double

    /// Labels, in the app's language.
    var labels: Labels

    nonisolated struct Labels: Codable, Hashable, Sendable {
        var nextWorkout: String
        var thisWeek: String
        /// "2 weeks in a row".
        var streak: String
        var setsPerMuscle: String
        /// "Start Legs".
        var start: String?
        /// Shown when no workout has followed a template yet.
        var noTemplate: String
    }

    /// "3/4", or "3" without a plan.
    var weekText: String {
        weekPlanned.map { "\(weekDone)/\($0)" } ?? "\(weekDone)"
    }
}

nonisolated enum WidgetStore {
    static let appGroup = "group.app.ironsage.IronSage"
    static let kind = "IronSageTraining"
    private static let key = "IronSage.widget.snapshot"

    static func read() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// True when it changed, so the widgets only reload then.
    @discardableResult
    static func write(_ snapshot: WidgetSnapshot?) -> Bool {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return false }
        let data = snapshot.flatMap { try? JSONEncoder().encode($0) }
        guard data != defaults.data(forKey: key) else { return false }
        defaults.set(data, forKey: key)
        return true
    }
}

/// Links from the widgets into the app.
nonisolated enum WidgetLink {
    static let scheme = "ironsage"
    /// Opens Today.
    static let today = URL(string: "ironsage://today")!
    /// Starts the template day due next.
    static let startUpNext = URL(string: "ironsage://start-up-next")!
}
