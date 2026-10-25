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

/// The main call to action: a black capsule with bone text (inverted in dark mode).
struct BrandPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.brandOnInk)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background(Color.brandInk, in: .capsule)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
