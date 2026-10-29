import SwiftUI

// Layouts that follow the text size the user chose in Settings › Display & Brightness
// › Text Size, or Accessibility › Larger Text.

/// A row with a name on the leading edge and a value on the trailing one. At the
/// accessibility text sizes the value goes under the name instead, where side by side
/// would squeeze both to a word per line.
struct AdaptiveRow<Leading: View, Trailing: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    @Environment(\.dynamicTypeSize) private var size

    var body: some View {
        if size.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                leading
                trailing
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: spacing) {
                leading
                Spacer(minLength: spacing)
                trailing
            }
        }
    }
}

/// Side by side while everything fits on one line, otherwise one above the other.
struct FittingStack<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing) { content }
            VStack(alignment: .leading, spacing: spacing) { content }
        }
    }
}

extension View {
    /// Pickers in a form show their value beside the label, which is cut short at the
    /// accessibility text sizes; there they open a list of their own instead.
    func adaptivePickerStyle() -> some View {
        modifier(AdaptivePickerStyle())
    }

    /// Charts keep growing with the text size up to the first accessibility size; their
    /// values are in the rows around them and in VoiceOver at any size.
    func chartTextSize() -> some View {
        dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

private struct AdaptivePickerStyle: ViewModifier {
    @Environment(\.dynamicTypeSize) private var size

    func body(content: Content) -> some View {
        if size.isAccessibilitySize {
            content.pickerStyle(.navigationLink)
        } else {
            content
        }
    }
}

/// A chart's height that grows with the text size, so its labels keep their room, up
/// to `maximum`: `@ChartHeight(160) private var chartHeight`.
@propertyWrapper
struct ChartHeight: DynamicProperty {
    private var scaled: ScaledMetric<CGFloat>
    private let maximum: CGFloat

    init(_ base: CGFloat, maximum: CGFloat? = nil) {
        scaled = ScaledMetric(wrappedValue: base, relativeTo: .caption)
        self.maximum = maximum ?? base * 2
    }

    var wrappedValue: CGFloat { min(scaled.wrappedValue, maximum) }
}
