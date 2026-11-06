import ActivityKit
import AppIntents
import Foundation

// Compiled into both the app and the widget extension: the extension draws the rest
// countdown on the lock screen and in the Dynamic Island, the app starts, updates and
// ends it.

/// The rest countdown after a set, shown while the app isn't on screen. The words come
/// from the app already in its language (the in-app pick included), so the extension
/// needs no strings of its own for it.
nonisolated struct RestActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        var startedAt: Date
        var endsAt: Date
        /// "Next: Back squat · set 3 · 100 kg × 6", or the exercise just done when the
        /// workout has no set left.
        var next: String
    }

    /// "Rest", "Rest is over" and "Get ready for your next set." in the app's language.
    var restTitle: String
    var overTitle: String
    var overDetail: String
    var lessLabel: String
    var moreLabel: String
    var skipLabel: String
}

/// What the buttons in the Dynamic Island ask the app to do.
nonisolated enum RestAction: Sendable {
    case extend(seconds: Int)
    case skip
}

/// Set by the app at launch. A Live Activity intent runs in the app's process, so the
/// buttons reach the workout; in the extension it stays nil and nothing happens there.
@MainActor
enum RestActions {
    static var perform: ((RestAction) -> Void)?
}

struct ExtendRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Change rest"
    static let isDiscoverable = false

    @Parameter(title: "Seconds")
    var seconds: Int

    init() {}

    init(seconds: Int) {
        self.seconds = seconds
    }

    func perform() async throws -> some IntentResult {
        let seconds = seconds
        await MainActor.run { RestActions.perform?(.extend(seconds: seconds)) }
        return .result()
    }
}

struct SkipRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Skip rest"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        await MainActor.run { RestActions.perform?(.skip) }
        return .result()
    }
}
