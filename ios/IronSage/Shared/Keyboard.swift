import SwiftUI
import UIKit

/// How the keyboard goes away, the same on every screen, as in Apple's own apps and
/// most workout loggers:
/// - a tap anywhere outside a text field closes it (`dismissesKeyboardOnTap()`, once
///   at the root);
/// - a number pad has no return key, so a screen with number fields puts Done above
///   it (`keyboardDoneButton()`; the workout screen has its own, with Next);
/// - return closes a text field's keyboard;
/// - scrolling a list closes it.
enum Keyboard {
    /// Ends editing in whichever field has the keyboard, wherever it is.
    @MainActor static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

extension View {
    /// Done above the keyboard, for screens with number fields.
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { Keyboard.dismiss() }
                    .fontWeight(.semibold)
            }
        }
    }

    /// A tap outside a text field closes the keyboard, in this window and every sheet
    /// shown over it. The tap still reaches what was tapped, so tapping a set's
    /// checkmark both closes the keyboard and checks the set.
    func dismissesKeyboardOnTap() -> some View {
        background(TapToDismissInstaller().frame(width: 0, height: 0).accessibilityHidden(true))
    }
}

/// Adds the tap recognizer to the window once the view is in one. Sheets and full-screen
/// covers are presented in the same window, so one recognizer covers them all.
private struct TapToDismissInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> InstallerView { InstallerView() }
    func updateUIView(_ uiView: InstallerView, context: Context) {}

    final class InstallerView: UIView {
        private let recognizer = KeyboardTapRecognizer()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, recognizer.view !== window else { return }
            recognizer.view?.removeGestureRecognizer(recognizer)
            window.addGestureRecognizer(recognizer)
        }
    }
}

private final class KeyboardTapRecognizer: UITapGestureRecognizer, UIGestureRecognizerDelegate {
    init() {
        super.init(target: nil, action: nil)
        addTarget(self, action: #selector(tapped))
        // Never take the tap from the button, row or field under it.
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    @objc private func tapped() {
        view?.endEditing(true)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // A tap in a text field moves the keyboard there instead.
        var view = touch.view
        while let current = view {
            if current is UITextField || current is UITextView { return false }
            view = current.superview
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
