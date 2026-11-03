import SwiftUI

// Scheme 4 of the IronSage brand: bone white with black type and red plates (see
// brand/). AccentColor is the red; these are the rest.

extension View {
    /// Bone white behind lists and forms (a warm near-black in dark mode).
    func brandBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.appBackground)
    }
}

/// The main call to action, at most one per screen: a red capsule, white text (dark
/// text on the lighter dark-mode red, which white would be too faint on).
struct BrandPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.brandOnAccent)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background(Color.accentColor, in: .capsule)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

/// An icon in a 44-point circle, the smallest target Apple recommends, for icon-only
/// buttons that sit side by side.
struct IconCircle: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.body.weight(.medium))
            .foregroundStyle(Color.primary)
            .frame(width: 44, height: 44)
            .background(Color(.secondarySystemGroupedBackground), in: .circle)
            .contentShape(.circle)
    }
}
