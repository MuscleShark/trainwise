import SwiftUI
import UIKit

/// The app's colors, for the extension (it has no asset catalog of its own).
enum Brand {
    /// The red accent: #C8372D, #FF6A55 in dark mode.
    static let accent = Color(UIColor { $0.userInterfaceStyle == .dark ? rgb(0xFF6A55) : rgb(0xC8372D) })
    /// The red on the always-dark Live Activity and Dynamic Island.
    static let accentOnDark = Color(rgb(0xFF6A55))
    static let onDark = Color(rgb(0xF4EFE6))
    static let onDarkSecondary = Color(rgb(0xB4B2A9))
    /// Bone, #F4EFE6; #161514 in dark mode.
    static let background = Color(UIColor { $0.userInterfaceStyle == .dark ? rgb(0x161514) : rgb(0xF4EFE6) })
    static let track = Color.primary.opacity(0.08)

    private static func rgb(_ hex: Int) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
