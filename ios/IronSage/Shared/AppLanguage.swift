import Foundation
import ObjectiveC

/// The language the app runs in: the phone's, or the one picked in Me › Profile.
///
/// A pick takes effect at once: strings come from that language's bundle (see
/// `LocalizedBundle`) and the root view is rebuilt with its locale. It is also written
/// to `AppleLanguages`, so from the next launch iOS's own parts of the app (system
/// buttons, the photo picker, number and date formats) use it too, as with the
/// per-app language in iOS Settings.
enum AppLanguage {
    enum Choice: String, CaseIterable, Identifiable {
        case system
        case english = "en"
        case chinese = "zh-Hans"

        var id: Self { self }
    }

    /// The user's pick, in UserDefaults. UI tests pass it as a launch argument.
    static let key = "IronSage.language"

    static var choice: Choice {
        UserDefaults.standard.string(forKey: key).flatMap(Choice.init(rawValue:)) ?? .system
    }

    /// The localization shown: "en" or "zh-Hans".
    static var current: String {
        choice == .system ? phoneLocalization : choice.rawValue
    }

    static var isChinese: Bool {
        current.hasPrefix("zh")
    }

    /// The app's locale: its language with the phone's region, so units and number
    /// formats still follow the region.
    static var locale: Locale {
        guard choice != .system else { return .current }
        var components = Locale.Components(locale: .current)
        components.languageComponents = Locale.Language.Components(identifier: current)
        return Locale(components: components)
    }

    /// Call once at launch, before any string is looked up.
    static func start() {
        #if DEBUG
        // UI tests start from the phone's language, whatever an earlier run picked.
        if ProcessInfo.processInfo.arguments.contains("-resetLanguage") {
            choose(.system)
        }
        #endif
        useStrings(of: choice)
    }

    static func choose(_ choice: Choice) {
        let defaults = UserDefaults.standard
        if choice == .system {
            defaults.removeObject(forKey: key)
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set(choice.rawValue, forKey: key)
            defaults.set([choice.rawValue], forKey: "AppleLanguages")
        }
        useStrings(of: choice)
    }

    /// Strings come from the picked language's bundle. With the phone's language the
    /// main bundle is left as iOS set it up, unless a pick in this session changed it.
    private static func useStrings(of choice: Choice) {
        if choice != .system, !(Bundle.main is LocalizedBundle) {
            object_setClass(Bundle.main, LocalizedBundle.self)
        }
        LocalizedBundle.strings = Bundle.main is LocalizedBundle ? bundle(for: current) : nil
    }

    /// The app localization that best fits the phone's languages. Read from defaults,
    /// which fall back to the phone's list once the app's own pick is removed.
    private static var phoneLocalization: String {
        let preferred = UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? Locale.preferredLanguages
        return Bundle.preferredLocalizations(from: Bundle.main.localizations, forPreferences: preferred)
            .first { $0 != "Base" } ?? "en"
    }

    private static func bundle(for localization: String) -> Bundle? {
        Bundle.main.path(forResource: localization, ofType: "lproj").flatMap(Bundle.init(path:))
    }
}

extension String {
    /// `String(localized:)` in the app's language. Plain `String(localized:)` keeps the
    /// language the app launched in, so after a pick in Me › Profile it would mix
    /// languages until the next launch.
    init(appLocalized value: String.LocalizationValue) {
        self.init(localized: value, bundle: LocalizedBundle.strings ?? .main)
    }

    // A literal is plain text, as with Foundation's own initializers.
    @_disfavoredOverload
    init(appLocalized resource: LocalizedStringResource) {
        var resource = resource
        resource.locale = AppLanguage.locale
        self.init(localized: resource)
    }
}

/// The main bundle's class while the app runs, so every string lookup (SwiftUI `Text`,
/// `String(localized:)`) reads the picked language's strings.
private nonisolated final class LocalizedBundle: Bundle, @unchecked Sendable {
    nonisolated(unsafe) static var strings: Bundle?

    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let strings = Self.strings {
            return strings.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }

}
