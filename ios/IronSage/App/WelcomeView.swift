import ClerkKitUI
import SwiftUI

struct WelcomeView: View {
    @State private var isSigningIn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Image(.logo)
                .resizable()
                .scaledToFit()
                .frame(width: 132)
                .accessibilityLabel(Text(verbatim: "IronSage"))
                .padding(.bottom, 12)
            Text("Know what to lift next.")
                .font(.title2.weight(.semibold))
            Text("Log every set, even without signal. Your training syncs to your account.")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Sign in or create account") {
                isSigningIn = true
            }
            .buttonStyle(BrandPrimaryButtonStyle())
        }
        .padding(24)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .sheet(isPresented: $isSigningIn) {
            AuthView()
        }
    }
}

#Preview {
    WelcomeView()
}
