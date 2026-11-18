import Foundation

/// The link to a shared template: https://ironsage.app/p/<code>. The same link opens the
/// app on an iPhone that has it (Associated Domains), and the web page has a button that
/// opens ironsage://shared/<code>.
public enum SharedPlanLink {
    public static let host = "ironsage.app"
    public static let appScheme = "ironsage"

    public static func url(code: String) -> URL {
        URL(string: "https://\(host)/p/\(code)")!
    }

    /// The code in a shared link, or in text that holds one, as when a whole message is
    /// pasted ("Try my plan https://ironsage.app/p/k3T9xQ2mLa"). A code on its own works
    /// too. Nil when there is none.
    public static func code(in text: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = text.firstMatch(of: /(?:ironsage\.app\/p\/|ironsage:\/\/shared\/)([A-Za-z0-9]{6,16})/) {
            return String(match.1)
        }
        if text.wholeMatch(of: /[A-Za-z0-9]{10}/) != nil {
            return text
        }
        return nil
    }

    /// The code of a link the app was opened with: the web link or the app's own.
    public static func code(of url: URL) -> String? {
        switch url.scheme {
        case "https", "http":
            guard url.host() == host || url.host() == "www.\(host)" else { return nil }
            let parts = url.pathComponents.filter { $0 != "/" }
            return parts.count == 2 && parts[0] == "p" ? validCode(parts[1]) : nil
        case appScheme:
            guard url.host() == "shared" else { return nil }
            let parts = url.pathComponents.filter { $0 != "/" }
            return parts.count == 1 ? validCode(parts[0]) : nil
        default:
            return nil
        }
    }

    private static func validCode(_ text: String) -> String? {
        text.wholeMatch(of: /[A-Za-z0-9]{6,16}/) != nil ? text : nil
    }
}
