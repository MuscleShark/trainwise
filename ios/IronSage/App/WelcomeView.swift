import ClerkKitUI
import SwiftUI

struct WelcomeView: View {
    @State private var isSigningIn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Text(verbatim: "IronSage")
                .font(.system(.largeTitle, design: .default, weight: .heavy))
                .fontWidth(.expanded)
            Text("Know what to lift next.")
                .font(.title2.weight(.semibold))
            Text("Log every set, even without signal. Your training syncs to your account.")
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                isSigningIn = true
            } label: {
                Text("Sign in or create account")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
        .frame(maxWidth: 560)
        .sheet(isPresented: $isSigningIn) {
            AuthView()
        }
    }
}

#Preview {
    WelcomeView()
}
